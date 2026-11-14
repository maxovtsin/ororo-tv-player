import AVFoundation
import Foundation
import OroroCore
@testable import OroroFeatures
import Testing

/// `AVPlayerEngine.waitUntilReady` against real `AVPlayerItem`s (KVO-driven, never Combine `.values`), and the
/// engine's per-load surround decision. Serialized: the tests share the process-global
/// `AudioOutput.lastObservedChannelCount`.
@Suite(.serialized) @MainActor struct AVPlayerEngineTests {
    private static let playback = Playback(
        streamURL: URL(string: "https://example.invalid/hls/stream.m3u8?wmsAuthSign=PLACEHOLDER")!,
        subtitles: [Subtitle(lang: "en", url: URL(string: "https://example.invalid/subs/en.vtt")!)],
        fetchedAt: Date(timeIntervalSince1970: 1_761_955_200)
    )

    @Test func becomesReadyForAPlayableItem() async throws {
        let item = AVPlayerItem(url: try TestMedia.silentWAV())
        let player = AVPlayer(playerItem: item)
        try await AVPlayerEngine.waitUntilReady(item, timeout: .seconds(20))
        #expect(item.status == .readyToPlay)
        // Already ready: returns at once from the current status.
        try await AVPlayerEngine.waitUntilReady(item, timeout: .milliseconds(1))
        _ = player
    }

    @Test func failedItemThrowsItemFailed() async {
        let item = AVPlayerItem(url: URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "missing-\(UUID()).mp4"))
        let player = AVPlayer(playerItem: item)
        await #expect(throws: AVPlayerEngine.Failure.itemFailed) {
            try await AVPlayerEngine.waitUntilReady(item, timeout: .seconds(20))
        }
        _ = player
    }

    @Test func itemThatNeverBecomesReadyTimesOut() async {
        // Never attached to a player: its status stays `.unknown`.
        let item = AVPlayerItem(url: URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "idle-\(UUID()).mp4"))
        await #expect(throws: AVPlayerEngine.Failure.readyTimedOut) {
            try await AVPlayerEngine.waitUntilReady(item, timeout: .milliseconds(200))
        }
    }

    @Test func cancellationThrowsCancellationError() async {
        let item = AVPlayerItem(url: URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "idle-\(UUID()).mp4"))
        let wait = Task { @MainActor in try await AVPlayerEngine.waitUntilReady(item, timeout: .seconds(30)) }
        await Task.yield()
        wait.cancel()
        await #expect(throws: CancellationError.self) { try await wait.value }
    }

    // MARK: - Surround

    private static func engine(_ subtitles: RecordingSubtitles, source: FakeSurroundSource, enabled: Bool = true,
                               channels: Int = 6) -> AVPlayerEngine {
        AVPlayerEngine(subtitles: subtitles,
                       surround: SurroundPolicy(isEnabled: { enabled }, makeSource: { onFailure in source.adopt(onFailure) }),
                       outputChannels: { channels }, readyTimeout: .seconds(5))
    }

    @Test func loadUsesSurroundWhenEnabledOnASixChannelOutput() async throws {
        let subtitles = RecordingSubtitles(), source = FakeSurroundSource()
        let engine = Self.engine(subtitles, source: source)
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        #expect(subtitles.surroundFlags == [true] && source.startCount == 1)
        #expect(AudioOutput.lastObservedChannelCount == 6)
        engine.stop()
        #expect(source.stopCount == 1)
    }

    @Test(arguments: [(false, 6), (true, 2)])
    func loadSkipsSurroundWhenDisabledOrStereo(enabled: Bool, channels: Int) async throws {
        let subtitles = RecordingSubtitles(), source = FakeSurroundSource()
        let engine = Self.engine(subtitles, source: source, enabled: enabled, channels: channels)
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        #expect(subtitles.surroundFlags == [false] && source.startCount == 0)
        engine.stop()
    }

    @Test func loadPlaysOriginalAudioWhenTheSourceCannotStart() async throws {
        let subtitles = RecordingSubtitles(), source = FakeSurroundSource(startFails: true)
        let engine = Self.engine(subtitles, source: source)
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        #expect(subtitles.surroundFlags == [false])
        #expect(source.stopCount == 1)
        engine.stop()
    }

    @Test func aSecondLoadStopsTheFirstSource() async throws {
        let subtitles = RecordingSubtitles(), source = FakeSurroundSource()
        let engine = Self.engine(subtitles, source: source)
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        #expect(source.startCount == 2 && source.stopCount == 1 && subtitles.surroundFlags == [true, true])
        engine.stop()
    }

    @Test func stopWhileSurroundStartsLeavesThePlayerEmpty() async throws {
        let subtitles = RecordingSubtitles(), source = FakeSurroundSource(startDelay: .milliseconds(300))
        let engine = Self.engine(subtitles, source: source)
        let load = Task { try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil) }
        try await Self.waitUntil { source.startCount == 1 }
        engine.stop()
        await #expect(throws: CancellationError.self) { try await load.value }
        #expect(engine.player.currentItem == nil && subtitles.surroundFlags.isEmpty && source.stopCount == 1)
    }

    @Test func aLoadSupersededWhileSurroundStartsDoesNotReplaceTheNewerItem() async throws {
        let subtitles = RecordingSubtitles(), source = FakeSurroundSource(startDelay: .milliseconds(300))
        let engine = Self.engine(subtitles, source: source)
        let first = Task { try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil) }
        try await Self.waitUntil { source.startCount == 1 }
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        await #expect(throws: CancellationError.self) { try await first.value }
        // Only the newer load built an asset, and its item is the one playing.
        #expect(subtitles.surroundFlags == [true] && engine.player.currentItem?.status == .readyToPlay)
        engine.stop()
    }

    // MARK: - Multichannel audio option

    @Test(arguments: [(true, 2), (false, 2), (false, 6)])
    func audioSelectionIsUntouchedWithoutAMultichannelOption(enabled: Bool, channels: Int) async throws {
        let subtitles = RecordingSubtitles(), source = FakeSurroundSource()
        let engine = Self.engine(subtitles, source: source, enabled: enabled, channels: channels)
        let events = Self.collect(engine)
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        let item = try #require(engine.player.currentItem)
        if let group = try await item.asset.loadMediaSelectionGroup(for: .audible) {
            #expect(item.currentMediaSelection.selectedMediaOption(in: group) == group.defaultOption)
        }
        engine.stop()
        let received = await events.value
        #expect(!received.contains(.userInput) && !received.contains { if case .subtitleChanged = $0 { true } else { false } })
    }

    // MARK: - Surround failure

    @Test func aFailureDuringPlaybackEmitsSurroundFailedAndDisablesSurround() async throws {
        let subtitles = RecordingSubtitles(), source = FakeSurroundSource()
        let engine = Self.engine(subtitles, source: source)
        var events = engine.events.makeAsyncIterator()
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        source.reportFailure(.format)
        while let event = await events.next(), event != .surroundFailed {}
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        #expect(subtitles.surroundFlags == [true, false] && source.startCount == 1)
        engine.stop()
    }

    @Test func aFailureWhileLoadingRetriesTheSameLoadWithoutSurround() async throws {
        // The surround asset can never become ready (missing file); the source fails 100 ms into the load.
        let subtitles = RecordingSubtitles(surroundAssetURL: URL(fileURLWithPath: "/nonexistent-\(UUID()).mp4"))
        let source = FakeSurroundSource(failsAfterStart: .milliseconds(100))
        let engine = Self.engine(subtitles, source: source)
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil) // returns normally, once
        #expect(subtitles.surroundFlags == [true, false])
        engine.stop()
    }

    @Test func aFailureFromAnEarlierLoadIsIgnored() async throws {
        let subtitles = RecordingSubtitles(), source = FakeSurroundSource()
        let engine = Self.engine(subtitles, source: source)
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        let stale = source.onFailure
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        stale?(.format)
        try await Task.sleep(for: .milliseconds(100))
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        #expect(subtitles.surroundFlags == [true, true, true])
        engine.stop()
    }

    @Test func aFailureAfterStopIsIgnored() async throws {
        let subtitles = RecordingSubtitles(), source = FakeSurroundSource()
        let engine = Self.engine(subtitles, source: source)
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        engine.stop()
        source.reportFailure(.format)
        try await Task.sleep(for: .milliseconds(100))
        #expect(engine.player.currentItem == nil)
    }

    @Test func disableSurroundAppliesToTheNextLoad() async throws {
        let subtitles = RecordingSubtitles(), source = FakeSurroundSource()
        let engine = Self.engine(subtitles, source: source)
        engine.disableSurround()
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        #expect(subtitles.surroundFlags == [false])
        engine.stop()
    }

    @Test func aDeadServerOnReturnToTheForegroundIsASurroundFailure() async throws {
        let subtitles = RecordingSubtitles(), source = FakeSurroundSource(servesAfterWake: false)
        let engine = Self.engine(subtitles, source: source)
        var events = engine.events.makeAsyncIterator()
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        await engine.sceneBecameActive()
        while let event = await events.next(), event != .surroundFailed {}
        engine.stop()
    }

    @Test func anItemFailureWithSurroundIsASurroundFailureOnly() async throws {
        let subtitles = RecordingSubtitles(), source = FakeSurroundSource()
        let engine = Self.engine(subtitles, source: source)
        let events = Self.collect(engine)
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        Self.failCurrentItem(engine)
        try await Task.sleep(for: .milliseconds(100))
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        engine.stop()
        let received = await events.value
        #expect(received.filter { $0 == .surroundFailed }.count == 1 && !received.contains(.failed))
        #expect(subtitles.surroundFlags == [true, false] && source.startCount == 1 && source.stopCount == 1)
    }

    @Test func aSourceFailureThenAnItemFailureYieldOneSurroundFailure() async throws {
        let subtitles = RecordingSubtitles(), source = FakeSurroundSource()
        let engine = Self.engine(subtitles, source: source)
        let events = Self.collect(engine)
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        source.reportFailure(.format)
        try await Task.sleep(for: .milliseconds(100))
        Self.failCurrentItem(engine)
        try await Task.sleep(for: .milliseconds(100))
        engine.stop()
        let received = await events.value
        #expect(received.filter { $0 == .surroundFailed }.count == 1 && !received.contains(.failed))
    }

    @Test func aQueuedSecondFailureSignalFromTheAbandonedItemIsIgnored() async throws {
        let subtitles = RecordingSubtitles(), source = FakeSurroundSource()
        let engine = Self.engine(subtitles, source: source)
        let events = Self.collect(engine)
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        // The item's status KVO fired off the main thread, so its callback hops; the failure notification wins the race.
        let observation = try #require(engine.observedItem)
        Self.failCurrentItem(engine)
        engine.received(.failed, from: observation)
        engine.received(.ended, from: observation)
        try await Task.sleep(for: .milliseconds(100))
        engine.stop()
        let received = await events.value
        #expect(received.filter { $0 == .surroundFailed }.count == 1 && !received.contains(.failed))
        #expect(!received.contains(.ended))
    }

    @Test func anItemFailureWithoutSurroundIsAFailure() async throws {
        let subtitles = RecordingSubtitles(), source = FakeSurroundSource()
        let engine = Self.engine(subtitles, source: source, enabled: false)
        let events = Self.collect(engine)
        try await engine.load(Self.playback, startAt: 0, subtitleLanguage: nil)
        Self.failCurrentItem(engine)
        try await Task.sleep(for: .milliseconds(100))
        engine.stop()
        let received = await events.value
        #expect(received.contains(.failed) && !received.contains(.surroundFailed))
    }

    /// Every event `engine` yields until it stops.
    private static func collect(_ engine: AVPlayerEngine) -> Task<[PlayerEvent], Never> {
        let events = engine.events
        return Task { @MainActor in
            var received: [PlayerEvent] = []
            for await event in events { received.append(event) }
            return received
        }
    }

    /// Reports the current item as failed mid-playback, as AVFoundation does.
    private static func failCurrentItem(_ engine: AVPlayerEngine) {
        NotificationCenter.default.post(name: AVPlayerItem.failedToPlayToEndTimeNotification,
                                        object: engine.player.currentItem)
    }

    /// Polls `condition` on the main actor every 10 ms, for at most 5 s.
    private static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
