import Foundation
import Testing
@testable import OroroCore

@Suite struct SurroundDebugSignalTests {
    private static func rms(_ x: [Float], _ range: Range<Int>) -> Float {
        (x[range].reduce(0) { $0 + $1 * $1 } / Float(range.count)).squareRoot()
    }

    @Test(arguments: 0..<6)
    func speakerTestSoundsOneChannelPerSlot(slot: Int) {
        let frames = SurroundDebugSignal.speakerTest.frames(startFrame: 0, count: 12 * 48_000)
        let firstBeep = slot * 96_000 + 960..<slot * 96_000 + 6_240 // 20–130 ms into the slot
        for channel in 0..<6 {
            let level = Self.rms(frames.channels[channel], firstBeep)
            #expect(channel == slot ? level > 0.1 : level == 0)
        }
    }

    @Test func speakerTestBeepCountIdentifiesTheChannel() {
        // Slot 3 (rear left) has 4 beeps: sound in the 4th beep window (900–1050 ms), silence where a 5th would be (1200–1350 ms).
        let frames = SurroundDebugSignal.speakerTest.frames(startFrame: 3 * 96_000, count: 96_000)
        #expect(Self.rms(frames.leftSurround, 44_160..<49_440) > 0.1)
        #expect(Self.rms(frames.leftSurround, 58_560..<63_840) == 0)
    }

    @Test(arguments: SurroundDebugSignal.allCases)
    func signalIsAFunctionOfTheAbsoluteFrame(signal: SurroundDebugSignal) {
        let whole = signal.frames(startFrame: 5_000, count: 4_096)
        let first = signal.frames(startFrame: 5_000, count: 1_000), second = signal.frames(startFrame: 6_000, count: 3_096)
        for channel in 0..<6 { #expect(first.channels[channel] + second.channels[channel] == whole.channels[channel]) }
    }

    @Test func steadyToneIsContinuousInTheFrontsOnly() {
        let frames = SurroundDebugSignal.steadyTone.frames(startFrame: 0, count: 48_000)
        #expect(Self.rms(frames.left, 0..<48_000) > 0.15 && frames.left == frames.right)
        #expect(frames.center.allSatisfy { $0 == 0 } && frames.leftSurround.allSatisfy { $0 == 0 } && frames.lfe.allSatisfy { $0 == 0 })
    }

    @Test func framesBeforeTheStartOfTheTitleAreSilent() {
        for signal in SurroundDebugSignal.allCases {
            let frames = signal.frames(startFrame: -2_000, count: 2_000)
            #expect(frames.channels.allSatisfy { $0.count == 2_000 && $0.allSatisfy { $0 == 0 } })
        }
    }
}
