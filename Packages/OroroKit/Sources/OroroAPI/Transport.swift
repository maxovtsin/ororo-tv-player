import Foundation
import OroroCore

// STUB (T3) — implemented by Task A2.
public enum Endpoint: Sendable, Equatable {
    case shows, movies, show(Int), movie(Int), episode(Int)

    /// "/shows", "/shows/12", "/episodes/5", …
    public var path: String {
        ""
    }
}

public struct RawResponse: Sendable {
    public let data: Data
    public let etag: String?
    public let notModified: Bool

    public init(data: Data, etag: String?, notModified: Bool) {
        self.data = data
        self.etag = etag
        self.notModified = notModified
    }
}

public struct Transport: Sendable {
    public init(baseURL: URL = URL(string: "https://ororo.tv/api/v2")!, session: URLSession = .shared) {}

    public func send(_ endpoint: Endpoint, credentials: Credentials, ifNoneMatch: String? = nil,
                     progress: (@Sendable (Double) -> Void)? = nil) async throws -> RawResponse {
        throw APIError.decoding
    }
}
