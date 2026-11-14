import Foundation
import OroroAPI
import OroroCore

/// The full show and movie lists, cached on disk as the raw API bytes.
///
/// Files in `directory`: `shows.json`, `movies.json` (raw list responses, which carry no playback URLs),
/// `meta.json` (`fetchedAt` and the lists' etags) and `home-snapshot.json`. Every write goes to a temp file
/// first and then replaces the destination, so a crash never leaves a half-written cache.
public actor CatalogRepository: CatalogProviding {
    public static let staleness: TimeInterval = 6 * 3600

    private let api: any OroroAPI
    private let credentials: any CredentialStoring
    private let directory: URL
    private let decodeShows: @Sendable (Data) throws -> [Title]
    private let decodeMovies: @Sendable (Data) throws -> [Title]
    private let useETag: Bool

    private var catalog: Catalog?
    /// Nil when there is no `meta.json` (then `lastUpdated()` is nil and the cache counts as stale).
    private var meta: Meta?
    /// Bumped by `clear`, `signIn` and every install of a new catalog. An operation that suspended and finds the
    /// generation changed writes nothing and installs nothing, so `clear` can't be undone by an in-flight call and
    /// `loadCached` can't roll back a newer catalog.
    private var generation = 0
    /// Test seam: called with each file name right before that file replaces its destination.
    private var beforeReplace: (@Sendable (String) throws -> Void)?

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
        catalog
    }

    public func lastUpdated() async -> Date? {
        meta?.fetchedAt
    }

    public func signIn(_ c: Credentials, progress: (@Sendable (Double) -> Void)?) async throws -> Catalog {
        generation += 1
        let started = generation
        // Shows first: a 401 here means bad credentials, and nothing has been stored yet.
        let shows = try await api.shows(c, ifNoneMatch: nil, progress: Self.half(of: progress, offset: 0))
        let movies = try await api.movies(c, ifNoneMatch: nil, progress: Self.half(of: progress, offset: 0.5))
        guard case .fresh(let showList) = shows, case .fresh(let movieList) = movies else { throw APIError.decoding }
        // Superseded by `clear` or another sign-in while downloading.
        guard generation == started else { throw CancellationError() }

        let newMeta = Meta(fetchedAt: Date(), showsETag: showList.etag, moviesETag: movieList.etag)
        try write(lists: [(Files.shows, showList.rawData), (Files.movies, movieList.rawData)], meta: newMeta)
        try credentials.save(c)

        let newCatalog = Catalog(shows: showList.titles, movies: movieList.titles, fetchedAt: newMeta.fetchedAt)
        install(newCatalog, meta: newMeta)
        return newCatalog
    }

    public func loadCached() async -> Catalog? {
        let started = generation
        let loaded = await Self.readCache(in: directory, decodeShows: decodeShows, decodeMovies: decodeMovies)
        // Something newer (or `clear`) happened while reading: keep it.
        guard generation == started else { return catalog }
        guard let loaded else { return nil }
        install(loaded.catalog, meta: loaded.meta)
        return loaded.catalog
    }

    public func refresh(force: Bool, now: Date) async throws -> Bool {
        if catalog == nil { _ = await loadCached() }
        if !force, let fetchedAt = catalog?.fetchedAt, now.timeIntervalSince(fetchedAt) < Self.staleness {
            return false
        }
        guard let c = credentials.load() else { throw APIError.unauthorized }
        let started = generation

        // Only offer an etag for a list we can actually keep on 304.
        let old = catalog
        let showsETag = useETag && old != nil ? meta?.showsETag : nil
        let moviesETag = useETag && old != nil ? meta?.moviesETag : nil
        let shows = try await api.shows(c, ifNoneMatch: showsETag, progress: nil)
        let movies = try await api.movies(c, ifNoneMatch: moviesETag, progress: nil)
        // Superseded by `clear`, `signIn` or another refresh while downloading.
        guard generation == started else { return false }

        var lists: [(String, Data)] = []
        var newMeta = Meta(fetchedAt: now, showsETag: showsETag, moviesETag: moviesETag)
        var newShows = old?.shows ?? []
        var newMovies = old?.movies ?? []
        switch shows {
        case .notModified:
            guard old != nil else { throw APIError.decoding }
        case .fresh(let list):
            lists.append((Files.shows, list.rawData))
            newMeta.showsETag = list.etag
            newShows = list.titles
        }
        switch movies {
        case .notModified:
            guard old != nil else { throw APIError.decoding }
        case .fresh(let list):
            lists.append((Files.movies, list.rawData))
            newMeta.moviesETag = list.etag
            newMovies = list.titles
        }
        try write(lists: lists, meta: newMeta)

        install(Catalog(shows: newShows, movies: newMovies, fetchedAt: now), meta: newMeta)
        return !lists.isEmpty
    }

    public func homeSnapshot() async -> HomeContent? {
        guard let data = try? Data(contentsOf: url(Files.homeSnapshot)) else { return nil }
        return try? JSONDecoder().decode(HomeContent.self, from: data)
    }

    public func saveHomeSnapshot(_ content: HomeContent) async {
        guard let data = try? Self.encode(content) else { return }
        try? write([(Files.homeSnapshot, data)])
    }

    public func clear() async {
        generation += 1
        try? FileManager.default.removeItem(at: directory)
        catalog = nil
        meta = nil
    }

    // MARK: - Files

    private enum Files {
        static let shows = "shows.json"
        static let movies = "movies.json"
        static let meta = "meta.json"
        static let homeSnapshot = "home-snapshot.json"
    }

    private struct Meta: Codable {
        var fetchedAt: Date
        var showsETag: String?
        var moviesETag: String?
    }

    /// Maps one download's 0...1 onto its half of the overall progress (the mean of the two downloads).
    private static func half(of progress: (@Sendable (Double) -> Void)?, offset: Double) -> (@Sendable (Double) -> Void)? {
        guard let progress else { return nil }
        return { @Sendable value in progress(offset + value / 2) }
    }

    private func url(_ name: String) -> URL {
        directory.appending(path: name)
    }

    private static func encode(_ value: some Encodable) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private func install(_ newCatalog: Catalog, meta newMeta: Meta?) {
        generation += 1
        catalog = newCatalog
        meta = newMeta
    }

    func setBeforeReplace(_ hook: (@Sendable (String) throws -> Void)?) {
        beforeReplace = hook
    }

    /// Writes the changed lists, then `meta.json`. Order matters: meta must be replaced LAST. If a crash lands
    /// between replacements, the disk can only hold new list bytes next to the OLD meta — old etag (→ the server
    /// answers 200 and we refetch) and old `fetchedAt` (→ stale, refreshed soon). Replacing meta first could pair a
    /// fresh `fetchedAt` and new etags with old list bytes, which a 304 would then keep forever.
    private func write(lists: [(String, Data)], meta newMeta: Meta) throws {
        try write(lists + [(Files.meta, try Self.encode(newMeta))])
    }

    /// Stages every file as a temp file, then replaces the destinations in the given order. A failure while staging
    /// leaves the old files untouched; each replacement is itself atomic.
    private func write(_ files: [(name: String, data: Data)]) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var staged: [(name: String, temp: URL)] = []
        defer { for item in staged { try? fileManager.removeItem(at: item.temp) } }
        for (name, data) in files {
            let temp = url(".\(name).\(UUID().uuidString).tmp")
            staged.append((name, temp))
            try data.write(to: temp)
        }
        for item in staged {
            try beforeReplace?(item.name)
            let destination = url(item.name)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: item.temp)
            } else {
                try fileManager.moveItem(at: item.temp, to: destination)
            }
        }
    }

    /// Reads and decodes the cache off the repository's executor. Nil if either list is missing or undecodable.
    @concurrent
    private static func readCache(in directory: URL,
                                  decodeShows: @Sendable (Data) throws -> [Title],
                                  decodeMovies: @Sendable (Data) throws -> [Title]) async -> (catalog: Catalog, meta: Meta?)? {
        do {
            let shows = try decodeShows(Data(contentsOf: directory.appending(path: Files.shows)))
            let movies = try decodeMovies(Data(contentsOf: directory.appending(path: Files.movies)))
            // Without meta: no etags, no `lastUpdated`, and the catalog counts as stale (refreshed in full).
            let meta = (try? Data(contentsOf: directory.appending(path: Files.meta)))
                .flatMap { try? JSONDecoder().decode(Meta.self, from: $0) }
            return (Catalog(shows: shows, movies: movies, fetchedAt: meta?.fetchedAt ?? .distantPast), meta)
        } catch {
            return nil
        }
    }
}
