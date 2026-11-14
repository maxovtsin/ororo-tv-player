import Foundation

/// The container side of simulated surround: reads the AAC packets out of a fragmented-MP4 HLS audio segment,
/// writes packets back into one, and turns a stereo init segment into a 5.1 one.
public enum FragmentedMP4 {
    /// One segment's audio track: its AAC packets in decode order, each `SurroundFormat.framesPerPacket` frames long.
    public struct AudioFragment: Equatable, Sendable {
        public var trackID: UInt32
        /// In the track's timescale, from the segment's first `tfdt`.
        public var baseDecodeTime: UInt64
        public var packets: [Data]

        public init(trackID: UInt32, baseDecodeTime: UInt64, packets: [Data]) {
            self.trackID = trackID
            self.baseDecodeTime = baseDecodeTime
            self.packets = packets
        }
    }

    public enum Failure: Error, Equatable {
        /// Not a sound box structure: truncated, missing a required box, or no samples.
        case malformed
        /// Well formed, but not 48 kHz stereo AAC-LC in 1024-frame packets.
        case unsupported
    }
}

// MARK: - Parsing segments

extension FragmentedMP4 {
    /// Every sample of every `moof`/`mdat` pair, in order. A segment may hold several fragments and several `trun`s per `traf`.
    public static func parseAudioSegment(_ data: Data) throws -> AudioFragment {
        let bytes = [UInt8](data)
        var trackID: UInt32?
        var baseDecodeTime: UInt64?
        var packets: [Data] = []
        for moof in try Box.children(of: bytes, in: 0..<bytes.count) where moof.type == "moof" {
            for traf in try Box.children(of: bytes, in: moof.payload) where traf.type == "traf" {
                let run = try trackFragment(traf, moofStart: moof.start, bytes: bytes)
                guard trackID == nil || trackID == run.header.trackID else { throw Failure.unsupported }
                trackID = run.header.trackID
                baseDecodeTime = baseDecodeTime ?? run.baseDecodeTime
                packets += run.packets
            }
        }
        guard let trackID, let baseDecodeTime, !packets.isEmpty else { throw Failure.malformed }
        return AudioFragment(trackID: trackID, baseDecodeTime: baseDecodeTime, packets: packets)
    }

    private struct TrackFragment {
        var header: TrackFragmentHeader
        var baseDecodeTime: UInt64?
        var packets: [Data] = []
    }

    private struct TrackFragmentHeader {
        var trackID: UInt32
        /// Absolute offset in the segment that `trun` data offsets count from.
        var baseDataOffset: Int
        var defaultDuration: UInt32?
        var defaultSize: UInt32?
    }

    private static func trackFragment(_ traf: Box, moofStart: Int, bytes: [UInt8]) throws -> TrackFragment {
        let children = try Box.children(of: bytes, in: traf.payload)
        guard let tfhd = children.first(where: { $0.type == "tfhd" }) else { throw Failure.malformed }
        var fragment = TrackFragment(header: try trackFragmentHeader(tfhd, moofStart: moofStart, bytes: bytes))
        var dataEnd: Int?
        for child in children {
            switch child.type {
            case "tfdt":
                var cursor = Cursor(bytes, child.payload)
                let version = try cursor.u8()
                try cursor.skip(3)
                let time = version == 1 ? try cursor.u64() : UInt64(try cursor.u32())
                fragment.baseDecodeTime = fragment.baseDecodeTime ?? time
            case "trun":
                dataEnd = try readTrackRun(child, header: fragment.header, dataStart: dataEnd, bytes: bytes, into: &fragment.packets)
            default:
                continue
            }
        }
        return fragment
    }

    private static func trackFragmentHeader(_ tfhd: Box, moofStart: Int, bytes: [UInt8]) throws -> TrackFragmentHeader {
        var cursor = Cursor(bytes, tfhd.payload)
        let flags = try cursor.u32() & 0xFF_FFFF
        var header = TrackFragmentHeader(trackID: try cursor.u32(), baseDataOffset: moofStart)
        if flags & 0x01 != 0 {
            header.baseDataOffset = try cursor.offset()
            // Bounded here so the data-offset and sample-size additions in `readTrackRun` cannot overflow.
            guard header.baseDataOffset <= bytes.count else { throw Failure.malformed }
        }
        if flags & 0x02 != 0 { try cursor.skip(4) } // sample description index
        if flags & 0x08 != 0 { header.defaultDuration = try cursor.u32() }
        if flags & 0x10 != 0 { header.defaultSize = try cursor.u32() }
        return header
    }

    /// Appends the run's samples and returns where its data ends, where a following run without a data offset starts.
    private static func readTrackRun(
        _ trun: Box, header: TrackFragmentHeader, dataStart: Int?, bytes: [UInt8], into packets: inout [Data]
    ) throws -> Int {
        var cursor = Cursor(bytes, trun.payload)
        let flags = try cursor.u32() & 0xFF_FFFF
        let count = try cursor.u32()
        var start = dataStart ?? header.baseDataOffset
        if flags & 0x001 != 0 { start = header.baseDataOffset + Int(Int32(bitPattern: try cursor.u32())) }
        if flags & 0x004 != 0 { try cursor.skip(4) } // first sample flags
        for _ in 0..<count {
            let duration = flags & 0x100 != 0 ? try cursor.u32() : header.defaultDuration
            let size = flags & 0x200 != 0 ? try cursor.u32() : header.defaultSize
            if flags & 0x400 != 0 { try cursor.skip(4) } // sample flags
            if flags & 0x800 != 0 { try cursor.skip(4) } // composition time offset
            guard let duration, let size else { throw Failure.unsupported }
            guard duration == SurroundFormat.framesPerPacket else { throw Failure.unsupported }
            let end = start + Int(size)
            guard size > 0, start >= 0, end <= bytes.count else { throw Failure.malformed }
            packets.append(Data(bytes[start..<end]))
            start = end
        }
        return start
    }
}

// MARK: - Building segments

extension FragmentedMP4 {
    /// One `moof` (`mfhd`, `traf`(`tfhd`, `tfdt`, `trun`)) and its `mdat`; durations come from the `tfhd` default.
    public static func buildAudioSegment(sequence: UInt32, fragment: AudioFragment) -> Data {
        let mfhd = box("mfhd", be32(0) + be32(sequence))
        // Default base is moof, default sample duration 1024, default sample flags "does not depend on others".
        let tfhd = box("tfhd", be32(0x02_0028) + be32(fragment.trackID) + be32(UInt32(SurroundFormat.framesPerPacket)) + be32(0x0200_0000))
        let tfdt = box("tfdt", be32(0x0100_0000) + be64(fragment.baseDecodeTime))
        let trunSize = 8 + 12 + 4 * fragment.packets.count
        let moofSize = 8 + mfhd.count + 8 + tfhd.count + tfdt.count + trunSize
        // Data offset and per-sample sizes; the data starts right after the mdat header.
        var trun = be32(0x00_0201) + be32(UInt32(fragment.packets.count)) + be32(UInt32(moofSize + 8))
        for packet in fragment.packets {
            trun += be32(UInt32(packet.count))
        }
        let moof = box("moof", mfhd + box("traf", tfhd + tfdt + box("trun", trun)))
        let mdat = box("mdat", fragment.packets.reduce(into: [UInt8]()) { $0 += $1 })
        return Data(moof + mdat)
    }

    private static func box(_ type: String, _ payload: [UInt8]) -> [UInt8] {
        be32(UInt32(payload.count + 8)) + Array(type.utf8) + payload
    }

    private static func be32(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    private static func be64(_ value: UInt64) -> [UInt8] {
        be32(UInt32(value >> 32)) + be32(UInt32(value & 0xFFFF_FFFF))
    }
}

// MARK: - The 5.1 init segment

extension FragmentedMP4 {
    /// The stereo init segment with its audio track declared as 6 channels, byte for byte otherwise.
    ///
    /// Only the sample entry's channel count and the AudioSpecificConfig's channel configuration change (measured:
    /// that alone reads back as a valid 5.1 track). Requires a 48 kHz stereo AAC-LC `mp4a` track.
    public static func surroundInitSegment(from stereoInit: Data) throws -> Data {
        var bytes = [UInt8](stereoInit)
        let entry = try audioSampleEntry(in: bytes)
        guard entry.type == "mp4a" else { throw Failure.unsupported }
        // Payload: reserved 6, data reference index 2, version 2, revision 2, vendor 4, channel count 2,
        // sample size 2, compression ID 2, packet size 2, sample rate 16.16.
        var cursor = Cursor(bytes, entry.payload)
        try cursor.skip(8)
        let version = try cursor.u16()
        try cursor.skip(6)
        let channelCountAt = cursor.at
        let channelCount = try cursor.u16()
        try cursor.skip(6)
        let sampleRate = try cursor.u32() >> 16
        guard version <= 1, channelCount == 2, Double(sampleRate) == SurroundFormat.sampleRate else { throw Failure.unsupported }
        let childrenStart = cursor.at + (version == 1 ? 16 : 0)
        guard childrenStart <= entry.payload.upperBound else { throw Failure.malformed }
        let children = try Box.children(of: bytes, in: childrenStart..<entry.payload.upperBound)
        guard let esds = children.first(where: { $0.type == "esds" }) else { throw Failure.malformed }
        let channelConfigurationBit = try channelConfigurationBit(inESDS: esds, bytes: bytes)

        bytes[channelCountAt] = 0
        bytes[channelCountAt + 1] = UInt8(SurroundFormat.channelCount)
        write(UInt8(SurroundFormat.channelCount), bits: 4, atBit: channelConfigurationBit, in: &bytes)
        return Data(bytes)
    }

    /// The sample entry of the `soun` track, after checking its media timescale.
    private static func audioSampleEntry(in bytes: [UInt8]) throws -> Box {
        let moov = try Box.child("moov", of: bytes, in: 0..<bytes.count)
        for trak in try Box.children(of: bytes, in: moov.payload) where trak.type == "trak" {
            let mdia = try Box.child("mdia", of: bytes, in: trak.payload)
            var hdlr = Cursor(bytes, try Box.child("hdlr", of: bytes, in: mdia.payload).payload)
            try hdlr.skip(8) // version and flags, pre-defined
            guard try hdlr.fourCC() == "soun" else { continue }

            var mdhd = Cursor(bytes, try Box.child("mdhd", of: bytes, in: mdia.payload).payload)
            let version = try mdhd.u8()
            try mdhd.skip(version == 1 ? 19 : 11) // flags, creation and modification times
            guard Double(try mdhd.u32()) == SurroundFormat.sampleRate else { throw Failure.unsupported }

            let minf = try Box.child("minf", of: bytes, in: mdia.payload)
            let stbl = try Box.child("stbl", of: bytes, in: minf.payload)
            var stsd = Cursor(bytes, try Box.child("stsd", of: bytes, in: stbl.payload).payload)
            try stsd.skip(4)
            guard try stsd.u32() == 1 else { throw Failure.unsupported }
            guard let entry = try Box.children(of: bytes, in: stsd.at..<stsd.end).first else { throw Failure.malformed }
            return entry
        }
        throw Failure.unsupported
    }

    /// Walks ES_Descriptor → DecoderConfigDescriptor → DecoderSpecificInfo and returns the absolute bit position of the
    /// AudioSpecificConfig's channel configuration, after checking for AAC-LC at 48 kHz in stereo.
    private static func channelConfigurationBit(inESDS esds: Box, bytes: [UInt8]) throws -> Int {
        var cursor = Cursor(bytes, esds.payload)
        try cursor.skip(4) // version and flags
        try cursor.enterDescriptor(tag: 0x03)
        try cursor.skip(2) // ES_ID
        let flags = try cursor.u8()
        if flags & 0x80 != 0 { try cursor.skip(2) } // depends-on ES_ID
        if flags & 0x40 != 0 { try cursor.skip(Int(try cursor.u8())) } // URL
        if flags & 0x20 != 0 { try cursor.skip(2) } // OCR ES_ID
        try cursor.enterDescriptor(tag: 0x04)
        guard try cursor.u8() == 0x40 else { throw Failure.unsupported } // MPEG-4 audio
        try cursor.skip(12) // stream type, buffer size, max and average bit rates
        let configEnd = try cursor.enterDescriptor(tag: 0x05)

        let config = cursor.at * 8, configEndBit = configEnd * 8
        func bits(_ count: Int, at bit: Int) throws -> Int {
            guard bit + count <= configEndBit else { throw Failure.malformed }
            return (bit..<bit + count).reduce(0) { $0 << 1 | Int(bytes[$1 / 8] >> (7 - $1 % 8) & 1) }
        }
        guard try bits(5, at: config) == 2 else { throw Failure.unsupported } // AAC-LC
        let frequencyIndex = try bits(4, at: config + 5)
        var channelBit = config + 9
        if frequencyIndex == 15 {
            guard Double(try bits(24, at: channelBit)) == SurroundFormat.sampleRate else { throw Failure.unsupported }
            channelBit += 24
        } else {
            guard frequencyIndex == 3 else { throw Failure.unsupported } // 48 kHz
        }
        guard try bits(4, at: channelBit) == 2 else { throw Failure.unsupported }
        return channelBit
    }

    private static func write(_ value: UInt8, bits count: Int, atBit start: Int, in bytes: inout [UInt8]) {
        for offset in 0..<count {
            let bit = start + offset, mask = UInt8(1) << (7 - bit % 8)
            let isSet = value >> (count - 1 - offset) & 1 == 1
            bytes[bit / 8] = isSet ? bytes[bit / 8] | mask : bytes[bit / 8] & ~mask
        }
    }
}

// MARK: - Reading boxes

private struct Box {
    var type: String
    /// Absolute offset of the box header.
    var start: Int
    var payload: Range<Int>

    /// The boxes laid end to end in `range`; anything that does not fit exactly is `.malformed`.
    static func children(of bytes: [UInt8], in range: Range<Int>) throws -> [Box] {
        var boxes: [Box] = []
        var cursor = Cursor(bytes, range)
        while cursor.at < range.upperBound {
            let start = cursor.at
            var size = Int(try cursor.u32())
            let type = try cursor.fourCC()
            if size == 1 {
                size = try cursor.offset()
            } else if size == 0 {
                size = range.upperBound - start
            }
            let header = cursor.at - start
            guard size >= header, size <= range.upperBound - start else { throw FragmentedMP4.Failure.malformed }
            boxes.append(Box(type: type, start: start, payload: cursor.at..<start + size))
            cursor.at = start + size
        }
        return boxes
    }

    /// The first child of `type`, or `.malformed`.
    static func child(_ type: String, of bytes: [UInt8], in range: Range<Int>) throws -> Box {
        guard let box = try children(of: bytes, in: range).first(where: { $0.type == type }) else {
            throw FragmentedMP4.Failure.malformed
        }
        return box
    }
}

/// Bounds-checked big-endian reads within one range; reading past it is `.malformed`.
private struct Cursor {
    let bytes: [UInt8]
    var at: Int
    let end: Int

    init(_ bytes: [UInt8], _ range: Range<Int>) {
        self.bytes = bytes
        at = range.lowerBound
        end = range.upperBound
    }

    mutating func skip(_ count: Int) throws {
        guard count >= 0, count <= end - at else { throw FragmentedMP4.Failure.malformed }
        at += count
    }

    mutating func u8() throws -> UInt8 {
        guard at < end else { throw FragmentedMP4.Failure.malformed }
        defer { at += 1 }
        return bytes[at]
    }

    mutating func u16() throws -> UInt16 {
        try read(2).reduce(0) { $0 << 8 | UInt16($1) }
    }

    mutating func u32() throws -> UInt32 {
        try read(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func u64() throws -> UInt64 {
        try read(8).reduce(0) { $0 << 8 | UInt64($1) }
    }

    /// A 64-bit size or offset that must fit an `Int`.
    mutating func offset() throws -> Int {
        guard let value = Int(exactly: try u64()) else { throw FragmentedMP4.Failure.malformed }
        return value
    }

    mutating func fourCC() throws -> String {
        String(bytes: try read(4), encoding: .isoLatin1) ?? "" // Latin-1 maps every byte, so this never falls back
    }

    /// Reads an MPEG-4 descriptor's tag and length, leaving the cursor at its contents; returns where they end.
    @discardableResult
    mutating func enterDescriptor(tag: UInt8) throws -> Int {
        guard try u8() == tag else { throw FragmentedMP4.Failure.malformed }
        var length = 0
        for _ in 0..<4 {
            let byte = try u8()
            length = length << 7 | Int(byte & 0x7F)
            if byte & 0x80 == 0 {
                guard length <= end - at else { throw FragmentedMP4.Failure.malformed }
                return at + length
            }
        }
        throw FragmentedMP4.Failure.malformed
    }

    private mutating func read(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count <= end - at else { throw FragmentedMP4.Failure.malformed }
        defer { at += count }
        return bytes[at..<at + count]
    }
}
