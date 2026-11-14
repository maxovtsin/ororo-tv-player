import Foundation
@testable import OroroFeatures
import OroroCore
import Testing

@Suite struct SurroundPolicyTests {
    @Test(arguments: [(2, false), (5, false), (6, true), (8, true)])
    func surroundNeedsSixOutputChannels(channels: Int, expected: Bool) {
        #expect(AudioOutput.supportsSurround(channels: channels) == expected)
    }

    @Test @MainActor func disabledPolicyIsNeverEnabled() async {
        #expect(await SurroundPolicy.disabled.isEnabled() == false)
    }

    @Test func debugSignalComesFromDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "surround-debug-\(UUID())"))
        #expect(SurroundDebug.signal(in: defaults) == nil)
        defaults.set("speakerTest", forKey: SurroundDebug.defaultsKey)
        #expect(SurroundDebug.signal(in: defaults) == .speakerTest)
        defaults.set("nonsense", forKey: SurroundDebug.defaultsKey)
        #expect(SurroundDebug.signal(in: defaults) == nil)
    }
}
