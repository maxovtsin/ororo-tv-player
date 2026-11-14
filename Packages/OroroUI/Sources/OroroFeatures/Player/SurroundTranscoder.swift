import AVFoundation
import OroroCore

/// Turns one HLS segment's stereo AAC-LC packets into the same number of 5.1 AAC-LC packets.
///
/// Segments are transcoded independently, so each call decodes a few packets either side of the segment, encodes the
/// whole span and keeps only the packets that line up with `current`. With `prerollPackets` before and
/// `postrollPackets` after, the joins are indistinguishable from one continuous encode (measured); the output lags
/// the source by a constant `outputLagFrames`. Converters are created per call and never leave it.
struct SurroundTranscoder: Sendable {
    enum Failure: Error, Equatable {
        case decoderUnavailable, encoderUnavailable, decodeFailed, encodeFailed
    }

    /// Replaces the upmix with a test signal, positioned by each call's `startFrame`.
    private let signal: SurroundDebugSignal?

    init(signal: SurroundDebugSignal? = nil) {
        self.signal = signal
    }

    /// Returns exactly `current.count` raw 5.1 AAC packets, time-aligned with `current`. `previous` and `next` are the
    /// neighbouring packets available (up to `prerollPackets` / `postrollPackets` are used); `startFrame` is the
    /// absolute frame index of `current`'s first packet and only positions the debug signal.
    func transcode(previous: [Data], current: [Data], next: [Data], startFrame: Int) throws -> [Data] {
        guard !current.isEmpty else { return [] }
        let preroll = SurroundFormat.prerollPackets, postroll = SurroundFormat.postrollPackets
        let packetFrames = SurroundFormat.framesPerPacket
        let before = Array(previous.suffix(preroll)), after = Array(next.prefix(postroll))
        let spanFrames = (preroll + current.count + postroll) * packetFrames

        let frames: SurroundFrames
        if let signal {
            frames = signal.frames(startFrame: startFrame - preroll * packetFrames, count: spanFrames)
        } else {
            var stereo = try Self.decode(before + current + after)
            if !before.isEmpty {
                // The first decoded packet has no history and is unreliable; it only feeds the encoder's warm-up.
                for channel in stereo.indices {
                    stereo[channel].replaceSubrange(0..<packetFrames, with: repeatElement(0, count: packetFrames))
                }
            }
            // Pad with silence so `current` always starts at packet `preroll` and is followed by `postroll` packets.
            let leading = [Float](repeating: 0, count: (preroll - before.count) * packetFrames)
            let trailing = [Float](repeating: 0, count: (postroll - after.count) * packetFrames)
            var upmixer = SurroundUpmixer()
            frames = upmixer.process(left: leading + stereo[0] + trailing, right: leading + stereo[1] + trailing)
        }

        // Output packet k carries input frames [k·1024 − 2112, k·1024 − 1088): skipping the encoder delay leaves
        // packet `preroll + encoderDelayPackets` starting `outputLagFrames` before `current`.
        let encoded = try Self.encode(frames)
        let first = preroll + SurroundFormat.encoderDelayPackets
        guard encoded.count >= first + current.count else { throw Failure.encodeFailed }
        return Array(encoded[first..<first + current.count])
    }

    // MARK: - Formats

    /// Built per call: AVFoundation objects stay local to one transcode.
    private static var surroundLayout: AVAudioChannelLayout? { AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_D) }

    private static func aacFormat(channels: Int, layout: AVAudioChannelLayout?) -> AVAudioFormat? {
        var description = AudioStreamBasicDescription(
            mSampleRate: SurroundFormat.sampleRate, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0, mBytesPerPacket: 0,
            mFramesPerPacket: UInt32(SurroundFormat.framesPerPacket), mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 0, mReserved: 0
        )
        guard let layout else { return AVAudioFormat(streamDescription: &description) }
        return AVAudioFormat(streamDescription: &description, channelLayout: layout)
    }

    // MARK: - Decoding

    /// Decodes stereo AAC to two channels of exactly `packets.count × 1024` frames, priming included.
    private static func decode(_ packets: [Data]) throws -> [[Float]] {
        guard let compressed = aacFormat(channels: 2, layout: nil),
              let pcm = AVAudioFormat(standardFormatWithSampleRate: SurroundFormat.sampleRate, channels: 2),
              let decoder = AVAudioConverter(from: compressed, to: pcm) else { throw Failure.decoderUnavailable }

        let input = AVAudioCompressedBuffer(
            format: compressed, packetCapacity: AVAudioPacketCount(packets.count),
            maximumPacketSize: max(packets.map(\.count).max() ?? 1, 1)
        )
        guard let descriptions = input.packetDescriptions else { throw Failure.decodeFailed }
        var offset = 0
        for (index, packet) in packets.enumerated() {
            packet.withUnsafeBytes { bytes in
                if let base = bytes.baseAddress { input.data.advanced(by: offset).copyMemory(from: base, byteCount: bytes.count) }
            }
            descriptions[index] = AudioStreamPacketDescription(
                mStartOffset: Int64(offset), mVariableFramesInPacket: 0, mDataByteSize: UInt32(packet.count)
            )
            offset += packet.count
        }
        input.packetCount = AVAudioPacketCount(packets.count)
        input.byteLength = UInt32(offset)

        let expected = packets.count * SurroundFormat.framesPerPacket
        guard let output = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: AVAudioFrameCount(expected + SurroundFormat.framesPerPacket)) else {
            throw Failure.decodeFailed
        }
        var fed = false
        var error: NSError?
        let status = decoder.convert(to: output, error: &error) { _, inputStatus in
            if fed {
                inputStatus.pointee = .endOfStream
                return nil
            }
            fed = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, Int(output.frameLength) == expected, let channels = output.floatChannelData else {
            throw Failure.decodeFailed
        }
        return (0..<2).map { Array(UnsafeBufferPointer(start: channels[$0], count: expected)) }
    }

    // MARK: - Encoding

    /// Encodes the frames as one stream, flushed at the end; returns every packet, encoder delay included.
    private static func encode(_ frames: SurroundFrames) throws -> [Data] {
        guard let layout = surroundLayout, let compressed = aacFormat(channels: SurroundFormat.channelCount, layout: layout) else {
            throw Failure.encoderUnavailable
        }
        let pcm = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: SurroundFormat.sampleRate, interleaved: false, channelLayout: layout
        )
        guard let encoder = AVAudioConverter(from: pcm, to: compressed) else { throw Failure.encoderUnavailable }
        encoder.bitRate = SurroundFormat.bitRate

        guard let input = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: AVAudioFrameCount(frames.count)),
              let destination = input.floatChannelData else { throw Failure.encodeFailed }
        input.frameLength = AVAudioFrameCount(frames.count)
        for (index, channel) in frames.channels.enumerated() {
            channel.withUnsafeBufferPointer { source in
                if let base = source.baseAddress { destination[index].update(from: base, count: source.count) }
            }
        }

        var packets: [Data] = []
        var fed = false
        while true {
            let output = AVAudioCompressedBuffer(
                format: compressed, packetCapacity: 64, maximumPacketSize: encoder.maximumOutputPacketSize
            )
            var error: NSError?
            let status = encoder.convert(to: output, error: &error) { _, inputStatus in
                if fed {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                fed = true
                inputStatus.pointee = .haveData
                return input
            }
            guard status != .error else { throw Failure.encodeFailed }
            if let descriptions = output.packetDescriptions {
                for index in 0..<Int(output.packetCount) {
                    let description = descriptions[index]
                    packets.append(Data(
                        bytes: output.data.advanced(by: Int(description.mStartOffset)), count: Int(description.mDataByteSize)
                    ))
                }
            }
            if status == .endOfStream || output.packetCount == 0 { break }
        }
        return packets
    }
}
