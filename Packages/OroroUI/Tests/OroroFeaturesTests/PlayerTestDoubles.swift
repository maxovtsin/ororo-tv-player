import AVFoundation
import AVKit
import Foundation
import OroroCore
@testable import OroroFeatures
import Synchronization

/// Small local media files for player tests.
enum TestMedia {
    /// A 0.5 s mono 8 kHz 16-bit silent WAV in the temporary directory.
    static func silentWAV() throws -> URL {
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

/// A `SubtitleProvider` that records whether each `makeAsset` call carried a surround source.
@MainActor final class RecordingSubtitles: SubtitleProvider {
    private(set) var surroundFlags: [Bool] = []
    private let surroundAssetURL: URL?

    /// - Parameter surroundAssetURL: served when `makeAsset` gets a source; otherwise (and by default) a silent WAV.
    init(surroundAssetURL: URL? = nil) {
        self.surroundAssetURL = surroundAssetURL
    }

    func makeAsset(for playback: Playback, preferredLanguage: String?, surround: (any SurroundSource)?) -> AVURLAsset {
        surroundFlags.append(surround != nil)
        if surround != nil, let surroundAssetURL { return AVURLAsset(url: surroundAssetURL) }
        // A temporary-directory write; failing it means the test host is broken.
        // swiftlint:disable:next force_try
        return AVURLAsset(url: try! TestMedia.silentWAV())
    }

    func attach(to controller: AVPlayerViewController, engine: AVPlayerEngine) {}
}

/// A `SurroundSource` that serves nothing: counts `start`/`stop`, fails on request and reports failures on demand.
final class FakeSurroundSource: SurroundSource {
    private struct State {
        var startCount = 0
        var stopCount = 0
        var onFailure: (@Sendable (SurroundFailure) -> Void)?
    }

    private struct StartFailed: Error {}

    private let state = Mutex(State())
    private let startFails: Bool
    private let servesAfterWake: Bool
    private let failsAfterStart: Duration?

    init(startFails: Bool = false, servesAfterWake: Bool = true, failsAfterStart: Duration? = nil) {
        self.startFails = startFails
        self.servesAfterWake = servesAfterWake
        self.failsAfterStart = failsAfterStart
    }

    var startCount: Int { state.withLock { $0.startCount } }
    var stopCount: Int { state.withLock { $0.stopCount } }
    var onFailure: (@Sendable (SurroundFailure) -> Void)? { state.withLock { $0.onFailure } }

    /// Keeps the engine's failure handler (as `SurroundPolicy.makeSource` would pass it) and returns `self`.
    func adopt(_ onFailure: @escaping @Sendable (SurroundFailure) -> Void) -> FakeSurroundSource {
        state.withLock { $0.onFailure = onFailure }
        return self
    }

    /// Calls the adopted failure handler, as a real source does when it gives up mid-playback.
    func reportFailure(_ failure: SurroundFailure) {
        onFailure?(failure)
    }

    func start() async throws -> URL {
        state.withLock { $0.startCount += 1 }
        if startFails { throw StartFailed() }
        if let failsAfterStart {
            Task { [self] in
                try? await Task.sleep(for: failsAfterStart)
                reportFailure(.format)
            }
        }
        return URL(string: "http://127.0.0.1:9/")!
    }

    func author(multivariant: String) async -> String? {
        multivariant
    }

    func ensureServing() async -> Bool {
        servesAfterWake
    }

    func stop() {
        state.withLock { $0.stopCount += 1 }
    }
}
