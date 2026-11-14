import AVFoundation
import Foundation
import Synchronization

/// A fragmented-MP4 AAC-LC HLS audio rendition written by `AVAssetWriter` from a known signal.
///
/// Signal: both channels carry a 60 Hz sine at 0.2; left adds 440 Hz at 0.2, right 660 Hz at 0.2; each channel adds
/// white noise at ±0.05 (SplitMix64 seeded 1 for left, 2 for right); every 0.5 s the left channel adds a 5 ms burst of
/// ±0.5 noise (drawn from the left generator), so transients land on segment joins. A mono fixture carries `left`.
public struct HLSAudioFixture: Sendable {
    public var initSegment: Data
    public var segments: [Data]
    /// The source signal, before AAC encoding.
    public var left: [Float]
    public var right: [Float]

    public static func make(seconds: Double, channels: Int = 2, sampleRate: Double = 48_000) async throws -> HLSAudioFixture {
        let (left, right) = signal(frames: Int(seconds * sampleRate), sampleRate: sampleRate)
        let source = channels == 1 ? [left] : [left, right]
        let collector = try await write(source, sampleRate: sampleRate)
        let output = collector.output.withLock { $0 }
        guard let initSegment = output.initSegment, !output.segments.isEmpty else { throw FixtureError.noSegments }
        return HLSAudioFixture(initSegment: initSegment, segments: output.segments, left: left, right: right)
    }

    // MARK: - Signal

    private static func signal(frames: Int, sampleRate: Double) -> (left: [Float], right: [Float]) {
        var leftNoise = SplitMix64(seed: 1), rightNoise = SplitMix64(seed: 2)
        let burstPeriod = Int(0.5 * sampleRate), burstLength = Int(0.005 * sampleRate)
        var left = [Float](repeating: 0, count: frames), right = left
        for frame in 0..<frames {
            let time = Double(frame) / sampleRate
            let hum = 0.2 * sin(2 * .pi * 60 * time)
            left[frame] = Float(hum + 0.2 * sin(2 * .pi * 440 * time)) + 0.05 * leftNoise.nextSigned()
            right[frame] = Float(hum + 0.2 * sin(2 * .pi * 660 * time)) + 0.05 * rightNoise.nextSigned()
            if frame % burstPeriod < burstLength {
                left[frame] += 0.5 * leftNoise.nextSigned()
            }
        }
        return (left, right)
    }

    // MARK: - Writing

    private static func write(_ channels: [[Float]], sampleRate: Double) async throws -> SegmentCollector {
        let writer = AVAssetWriter(contentType: .mpeg4Movie)
        writer.outputFileTypeProfile = .mpeg4AppleHLS
        writer.preferredOutputSegmentInterval = CMTime(seconds: 2, preferredTimescale: 1)
        writer.initialSegmentStartTime = .zero
        let collector = SegmentCollector()
        writer.delegate = collector
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels.count,
            AVEncoderBitRateKey: 128_000
        ])
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw FixtureError.writer(writer.error) }
        writer.add(input)
        guard writer.startWriting() else { throw FixtureError.writer(writer.error) }
        writer.startSession(atSourceTime: .zero)

        let format = try pcmFormat(channels: channels.count, sampleRate: sampleRate)
        let frames = channels[0].count, chunk = 4_800
        var start = 0
        while start < frames {
            let count = min(chunk, frames - start)
            let buffer = try sampleBuffer(channels, start: start, count: count, format: format, sampleRate: sampleRate)
            // Polled rather than `requestMediaDataWhenReady`, whose closure would capture non-Sendable writer objects.
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            guard input.append(buffer) else { throw FixtureError.writer(writer.error) }
            start += count
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw FixtureError.writer(writer.error) }
        return collector
    }

    private static func pcmFormat(channels: Int, sampleRate: Double) throws -> CMAudioFormatDescription {
        let bytesPerFrame = UInt32(4 * channels)
        var description = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format
        )
        guard status == noErr, let format else { throw FixtureError.coreMedia(status) }
        return format
    }

    private static func sampleBuffer(
        _ channels: [[Float]], start: Int, count: Int, format: CMAudioFormatDescription, sampleRate: Double
    ) throws -> CMSampleBuffer {
        var interleaved = [Float](repeating: 0, count: count * channels.count)
        for frame in 0..<count {
            for (index, channel) in channels.enumerated() {
                interleaved[frame * channels.count + index] = channel[start + frame]
            }
        }
        let length = interleaved.count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &block
        )
        guard status == noErr, let block else { throw FixtureError.coreMedia(status) }
        status = interleaved.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: length)
        }
        guard status == noErr else { throw FixtureError.coreMedia(status) }
        var buffer: CMSampleBuffer?
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
            presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(sampleRate)),
            packetDescriptions: nil, sampleBufferOut: &buffer
        )
        guard status == noErr, let buffer else { throw FixtureError.coreMedia(status) }
        return buffer
    }
}

private enum FixtureError: Error {
    case writer((any Error)?)
    case coreMedia(OSStatus)
    case noSegments
}

/// Receives the writer's segments, which arrive on a queue of its choosing.
private final class SegmentCollector: NSObject, AVAssetWriterDelegate, Sendable {
    struct Output {
        var initSegment: Data?
        var segments: [Data] = []
    }

    let output = Mutex(Output())

    func assetWriter(
        _ writer: AVAssetWriter, didOutputSegmentData segmentData: Data,
        segmentType: AVAssetSegmentType, segmentReport: AVAssetSegmentReport?
    ) {
        output.withLock { output in
            if segmentType == .initialization {
                output.initSegment = segmentData
            } else {
                output.segments.append(segmentData)
            }
        }
    }
}

/// SplitMix64, so the noise is identical on every run and platform.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    /// Uniform in -1...1.
    mutating func nextSigned() -> Float {
        Float(Double(next() >> 11) / Double(1 << 53) * 2 - 1)
    }
}
