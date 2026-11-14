import Foundation
import OroroCore

/// Real glue: each call sends through `Transport`, then decodes with `Decoders`.
public struct LiveOroroAPI: OroroAPI {
    private let transport: Transport

    public init(transport: Transport) {
        self.transport = transport
    }

    public func shows(_ c: Credentials, ifNoneMatch: String?,
                      progress: (@Sendable (Double) -> Void)?) async throws -> Conditional<ListResponse> {
        try await list(.shows, c, ifNoneMatch: ifNoneMatch, progress: progress, decode: Decoders.shows)
    }

    public func movies(_ c: Credentials, ifNoneMatch: String?,
                       progress: (@Sendable (Double) -> Void)?) async throws -> Conditional<ListResponse> {
        try await list(.movies, c, ifNoneMatch: ifNoneMatch, progress: progress, decode: Decoders.movies)
    }

    public func show(id: Int, _ c: Credentials) async throws -> ShowDetail {
        let response = try await transport.send(.show(id), credentials: c)
        return try Decoders.show(response.data)
    }

    public func movie(id: Int, _ c: Credentials) async throws -> MovieDetail {
        let response = try await transport.send(.movie(id), credentials: c)
        return try Decoders.movie(response.data, now: Date())
    }

    public func episode(id: Int, _ c: Credentials) async throws -> EpisodeDetail {
        let response = try await transport.send(.episode(id), credentials: c)
        return try Decoders.episode(response.data, showID: nil, now: Date())
    }

    private func list(_ endpoint: Endpoint, _ c: Credentials, ifNoneMatch: String?,
                      progress: (@Sendable (Double) -> Void)?,
                      decode: (Data) throws -> [Title]) async throws -> Conditional<ListResponse> {
        let response = try await transport.send(endpoint, credentials: c, ifNoneMatch: ifNoneMatch, progress: progress)
        if response.notModified { return .notModified }
        let titles = try decode(response.data)
        return .fresh(ListResponse(titles: titles, rawData: response.data, etag: response.etag))
    }
}
