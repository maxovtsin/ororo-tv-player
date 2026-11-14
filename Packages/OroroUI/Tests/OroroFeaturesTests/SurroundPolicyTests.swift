@testable import OroroFeatures
import Testing

@Suite struct SurroundPolicyTests {
    @Test(arguments: [(2, false), (5, false), (6, true), (8, true)])
    func surroundNeedsSixOutputChannels(channels: Int, expected: Bool) {
        #expect(AudioOutput.supportsSurround(channels: channels) == expected)
    }

    @Test @MainActor func disabledPolicyIsNeverEnabled() async {
        #expect(await SurroundPolicy.disabled.isEnabled() == false)
    }
}
