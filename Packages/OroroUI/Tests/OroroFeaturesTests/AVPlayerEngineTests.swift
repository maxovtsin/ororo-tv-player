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
}
