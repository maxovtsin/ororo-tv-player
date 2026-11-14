import Foundation
import Observation
import OroroCore

/// The player's state machine: resolve what to play, resume, progress saving, next episode, autoplay, failures.
///
/// Engine events arrive through `engine.events`; `PlayerScreen` drives the public methods.
/// All timing goes through the injected `clock` (progress tick, countdown) and `now` (URL expiry, library dates).
@MainActor @Observable public final class PlaybackSession {
    public enum Phase: Equatable {
        case preparing, askResume(position: TimeInterval), playing, countdown(next: EpisodeRef, secondsLeft: Int),
             stillWatching, failed(Failure), finished
    }

    public enum Failure: Equatable { case fetch, notPlayable, stream }

    public private(set) var phase: Phase = .preparing
    public private(set) var current: PlayableID?
    public private(set) var nextEpisode: Episode?
    public private(set) var showsNextEpisodeAction = false

    // Spec constants.
    static let progressTick: Duration = .seconds(10), countdownSeconds = 5, stillWatchingAfter = 3
    static let nextActionWindow: TimeInterval = 40, stallTimeout: TimeInterval = 30
    static let urlLifetime: TimeInterval = 30 * 3600
    /// Playback this far past an automatic recovery counts as recovered (re-arms the next automatic attempt).
    static let recoveredAfter: TimeInterval = 10

    private let request: PlayRequest
    private let environment: AppEnvironment
    private let session: AppSession
    private let engine: any PlayerEngine
    private let clock: any Clock<Duration>
    private let now: () -> Date

    /// The current item's context (nil for movies).
    private struct ShowState {
        let showID: Int
        var newestVideo: Date?
        var episodes: [Episode]
    }

    private var show: ShowState?
    private var currentEpisode: Episode?
    private var playback: Playback?
    private var position: TimeInterval = 0
    private var duration: TimeInterval = 0
    /// True once the current item crossed the watched threshold (finish recorded; progress no longer written).
    private var finishedCurrent = false
    private var consecutiveAutoplays = 0
    /// The one automatic recovery for the current failure was used.
    private var autoRecoveryUsed = false
    /// Where the last automatic recovery resumed; playback past it re-arms automatic recovery.
    private var recoveryPosition: TimeInterval?
    /// Elapsed clock time since progress was last written to the library.
    private var sinceProgressWrite: () -> Duration = { .zero }
    /// The next episode being loaded, or nil when the request itself is (what `retry` repeats after a fetch failure).
    private var nextLoad: Episode?
    private var eventTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?

    public init(request: PlayRequest, environment: AppEnvironment, session: AppSession, engine: any PlayerEngine,
                clock: any Clock<Duration> = ContinuousClock(), now: @escaping () -> Date = Date.init) {
        self.request = request
        self.environment = environment
        self.session = session
        self.engine = engine
        self.clock = clock
        self.now = now
    }

    isolated deinit {
        eventTask?.cancel()
        countdownTask?.cancel()
    }

    // MARK: - Public API

    public func start() async {
        listenToEngine()
        cancelCountdownTask()
        phase = .preparing
        resetItemState()
        nextLoad = nil

        guard let target = await resolveTarget() else { return }
        current = target
        guard let fetched = await fetchPlayback(for: target) else { return }
        playback = fetched

        if !request.startOver, let resume = await environment.library.snapshot().resumePosition(target) {
            phase = .askResume(position: resume)
        } else {
            await load(at: 0)
        }
    }

    public func chooseResume(_ resume: Bool) async {
        guard case .askResume(let position) = phase else { return }
        await load(at: resume ? position : 0)
    }

    public func playNextNow() async {
        guard let nextEpisode else { return }
        consecutiveAutoplays = 0
        cancelCountdownTask()
        await recordProgressNow()
        await play(nextEpisode)
    }

    public func cancelCountdown() {
        guard case .countdown = phase else { return }
        cancelCountdownTask()
        phase = .finished
    }

    public func confirmStillWatching(_ yes: Bool) async {
        guard phase == .stillWatching else { return }
        guard yes, let nextEpisode else {
            phase = .finished
            return
        }
        consecutiveAutoplays = 0
        await play(nextEpisode)
    }

    public func retry() async {
        guard case .failed(let failure) = phase else { return }
        switch failure {
        case .fetch, .notPlayable:
            if let nextLoad {
                // A failed next-episode load: retry that episode, not the original request.
                await play(nextLoad)
            } else {
                await start()
            }
        case .stream:
            autoRecoveryUsed = false
            recoveryPosition = nil
            await reloadStream(automatic: false)
        }
    }

    /// Records + flushes; returns what the caller stores in `launcher.lastPlayed`.
    @discardableResult
    public func willDismiss() async -> PlayableID? {
        cancelCountdownTask()
        eventTask?.cancel()
        eventTask = nil
        await recordProgressNow()
        await environment.library.flush()
        return current
    }

    public func sceneBecameActive() async {
        guard phase == .playing, let playback,
              now().timeIntervalSince(playback.fetchedAt) > Self.urlLifetime else { return }
        await streamFailed()
    }

}

// MARK: - Events

extension PlaybackSession {

    func handle(_ event: PlayerEvent) async {
        switch event {
        case .userInput:
            consecutiveAutoplays = 0
        case .subtitleChanged(let language):
            await environment.library.update { $0.preferences.subtitleLanguage = language }
        case .resumed:
            break
        case .time(let position, let duration):
            guard phase == .playing else { return }
            await timeChanged(position: position, duration: duration)
        case .paused:
            guard phase == .playing else { return }
            await recordProgressNow()
            await environment.library.flush()
        case .ended:
            guard phase == .playing else { return }
            await ended()
        case .failed:
            guard phase == .playing else { return }
            await streamFailed()
        case .stalled(let seconds):
            guard phase == .playing, seconds >= Self.stallTimeout else { return }
            await streamFailed()
        }
    }

    private func listenToEngine() {
        guard eventTask == nil else { return }
        let events = engine.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self, !Task.isCancelled else { return }
                await self.handle(event)
            }
        }
    }

    private func timeChanged(position: TimeInterval, duration: TimeInterval) async {
        if position.isFinite { self.position = max(position, 0) }
        if duration.isFinite { self.duration = max(duration, 0) }
        showsNextEpisodeAction = nextEpisode != nil && self.duration > 0
            && self.duration - self.position <= Self.nextActionWindow
        if let recoveryPosition, self.position > recoveryPosition + Self.recoveredAfter {
            // Playback recovered: a later failure gets its own automatic attempt.
            self.recoveryPosition = nil
            autoRecoveryUsed = false
        }
        guard !finishedCurrent else { return }
        // `shouldMarkWatched` reads only its arguments; no need to snapshot the store on every tick.
        if Library().shouldMarkWatched(position: self.position, duration: self.duration) {
            await finishCurrent()
        } else if sinceProgressWrite() >= Self.progressTick {
            await recordProgressNow()
        }
    }

    private func ended() async {
        if !finishedCurrent, duration > 0 { await finishCurrent() }
        showsNextEpisodeAction = false
        guard let nextEpisode, await environment.library.snapshot().preferences.autoplayNext else {
            phase = .finished
            return
        }
        if consecutiveAutoplays >= Self.stillWatchingAfter - 1 {
            phase = .stillWatching
        } else {
            startCountdown(to: nextEpisode)
        }
    }

    // MARK: - Countdown

    private func startCountdown(to episode: Episode) {
        let ref = Self.ref(episode)
        phase = .countdown(next: ref, secondsLeft: Self.countdownSeconds)
        countdownTask?.cancel()
        countdownTask = Task { [weak self, clock] in
            for secondsLeft in (0..<Self.countdownSeconds).reversed() {
                do { try await clock.sleep(for: .seconds(1)) } catch { return }
                guard let self, !Task.isCancelled else { return }
                if secondsLeft > 0 {
                    self.phase = .countdown(next: ref, secondsLeft: secondsLeft)
                } else {
                    self.countdownTask = nil
                    self.consecutiveAutoplays += 1
                    await self.play(episode)
                }
            }
        }
    }

    private func cancelCountdownTask() {
        countdownTask?.cancel()
        countdownTask = nil
    }

}

// MARK: - Loading

extension PlaybackSession {

    /// Movie or episode to play; loads show context for episodes. Nil after setting a failed phase.
    private func resolveTarget() async -> PlayableID? {
        switch request.target {
        case .movie(let id):
            show = nil
            return PlayableID(kind: .movie, id: id)
        case .episode(let id, let showID):
            // Next-episode order needs the show's episodes; without them playback still works.
            let detail = try? await environment.details.show(id: showID)
            show = ShowState(showID: showID, newestVideo: detail?.title.newestVideo, episodes: detail?.episodes ?? [])
            setEpisodeContext(id: id)
            return PlayableID(kind: .episode, id: id)
        case .show(let showID):
            let library = await environment.library.snapshot()
            let resume = LibraryQueries.resumeTarget(showID: showID, library: library)
            let detail: ShowDetail?
            do {
                detail = try await environment.details.show(id: showID)
            } catch {
                guard resume != nil else {
                    fail(.fetch, error: error)
                    return nil
                }
                detail = nil
            }
            show = ShowState(showID: showID, newestVideo: detail?.title.newestVideo, episodes: detail?.episodes ?? [])
            guard let episodeID = resume?.episodeID ?? detail.flatMap({ EpisodeOrdering.first(in: $0.episodes) })?.id else {
                phase = .failed(.notPlayable)
                return nil
            }
            setEpisodeContext(id: episodeID)
            return PlayableID(kind: .episode, id: episodeID)
        }
    }

    private func setEpisodeContext(id: Int) {
        let episodes = show?.episodes ?? []
        currentEpisode = episodes.first { $0.id == id }
        nextEpisode = EpisodeOrdering.next(after: id, in: episodes)
    }

    /// Always a network fetch; nil when the response has no URL.
    private func requestPlayback(for target: PlayableID) async throws -> Playback? {
        switch target.kind {
        case .movie:
            return try await environment.details.moviePlayback(id: target.id).playback
        case .episode:
            let detail = try await environment.details.episodePlayback(id: target.id)
            if currentEpisode == nil {
                // Not in the show detail: keep the fetched episode's season/number, never its showID.
                currentEpisode = detail.episode
            }
            return detail.playback
        }
    }

    /// Nil after setting `.failed(.fetch)` / `.failed(.notPlayable)`.
    private func fetchPlayback(for target: PlayableID) async -> Playback? {
        let fetched: Playback?
        do {
            fetched = try await requestPlayback(for: target)
        } catch {
            fail(.fetch, error: error)
            return nil
        }
        guard let fetched else {
            phase = .failed(.notPlayable)
            return nil
        }
        return fetched
    }

    private func load(at start: TimeInterval) async {
        guard let playback else { return }
        phase = .preparing
        let preferred = await environment.library.snapshot().preferences.subtitleLanguage
        let available = Set(playback.subtitles.map(\.lang))
        let language = preferred.flatMap { available.contains($0) ? $0 : nil }
        do {
            try await engine.load(playback, startAt: start, subtitleLanguage: language)
        } catch {
            phase = .failed(.stream)
            return
        }
        position = start
        restartProgressStopwatch()
        engine.play()
        phase = .playing
    }

    /// Loads `episode` as the new current item with fresh playback, from the start.
    private func play(_ episode: Episode) async {
        cancelCountdownTask()
        phase = .preparing
        resetItemState()
        nextLoad = episode
        current = PlayableID(kind: .episode, id: episode.id)
        setEpisodeContext(id: episode.id)
        if currentEpisode == nil { currentEpisode = episode }
        guard let target = current, let fetched = await fetchPlayback(for: target) else { return }
        playback = fetched
        await load(at: 0)
    }

    private func resetItemState() {
        playback = nil
        position = 0
        duration = 0
        finishedCurrent = false
        autoRecoveryUsed = false
        recoveryPosition = nil
        showsNextEpisodeAction = false
    }

    // MARK: - Failures

    /// Mid-stream failure, long stall or expired URL: one automatic refetch + reload, then `.failed(.stream)`.
    private func streamFailed() async {
        guard !autoRecoveryUsed else {
            phase = .failed(.stream)
            return
        }
        autoRecoveryUsed = true
        await reloadStream(automatic: true)
    }

    private func reloadStream(automatic: Bool) async {
        guard let target = current else { return }
        phase = .preparing
        let resumeAt = position
        let fetched: Playback?
        do {
            fetched = try await requestPlayback(for: target)
        } catch {
            session.report(error)
            phase = .failed(.stream)
            return
        }
        guard let fetched else {
            phase = .failed(.notPlayable)
            return
        }
        playback = fetched
        await load(at: resumeAt)
        if automatic, phase == .playing { recoveryPosition = resumeAt }
    }

    private func fail(_ failure: Failure, error: any Error) {
        session.report(error)
        phase = .failed(failure)
    }

}

// MARK: - Library

extension PlaybackSession {

    private var showContext: ShowContext? {
        guard let show, let episode = currentEpisode else { return nil }
        return ShowContext(showID: show.showID, season: episode.season, number: episode.number ?? 0,
                           episodeName: episode.name, newestVideo: show.newestVideo)
    }

    private func recordProgressNow() async {
        guard let current, !finishedCurrent, duration > 0 else { return }
        let context = showContext, position = position, duration = duration, date = now()
        restartProgressStopwatch()
        await environment.library.update {
            $0.recordProgress(current, show: context, position: position, duration: duration, now: date)
        }
    }

    private func finishCurrent() async {
        guard let current, !finishedCurrent else { return }
        finishedCurrent = true
        let context = showContext, next = nextEpisode.map(Self.ref), date = now()
        await environment.library.update { $0.finish(current, show: context, next: next, now: date) }
    }

    private func restartProgressStopwatch() {
        sinceProgressWrite = clock.stopwatch()
    }

    private static func ref(_ episode: Episode) -> EpisodeRef {
        EpisodeOrdering.ref(episode) ?? EpisodeRef(episodeID: episode.id, season: episode.season, number: 0)
    }
}

private extension Clock where Duration == Swift.Duration {
    /// Elapsed time on this clock since the call.
    func stopwatch() -> () -> Swift.Duration {
        let start = now
        return { start.duration(to: self.now) }
    }
}
