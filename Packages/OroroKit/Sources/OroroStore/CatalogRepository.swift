import Foundation
import OroroAPI
import OroroCore

// STUB (T3) — implemented by Task ST3. `staleness` and `cachesDirectory()` are final.
public actor CatalogRepository: CatalogProviding {
    public static let staleness: TimeInterval = 6 * 3600

    private let api: any OroroAPI
    private let credentials: any CredentialStoring
    private let directory: URL
    private let decodeShows: @Sendable (Data) throws -> [Title]
    private let decodeMovies: @Sendable (Data) throws -> [Title]
    private let useETag: Bool

    public init(api: any OroroAPI, credentials: any CredentialStoring, directory: URL,
                decodeShows: @escaping @Sendable (Data) throws -> [Title] = Decoders.shows,
                decodeMovies: @escaping @Sendable (Data) throws -> [Title] = Decoders.movies,
                useETag: Bool = true) {
        self.api = api
        self.credentials = credentials
        self.directory = directory
        self.decodeShows = decodeShows
        self.decodeMovies = decodeMovies
        self.useETag = useETag
    }

    /// <Caches>/catalog
    public static func cachesDirectory() -> URL {
        URL.cachesDirectory.appending(path: "catalog", directoryHint: .isDirectory)
    }

    public func current() async -> Catalog? {
        nil
    }

    public func lastUpdated() async -> Date? {
        nil
    }

    public func signIn(_ c: Credentials, progress: (@Sendable (Double) -> Void)?) async throws -> Catalog {
        throw APIError.decoding
    }

    public func loadCached() async -> Catalog? {
        nil
    }

    public func refresh(force: Bool, now: Date) async throws -> Bool {
        false
    }

    public func homeSnapshot() async -> HomeContent? {
        nil
    }

    public func saveHomeSnapshot(_ content: HomeContent) async {}

    public func clear() async {}
}
