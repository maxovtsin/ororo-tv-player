import AVFoundation
import Combine
import OroroCore

/// `PlayerEngine` over `AVPlayer`. Maps AVFoundation state to `PlayerEvent`s for `PlaybackSession`.
/// Never logs or stores the stream URL.
@MainActor final class AVPlayerEngine: PlayerEngine {
    enum Failure: Error { case itemFailed }

    let player = AVPlayer()
    let subtitles: any SubtitleProvider
    let events: AsyncStream<PlayerEvent>

    private let continuation: AsyncStream<PlayerEvent>.Continuation
    private var timeObserver: Any?
    private var statusTask: Task<Void, Never>?
    private var itemTasks: [Task<Void, Never>] = []
    private var stallTask: Task<Void, Never>?
    private var lastStatus: AVPlayer.TimeControlStatus?
    /// Set by `play()` / `pause()` so the resulting status change is not reported as remote input.
    private var expectsStatusChange = false
    /// Targets of the engine's own seeks; their `timeJumped` notifications (which may arrive after the seek
    /// completes) are not remote input.
    private var ownSeekTargets: [TimeInterval] = []
    private static let seekMatchTolerance: TimeInterval = 1.5
    private var legibleGroup: AVMediaSelectionGroup?
    private var selectedLanguage: String?

    init(subtitles: any SubtitleProvider = HLSInjectedSubtitles()) {
        self.subtitles = subtitles
        (events, continuation) = AsyncStream.makeStream(of: PlayerEvent.self)
        player.appliesMediaSelectionCriteriaAutomatically = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        observeTimeControlStatus()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.emitTime() }
        }
    }

    var position: TimeInterval {
        Self.seconds(player.currentTime())
    }

    var duration: TimeInterval {
        player.currentItem.map { Self.seconds($0.duration) } ?? 0
    }

    func load(_ playback: Playback, startAt: TimeInterval, subtitleLanguage: String?) async throws {
        tearDownItem()
        try? AVAudioSession.sharedInstance().setActive(true)
        let asset = subtitles.makeAsset(for: playback, preferredLanguage: subtitleLanguage)
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        try await Self.waitUntilReady(item)
        legibleGroup = try? await asset.loadMediaSelectionGroup(for: .legible)
        selectSubtitle(subtitleLanguage, in: item)
        if startAt > 0 { await seek(to: startAt) }
        observe(item)
    }

    func play() {
        expectsStatusChange = player.timeControlStatus != .playing
        player.play()
    }

    func pause() {
        expectsStatusChange = player.timeControlStatus != .paused
        player.pause()
    }

    func seek(to position: TimeInterval) async {
        let target = max(position, 0)
        ownSeekTargets.append(target)
        let time = CMTime(seconds: target, preferredTimescale: 600)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            player.seek(to: time) { _ in done.resume() }
        }
    }

    /// Stops playback, removes every observer and ends `events`. Call after `PlaybackSession.willDismiss()`.
    func stop() {
        tearDownItem()
        statusTask?.cancel()
        statusTask = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        continuation.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Observation

    private func observeTimeControlStatus() {
        let statuses = player.publisher(for: \.timeControlStatus).removeDuplicates().values
        statusTask = Task { [weak self] in
            for await status in statuses {
                self?.handle(status)
            }
        }
    }

    private func handle(_ status: AVPlayer.TimeControlStatus) {
        let previous = lastStatus
        lastStatus = status
        if status != .waitingToPlayAtSpecifiedRate { stopStallCounter() }
        let isRemoteInput = !expectsStatusChange
        switch status {
        case .playing:
            expectsStatusChange = false
            guard previous != nil else { return }
            continuation.yield(.resumed)
            if isRemoteInput, previous == .paused { continuation.yield(.userInput) }
        case .paused:
            expectsStatusChange = false
            guard previous != nil, player.currentItem != nil else { return }
            continuation.yield(.paused)
            if isRemoteInput, !isAtEnd { continuation.yield(.userInput) }
        case .waitingToPlayAtSpecifiedRate:
            if player.reasonForWaitingToPlay != .noItemToPlay { startStallCounter() }
        @unknown default:
            break
        }
    }

    private func observe(_ item: AVPlayerItem) {
        let center = NotificationCenter.default
        let failures = item.publisher(for: \.status).filter { $0 == .failed }.map { _ in () }
            .merge(with: center.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item).map { _ in () })
            .values
        let ends = center.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item).map { _ in () }.values
        let selections = center.publisher(for: AVPlayerItem.mediaSelectionDidChangeNotification, object: item)
            .map { _ in () }.values
        let jumps = center.publisher(for: AVPlayerItem.timeJumpedNotification, object: item).map { _ in () }.values

        itemTasks = [
            Task { [weak self] in for await _ in failures { self?.continuation.yield(.failed) } },
            Task { [weak self] in for await _ in ends { self?.continuation.yield(.ended) } },
            Task { [weak self] in for await _ in selections { self?.selectionChanged() } },
            Task { [weak self] in for await _ in jumps { self?.timeJumped() } }
        ]
    }

    private func tearDownItem() {
        itemTasks.forEach { $0.cancel() }
        itemTasks = []
        stopStallCounter()
        legibleGroup = nil
        selectedLanguage = nil
        ownSeekTargets = []
    }

    private func emitTime() {
        guard player.currentItem?.status == .readyToPlay else { return }
        continuation.yield(.time(position: position, duration: duration))
    }

    private func timeJumped() {
        let now = position
        if let index = ownSeekTargets.firstIndex(where: { abs($0 - now) <= Self.seekMatchTolerance }) {
            ownSeekTargets.removeSubrange(...index)
            return
        }
        continuation.yield(.userInput)
    }

    // MARK: - Stalls

    private func startStallCounter() {
        guard stallTask == nil else { return }
        stallTask = Task { [weak self] in
            var seconds: TimeInterval = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                seconds += 1
                continuation.yield(.stalled(seconds: seconds))
            }
        }
    }

    private func stopStallCounter() {
        stallTask?.cancel()
        stallTask = nil
    }

    // MARK: - Subtitles

    private func selectSubtitle(_ language: String?, in item: AVPlayerItem) {
        guard let group = legibleGroup else { return }
        let option = language.flatMap { lang in group.options.first { Self.language(of: $0) == lang } }
        item.select(option, in: group)
        selectedLanguage = option.flatMap(Self.language(of:))
    }

    private func selectionChanged() {
        guard let group = legibleGroup, let item = player.currentItem else { return }
        let language = item.currentMediaSelection.selectedMediaOption(in: group).flatMap(Self.language(of:))
        guard language != selectedLanguage else { return }
        selectedLanguage = language
        continuation.yield(.subtitleChanged(language))
        continuation.yield(.userInput)
    }

    // MARK: - Helpers

    private var isAtEnd: Bool {
        let duration = duration
        return duration > 0 && position >= duration - 1
    }

    private static func language(of option: AVMediaSelectionOption) -> String? {
        option.extendedLanguageTag ?? option.locale?.language.languageCode?.identifier
    }

    private static func seconds(_ time: CMTime) -> TimeInterval {
        let seconds = time.seconds
        return seconds.isFinite ? max(seconds, 0) : 0
    }

    private static func waitUntilReady(_ item: AVPlayerItem) async throws {
        for await status in item.publisher(for: \.status).values {
            switch status {
            case .readyToPlay: return
            case .failed: throw Failure.itemFailed
            default: continue
            }
        }
        throw CancellationError()
    }
}
