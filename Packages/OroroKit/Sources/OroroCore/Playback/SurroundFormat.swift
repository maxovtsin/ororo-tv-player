import Foundation

/// The fixed parameters of simulated 5.1 surround, shared by the container, transcoding and playlist layers.
public enum SurroundFormat {
    /// The only sample rate supported, on input and output.
    public static let sampleRate: Double = 48_000
    /// AAC-LC frame length; any other frame length is unsupported.
    public static let framesPerPacket: Int = 1024
    /// Order C L R Ls Rs LFE (`kAudioChannelLayoutTag_MPEG_5_1_D`, AAC channel configuration 6).
    public static let channelCount: Int = 6
    /// Encoder setting (measured average output ≈ 394 kb/s).
    public static let bitRate: Int = 384_000
    /// Flat addition to every variant's `BANDWIDTH` and `AVERAGE-BANDWIDTH`.
    public static let addedBitsPerSecond: Int = 384_000
    /// Previous-segment packets fed to the encoder before the current segment (measured minimum 2).
    public static let prerollPackets: Int = 4
    /// Next-segment packets fed after the current segment (measured exact minimum 2).
    public static let postrollPackets: Int = 2
    /// Output packets dropped: the measured encoder delay is 2112 frames, leaving a constant 64-frame lag.
    public static let encoderDelayPackets: Int = 2
    /// The lag that remains after dropping `encoderDelayPackets`.
    public static let outputLagFrames: Int = 64
    /// −20 dB; the receiver's bass management feeds the subwoofer.
    public static let lfeGain: Float = 0.1
}
