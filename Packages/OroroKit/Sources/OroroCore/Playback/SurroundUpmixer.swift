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
///
/// A fixed, short-memory matrix:
/// - C = ½(L + R); the fronts keep L − ½C and R − ½C, so a centred voice is anchored in the centre.
/// - Ls/Rs carry the side signal ½(L − R), band-limited to 100 Hz – 7 kHz, delayed 12 ms, at −3 dB,
///   and decorrelated by two different first-order all-passes (Rs inverted).
/// - LFE is a quiet (`SurroundFormat.lfeGain`) 120 Hz low-pass of the mid signal; the receiver's bass management does the rest.
///
/// Every filter forgets its input well within 3072 frames, which segment pre-roll relies on.
public struct SurroundUpmixer: Sendable {
    private var surroundHighPass: Biquad
    private var surroundLowPass: (Biquad, Biquad)
    private var lfeLowPass: (Biquad, Biquad)
    private var leftAllPass = FirstOrderAllPass(coefficient: 0.5)
    private var rightAllPass = FirstOrderAllPass(coefficient: -0.5)
    private var delayLine: [Float]
    private var delayIndex = 0

    private static let surroundGain: Float = 0.707_106_8
    private static let surroundDelay = 0.012

    public init(sampleRate: Double = SurroundFormat.sampleRate) {
        // A 4th-order Butterworth is two biquads with these Qs.
        let butterworth4 = (0.541_196_1, 1.306_563)
        surroundHighPass = Biquad(highPass: 100, q: 0.5.squareRoot(), sampleRate: sampleRate)
        surroundLowPass = (
            Biquad(lowPass: 7000, q: butterworth4.0, sampleRate: sampleRate),
            Biquad(lowPass: 7000, q: butterworth4.1, sampleRate: sampleRate)
        )
        lfeLowPass = (
            Biquad(lowPass: 120, q: butterworth4.0, sampleRate: sampleRate),
            Biquad(lowPass: 120, q: butterworth4.1, sampleRate: sampleRate)
        )
        delayLine = [Float](repeating: 0, count: max(1, Int((Self.surroundDelay * sampleRate).rounded())))
    }

    public mutating func process(left: [Float], right: [Float]) -> SurroundFrames {
        let count = min(left.count, right.count)
        var frames = SurroundFrames(silence: count)
        let delayLength = delayLine.count
        for index in 0..<count {
            let center = 0.5 * (left[index] + right[index])
            let side = 0.5 * (Double(left[index]) - Double(right[index]))
            frames.center[index] = center
            frames.left[index] = left[index] - 0.5 * center
            frames.right[index] = right[index] - 0.5 * center

            let band = surroundLowPass.1.process(surroundLowPass.0.process(surroundHighPass.process(side)))
            let delayed = delayLine[delayIndex]
            delayLine[delayIndex] = Float(band) * Self.surroundGain
            delayIndex += 1
            if delayIndex == delayLength { delayIndex = 0 }
            frames.leftSurround[index] = leftAllPass.process(delayed)
            frames.rightSurround[index] = -rightAllPass.process(delayed)

            let bass = lfeLowPass.1.process(lfeLowPass.0.process(Double(center)))
            frames.lfe[index] = SurroundFormat.lfeGain * Float(bass)
        }
        return frames
    }
}

/// RBJ-cookbook biquad in transposed direct form II, computed in Double so low cut-offs stay accurate.
private struct Biquad: Sendable {
    private let b0, b1, b2, a1, a2: Double
    private var z1 = 0.0, z2 = 0.0

    init(lowPass frequency: Double, q: Double, sampleRate: Double) {
        let (cosine, alpha) = Self.prewarp(frequency, q, sampleRate)
        let a0 = 1 + alpha
        b0 = (1 - cosine) / 2 / a0
        b1 = (1 - cosine) / a0
        b2 = b0
        a1 = -2 * cosine / a0
        a2 = (1 - alpha) / a0
    }

    init(highPass frequency: Double, q: Double, sampleRate: Double) {
        let (cosine, alpha) = Self.prewarp(frequency, q, sampleRate)
        let a0 = 1 + alpha
        b0 = (1 + cosine) / 2 / a0
        b1 = -(1 + cosine) / a0
        b2 = b0
        a1 = -2 * cosine / a0
        a2 = (1 - alpha) / a0
    }

    private static func prewarp(_ frequency: Double, _ q: Double, _ sampleRate: Double) -> (cosine: Double, alpha: Double) {
        let omega = 2 * Double.pi * frequency / sampleRate
        return (cos(omega), sin(omega) / (2 * q))
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}

/// H(z) = (c + z⁻¹) / (1 + c·z⁻¹): flat magnitude, frequency-dependent phase.
private struct FirstOrderAllPass: Sendable {
    let coefficient: Float
    private var previousInput: Float = 0
    private var previousOutput: Float = 0

    init(coefficient: Float) { self.coefficient = coefficient }

    mutating func process(_ x: Float) -> Float {
        let y = coefficient * x + previousInput - coefficient * previousOutput
        previousInput = x
        previousOutput = y
        return y
    }
}
