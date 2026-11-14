import Foundation
import Testing
@testable import OroroCore

@Suite struct SurroundUpmixerTests {
    static func sine(_ hz: Double, count: Int = 48_000, amplitude: Float = 0.5) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * hz * Double($0) / 48_000)) }
    }
    static func rms(_ x: ArraySlice<Float>) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))).squareRoot() }

    @Test func outputLengthMatchesInputAcrossChunks() {
        var upmixer = SurroundUpmixer()
        for size in [1, 7, 1024, 5000] {
            let frames = upmixer.process(left: Self.sine(440, count: size), right: Self.sine(550, count: size))
            #expect(frames.channels.allSatisfy { $0.count == size })
        }
    }

    @Test func chunkingDoesNotChangeTheResult() {
        let left = Self.sine(440), right = Self.sine(660)
        var whole = SurroundUpmixer(), pieces = SurroundUpmixer()
        let expected = whole.process(left: left, right: right)
        var joined = [[Float]](repeating: [], count: 6)
        for start in stride(from: 0, to: left.count, by: 1000) {
            let end = min(start + 1000, left.count)
            let part = pieces.process(left: Array(left[start..<end]), right: Array(right[start..<end]))
            for channel in 0..<6 { joined[channel] += part.channels[channel] }
        }
        #expect(joined == expected.channels)
    }

    @Test func monoContentGoesToTheCentreNotTheSurrounds() {
        var upmixer = SurroundUpmixer()
        let voice = Self.sine(1000)
        let frames = upmixer.process(left: voice, right: voice)
        #expect(Self.rms(frames.center[24_000...]) > 0.1)
        #expect(Self.rms(frames.leftSurround[24_000...]) < 0.01 && Self.rms(frames.rightSurround[24_000...]) < 0.01)
    }

    @Test func outOfPhaseContentReachesBothSurrounds() {
        var upmixer = SurroundUpmixer()
        let wide = Self.sine(1000)
        let frames = upmixer.process(left: wide, right: wide.map { -$0 })
        #expect(Self.rms(frames.leftSurround[24_000...]) > 0.05 && Self.rms(frames.rightSurround[24_000...]) > 0.05)
        #expect(Self.rms(frames.center[24_000...]) < 0.01)
    }

    @Test func subwooferChannelIsQuietBassOnly() {
        var bass = SurroundUpmixer(), treble = SurroundUpmixer()
        let low = bass.process(left: Self.sine(50), right: Self.sine(50))
        let high = treble.process(left: Self.sine(2000), right: Self.sine(2000))
        #expect(Self.rms(low.lfe[24_000...]) > 10 * Self.rms(high.lfe[24_000...]))
        // −20 dB: the receiver's bass management, not this channel, feeds the subwoofer.
        #expect(Self.rms(low.lfe[24_000...]) < 0.15 * Self.rms(Self.sine(50)[24_000...]))
        #expect(Self.rms(low.lfe[24_000...]) > 0.02 * Self.rms(Self.sine(50)[24_000...]))
    }

    private static func noise(seed: UInt64, count: Int = 48_000, amplitude: Float = 0.3) -> [Float] {
        var state = seed
        return (0..<count).map { _ in
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return amplitude * (Float((z ^ (z >> 31)) >> 40) / Float(1 << 23) - 1)
        }
    }
    private static func power(_ channels: [[Float]], from start: Int = 4096) -> Float {
        channels.reduce(0) { $0 + $1[start...].reduce(0) { $0 + $1 * $1 } }
    }
    private static func correlation(_ a: ArraySlice<Float>, _ b: ArraySlice<Float>) -> Float {
        let dot = zip(a, b).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        return dot / (a.reduce(0) { $0 + $1 * $1 } * b.reduce(0) { $0 + $1 * $1 }).squareRoot()
    }

    @Test(arguments: [(1 as UInt64, 1 as UInt64), (1, 2)]) // identical channels (centred) and independent channels (wide)
    func loudnessStaysCloseToTheStereoInput(leftSeed: UInt64, rightSeed: UInt64) {
        var upmixer = SurroundUpmixer()
        let left = Self.noise(seed: leftSeed), right = Self.noise(seed: rightSeed)
        let frames = upmixer.process(left: left, right: right)
        let ratio = 10 * log10(Self.power(Array(frames.channels.prefix(5))) / Self.power([left, right]))
        #expect(abs(ratio) <= 2)
    }

    @Test func centredVoiceIsLouderInTheCentreThanInTheFronts() {
        var upmixer = SurroundUpmixer()
        let voice = Self.sine(1000)
        let frames = upmixer.process(left: voice, right: voice)
        #expect(Self.rms(frames.center[24_000...]) > 1.5 * Self.rms(frames.left[24_000...]))
        #expect(Self.rms(frames.center[24_000...]) > 1.5 * Self.rms(frames.right[24_000...]))
    }

    @Test func hardPannedSoundStaysInItsFrontSpeaker() {
        var upmixer = SurroundUpmixer()
        let frames = upmixer.process(left: Self.sine(1000), right: [Float](repeating: 0, count: 48_000))
        #expect(Self.rms(frames.left[24_000...]) > 2 * Self.rms(frames.right[24_000...]))
        #expect(Self.rms(frames.left[24_000...]) > Self.rms(frames.center[24_000...]))
    }

    @Test func surroundsAreDelayed() {
        var upmixer = SurroundUpmixer()
        var impulse = [Float](repeating: 0, count: 4096)
        impulse[0] = 1
        let frames = upmixer.process(left: impulse, right: [Float](repeating: 0, count: 4096))
        #expect(frames.leftSurround[..<480].allSatisfy { abs($0) < 1e-4 })   // nothing in the first 10 ms
        #expect(frames.leftSurround[480..<1200].contains { abs($0) > 0.01 }) // arrives by 25 ms
    }

    @Test func surroundsAreBandLimited() {
        func level(_ hz: Double) -> Float {
            var upmixer = SurroundUpmixer()
            let tone = Self.sine(hz)
            return Self.rms(upmixer.process(left: tone, right: tone.map { -$0 }).leftSurround[24_000...])
        }
        #expect(level(14_000) < 0.1 * level(1000)) // 4th-order low-pass at 7 kHz is about −24 dB an octave up
        #expect(level(40) < 0.3 * level(1000))     // 2nd-order high-pass at 100 Hz is about −16 dB at 40 Hz
    }

    @Test func surroundsAreDecorrelatedFromEachOther() {
        var upmixer = SurroundUpmixer()
        let wide = Self.noise(seed: 3)
        let frames = upmixer.process(left: wide, right: wide.map { -$0 })
        #expect(abs(Self.correlation(frames.leftSurround[4096...], frames.rightSurround[4096...])) < 0.9)
    }

    @Test func stateIsShortLived() {
        var upmixer = SurroundUpmixer()
        _ = upmixer.process(left: Self.noise(seed: 4), right: Self.noise(seed: 5))
        let tail = upmixer.process(left: [Float](repeating: 0, count: 8192), right: [Float](repeating: 0, count: 8192))
        #expect(tail.channels.allSatisfy { $0[3072...].allSatisfy { abs($0) < 1e-4 } })
    }
}
