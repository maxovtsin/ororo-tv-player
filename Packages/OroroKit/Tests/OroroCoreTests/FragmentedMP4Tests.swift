import Foundation
import OroroTestSupport
import Testing
@testable import OroroCore

@Suite struct FragmentedMP4Tests {
    @Test func parsesEveryAACFrameOfASegment() async throws {
        let fixture = try await HLSAudioFixture.make(seconds: 6)
        let fragments = try fixture.segments.map(FragmentedMP4.parseAudioSegment)
        #expect(fragments.count >= 2)
        #expect(fragments.allSatisfy { !$0.packets.isEmpty })
        for (previous, next) in zip(fragments, fragments.dropFirst()) {
            #expect(next.baseDecodeTime == previous.baseDecodeTime + UInt64(previous.packets.count) * 1024)
        }
    }

    @Test func rebuiltSegmentParsesBackIdentically() async throws {
        let fragment = try FragmentedMP4.parseAudioSegment(try await HLSAudioFixture.make(seconds: 2).segments[0])
        let rebuilt = FragmentedMP4.buildAudioSegment(sequence: 7, fragment: fragment)
        #expect(try FragmentedMP4.parseAudioSegment(rebuilt) == fragment)
    }

    @Test func parsesSeveralMovieFragmentsAndPerSampleFields() throws {
        // Hand-built: moof+mdat twice; first trun has per-sample duration+size (flags 0x301), second uses tfhd defaults.
        let segment = HandBuilt.segment(fragments: [
            .init(baseTime: 4096, sizes: [3, 5], perSampleDurations: true),
            .init(baseTime: 6144, sizes: [4], perSampleDurations: false)
        ])
        let parsed = try FragmentedMP4.parseAudioSegment(segment)
        #expect(parsed.baseDecodeTime == 4096 && parsed.trackID == 1)
        #expect(parsed.packets.map(\.count) == [3, 5, 4])
    }

    @Test func rejectsFramesThatAreNot1024Samples() {
        let heAAC = HandBuilt.segment(fragments: [.init(baseTime: 0, sizes: [3, 5], perSampleDurations: true, duration: 2048)])
        #expect(throws: FragmentedMP4.Failure.unsupported) { try FragmentedMP4.parseAudioSegment(heAAC) }
    }

    @Test func surroundInitDeclaresSixChannels() async throws {
        let fixture = try await HLSAudioFixture.make(seconds: 2)
        let patched = try FragmentedMP4.surroundInitSegment(from: fixture.initSegment)
        #expect(patched.count == fixture.initSegment.count)
        #expect(try HandBuilt.channelCount(ofInit: patched) == 6)
        #expect(try HandBuilt.channelConfiguration(ofInit: patched) == 6)
    }

    @Test func rejectsWhatItCannotUpmix() async throws {
        let mono = try await HLSAudioFixture.make(seconds: 2, channels: 1)
        #expect(throws: FragmentedMP4.Failure.unsupported) { try FragmentedMP4.surroundInitSegment(from: mono.initSegment) }
        let slow = try await HLSAudioFixture.make(seconds: 2, sampleRate: 44_100)
        #expect(throws: FragmentedMP4.Failure.unsupported) { try FragmentedMP4.surroundInitSegment(from: slow.initSegment) }
        let good = try await HLSAudioFixture.make(seconds: 2).initSegment
        #expect(throws: FragmentedMP4.Failure.unsupported) {
            try FragmentedMP4.surroundInitSegment(from: HandBuilt.replacingFourCC("mp4a", with: "enca", in: good))
        }
        #expect(throws: FragmentedMP4.Failure.unsupported) {
            try FragmentedMP4.surroundInitSegment(from: HandBuilt.replacingFourCC("mp4a", with: "ec-3", in: good))
        }
        #expect(throws: FragmentedMP4.Failure.malformed) { try FragmentedMP4.parseAudioSegment(Data([0, 0, 0, 8, 0x6D, 0x6F])) }
        #expect(throws: FragmentedMP4.Failure.malformed) { try FragmentedMP4.surroundInitSegment(from: Data(repeating: 0, count: 64)) }
    }
}

/// Fixtures built byte by byte, and readers that deliberately share no code with `FragmentedMP4`.
private enum HandBuilt {
    struct Spec {
        var baseTime: UInt64
        var sizes: [Int]
        var perSampleDurations: Bool
        var duration: UInt32 = 1024
    }

    struct Missing: Error {}

    /// One `moof`+`mdat` pair per spec, track 1. Per-sample specs use `trun` flags 0x301 and a version 1 `tfdt`;
    /// the others put duration and size (the first of `sizes`) in `tfhd` and use a version 0 `tfdt`.
    static func segment(fragments: [Spec]) -> Data {
        var segment = Data()
        for (index, spec) in fragments.enumerated() {
            let mfhd = MP4Bytes.box("mfhd", MP4Bytes.be32(0) + MP4Bytes.be32(UInt32(index + 1)))
            let tfhd: Data, tfdt: Data, trunFlags: UInt32, perSample: Data
            if spec.perSampleDurations {
                tfhd = MP4Bytes.box("tfhd", MP4Bytes.be32(0x02_0000) + MP4Bytes.be32(1))
                tfdt = MP4Bytes.box("tfdt", MP4Bytes.be32(0x0100_0000) + MP4Bytes.be64(spec.baseTime))
                trunFlags = 0x301
                perSample = spec.sizes.reduce(into: Data()) { $0 += MP4Bytes.be32(spec.duration) + MP4Bytes.be32(UInt32($1)) }
            } else {
                let defaults = MP4Bytes.be32(spec.duration) + MP4Bytes.be32(UInt32(spec.sizes[0]))
                tfhd = MP4Bytes.box("tfhd", MP4Bytes.be32(0x02_0018) + MP4Bytes.be32(1) + defaults)
                tfdt = MP4Bytes.box("tfdt", MP4Bytes.be32(0) + MP4Bytes.be32(UInt32(spec.baseTime)))
                trunFlags = 0x001
                perSample = Data()
            }
            let trunSize = 8 + 12 + perSample.count
            let moofSize = 8 + mfhd.count + 8 + tfhd.count + tfdt.count + trunSize
            let trun = MP4Bytes.box(
                "trun",
                MP4Bytes.be32(trunFlags) + MP4Bytes.be32(UInt32(spec.sizes.count)) + MP4Bytes.be32(UInt32(moofSize + 8)) + perSample
            )
            let payload = spec.sizes.enumerated().reduce(into: Data()) { $0 += Data(repeating: UInt8($1.offset), count: $1.element) }
            segment += MP4Bytes.box("moof", mfhd + MP4Bytes.box("traf", tfhd + tfdt + trun)) + MP4Bytes.box("mdat", payload)
        }
        return segment
    }

    /// The `mp4a` sample entry's channel count.
    static func channelCount(ofInit data: Data) throws -> Int {
        let bytes = [UInt8](data)
        guard let type = find("mp4a", in: bytes) else { throw Missing() }
        // Box start (type - 4) + header 8 + reserved 6 + index 2 + version 2 + revision 2 + vendor 4.
        return Int(bytes[type + 20]) << 8 | Int(bytes[type + 21])
    }

    /// The channel configuration in the `esds` AudioSpecificConfig.
    static func channelConfiguration(ofInit data: Data) throws -> Int {
        let bytes = [UInt8](data)
        guard let type = find("esds", in: bytes) else { throw Missing() }
        var at = type + 8 // past the type and the full-box version and flags
        func enter(_ tag: UInt8) throws {
            guard bytes[at] == tag else { throw Missing() }
            at += 1
            while bytes[at] & 0x80 != 0 { at += 1 }
            at += 1
        }
        try enter(0x03)
        at += 3 // ES_ID, flags (none set by AVAssetWriter)
        try enter(0x04)
        at += 13
        try enter(0x05)
        // 5 bits object type, 4 bits sampling frequency index, 4 bits channel configuration.
        return Int(bytes[at + 1] >> 3 & 0x0F)
    }

    static func replacingFourCC(_ old: String, with new: String, in data: Data) -> Data {
        var bytes = [UInt8](data)
        var from = 0
        while let at = find(old, in: bytes, from: from) {
            bytes.replaceSubrange(at..<at + 4, with: Array(new.utf8))
            from = at + 4
        }
        return Data(bytes)
    }

    private static func find(_ fourCC: String, in bytes: [UInt8], from: Int = 0) -> Int? {
        let pattern = Array(fourCC.utf8)
        guard bytes.count >= pattern.count, from <= bytes.count - pattern.count else { return nil }
        return (from...(bytes.count - pattern.count)).first { bytes[$0..<$0 + pattern.count].elementsEqual(pattern) }
    }
}
