import Foundation

/// Big-endian building blocks for hand-built MP4 box fixtures.
public enum MP4Bytes {
    /// A box with a 32-bit size header; `type` must be four ASCII characters.
    public static func box(_ type: String, _ payload: Data) -> Data {
        be32(UInt32(payload.count + 8)) + Data(type.utf8) + payload
    }

    public static func be32(_ value: UInt32) -> Data {
        Data([UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }

    public static func be64(_ value: UInt64) -> Data {
        be32(UInt32(value >> 32)) + be32(UInt32(value & 0xFFFF_FFFF))
    }
}
