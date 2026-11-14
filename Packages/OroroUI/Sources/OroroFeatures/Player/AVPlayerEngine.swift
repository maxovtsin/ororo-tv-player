import AVFoundation
import OroroCore
import os

/// `PlayerEngine` over `AVPlayer`. Maps AVFoundation state to `PlayerEvent`s for `PlaybackSession`.
/// Never logs or stores the stream URL.
///
/// Observation uses block-based KVO and NotificationCenter observers, never Combine's `publisher(for:).values`:
/// on a real HLS item that async sequence never delivered `.readyToPlay`, which left every video black.
@MainActor final class AVPlayerEngine: PlayerEngine {
    enum Failure: Error { case itemFailed, readyTimedOut }

    /// An item that never becomes ready fails like a long stall (the session recovers once, then shows the error).
    static let readyTimeout: Duration = .seconds(30)

    private static let log = Logger(subsystem: "com.dissimirall.Ororo-Player", category: "Surround")

    let player = AVPlayer()
    let subtitles: any SubtitleProvider
    let surround: SurroundPolicy
    private let outputChannels: @MainActor () -> Int
    private let readyTimeout: Duration
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
    /// The current load's surround source (also while it starts, so `stop()` reaches it); `nil` plays original audio.
    private var surroundSource: (any SurroundSource)?
    /// Bumped by every load and by `stop()`; a surround start that finishes after its load was superseded is dropped,
    /// and a surround failure reported for an earlier load is ignored.
    private var loadGeneration = 0
    /// The generation of the load in progress (from its start until it returns); a surround failure reported meanwhile
    /// makes that load retry without surround instead of emitting `.surroundFailed`.
    private var loadInFlight: Int?
    /// The surround source of the load in progress reported a failure.
    private var failedDuringLoad = false
    /// Surround failed or was disabled: this engine plays original audio for the rest of its life.
    private var surroundDisabled = false
    /// Numbers each `observe(_:)`; `observedItem` is the live one (`nil` once silenced), so callbacks from an earlier or
    /// silenced item are dropped even when already queued.
    private var itemObservationCount = 0
    private(set) var observedItem: Int?
    /// The current item was given up for a surround failure: it reports nothing more (the session reloads).
    private var silencedItem = false
    /// A source reported `.slowDevice`: no engine plays surround again until the app is relaunched.
    private static var surroundDisabledUntilRelaunch = false

    init(subtitles: any SubtitleProvider = HLSInjectedSubtitles(),
         surround: SurroundPolicy = .disabled,
         outputChannels: @escaping @MainActor () -> Int = AudioOutput.channelCount,
         readyTimeout: Duration = AVPlayerEngine.readyTimeout) {
        self.subtitles = subtitles
        self.surround = surround
        self.outputChannels = outputChannels
        self.readyTimeout = readyTimeout
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
        loadGeneration += 1
        let generation = loadGeneration
        loadInFlight = generation
        failedDuringLoad = false
        defer { if loadInFlight == generation { loadInFlight = nil } }
        let source = await startSurround(generation: generation)
        // `stop()` or a newer load ran while surround started: installing an item now would revive a stopped player
        // or replace the newer load's item.
        guard isCurrent(generation) else { throw CancellationError() }
        var asset = subtitles.makeAsset(for: playback, preferredLanguage: subtitleLanguage, surround: source)
        var item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        do {
            try await Self.waitUntilReady(item, timeout: readyTimeout)
            if source != nil, failedDuringLoad { throw SurroundFailedWhileLoading() }
        } catch {
            // A surround item that failed, timed out or lost its source: once, the same load with original audio.
            guard source != nil, !(error is CancellationError), isCurrent(generation) else { throw error }
            Self.log.notice("Surround load failed; retrying with original audio")
            disableSurroundAfterFailure()
            asset = subtitles.makeAsset(for: playback, preferredLanguage: subtitleLanguage, surround: nil)
            item = AVPlayerItem(asset: asset)
            player.replaceCurrentItem(with: item)
            try await Self.waitUntilReady(item, timeout: readyTimeout)
        }
        legibleGroup = try? await asset.loadMediaSelectionGroup(for: .legible)
        selectSubtitle(subtitleLanguage, in: item)
        if startAt > 0 { await seek(to: startAt) }
        observe(item)
        loadInFlight = nil
        // The source gave up after the item became ready: the session reloads, now with original audio.
        if failedDuringLoad, surroundSource != nil, isCurrent(generation) { abandonSurroundItem() }
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
        loadGeneration += 1
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
        itemObservationCount += 1
        let observation = itemObservationCount
        observedItem = observation
        // A callback already queued when the item is silenced or replaced must not reach the session.
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Self.onMain { self?.received(.failed, from: observation) }
        }
        let center = NotificationCenter.default
        func on(_ name: Notification.Name, _ signal: ItemSignal) -> any NSObjectProtocol {
            center.addObserver(forName: name, object: item, queue: .main) { [weak self] _ in
                Self.onMain { self?.received(signal, from: observation) }
            }
        }
        itemNotificationTokens = [
            on(AVPlayerItem.failedToPlayToEndTimeNotification, .failed),
            on(AVPlayerItem.didPlayToEndTimeNotification, .ended),
            on(AVPlayerItem.mediaSelectionDidChangeNotification, .selectionChanged),
            on(AVPlayerItem.timeJumpedNotification, .timeJumped)
        ]
    }

    enum ItemSignal: Sendable { case failed, ended, selectionChanged, timeJumped }

    /// One observer callback of item observation `observation`. Dropped unless that observation is still live: a callback
    /// already queued when its item was silenced or replaced must not reach the session.
    func received(_ signal: ItemSignal, from observation: Int) {
        guard observedItem == observation else { return }
        switch signal {
        case .failed: itemFailed()
        case .ended: continuation.yield(.ended)
        case .selectionChanged: selectionChanged()
        case .timeJumped: timeJumped()
        }
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
        surroundSource?.stop()
        surroundSource = nil
        silenceItem()
        silencedItem = false
        legibleGroup = nil
        selectedLanguage = nil
        ownSeeks = []
    }

    /// Removes the current item's observers and stall counter; while `silencedItem`, it reports no more time or stalls.
    private func silenceItem() {
        silencedItem = true
        observedItem = nil
        itemObservation?.invalidate()
        itemObservation = nil
        itemNotificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        itemNotificationTokens = []
        stopStallCounter()
    }

    private func emitTime() {
        guard !silencedItem, player.currentItem?.status == .readyToPlay else { return }
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
        guard stallTask == nil, !silencedItem else { return }
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

// MARK: - Surround

extension AVPlayerEngine {
    func disableSurround() {
        surroundDisabled = true
    }

    /// Back from the background: a surround server that did not survive sleep is a surround failure.
    func sceneBecameActive() async {
        guard !isStopped, let source = surroundSource else { return }
        let generation = loadGeneration
        let serving = await source.ensureServing()
        if !serving { surroundFailed(.format, generation: generation) }
    }

    /// The surround source of load `generation` gave up. Ignored for an earlier load, after `stop()`, or once the load
    /// no longer plays surround.
    func surroundFailed(_ failure: SurroundFailure, generation: Int) {
        guard isCurrent(generation), surroundSource != nil else { return }
        Self.log.notice("Surround failed: \(String(describing: failure), privacy: .public)")
        surroundDisabled = true
        if failure == .slowDevice { Self.surroundDisabledUntilRelaunch = true }
        if loadInFlight == generation {
            failedDuringLoad = true
        } else {
            abandonSurroundItem()
        }
    }

    /// The current item failed. With an active surround source that is a surround failure: one `.surroundFailed`
    /// (never also `.failed`), so the session reloads once with original audio and keeps its automatic recovery.
    private func itemFailed() {
        guard !isStopped else { return }
        guard surroundSource != nil else {
            continuation.yield(.failed)
            return
        }
        Self.log.notice("Surround item failed")
        abandonSurroundItem()
    }

    /// Drops the failed surround source and silences its item, then yields the one `.surroundFailed` the session
    /// reloads on. The next load replaces the item.
    private func abandonSurroundItem() {
        disableSurroundAfterFailure()
        silenceItem()
        continuation.yield(.surroundFailed)
    }

    private struct SurroundFailedWhileLoading: Error {}

    /// Load `generation` is still the latest and the engine runs.
    private func isCurrent(_ generation: Int) -> Bool {
        !isStopped && generation == loadGeneration
    }

    /// Stops the current source and plays original audio from now on.
    private func disableSurroundAfterFailure() {
        surroundDisabled = true
        surroundSource?.stop()
        surroundSource = nil
    }

    /// Decides whether load `generation` plays simulated 5.1 and starts its source; `nil` means original audio.
    /// Order: a failed or disabled surround, output channels, then the preference, then the source start.
    /// Logs one line (never the stream URL).
    private func startSurround(generation: Int) async -> (any SurroundSource)? {
        let channels = outputChannels()
        AudioOutput.lastObservedChannelCount = channels
        var source: (any SurroundSource)?
        if !Self.surroundDisabledUntilRelaunch, !surroundDisabled, AudioOutput.supportsSurround(channels: channels),
           await surround.isEnabled(), generation == loadGeneration {
            let candidate = surround.makeSource { [weak self] failure in
                Task { @MainActor in self?.surroundFailed(failure, generation: generation) }
            }
            surroundSource = candidate
            do {
                _ = try await candidate.start()
                // A newer load or `stop()` has already stopped the candidate through `tearDownItem()`.
                if generation == loadGeneration { source = candidate }
            } catch {
                if generation == loadGeneration {
                    candidate.stop()
                    surroundSource = nil
                }
            }
        }
        let port = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType.rawValue ?? "none"
        Self.log.notice(
            "Output channels \(channels, privacy: .public), port \(port, privacy: .public), surround \(source != nil, privacy: .public)"
        )
        return source
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
