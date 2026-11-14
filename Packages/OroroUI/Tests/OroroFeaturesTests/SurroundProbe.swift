import Accelerate
import AVFoundation
import Foundation
import OroroCore

/// Measurement helpers for surround audio tests: decoding raw AAC, reading a container back, and comparing signals.
enum SurroundProbe {
    enum Failure: Error {
        case formatUnavailable
        case decodeFailed((any Error)?)
        case noAudioTrack
        case readFailed((any Error)?)
    }

    /// Decodes raw AAC-LC packets (2 → stereo, 6 → `MPEG_5_1_D`) to one array per channel of exactly
    /// `packets.count × 1024` frames. No priming is removed.
    static func decode(packets: [Data], channels: Int) throws -> [[Float]] {
        let layout = channels == 6 ? AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_D) : nil
        var description = AudioStreamBasicDescription(
            mSampleRate: SurroundFormat.sampleRate, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0, mBytesPerPacket: 0,
            mFramesPerPacket: UInt32(SurroundFormat.framesPerPacket), mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 0, mReserved: 0
        )
        let compressed = layout.map { AVAudioFormat(streamDescription: &description, channelLayout: $0) }
            ?? AVAudioFormat(streamDescription: &description)
        let pcm = layout.map {
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: SurroundFormat.sampleRate, interleaved: false, channelLayout: $0)
        } ?? AVAudioFormat(standardFormatWithSampleRate: SurroundFormat.sampleRate, channels: AVAudioChannelCount(channels))
        guard let compressed, let pcm, let decoder = AVAudioConverter(from: compressed, to: pcm) else {
            throw Failure.formatUnavailable
        }

        let input = AVAudioCompressedBuffer(
            format: compressed, packetCapacity: AVAudioPacketCount(max(packets.count, 1)),
            maximumPacketSize: max(packets.map(\.count).max() ?? 1, 1)
        )
        var offset = 0
        for (index, packet) in packets.enumerated() {
            packet.withUnsafeBytes { input.data.advanced(by: offset).copyMemory(from: $0.baseAddress!, byteCount: packet.count) }
            input.packetDescriptions?[index] = AudioStreamPacketDescription(
                mStartOffset: Int64(offset), mVariableFramesInPacket: 0, mDataByteSize: UInt32(packet.count)
            )
            offset += packet.count
        }
        input.packetCount = AVAudioPacketCount(packets.count)
        input.byteLength = UInt32(offset)

        var output = [[Float]](repeating: [], count: channels)
        var fed = false
        while true {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: 16_384) else { throw Failure.formatUnavailable }
            var error: NSError?
            let status = decoder.convert(to: buffer, error: &error) { _, inputStatus in
                if fed {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                fed = true
                inputStatus.pointee = .haveData
                return input
            }
            if status == .error { throw Failure.decodeFailed(error) }
            if let data = buffer.floatChannelData {
                for channel in 0..<channels {
                    output[channel] += UnsafeBufferPointer(start: data[channel], count: Int(buffer.frameLength))
                }
            }
            if status == .endOfStream || buffer.frameLength == 0 { break }
        }
        return output
    }

    /// Writes init + segments to a temporary `.mp4` and reads it back as 6-channel float PCM in `MPEG_5_1_D` order.
    /// The reader trims the 2112 priming frames, so its output starts 2112 frames into the packet stream.
    static func readContainer(initSegment: Data, segments: [Data]) async throws -> [[Float]] {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("surround-probe-\(UUID().uuidString).mp4")
        try (segments.reduce(initSegment, +)).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let asset = AVURLAsset(url: file)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw Failure.noAudioTrack }
        let reader = try AVAssetReader(asset: asset)
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = kAudioChannelLayoutTag_MPEG_5_1_D
        let channels = SurroundFormat.channelCount
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
            AVNumberOfChannelsKey: channels,
            AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
        ])
        reader.add(output)
        guard reader.startReading() else { throw Failure.readFailed(reader.error) }

        var result = [[Float]](repeating: [], count: channels)
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var interleaved = [Float](repeating: 0, count: CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size)
            let status = interleaved.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
            }
            guard status == noErr else { throw Failure.readFailed(nil) }
            for (index, value) in interleaved.enumerated() {
                result[index % channels].append(value)
            }
        }
        guard reader.status == .completed else { throw Failure.readFailed(reader.error) }
        return result
    }

    /// The lag in frames (positive = `signal` late) with the highest normalised cross-correlation, searched over
    /// `-maxLag...maxLag` on a window of at most one second of `reference`.
    static func bestLag(of signal: [Float], against reference: [Float], maxLag: Int) -> Int {
        let start = maxLag
        let length = min(48_000, min(signal.count, reference.count) - 2 * maxLag)
        guard length > 0 else { return 0 }
        var best = 0, bestScore = -Float.infinity
        signal.withUnsafeBufferPointer { signal in
            reference.withUnsafeBufferPointer { reference in
                let target = reference.baseAddress! + start
                for lag in -maxLag...maxLag {
                    let candidate = signal.baseAddress! + start + lag
                    var product: Float = 0, energy: Float = 0
                    vDSP_dotpr(candidate, 1, target, 1, &product, vDSP_Length(length))
                    vDSP_svesq(candidate, 1, &energy, vDSP_Length(length))
                    let score = energy > 0 ? product / energy.squareRoot() : 0
                    if score > bestScore {
                        bestScore = score
                        best = lag
                    }
                }
            }
        }
        return best
    }

    /// RMS of `a − b` per 1024-frame block, over the shorter length.
    static func packetErrors(_ a: [Float], _ b: [Float]) -> [Float] {
        let block = SurroundFormat.framesPerPacket
        return (0..<min(a.count, b.count) / block).map { index in
            let range = index * block..<(index + 1) * block
            let sum = range.reduce(Float(0)) { sum, frame in
                let difference = a[frame] - b[frame]
                return sum + difference * difference
            }
            return (sum / Float(block)).squareRoot()
        }
    }
}
