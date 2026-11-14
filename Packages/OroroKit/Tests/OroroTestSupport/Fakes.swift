import Foundation
import OroroCore
import Synchronization

// Working in-memory fakes for every OroroCore protocol. Each actor exposes its settable state as
// `public var` and a `configure { $0.… = … }` method to change it from outside the actor; call counters
// are `public private(set)`.

// MARK: - Sample details shared by FakeAPI and FakeDetails

public extension Samples {
    static let credentials = Credentials(email: "user@example.invalid", password: "placeholder")

    /// Seasons 1 and 2 with 5 episodes each (`Samples.episodes`), or nil when `id` is not a catalog show.
    static func showDetail(_ id: Int, catalog: Catalog = Samples.catalog) -> ShowDetail? {
        guard let title = catalog.title(TitleID(kind: .show, id: id)) else { return nil }
        return ShowDetail(title: title, seasonCount: 2, episodes: episodes(showID: id, seasons: [1: 5, 2: 5]))
    }

    /// Trailer "trailer-<id>", qualities 480p/720p/1080p, subtitles en + ru; nil when `id` is not a catalog movie.
    static func movieDetail(_ id: Int, withPlayback: Bool, catalog: Catalog = Samples.catalog, now: Date = Samples.now) -> MovieDetail? {
        guard let title = catalog.title(TitleID(kind: .movie, id: id)) else { return nil }
        return MovieDetail(title: title, trailerYouTubeID: "trailer-\(id)", qualities: ["480p", "720p", "1080p"],
                           subtitleLanguages: ["en", "ru"],
                           playback: withPlayback ? playback(path: "movies/\(id)", now: now) : nil)
    }

    /// Decodes the `Samples.episodes` id scheme (showID * 10_000 + season * 100 + number).
    /// Nil when the show is not in the catalog.
    static func episodeDetail(_ id: Int, withPlayback: Bool, catalog: Catalog = Samples.catalog, now: Date = Samples.now) -> EpisodeDetail? {
        let showID = id / 10_000, season = (id % 10_000) / 100, number = id % 100
        guard let show = catalog.title(TitleID(kind: .show, id: showID)) else { return nil }
        let episode = Episode(id: id, showID: showID, name: "Episode \(number)", plot: nil, season: season, number: number,
                              airdate: nil, resolution: .hd, qualities: ["240p", "480p", "720p"])
        return EpisodeDetail(episode: episode, showName: show.name, subtitleLanguages: ["en", "ru"],
                             playback: withPlayback ? playback(path: "episodes/\(id)", now: now) : nil)
    }

    static func playback(path: String, now: Date = Samples.now) -> Playback {
        let base = URL(string: "https://example.invalid/\(path)")!
        return Playback(
            streamURL: base.appending(path: "master.m3u8"),
            subtitles: [Subtitle(lang: "en", url: base.appending(path: "en.vtt")),
                        Subtitle(lang: "ru", url: base.appending(path: "ru.vtt"))],
            fetchedAt: now
        )
    }
}

// MARK: - FakeAPI

public actor FakeAPI: OroroAPI {
    public var showsResult: Result<Conditional<ListResponse>, APIError>
    public var moviesResult: Result<Conditional<ListResponse>, APIError>
    /// Per-id overrides; otherwise details come from `Samples.showDetail` etc. (`.notFound` for unknown ids).
    public var showResults: [Int: Result<ShowDetail, APIError>] = [:]
    public var movieResults: [Int: Result<MovieDetail, APIError>] = [:]
    public var episodeResults: [Int: Result<EpisodeDetail, APIError>] = [:]
    /// When set, every detail call (show/movie/episode) throws it.
    public var detailError: APIError?
    /// Suspends every call for this long before answering (for concurrency tests).
    public var delay: Duration = .zero
    public var catalog: Catalog
    public var now: Date

    public private(set) var showsCalls = 0, moviesCalls = 0
    public private(set) var showCalls = 0, movieCalls = 0, episodeCalls = 0
    public private(set) var showsIfNoneMatch: [String?] = [], moviesIfNoneMatch: [String?] = []
    public private(set) var lastCredentials: Credentials?

    public init(catalog: Catalog = Samples.catalog, now: Date = Samples.now) {
        self.catalog = catalog
        self.now = now
        showsResult = .success(.fresh(ListResponse(titles: catalog.shows, rawData: Data("shows".utf8), etag: "\"shows-1\"")))
        moviesResult = .success(.fresh(ListResponse(titles: catalog.movies, rawData: Data("movies".utf8), etag: "\"movies-1\"")))
    }

    public func configure(_ change: @Sendable (isolated FakeAPI) -> Void) {
        change(self)
    }

    public var totalCalls: Int { showsCalls + moviesCalls + showCalls + movieCalls + episodeCalls }

    public func shows(_ c: Credentials, ifNoneMatch: String?,
                      progress: (@Sendable (Double) -> Void)?) async throws -> Conditional<ListResponse> {
        showsCalls += 1
        showsIfNoneMatch.append(ifNoneMatch)
        lastCredentials = c
        await pause()
        progress?(1)
        return try showsResult.get()
    }

    public func movies(_ c: Credentials, ifNoneMatch: String?,
                       progress: (@Sendable (Double) -> Void)?) async throws -> Conditional<ListResponse> {
        moviesCalls += 1
        moviesIfNoneMatch.append(ifNoneMatch)
        lastCredentials = c
        await pause()
        progress?(1)
        return try moviesResult.get()
    }

    public func show(id: Int, _ c: Credentials) async throws -> ShowDetail {
        showCalls += 1
        lastCredentials = c
        await pause()
        if let detailError { throw detailError }
        if let result = showResults[id] { return try result.get() }
        guard let detail = Samples.showDetail(id, catalog: catalog) else { throw APIError.notFound }
        return detail
    }

    public func movie(id: Int, _ c: Credentials) async throws -> MovieDetail {
        movieCalls += 1
        lastCredentials = c
        await pause()
        if let detailError { throw detailError }
        if let result = movieResults[id] { return try result.get() }
        guard let detail = Samples.movieDetail(id, withPlayback: true, catalog: catalog, now: now) else { throw APIError.notFound }
        return detail
    }

    public func episode(id: Int, _ c: Credentials) async throws -> EpisodeDetail {
        episodeCalls += 1
        lastCredentials = c
        await pause()
        if let detailError { throw detailError }
        if let result = episodeResults[id] { return try result.get() }
        guard let detail = Samples.episodeDetail(id, withPlayback: true, catalog: catalog, now: now) else { throw APIError.notFound }
        return detail
    }

    private func pause() async {
        if delay > .zero { try? await Task.sleep(for: delay) }
    }
}

// MARK: - InMemoryLibraryStore

public actor InMemoryLibraryStore: LibraryStoring {
    public var library: Library
    public private(set) var updateCount = 0, flushCount = 0, eraseCount = 0
    private var continuations: [UUID: AsyncStream<Library>.Continuation] = [:]

    public init(_ library: Library = Library()) {
        self.library = library
    }

    public func configure(_ change: @Sendable (isolated InMemoryLibraryStore) -> Void) {
        change(self)
    }

    public func snapshot() async -> Library {
        library
    }

    public func update(_ mutate: @Sendable (inout Library) -> Void) async {
        mutate(&library)
        updateCount += 1
        publish()
    }

    public func flush() async {
        flushCount += 1
    }

    public func erase() async {
        library = Library()
        eraseCount += 1
        publish()
    }

    /// Emits the library after every `update`/`erase` (not the current value on subscription).
    public func updates() async -> AsyncStream<Library> {
        let (stream, continuation) = AsyncStream<Library>.makeStream()
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return stream
    }

    private func publish() {
        for continuation in continuations.values { continuation.yield(library) }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }
}

// MARK: - FakeCatalog

public actor FakeCatalog: CatalogProviding {
    /// What `current()` returns.
    public var catalog: Catalog?
    /// What `loadCached()` returns (and, when non-nil, installs as `catalog`).
    public var cachedCatalog: Catalog?
    public var lastUpdatedDate: Date?
    public var signInResult: Result<Catalog, APIError>
    /// `refresh` returns this; on `.success(true)` `refreshedCatalog` (if any) becomes `catalog`.
    public var refreshResult: Result<Bool, APIError> = .success(false)
    public var refreshedCatalog: Catalog?
    public var snapshot: HomeContent?
    /// Saved on a successful `signIn` when provided.
    public var credentials: (any CredentialStoring)?

    public private(set) var signInCalls = 0, loadCachedCalls = 0, refreshCalls = 0, clearCalls = 0, saveSnapshotCalls = 0
    public private(set) var lastSignInCredentials: Credentials?
    public private(set) var lastRefreshForce: Bool?

    public init(current: Catalog? = nil, cached: Catalog? = nil,
                signInResult: Result<Catalog, APIError> = .success(Samples.catalog),
                credentials: (any CredentialStoring)? = nil) {
        catalog = current
        cachedCatalog = cached
        lastUpdatedDate = current?.fetchedAt
        self.signInResult = signInResult
        self.credentials = credentials
    }

    public func configure(_ change: @Sendable (isolated FakeCatalog) -> Void) {
        change(self)
    }

    public func current() async -> Catalog? {
        catalog
    }

    public func lastUpdated() async -> Date? {
        lastUpdatedDate
    }

    public func signIn(_ c: Credentials, progress: (@Sendable (Double) -> Void)?) async throws -> Catalog {
        signInCalls += 1
        lastSignInCredentials = c
        progress?(0.5)
        let result = try signInResult.get()
        progress?(1)
        try credentials?.save(c)
        catalog = result
        lastUpdatedDate = result.fetchedAt
        return result
    }

    public func loadCached() async -> Catalog? {
        loadCachedCalls += 1
        if let cachedCatalog {
            catalog = cachedCatalog
            lastUpdatedDate = cachedCatalog.fetchedAt
        }
        return cachedCatalog
    }

    public func refresh(force: Bool, now: Date) async throws -> Bool {
        refreshCalls += 1
        lastRefreshForce = force
        let changed = try refreshResult.get()
        if changed, let refreshedCatalog { catalog = refreshedCatalog }
        lastUpdatedDate = now
        return changed
    }

    public func homeSnapshot() async -> HomeContent? {
        snapshot
    }

    public func saveHomeSnapshot(_ content: HomeContent) async {
        saveSnapshotCalls += 1
        snapshot = content
    }

    public func clear() async {
        clearCalls += 1
        catalog = nil
        cachedCatalog = nil
        snapshot = nil
        lastUpdatedDate = nil
    }
}

// MARK: - FakeDetails

public actor FakeDetails: DetailProviding {
    public var catalog: Catalog
    public var now: Date
    /// Per-id overrides; otherwise details come from `Samples.showDetail` etc. (`.notFound` for unknown ids).
    public var showResults: [Int: Result<ShowDetail, APIError>] = [:]
    public var movieResults: [Int: Result<MovieDetail, APIError>] = [:]
    public var episodeResults: [Int: Result<EpisodeDetail, APIError>] = [:]
    /// When set, every call throws it.
    public var error: APIError?
    /// Suspends every call for this long (lets concurrent callers overlap).
    public var delay: Duration = .zero

    public private(set) var showCalls = 0, movieCalls = 0, episodeCalls = 0
    public private(set) var moviePlaybackCalls = 0, episodePlaybackCalls = 0, clearCalls = 0
    public private(set) var requestedShowIDs: [Int] = []
    /// Highest number of calls that were in flight at the same time.
    public private(set) var maxConcurrentCalls = 0
    private var inFlight = 0

    public init(catalog: Catalog = Samples.catalog, now: Date = Samples.now) {
        self.catalog = catalog
        self.now = now
    }

    public func configure(_ change: @Sendable (isolated FakeDetails) -> Void) {
        change(self)
    }

    public var totalCalls: Int { showCalls + movieCalls + episodeCalls + moviePlaybackCalls + episodePlaybackCalls }

    public func show(id: Int) async throws -> ShowDetail {
        showCalls += 1
        requestedShowIDs.append(id)
        try await enter()
        if let result = showResults[id] { return try result.get() }
        guard let detail = Samples.showDetail(id, catalog: catalog) else { throw APIError.notFound }
        return detail
    }

    public func movie(id: Int) async throws -> MovieDetail {
        movieCalls += 1
        return try await movieDetail(id, withPlayback: false)
    }

    public func episode(id: Int) async throws -> EpisodeDetail {
        episodeCalls += 1
        return try await episodeDetail(id, withPlayback: false)
    }

    public func moviePlayback(id: Int) async throws -> MovieDetail {
        moviePlaybackCalls += 1
        return try await movieDetail(id, withPlayback: true)
    }

    public func episodePlayback(id: Int) async throws -> EpisodeDetail {
        episodePlaybackCalls += 1
        return try await episodeDetail(id, withPlayback: true)
    }

    public func clear() async {
        clearCalls += 1
    }

    private func movieDetail(_ id: Int, withPlayback: Bool) async throws -> MovieDetail {
        try await enter()
        if var override = try movieResults[id]?.get() {
            if !withPlayback { override.playback = nil }
            return override
        }
        guard let detail = Samples.movieDetail(id, withPlayback: withPlayback, catalog: catalog, now: now) else { throw APIError.notFound }
        return detail
    }

    private func episodeDetail(_ id: Int, withPlayback: Bool) async throws -> EpisodeDetail {
        try await enter()
        if var override = try episodeResults[id]?.get() {
            if !withPlayback { override.playback = nil }
            return override
        }
        guard let detail = Samples.episodeDetail(id, withPlayback: withPlayback, catalog: catalog, now: now) else {
            throw APIError.notFound
        }
        return detail
    }

    /// Tracks concurrency, waits `delay`, then throws `error` if set.
    private func enter() async throws {
        inFlight += 1
        maxConcurrentCalls = max(maxConcurrentCalls, inFlight)
        if delay > .zero { try? await Task.sleep(for: delay) } else { await Task.yield() }
        inFlight -= 1
        if let error { throw error }
    }
}

// MARK: - InMemoryCredentialStore

public final class InMemoryCredentialStore: CredentialStoring {
    private struct State {
        var credentials: Credentials?
        var saveError: APIError?
        var loadCount = 0, saveCount = 0, clearCount = 0
    }

    private let state: Mutex<State>

    public init(_ credentials: Credentials? = nil) {
        state = Mutex(State(credentials: credentials))
    }

    /// The stored credentials, without counting as a `load()`.
    public var stored: Credentials? { state.withLock { $0.credentials } }
    public var loadCount: Int { state.withLock { $0.loadCount } }
    public var saveCount: Int { state.withLock { $0.saveCount } }
    public var clearCount: Int { state.withLock { $0.clearCount } }

    /// When set, `save` throws it and stores nothing.
    public func setSaveError(_ error: APIError?) {
        state.withLock { $0.saveError = error }
    }

    public func load() -> Credentials? {
        state.withLock { state in
            state.loadCount += 1
            return state.credentials
        }
    }

    public func save(_ c: Credentials) throws {
        try state.withLock { state in
            state.saveCount += 1
            if let error = state.saveError { throw error }
            state.credentials = c
        }
    }

    public func clear() throws {
        state.withLock { state in
            state.clearCount += 1
            state.credentials = nil
        }
    }
}

// MARK: - FakeNewEpisodes

public actor FakeNewEpisodes: NewEpisodeResolving {
    /// What `resolve` returns (and then caches).
    public var result: [Int: NewEpisodeInfo]
    public var cachedValue: [Int: NewEpisodeInfo] = [:]
    public private(set) var resolveCalls = 0
    public private(set) var lastShows: [Title] = []

    public init(result: [Int: NewEpisodeInfo] = [:]) {
        self.result = result
    }

    public func configure(_ change: @Sendable (isolated FakeNewEpisodes) -> Void) {
        change(self)
    }

    public func cached() async -> [Int: NewEpisodeInfo] {
        cachedValue
    }

    public func resolve(shows: [Title], library: Library) async -> [Int: NewEpisodeInfo] {
        resolveCalls += 1
        lastShows = shows
        cachedValue = result
        return result
    }
}
