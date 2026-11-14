import Foundation

public enum Conditional<T: Sendable>: Sendable {
    case notModified, fresh(T)
}

public struct ListResponse: Sendable {
    public let titles: [Title]
    public let rawData: Data
    public let etag: String?

    public init(titles: [Title], rawData: Data, etag: String?) {
        self.titles = titles
        self.rawData = rawData
        self.etag = etag
    }
}

public protocol OroroAPI: Sendable {
    func shows(_ c: Credentials, ifNoneMatch: String?, progress: (@Sendable (Double) -> Void)?) async throws -> Conditional<ListResponse>
    func movies(_ c: Credentials, ifNoneMatch: String?, progress: (@Sendable (Double) -> Void)?) async throws -> Conditional<ListResponse>
    func show(id: Int, _ c: Credentials) async throws -> ShowDetail
    func movie(id: Int, _ c: Credentials) async throws -> MovieDetail
    /// `episode.showID` is 0 when unknown (the endpoint does not return it); consumers take the show id from
    /// `PlayRequest.Target.episode(showID:)` or the show detail, never from `EpisodeDetail`.
    func episode(id: Int, _ c: Credentials) async throws -> EpisodeDetail
}

public protocol CredentialStoring: Sendable {
    func load() -> Credentials?
    func save(_ c: Credentials) throws
    func clear() throws
}

public protocol CatalogProviding: Sendable {
    func current() async -> Catalog?
    func lastUpdated() async -> Date?
    /// Fetches, caches, stores credentials.
    func signIn(_ c: Credentials, progress: (@Sendable (Double) -> Void)?) async throws -> Catalog
    /// Decodes cache files; nil if none.
    func loadCached() async -> Catalog?
    /// True when a new catalog was swapped in.
    func refresh(force: Bool, now: Date) async throws -> Bool
    func homeSnapshot() async -> HomeContent?
    func saveHomeSnapshot(_ content: HomeContent) async
    func clear() async
}

public protocol LibraryStoring: Sendable {
    func snapshot() async -> Library
    /// Applies to memory now; flush is throttled.
    func update(_ mutate: @Sendable (inout Library) -> Void) async
    func flush() async
    func erase() async
    func updates() async -> AsyncStream<Library>
}

public protocol DetailProviding: Sendable {
    func show(id: Int) async throws -> ShowDetail               // cached
    func movie(id: Int) async throws -> MovieDetail             // cached, playback == nil
    func episode(id: Int) async throws -> EpisodeDetail         // cached, playback == nil
    func moviePlayback(id: Int) async throws -> MovieDetail     // always network
    func episodePlayback(id: Int) async throws -> EpisodeDetail // always network
    func clear() async
}

public protocol NewEpisodeResolving: Sendable {
    func cached() async -> [Int: NewEpisodeInfo]
    func resolve(shows: [Title], library: Library) async -> [Int: NewEpisodeInfo]
}
