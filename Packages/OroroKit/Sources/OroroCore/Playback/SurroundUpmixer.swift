import Foundation

/// Six planar channels of audio, in the order C, L, R, Ls, Rs, LFE.
public struct SurroundFrames: Equatable, Sendable {
    public var center: [Float]
    public var left: [Float]
    public var right: [Float]
    public var leftSurround: [Float]
    public var rightSurround: [Float]
    public var lfe: [Float]

    public init(silence count: Int) {
        let zeros = [Float](repeating: 0, count: count)
        center = zeros
        left = zeros
        right = zeros
        leftSurround = zeros
        rightSurround = zeros
        lfe = zeros
    }

    /// The channels in layout order: C, L, R, Ls, Rs, LFE.
    public var channels: [[Float]] { [center, left, right, leftSurround, rightSurround, lfe] }

    public var count: Int { center.count }
}

/// Streaming stereo → 5.1 upmixer. State carries between calls, and the output never depends on how the input is chunked.
/// The matrix is a deliberately crude placeholder; only the body of `process` is expected to change.
public struct SurroundUpmixer: Sendable {
    private let lowPassCoefficient: Float
    private var lowPassState: Float = 0

    public init(sampleRate: Double = SurroundFormat.sampleRate) {
        lowPassCoefficient = Float(1 - exp(-2 * Double.pi * 120 / sampleRate))
    }

    public mutating func process(left: [Float], right: [Float]) -> SurroundFrames {
        let count = min(left.count, right.count)
        var frames = SurroundFrames(silence: count)
        for index in 0..<count {
            let mid = 0.5 * (left[index] + right[index])
            let side = 0.5 * (left[index] - right[index])
            lowPassState += lowPassCoefficient * (mid - lowPassState)
            frames.center[index] = mid
            frames.left[index] = left[index]
            frames.right[index] = right[index]
            frames.leftSurround[index] = side
            frames.rightSurround[index] = -side
            frames.lfe[index] = SurroundFormat.lfeGain * lowPassState
        }
        return frames
    }
}
