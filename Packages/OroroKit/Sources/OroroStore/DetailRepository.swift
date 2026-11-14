import Foundation
import OroroCore

// STUB (T3) — implemented by Task ST4.
public actor DetailRepository: DetailProviding {
    private let api: any OroroAPI
    private let credentials: any CredentialStoring
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date

    public init(api: any OroroAPI, credentials: any CredentialStoring, ttl: TimeInterval = 600,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.api = api
        self.credentials = credentials
        self.ttl = ttl
        self.now = now
    }

    public func show(id: Int) async throws -> ShowDetail {
        throw APIError.decoding
    }

    public func movie(id: Int) async throws -> MovieDetail {
        throw APIError.decoding
    }

    public func episode(id: Int) async throws -> EpisodeDetail {
        throw APIError.decoding
    }

    public func moviePlayback(id: Int) async throws -> MovieDetail {
        throw APIError.decoding
    }

    public func episodePlayback(id: Int) async throws -> EpisodeDetail {
        throw APIError.decoding
    }

    public func clear() async {}
}
