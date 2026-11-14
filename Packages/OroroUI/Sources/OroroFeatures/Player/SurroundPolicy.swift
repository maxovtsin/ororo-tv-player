import AVFoundation
import OroroCore

/// What the current audio route can play.
public enum AudioOutput {
    /// 5.1: the fewest output channels that make simulated surround worthwhile.
    public static let surroundChannelCount = 6

    /// The route's maximum output channel count (2 for TV speakers, 6 or 8 for a surround receiver over HDMI).
    @MainActor public static func channelCount() -> Int {
        AVAudioSession.sharedInstance().maximumOutputNumberOfChannels
    }

    public static func supportsSurround(channels: Int) -> Bool {
        channels >= surroundChannelCount
    }

    /// The channel count the player saw on its latest load (memory only; `nil` before the first load).
    @MainActor public static var lastObservedChannelCount: Int?
}

/// Debug-only test signal that replaces the upmix. Always off in release builds.
enum SurroundDebug {
    static let defaultsKey = "debug.surroundSignal"

    static func signal(in defaults: UserDefaults = .standard) -> SurroundDebugSignal? {
        #if DEBUG
        defaults.string(forKey: defaultsKey).flatMap(SurroundDebugSignal.init(rawValue:))
        #else
        nil
        #endif
    }
}

/// Whether, and with which source, the player plays simulated 5.1 for a title.
struct SurroundPolicy: Sendable {
    /// The user's preference.
    var isEnabled: @MainActor @Sendable () async -> Bool
    /// A fresh source for one load; `onFailure` is called if it gives up after playback started.
    var makeSource: @MainActor @Sendable (_ onFailure: @escaping @Sendable (SurroundFailure) -> Void) -> any SurroundSource

    /// Never plays surround.
    static let disabled = SurroundPolicy(isEnabled: { false }, makeSource: { _ in UnavailableSurroundSource() })

    /// Generates 5.1 with `SurroundAudioSource` when `isEnabled` says so. tvOS only: elsewhere it is `.disabled`.
    static func live(isEnabled: @escaping @MainActor @Sendable () async -> Bool) -> SurroundPolicy {
        #if os(tvOS)
        SurroundPolicy(isEnabled: isEnabled, makeSource: { onFailure in SurroundAudioSource(
                transcode: SurroundAudioSource.liveTranscode(signal: SurroundDebug.signal()),
                onFailure: onFailure
            )
        })
        #else
        .disabled
        #endif
    }
}

/// The source of `SurroundPolicy.disabled`: never starts.
private struct UnavailableSurroundSource: SurroundSource {
    private struct Unavailable: Error {}

    func start() async throws -> URL { throw Unavailable() }
    func author(multivariant: String) async -> String? { nil }
    func ensureServing() async -> Bool { false }
    func stop() {}
}
