import Foundation

/// Test signals for checking channel order and segment joins on real hardware. Each is a pure function of the absolute frame index.
public enum SurroundDebugSignal: String, Sendable, CaseIterable {
    /// A 12 s cycle of six 2 s slots (C, L, R, Ls, Rs, LFE); slot k beeps k + 1 times on channel k only.
    case speakerTest
    /// 440 Hz in left and right, everything else silent.
    case steadyTone

    private static let amplitude = 0.25
    private static let slotFrames = 96_000
    private static let beepFrames = 7_200
    private static let beepPeriodFrames = 14_400
    private static let fadeFrames = 240

    /// Frames below 0 are silence.
    public func frames(startFrame: Int, count: Int) -> SurroundFrames {
        var frames = SurroundFrames(silence: count)
        for index in 0..<count {
            let frame = startFrame + index
            guard frame >= 0 else { continue }
            switch self {
            case .speakerTest:
                let slot = (frame / Self.slotFrames) % SurroundFormat.channelCount
                let value = Self.beep(slot: slot, frame: frame % Self.slotFrames)
                switch slot {
                case 0: frames.center[index] = value
                case 1: frames.left[index] = value
                case 2: frames.right[index] = value
                case 3: frames.leftSurround[index] = value
                case 4: frames.rightSurround[index] = value
                default: frames.lfe[index] = value
                }
            case .steadyTone:
                let value = Float(Self.amplitude * sin(2 * Double.pi * 440 * Double(frame) / SurroundFormat.sampleRate))
                frames.left[index] = value
                frames.right[index] = value
            }
        }
        return frames
    }

    private static func beep(slot: Int, frame: Int) -> Float {
        let beepIndex = frame / beepPeriodFrames
        let position = frame % beepPeriodFrames
        guard beepIndex <= slot, position < beepFrames else { return 0 }
        let fade = Double(min(position + 1, beepFrames - position, fadeFrames)) / Double(fadeFrames)
        let hertz = slot == 5 ? 60.0 : 1_000.0
        return Float(amplitude * fade * sin(2 * Double.pi * hertz * Double(frame) / SurroundFormat.sampleRate))
    }
}
