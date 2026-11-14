import AVFoundation
import OroroCore

/// `PlayerEngine` over `AVPlayer`. Maps AVFoundation state to `PlayerEvent`s for `PlaybackSession`.
/// Never logs or stores the stream URL.
///
/// Observation uses block-based KVO and NotificationCenter observers, never Combine's `publisher(for:).values`:
/// on a real HLS item that async sequence never delivered `.readyToPlay`, which left every video black.
@MainActor final class AVPlayerEngine: PlayerEngine {
    enum Failure: Error { case itemFailed, readyTimedOut }

    /// An item that never becomes ready fails like a long stall (the session recovers once, then shows the error).
    static let readyTimeout: Duration = .seconds(30)

    let player = AVPlayer()
    let subtitles: any SubtitleProvider
    let events: AsyncStream<PlayerEvent>

    private let continuation: AsyncStream<PlayerEvent>.Continuation
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var itemNotificationTokens: [any NSObjectProtocol] = []
    private var stallTask: Task<Void, Never>?
    private var lastStatus: AVPlayer.TimeControlStatus?
    /// Set by `play()` / `pause()` so the resulting status change is not reported as remote input.
    private var expectsStatusChange = false
    /// Targets of the engine's own seeks; their `timeJumped` notifications (which may arrive after the seek
    /// completes) are not remote input.
    /// Start times of the engine's own seeks. Each consumes the next `timeJumped` (whatever position the default
    /// HLS seek tolerance lands on); entries expire so a stale one can't swallow a genuine remote jump.
    private var isStopped = false
    private var ownSeeks: [ContinuousClock.Instant] = []
    private static let ownSeekExpiry: Duration = .seconds(2)
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
        ownSeeks.append(.now)
        let time = CMTime(seconds: target, preferredTimescale: 600)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            player.seek(to: time) { _ in done.resume() }
        }
    }

    /// Stops playback, removes every observer and ends `events`. Idempotent. Call after `PlaybackSession.willDismiss()`.
    func stop() {
        guard !isStopped else { return }
        isStopped = true
        tearDownItem()
        statusObservation?.invalidate()
        statusObservation = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        continuation.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Observation

    private func observeTimeControlStatus() {
        statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Self.onMain { self?.handle(status) }
        }
    }

    private func handle(_ status: AVPlayer.TimeControlStatus) {
        guard !isStopped, status != lastStatus else { return }
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
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Self.onMain { self?.continuation.yield(.failed) }
        }
        let center = NotificationCenter.default
        func on(_ name: Notification.Name, _ action: @escaping @MainActor (AVPlayerEngine) -> Void) -> any NSObjectProtocol {
            center.addObserver(forName: name, object: item, queue: .main) { [weak self] _ in
                Self.onMain { if let self { action(self) } }
            }
        }
        itemNotificationTokens = [
            on(AVPlayerItem.failedToPlayToEndTimeNotification) { $0.continuation.yield(.failed) },
            on(AVPlayerItem.didPlayToEndTimeNotification) { $0.continuation.yield(.ended) },
            on(AVPlayerItem.mediaSelectionDidChangeNotification) { $0.selectionChanged() },
            on(AVPlayerItem.timeJumpedNotification) { $0.timeJumped() }
        ]
    }

    /// Runs `work` on the main actor: inline when already on the main thread (keeps KVO order), else hops.
    nonisolated private static func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            Task { @MainActor in work() }
        }
    }

    private func tearDownItem() {
        itemObservation?.invalidate()
        itemObservation = nil
        itemNotificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        itemNotificationTokens = []
        stopStallCounter()
        legibleGroup = nil
        selectedLanguage = nil
        ownSeeks = []
    }

    private func emitTime() {
        guard player.currentItem?.status == .readyToPlay else { return }
        continuation.yield(.time(position: position, duration: duration))
    }

    private func timeJumped() {
        let now = ContinuousClock.now
        ownSeeks.removeAll { now - $0 > Self.ownSeekExpiry }
        if !ownSeeks.isEmpty {
            ownSeeks.removeFirst()
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

    /// Waits for `.readyToPlay` (current status first, then KVO); throws `Failure.itemFailed`,
    /// `Failure.readyTimedOut` after `timeout`, or `CancellationError` when cancelled.
    static func waitUntilReady(_ item: AVPlayerItem, timeout: Duration = readyTimeout) async throws {
        switch item.status {
        case .readyToPlay: return
        case .failed: throw Failure.itemFailed
        default: break
        }
        let waiter = ReadyWaiter()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                waiter.begin(item: item, timeout: timeout, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor in waiter.finish(.failure(CancellationError())) }
        }
    }

}

/// One `waitUntilReady`: resumes its continuation exactly once (ready, failed, timed out or cancelled).
@MainActor private final class ReadyWaiter {
    private var continuation: CheckedContinuation<Void, any Error>?
    private var observation: NSKeyValueObservation?
    private var timer: Task<Void, Never>?
    private var isFinished = false

    func begin(item: AVPlayerItem, timeout: Duration, continuation: CheckedContinuation<Void, any Error>) {
        guard !isFinished else {
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        observation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.statusChanged(status) }
            } else {
                Task { @MainActor in self?.statusChanged(status) }
            }
        }
        timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.finish(.failure(AVPlayerEngine.Failure.readyTimedOut))
        }
    }

    func finish(_ result: Result<Void, any Error>) {
        guard !isFinished else { return }
        isFinished = true
        observation?.invalidate()
        observation = nil
        timer?.cancel()
        timer = nil
        continuation?.resume(with: result)
        continuation = nil
    }

    private func statusChanged(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay: finish(.success(()))
        case .failed: finish(.failure(AVPlayerEngine.Failure.itemFailed))
        default: break
        }
    }
}
