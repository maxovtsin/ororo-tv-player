import Foundation
import OroroCore
import OroroTestSupport
import Synchronization
import Testing
@testable import OroroStore

/// A class so `deinit` removes each test's temp directory.
@Suite final class CatalogRepositoryTests {
    // MARK: - Fixture data

    /// Raw bytes → titles. "shows"/"movies" are what `FakeAPI` serves by default; the "-v2" lists are smaller updates.
    static let showsV2 = Array(Samples.catalog.shows.prefix(10))
    static let moviesV2 = Array(Samples.catalog.movies.prefix(7))

    static let decodeShows: @Sendable (Data) throws -> [Title] = { data in
        switch String(bytes: data, encoding: .utf8) {
        case "shows": Samples.catalog.shows
        case "shows-v2": showsV2
        default: throw APIError.decoding
        }
    }

    static let decodeMovies: @Sendable (Data) throws -> [Title] = { data in
        switch String(bytes: data, encoding: .utf8) {
        case "movies": Samples.catalog.movies
        case "movies-v2": moviesV2
        default: throw APIError.decoding
        }
    }

    static let showsV2Response = Conditional.fresh(ListResponse(titles: showsV2, rawData: Data("shows-v2".utf8), etag: "\"shows-2\""))
    static let moviesV2Response = Conditional.fresh(ListResponse(titles: moviesV2, rawData: Data("movies-v2".utf8), etag: "\"movies-2\""))

    let directory: URL
    let api = FakeAPI()
    let credentials = InMemoryCredentialStore()

    init() {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "CatalogRepositoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func makeRepository(api: FakeAPI? = nil, credentials: InMemoryCredentialStore? = nil, useETag: Bool = true) -> CatalogRepository {
        CatalogRepository(api: api ?? self.api, credentials: credentials ?? self.credentials, directory: directory,
                          decodeShows: Self.decodeShows, decodeMovies: Self.decodeMovies, useETag: useETag)
    }

    func fileExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: name).path)
    }

    func fileContents(_ name: String) throws -> String {
        try #require(String(bytes: Data(contentsOf: directory.appending(path: name)), encoding: .utf8))
    }

    // MARK: - Sign-in

    @Test func signInFetchesBothCachesAndSavesCredentials() async throws {
        let repository = makeRepository()
        let reported = Mutex<[Double]>([])

        let catalog = try await repository.signIn(Samples.credentials) { value in reported.withLock { $0.append(value) } }

        #expect(catalog.shows == Samples.catalog.shows)
        #expect(catalog.movies == Samples.catalog.movies)
        #expect(await api.showsCalls == 1)
        #expect(await api.moviesCalls == 1)
        #expect(await api.showsIfNoneMatch == [nil])
        #expect(await api.lastCredentials == Samples.credentials)
        #expect(credentials.stored == Samples.credentials)
        #expect(await repository.current() == catalog)
        #expect(await repository.lastUpdated() == catalog.fetchedAt)
        // Each download reports 1 when done; overall progress is the mean of the two. `/shows` succeeding is
        // reported explicitly just past 0.5, even when no Content-Length means no byte progress.
        #expect(reported.withLock { $0 } == [0.5, CatalogRepository.showsCompletedProgress, 1.0])
        #expect(try fileContents("shows.json") == "shows")
        #expect(try fileContents("movies.json") == "movies")
        #expect(fileExists("meta.json"))
        // Only the final files, no temp leftovers.
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(names == ["meta.json", "movies.json", "shows.json"])
    }

    @Test func signInWith401ThrowsAndSavesNothing() async throws {
        await api.configure { $0.showsResult = .failure(.unauthorized) }
        let repository = makeRepository()

        await #expect(throws: APIError.unauthorized) {
            _ = try await repository.signIn(Samples.credentials, progress: nil)
        }

        #expect(await api.moviesCalls == 0)
        #expect(credentials.stored == nil)
        #expect(credentials.saveCount == 0)
        #expect(await repository.current() == nil)
        #expect(!fileExists("shows.json"))
        #expect(!fileExists("movies.json"))
        #expect(!fileExists("meta.json"))
    }

    // MARK: - Cache

    @Test func loadCachedReadsWhatSignInWrote() async throws {
        let signedIn = try await makeRepository().signIn(Samples.credentials, progress: nil)

        let relaunched = makeRepository(api: FakeAPI())
        let cached = try #require(await relaunched.loadCached())

        #expect(cached == signedIn)
        #expect(cached.shows.count == 48)
        #expect(cached.movies.count == 48)
        #expect(await relaunched.current() == signedIn)
        #expect(await relaunched.lastUpdated() == signedIn.fetchedAt)
    }

    @Test func loadCachedIsNilWithoutFiles() async throws {
        #expect(await makeRepository().loadCached() == nil)

        // One list missing → nil.
        _ = try await makeRepository().signIn(Samples.credentials, progress: nil)
        try FileManager.default.removeItem(at: directory.appending(path: "movies.json"))
        let missingMovies = makeRepository()
        #expect(await missingMovies.loadCached() == nil)
        #expect(await missingMovies.current() == nil)

        // Undecodable list → nil.
        try Data("garbage".utf8).write(to: directory.appending(path: "movies.json"))
        #expect(await makeRepository().loadCached() == nil)
    }

    // MARK: - Refresh

    @Test func refreshSkipsWhenFresh() async throws {
        let signedIn = try await makeRepository().signIn(Samples.credentials, progress: nil)
        let freshAPI = FakeAPI()
        let repository = makeRepository(api: freshAPI)
        _ = await repository.loadCached()

        let changed = try await repository.refresh(force: false, now: signedIn.fetchedAt.addingTimeInterval(CatalogRepository.staleness - 1))

        #expect(changed == false)
        #expect(await freshAPI.totalCalls == 0)
        #expect(await repository.current() == signedIn)
    }

    @Test func refreshFetchesWhenStale() async throws {
        let repository = makeRepository()
        let signedIn = try await repository.signIn(Samples.credentials, progress: nil)
        await api.configure {
            $0.showsResult = .success(Self.showsV2Response)
            $0.moviesResult = .success(Self.moviesV2Response)
        }
        let now = signedIn.fetchedAt.addingTimeInterval(CatalogRepository.staleness)

        let changed = try await repository.refresh(force: false, now: now)

        #expect(changed)
        #expect(await api.showsCalls == 2)
        #expect(await api.moviesCalls == 2)
        let current = try #require(await repository.current())
        #expect(current.shows == Self.showsV2)
        #expect(current.movies == Self.moviesV2)
        #expect(current.fetchedAt == now)
        #expect(await repository.lastUpdated() == now)
        #expect(try fileContents("shows.json") == "shows-v2")
        #expect(try fileContents("movies.json") == "movies-v2")
        #expect(await makeRepository(api: FakeAPI()).loadCached() == current)
    }

    @Test func forceRefreshIgnoresFreshness() async throws {
        let repository = makeRepository()
        let signedIn = try await repository.signIn(Samples.credentials, progress: nil)
        await api.configure { $0.showsResult = .success(Self.showsV2Response) }
        let now = signedIn.fetchedAt.addingTimeInterval(60)

        let changed = try await repository.refresh(force: true, now: now)

        #expect(changed)
        #expect(await api.showsCalls == 2)
        #expect(await api.moviesCalls == 2)
        #expect(await repository.current()?.shows == Self.showsV2)
        #expect(await repository.lastUpdated() == now)
    }

    @Test func refreshSendsStoredEtagsAndKeepsListOn304() async throws {
        let repository = makeRepository()
        let signedIn = try await repository.signIn(Samples.credentials, progress: nil)
        await api.configure {
            $0.showsResult = .success(.notModified)
            $0.moviesResult = .success(Self.moviesV2Response)
        }
        let now = signedIn.fetchedAt.addingTimeInterval(CatalogRepository.staleness + 1)

        let changed = try await repository.refresh(force: false, now: now)

        #expect(changed)
        #expect(await api.showsIfNoneMatch == [nil, "\"shows-1\""])
        #expect(await api.moviesIfNoneMatch == [nil, "\"movies-1\""])
        let current = try #require(await repository.current())
        #expect(current.shows == Samples.catalog.shows)
        #expect(current.movies == Self.moviesV2)
        #expect(try fileContents("shows.json") == "shows")
        #expect(try fileContents("movies.json") == "movies-v2")

        // The new movies etag is persisted: a relaunched repository sends it.
        let relaunchedAPI = FakeAPI()
        await relaunchedAPI.configure {
            $0.showsResult = .success(.notModified)
            $0.moviesResult = .success(.notModified)
        }
        let relaunched = makeRepository(api: relaunchedAPI)
        #expect(await relaunched.loadCached() == current)
        _ = try await relaunched.refresh(force: true, now: now)
        #expect(await relaunchedAPI.showsIfNoneMatch == ["\"shows-1\""])
        #expect(await relaunchedAPI.moviesIfNoneMatch == ["\"movies-2\""])
    }

    @Test func refreshWithBoth304ReturnsFalseButUpdatesFetchedAt() async throws {
        let repository = makeRepository()
        let signedIn = try await repository.signIn(Samples.credentials, progress: nil)
        await api.configure {
            $0.showsResult = .success(.notModified)
            $0.moviesResult = .success(.notModified)
        }
        let now = signedIn.fetchedAt.addingTimeInterval(CatalogRepository.staleness + 1)

        let changed = try await repository.refresh(force: false, now: now)

        #expect(changed == false)
        #expect(await repository.lastUpdated() == now)
        let current = try #require(await repository.current())
        #expect(current.shows == signedIn.shows)
        #expect(current.movies == signedIn.movies)
        #expect(current.fetchedAt == now)
        // Persisted: a relaunched repository considers itself fresh.
        let relaunchedAPI = FakeAPI()
        let relaunched = makeRepository(api: relaunchedAPI)
        #expect(await relaunched.loadCached()?.fetchedAt == now)
        #expect(try await relaunched.refresh(force: false, now: now.addingTimeInterval(60)) == false)
        #expect(await relaunchedAPI.totalCalls == 0)
    }

    @Test func failedRefreshKeepsOldCatalog() async throws {
        let repository = makeRepository()
        let signedIn = try await repository.signIn(Samples.credentials, progress: nil)
        await api.configure {
            $0.showsResult = .success(Self.showsV2Response)
            $0.moviesResult = .failure(.offline)
        }

        await #expect(throws: APIError.offline) {
            _ = try await repository.refresh(force: true, now: signedIn.fetchedAt.addingTimeInterval(60))
        }

        #expect(await repository.current() == signedIn)
        #expect(await repository.lastUpdated() == signedIn.fetchedAt)
        #expect(try fileContents("shows.json") == "shows")
        #expect(try fileContents("movies.json") == "movies")
        #expect(await makeRepository(api: FakeAPI()).loadCached() == signedIn)
    }

    struct SimulatedCrash: Error {}

    @Test func metaIsReplacedLastSoACrashLeavesOldMeta() async throws {
        let repository = makeRepository()
        let signedIn = try await repository.signIn(Samples.credentials, progress: nil)
        await api.configure {
            $0.showsResult = .success(Self.showsV2Response)
            $0.moviesResult = .success(Self.moviesV2Response)
        }
        let replaced = Mutex<[String]>([])
        await repository.setBeforeReplace { name in
            replaced.withLock { $0.append(name) }
            if name == "meta.json" { throw SimulatedCrash() }
        }

        await #expect(throws: SimulatedCrash.self) {
            _ = try await repository.refresh(force: true, now: signedIn.fetchedAt.addingTimeInterval(60))
        }

        #expect(replaced.withLock { $0 } == ["shows.json", "movies.json", "meta.json"])
        #expect(await repository.current() == signedIn)
        // On disk: new lists next to the OLD meta, so the next refresh sends the old etags (server answers 200).
        let relaunchedAPI = FakeAPI()
        let relaunched = makeRepository(api: relaunchedAPI)
        let cached = try #require(await relaunched.loadCached())
        #expect(cached.shows == Self.showsV2)
        #expect(await relaunched.lastUpdated() == signedIn.fetchedAt)
        _ = try await relaunched.refresh(force: true, now: signedIn.fetchedAt.addingTimeInterval(120))
        #expect(await relaunchedAPI.showsIfNoneMatch == ["\"shows-1\""])
        #expect(await relaunchedAPI.moviesIfNoneMatch == ["\"movies-1\""])
    }

    @Test func loadCachedWithoutMetaHasNoLastUpdatedAndIsStale() async throws {
        _ = try await makeRepository().signIn(Samples.credentials, progress: nil)
        try FileManager.default.removeItem(at: directory.appending(path: "meta.json"))
        let relaunchedAPI = FakeAPI()
        let relaunched = makeRepository(api: relaunchedAPI)

        #expect(await relaunched.loadCached()?.shows == Samples.catalog.shows)
        #expect(await relaunched.lastUpdated() == nil)
        #expect(try await relaunched.refresh(force: false, now: Date()))
        #expect(await relaunchedAPI.showsIfNoneMatch == [nil])
    }

    @Test func clearDuringRefreshIsNotUndone() async throws {
        let repository = makeRepository()
        let signedIn = try await repository.signIn(Samples.credentials, progress: nil)
        await api.configure {
            $0.showsResult = .success(Self.showsV2Response)
            $0.moviesResult = .success(Self.moviesV2Response)
            $0.delay = .milliseconds(100)
        }

        let refresh = Task { try await repository.refresh(force: true, now: signedIn.fetchedAt.addingTimeInterval(60)) }
        while await api.showsCalls < 2 { await Task.yield() }
        await repository.clear()

        #expect(try await refresh.value == false)
        #expect(await repository.current() == nil)
        #expect(await repository.lastUpdated() == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func useETagFalseNeverSendsIfNoneMatch() async throws {
        let repository = makeRepository(useETag: false)
        let signedIn = try await repository.signIn(Samples.credentials, progress: nil)

        _ = try await repository.refresh(force: true, now: signedIn.fetchedAt.addingTimeInterval(60))
        _ = try await repository.refresh(force: true, now: signedIn.fetchedAt.addingTimeInterval(120))

        #expect(await api.showsIfNoneMatch == [nil, nil, nil])
        #expect(await api.moviesIfNoneMatch == [nil, nil, nil])
    }

    // MARK: - Home snapshot and clear

    static let snapshot = HomeContent(
        hero: [HeroItem(title: Samples.catalog.shows[0], action: .playFirstEpisode),
               HeroItem(title: Samples.catalog.movies[0], action: .playMovie)],
        shelves: [Shelf(id: "popularShows", kind: .popularShows,
                        items: Samples.catalog.shows.prefix(3).map { ShelfItem(title: $0, badge: .new) },
                        totalCount: 48),
                  Shelf(id: "genre-Drama", kind: .genre("Drama"),
                        items: Samples.catalog.movies.prefix(2).map { ShelfItem(title: $0, progress: 0.4) },
                        totalCount: 12)]
    )

    @Test func homeSnapshotRoundTrips() async throws {
        let repository = makeRepository()
        #expect(await repository.homeSnapshot() == nil)

        await repository.saveHomeSnapshot(Self.snapshot)

        #expect(await repository.homeSnapshot() == Self.snapshot)
        #expect(fileExists("home-snapshot.json"))
        #expect(await makeRepository(api: FakeAPI()).homeSnapshot() == Self.snapshot)
    }

    @Test func clearRemovesEverything() async throws {
        let repository = makeRepository()
        _ = try await repository.signIn(Samples.credentials, progress: nil)
        await repository.saveHomeSnapshot(Self.snapshot)

        await repository.clear()

        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(await repository.current() == nil)
        #expect(await repository.lastUpdated() == nil)
        #expect(await repository.homeSnapshot() == nil)
        #expect(await repository.loadCached() == nil)
    }
}
