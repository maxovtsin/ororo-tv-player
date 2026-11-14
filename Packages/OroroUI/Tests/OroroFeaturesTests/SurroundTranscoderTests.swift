import Foundation
import OroroCore
@testable import OroroFeatures
import OroroTestSupport
import Testing

@Suite struct SurroundTranscoderTests {
    private struct Pieces { var fixture: HLSAudioFixture; var fragments: [FragmentedMP4.AudioFragment]; var output: [[Data]] }

    /// Transcodes each segment on its own, with the neighbours the source would pass.
    private static func transcodeBySegment(seconds: Double, signal: SurroundDebugSignal? = nil) async throws -> Pieces {
        let fixture = try await HLSAudioFixture.make(seconds: seconds)
        let fragments = try fixture.segments.map(FragmentedMP4.parseAudioSegment)
        let transcoder = SurroundTranscoder(signal: signal)
        let output = try fragments.indices.map { index in
            try transcoder.transcode(
                previous: index > 0 ? Array(fragments[index - 1].packets.suffix(SurroundFormat.prerollPackets)) : [],
                current: fragments[index].packets,
                next: index + 1 < fragments.count ? Array(fragments[index + 1].packets.prefix(SurroundFormat.postrollPackets)) : [],
                startFrame: Int(fragments[index].baseDecodeTime))
        }
        return Pieces(fixture: fixture, fragments: fragments, output: output)
    }

    @Test func producesOnePacketPerInputPacket() async throws {
        let pieces = try await Self.transcodeBySegment(seconds: 8)
        #expect(pieces.fragments.count >= 3)
        #expect(pieces.output.map(\.count) == pieces.fragments.map(\.packets.count))
    }

    @Test func joinsAreNoWorseThanTheRestOfTheStream() async throws {
        let pieces = try await Self.transcodeBySegment(seconds: 8)
        let source = pieces.fragments.flatMap(\.packets)
        let stereo = try SurroundProbe.decode(packets: source, channels: 2)
        var upmixer = SurroundUpmixer()
        let truth = upmixer.process(left: stereo[0], right: stereo[1])
        let decoded = try SurroundProbe.decode(packets: pieces.output.flatMap { $0 }, channels: 6)
        let lag = SurroundFormat.outputLagFrames

        var boundaries: Set<Int> = [], block = 0
        for fragment in pieces.fragments.dropLast() {
            block += fragment.packets.count
            boundaries.formUnion(block - 2...block + 2)
        }
        for channel in [1, 3] { // left front, left surround
            let errors = SurroundProbe.packetErrors(Array(decoded[channel].dropFirst(lag)), truth.channels[channel])
            let interior = errors.indices.filter { $0 >= 3 && $0 < errors.count - 2 }
            let nearJoins = interior.filter(boundaries.contains).map { errors[$0] }.max() ?? 0
            let elsewhere = interior.filter { !boundaries.contains($0) }.map { errors[$0] }.max() ?? 0
            // Measured on this fixture: L 0.024 near joins vs 0.021 elsewhere, Ls 0.018 vs 0.015. The peaks are the fixture's
            // noise bursts, and one continuous encode gives the same values (≈ 0.021 elsewhere). A missing post-roll ≈ 0.15.
            #expect(nearJoins <= 1.25 * elsewhere)
            #expect(elsewhere < 0.05)
        }
    }

    @Test func outputLagsTheSourceByExactlyTheEncoderRemainder() async throws {
        let pieces = try await Self.transcodeBySegment(seconds: 4)
        let stereo = try SurroundProbe.decode(packets: pieces.fragments.flatMap(\.packets), channels: 2)
        let decoded = try SurroundProbe.decode(packets: pieces.output.flatMap { $0 }, channels: 6)
        let lag = SurroundProbe.bestLag(of: decoded[1], against: stereo[0], maxLag: 4800)
        #expect((0...128).contains(lag)) // 64 expected; an off-by-one packet would be ±1024 or more
    }

    @Test func everyChannelKeepsItsPlaceThroughEncodingAndTheContainer() async throws {
        let pieces = try await Self.transcodeBySegment(seconds: 13, signal: .speakerTest)
        let initSegment = try FragmentedMP4.surroundInitSegment(from: pieces.fixture.initSegment)
        let segments = zip(pieces.fragments, pieces.output).enumerated().map { index, pair in
            var fragment = pair.0
            fragment.packets = pair.1
            return FragmentedMP4.buildAudioSegment(sequence: UInt32(index + 1), fragment: fragment)
        }
        let channels = try await SurroundProbe.readContainer(initSegment: initSegment, segments: segments)
        #expect(channels.count == 6)
        for slot in 0..<6 {
            // 30–90 ms into the slot's first beep, in reader time (2112-frame trim, 64-frame lag: the beep spans −43…107 ms).
            let window = slot * 96_000 + 1_440..<slot * 96_000 + 4_320
            for channel in 0..<6 {
                let level = (channels[channel][window].reduce(0) { $0 + $1 * $1 } / Float(window.count)).squareRoot()
                #expect(channel == slot ? level > 0.05 : level < 0.01)
            }
        }
    }

    @Test func shortSegmentsAndShortNeighboursKeepTheirPacketCount() async throws {
        let packets = try FragmentedMP4.parseAudioSegment(try await HLSAudioFixture.make(seconds: 2).segments[0]).packets
        let transcoder = SurroundTranscoder()
        #expect(try transcoder.transcode(previous: [], current: [packets[0]], next: [], startFrame: 0).count == 1)
        #expect(try transcoder.transcode(
            previous: Array(packets[0..<2]), current: Array(packets[2..<4]), next: [packets[4]], startFrame: 2048).count == 2)
        #expect(try transcoder.transcode(
            previous: Array(packets[0..<4]), current: Array(packets[4..<7]), next: [], startFrame: 4096).count == 3)
        #expect(try transcoder.transcode(previous: [], current: [], next: [], startFrame: 0).isEmpty)
    }

    @Test func garbageInputDoesNotCrash() {
        let garbage = [Data(repeating: 0xAB, count: 300)]
        // The decoder may reject it or conceal it; either way the call returns.
        let result = Result { try SurroundTranscoder().transcode(previous: [], current: garbage, next: [], startFrame: 0) }
        if case .success(let packets) = result { #expect(packets.count == 1) }
    }
}
