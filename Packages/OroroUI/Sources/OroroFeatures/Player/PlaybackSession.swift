import Foundation
import Observation
import OroroCore

/// The player's state machine: resolve what to play, resume, progress saving, next episode, autoplay, failures.
///
/// Engine events arrive through `engine.events`; `PlayerScreen` drives the public methods.
/// All timing goes through the injected `clock` (progress tick, countdown, recovery) and `now` (URL expiry, library dates).
/// After `willDismiss()` nothing touches the engine, `phase` or `current` again.
@MainActor @Observable public final class PlaybackSession {
    public enum Phase: Equatable {
        case preparing, askResume(position: TimeInterval), playing, countdown(next: EpisodeRef, secondsLeft: Int),
             stillWatching, failed(Failure), finished
    }

    /// `.unauthorized`: the credentials were rejected; the player closes so the app can ask to sign in again.
    public enum Failure: Equatable { case fetch, notPlayable, stream, unauthorized }

    public private(set) var phase: Phase = .preparing
    public private(set) var current: PlayableID?
    public private(set) var nextEpisode: Episode?
    public private(set) var showsNextEpisodeAction = false

    // Spec constants.
    static let progressTick: Duration = .seconds(10), countdownSeconds = 5
    /// "Still watching?" is asked instead of the autoplay that would follow this many consecutive ones.
    static let stillWatchingAfter = 3
    static let nextActionWindow: TimeInterval = 40, stallTimeout: TimeInterval = 30
    static let urlLifetime: TimeInterval = 30 * 3600
    /// Clock time spent playing after an automatic recovery that re-arms the next automatic attempt.
    static let recoveredAfter: Duration = .seconds(10)

    private let request: PlayRequest
    private let environment: AppEnvironment
    private let session: AppSession
    private let engine: any PlayerEngine
    private let clock: any Clock<Duration>
    private let now: () -> Date

    /// The current item's show context (nil for movies).
    private struct ShowState {
        let showID: Int
        var name: String?
        var newestVideo: Date?
        var episodes: [Episode]
    }

    @ObservationIgnored private var show: ShowState?
    @ObservationIgnored private var currentEpisode: Episode?
    /// The movie being played (nil for episodes); shown above the progress line.
    @ObservationIgnored private var movieName: String?
    @ObservationIgnored private var playback: Playback?
    @ObservationIgnored private var position: TimeInterval = 0
    @ObservationIgnored private var duration: TimeInterval = 0
    /// True once the current item crossed the watched threshold (finish recorded; progress no longer written).
    @ObservationIgnored private var finishedCurrent = false
    @ObservationIgnored private var consecutiveAutoplays = 0
    /// The one automatic recovery for the current failure was used.
    @ObservationIgnored private var autoRecoveryUsed = false
    /// Clock time since the last automatic recovery succeeded; nil when none is pending re-arm.
    @ObservationIgnored private var sinceRecovery: (() -> Duration)?
    /// Elapsed clock time since progress was last written to the library.
    @ObservationIgnored private var sinceProgressWrite: () -> Duration = { .zero }
    /// The next episode last asked for, or nil when the request itself is (what `retry` repeats after a fetch failure).
    @ObservationIgnored private var nextLoad: Episode?
    /// A next-episode play is in flight (countdown and `playNextNow` never overlap).
    @ObservationIgnored private var loadingNext = false
    @ObservationIgnored private var dismissed = false
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?

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
        guard !dismissed else { return }
        listenToEngine()
        cancelCountdownTask()
        phase = .preparing
        resetItemState()
        nextLoad = nil

        guard let target = await resolveTarget(), !dismissed else { return }
        current = target
        guard let fetched = await fetchPlayback(for: target), !dismissed else { return }
        if currentEpisode == nil, let episode = fetched.episode {
            // Not in the show detail: keep the fetched episode's season/number, never its showID.
            currentEpisode = episode
        }
        playback = fetched.playback

        let resume = request.startOver ? nil : await environment.library.snapshot().resumePosition(target)
        guard !dismissed else { return }
        if let resume {
            phase = .askResume(position: resume)
        } else {
            await load(at: 0)
        }
    }

    public func chooseResume(_ resume: Bool) async {
        guard !dismissed, case .askResume(let position) = phase else { return }
        await load(at: resume ? position : 0)
    }

    public func playNextNow() async {
        guard !dismissed, !loadingNext, let nextEpisode else { return }
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
        guard !dismissed, phase == .stillWatching else { return }
        guard yes, let nextEpisode else {
            phase = .finished
            return
        }
        consecutiveAutoplays = 0
        await play(nextEpisode)
    }

    public func retry() async {
        guard !dismissed, case .failed(let failure) = phase else { return }
        switch failure {
        case .fetch, .notPlayable, .unauthorized:
            if let nextLoad {
                // A failed next-episode load: retry that episode, not the original request.
                await play(nextLoad)
            } else {
                await start()
            }
        case .stream:
            autoRecoveryUsed = false
            sinceRecovery = nil
            await reloadStream(automatic: false)
        }
    }

    /// Records + flushes; returns what the caller stores in `launcher.lastPlayed`.
    @discardableResult
    public func willDismiss() async -> PlayableID? {
        dismissed = true
        cancelCountdownTask()
        eventTask?.cancel()
        eventTask = nil
        let played = current
        await recordProgressNow()
        await environment.library.flush()
        return played
    }

    public func sceneBecameActive() async {
        guard !dismissed else { return }
        await engine.sceneBecameActive()
        guard !dismissed, phase == .playing, let playback,
              now().timeIntervalSince(playback.fetchedAt) > Self.urlLifetime else { return }
        // An expired URL says nothing about surround: keep it.
        await streamFailed(keepSurround: true)
    }
}

// MARK: - Events

extension PlaybackSession {
    func handle(_ event: PlayerEvent) async {
        guard !dismissed else { return }
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
        case .surroundFailed:
            await surroundFailed()
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
        if let sinceRecovery, sinceRecovery() >= Self.recoveredAfter {
            // Playback recovered: a later failure gets its own automatic attempt.
            self.sinceRecovery = nil
            autoRecoveryUsed = false
        }
        guard !finishedCurrent else { return }
        if Library.shouldMarkWatched(position: self.position, duration: self.duration) {
            await finishCurrent()
        } else if sinceProgressWrite() >= Self.progressTick {
            await recordProgressNow()
        }
    }

    private func ended() async {
        if !finishedCurrent, duration > 0 { await finishCurrent() }
        showsNextEpisodeAction = false
        let autoplay = await environment.library.snapshot().preferences.autoplayNext
        guard !dismissed else { return }
        guard let nextEpisode, autoplay else {
            phase = .finished
            return
        }
        if consecutiveAutoplays >= Self.stillWatchingAfter {
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
        // The task stays referenced until its play completes, so `willDismiss` can cancel it.
        countdownTask = Task { [weak self, clock] in
            for secondsLeft in (0..<Self.countdownSeconds).reversed() {
                do { try await clock.sleep(for: .seconds(1)) } catch { return }
                guard let self, !Task.isCancelled, !self.dismissed else { return }
                if secondsLeft > 0 {
                    self.phase = .countdown(next: ref, secondsLeft: secondsLeft)
                } else {
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
            show = ShowState(showID: showID, name: showName(showID, detail), newestVideo: detail?.title.newestVideo,
                             episodes: detail?.episodes ?? [])
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
                    if !dismissed { fail(.fetch, error: error) }
                    return nil
                }
                detail = nil
            }
            show = ShowState(showID: showID, name: showName(showID, detail), newestVideo: detail?.title.newestVideo,
                             episodes: detail?.episodes ?? [])
            guard let episodeID = resume?.episodeID ?? detail.flatMap({ EpisodeOrdering.first(in: $0.episodes) })?.id else {
                if !dismissed { phase = .failed(.notPlayable) }
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

    /// Always a network fetch; `playback` is nil when the response has no URL. `episode` only for episodes.
    /// A playback request's result; `movieName` is set for movies only.
    private struct Fetched {
        let playback: Playback?
        let episode: Episode?
        var movieName: String?
    }

    private func requestPlayback(for target: PlayableID) async throws -> Fetched {
        switch target.kind {
        case .movie:
            let detail = try await environment.details.moviePlayback(id: target.id)
            return Fetched(playback: detail.playback, episode: nil, movieName: detail.title.name)
        case .episode:
            let detail = try await environment.details.episodePlayback(id: target.id)
            return Fetched(playback: detail.playback, episode: detail.episode)
        }
    }

    /// The show's name from its detail, else from the catalog.
    private func showName(_ showID: Int, _ detail: ShowDetail?) -> String? {
        detail?.title.name ?? session.catalog?.title(TitleID(kind: .show, id: showID))?.name
    }

    /// Nil after setting `.failed(.fetch)` / `.failed(.notPlayable)`, or once dismissed.
    private func fetchPlayback(for target: PlayableID) async -> (playback: Playback, episode: Episode?)? {
        let fetched: Fetched
        do {
            fetched = try await requestPlayback(for: target)
        } catch {
            if !dismissed { fail(.fetch, error: error) }
            return nil
        }
        guard !dismissed else { return nil }
        guard let playback = fetched.playback else {
            phase = .failed(.notPlayable)
            return nil
        }
        if target.kind == .movie {
            movieName = fetched.movieName ?? session.catalog?.title(TitleID(kind: .movie, id: target.id))?.name
        }
        return (playback, fetched.episode)
    }

    private func load(at start: TimeInterval) async {
        guard let playback, !dismissed else { return }
        phase = .preparing
        let preferred = await environment.library.snapshot().preferences.subtitleLanguage
        guard !dismissed else { return }
        let available = Set(playback.subtitles.map(\.lang))
        let language = preferred.flatMap { available.contains($0) ? $0 : nil }
        engine.nowPlaying = NowPlaying.make(movieName: movieName, showName: show?.name, episode: currentEpisode)
        do {
            try await engine.load(playback, startAt: start, subtitleLanguage: language)
        } catch {
            guard !dismissed else { return }
            session.report(error)
            position = start
            await streamFailed() // recover like a mid-stream failure
            return
        }
        guard !dismissed else { return }
        position = start
        restartProgressStopwatch()
        engine.play()
        phase = .playing
    }

    /// Loads `episode` as the new current item with fresh playback, from the start.
    /// `current` and the item state move only once its playback is fetched.
    private func play(_ episode: Episode) async {
        guard !dismissed, !loadingNext else { return }
        loadingNext = true
        defer { loadingNext = false }
        phase = .preparing
        showsNextEpisodeAction = false
        nextLoad = episode
        let target = PlayableID(kind: .episode, id: episode.id)
        guard let fetched = await fetchPlayback(for: target) else { return }
        resetItemState()
        current = target
        setEpisodeContext(id: episode.id)
        if currentEpisode == nil { currentEpisode = episode }
        playback = fetched.playback
        await load(at: 0)
    }

    private func resetItemState() {
        playback = nil
        position = 0
        duration = 0
        finishedCurrent = false
        autoRecoveryUsed = false
        sinceRecovery = nil
        showsNextEpisodeAction = false
    }

    // MARK: - Failures

    /// Mid-stream or load failure, long stall, expired URL: one automatic refetch + reload, then `.failed(.stream)`.
    /// The automatic reload plays original audio unless `keepSurround` (the failure cannot be surround's).
    private func streamFailed(keepSurround: Bool = false) async {
        guard !dismissed else { return }
        guard !autoRecoveryUsed else {
            phase = .failed(.stream)
            return
        }
        autoRecoveryUsed = true
        sinceRecovery = nil
        if !keepSurround { engine.disableSurround() }
        await reloadStream(automatic: true)
    }

    /// Simulated surround gave up while playing: reload with original audio at the current position.
    /// Not a stream failure, so the automatic recovery stays armed.
    private func surroundFailed() async {
        guard phase == .playing else { return }
        await reloadStream(automatic: false)
    }

    private func reloadStream(automatic: Bool) async {
        guard let target = current, !dismissed else { return }
        phase = .preparing
        let resumeAt = position
        let fetched: Playback?
        do {
            fetched = try await requestPlayback(for: target).playback
        } catch {
            guard !dismissed else { return }
            fail(.stream, error: error)
            return
        }
        guard !dismissed else { return }
        guard let fetched else {
            phase = .failed(.notPlayable)
            return
        }
        playback = fetched
        await load(at: resumeAt)
        if automatic, !dismissed, phase == .playing, autoRecoveryUsed { sinceRecovery = clock.stopwatch() }
    }

    /// Reports `error`; a 401 always becomes `.unauthorized` (Retry would only repeat it).
    private func fail(_ failure: Failure, error: any Error) {
        session.report(error)
        let unauthorized = (error as? APIError) == .unauthorized
        phase = .failed(unauthorized ? .unauthorized : failure)
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
