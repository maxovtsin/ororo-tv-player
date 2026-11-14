import Foundation
import OroroCore

// STUB (T3) — implemented by Task A1.
public enum Decoders {
    /// Top-level key "shows".
    public static func shows(_ data: Data) throws -> [Title] {
        throw APIError.decoding
    }

    /// Top-level key "movies".
    public static func movies(_ data: Data) throws -> [Title] {
        throw APIError.decoding
    }

    public static func show(_ data: Data) throws -> ShowDetail {
        throw APIError.decoding
    }

    public static func movie(_ data: Data, now: Date) throws -> MovieDetail {
        throw APIError.decoding
    }

    public static func episode(_ data: Data, showID: Int?, now: Date) throws -> EpisodeDetail {
        throw APIError.decoding
    }
}
