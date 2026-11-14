import AVFoundation
import Foundation
@testable import OroroFeatures
import Testing

/// `AVPlayerEngine.waitUntilReady` against real `AVPlayerItem`s (KVO-driven, never Combine `.values`).
@Suite @MainActor struct AVPlayerEngineTests {
    @Test func becomesReadyForAPlayableItem() async throws {
        let item = AVPlayerItem(url: try Self.silentWAV())
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

    /// A 0.5 s mono 8 kHz 16-bit silent WAV in the temporary directory.
    private static func silentWAV() throws -> URL {
        let sampleRate: UInt32 = 8_000, samples = 4_000
        let dataSize = UInt32(samples * 2)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(sampleRate); append(sampleRate * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(dataSize)
        data.append(Data(count: Int(dataSize)))
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "silence-\(UUID()).wav")
        try data.write(to: url)
        return url
    }
}
