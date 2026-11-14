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
}
