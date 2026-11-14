import Foundation
import OroroCore
import OroroFeatures
import OroroTestSupport
import Testing

@Suite @MainActor struct AppSessionTests {
    /// The fakes behind one `AppSession`.
    struct Harness {
        let api = FakeAPI()
        let catalog: FakeCatalog
        let library: InMemoryLibraryStore
        let details = FakeDetails()
        let credentials: InMemoryCredentialStore
        let newEpisodes: FakeNewEpisodes
        let session: AppSession

        @MainActor init(credentials stored: Credentials? = Samples.credentials, cached: Catalog? = nil,
                        signInResult: Result<Catalog, APIError> = .success(Samples.catalog),
                        library: Library = Library(), newEpisodes: [Int: NewEpisodeInfo] = [:]) {
            credentials = InMemoryCredentialStore(stored)
            catalog = FakeCatalog(cached: cached, signInResult: signInResult, credentials: credentials)
            self.library = InMemoryLibraryStore(library)
            self.newEpisodes = FakeNewEpisodes(result: newEpisodes)
            session = AppSession(environment: AppEnvironment(
                api: api, catalog: catalog, library: self.library, details: details,
                credentials: credentials, newEpisodes: self.newEpisodes
            ))
        }
    }

    /// Yields until `condition` holds (background work hops between actors); no wall-clock waits.
    private func eventually(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<5_000 {
            if await condition() { return true }
            await Task.yield()
        }
        return await condition()
    }

    nonisolated private static let changedCatalog = Catalog(shows: Array(Samples.catalog.shows.prefix(10)),
                                                movies: Samples.catalog.movies, fetchedAt: Samples.now.addingTimeInterval(3_600))

    // MARK: - start

    @Test func startWithoutCredentialsIsSignedOut() async {
        let harness = Harness(credentials: nil, cached: Samples.catalog)
        await harness.session.start()
        #expect(harness.session.state == .signedOut)
        #expect(harness.session.catalog == nil)
        #expect(await harness.catalog.loadCachedCalls == 0)
        #expect(await harness.catalog.signInCalls == 0)
    }

    @Test func startWithCacheIsReadyImmediatelyThenRefreshes() async {
        let harness = Harness(cached: Samples.catalog)
        await harness.session.start()
        #expect(harness.session.state == .ready)
        #expect(harness.session.catalog == Samples.catalog)
        #expect(await harness.catalog.signInCalls == 0)
        #expect(await eventually { await harness.catalog.refreshCalls == 1 })
        #expect(await harness.catalog.lastRefreshForce == false)
        #expect(harness.session.state == .ready)
    }

    @Test func startWithSnapshotIsReadyBeforeTheCatalogDecodes() async {
        let harness = Harness(cached: Samples.catalog)
        await harness.catalog.configure { $0.snapshot = HomeContent(hero: [], shelves: []) }
        await harness.session.start()
        #expect(harness.session.state == .ready)
        #expect(await eventually { harness.session.catalog == Samples.catalog })
        #expect(await eventually { await harness.catalog.refreshCalls == 1 })
        #expect(await harness.catalog.loadCachedCalls == 1)
    }

    @Test func startWithCredentialsButNoCacheLoads() async {
        let harness = Harness(cached: nil)
        await harness.session.start()
        #expect(await harness.catalog.signInCalls == 1)
        #expect(await harness.catalog.lastSignInCredentials == Samples.credentials)
        #expect(harness.session.state == .ready)
        #expect(harness.session.catalog == Samples.catalog)
        #expect(harness.session.catalogVersion == 1)
    }

    @Test func startWithoutCacheOfflineFailsThenRetrySucceeds() async {
        let harness = Harness(cached: nil, signInResult: .failure(.offline))
        await harness.session.start()
        #expect(harness.session.state == .failed(.offline))

        await harness.catalog.configure { $0.signInResult = .success(Samples.catalog) }
        await harness.session.retry()
        #expect(harness.session.state == .ready)
        #expect(harness.session.catalog == Samples.catalog)
        #expect(await harness.catalog.signInCalls == 2)
    }

    @Test func startWithoutCacheRejectedCredentialsIsSignedOut() async {
        let harness = Harness(cached: nil, signInResult: .failure(.unauthorized))
        await harness.session.start()
        #expect(harness.session.state == .signedOut)
    }

    // MARK: - sign-in / sign-out

    @Test func signInSuccessBecomesReady() async throws {
        let harness = Harness(credentials: nil)
        await harness.session.start()
        try await harness.session.signIn(email: "user@example.invalid", password: "placeholder")
        #expect(harness.session.state == .ready)
        #expect(harness.session.catalog == Samples.catalog)
        #expect(harness.session.catalogVersion == 1)
        #expect(harness.credentials.stored == Samples.credentials)
    }

    @Test func signInWrongPasswordThrowsUnauthorizedAndStaysSignedOut() async {
        let harness = Harness(credentials: nil, signInResult: .failure(.unauthorized))
        await harness.session.start()
        await #expect(throws: APIError.unauthorized) {
            try await harness.session.signIn(email: "user@example.invalid", password: "wrong")
        }
        #expect(harness.session.state == .signedOut)
        #expect(harness.session.catalog == nil)
        #expect(harness.credentials.stored == nil)
    }

    @Test func signInOfflineThrowsOffline() async {
        let harness = Harness(credentials: nil, signInResult: .failure(.offline))
        await harness.session.start()
        await #expect(throws: APIError.offline) {
            try await harness.session.signIn(email: "user@example.invalid", password: "placeholder")
        }
        #expect(harness.session.state == .signedOut)
    }

    @Test func signInClearsNeedsReauth() async throws {
        let harness = Harness(cached: Samples.catalog)
        await harness.session.start()
        harness.session.report(APIError.unauthorized)
        #expect(harness.session.needsReauth)
        try await harness.session.signIn(email: "user@example.invalid", password: "new-placeholder")
        #expect(harness.session.needsReauth == false)
        #expect(harness.session.state == .ready)
    }

    @Test func signOutClearsCredentialsButKeepsLibrary() async {
        let listed = Library(myList: [MyListItem(title: TitleID(kind: .show, id: 101), addedAt: Samples.now)])
        let harness = Harness(cached: Samples.catalog, library: listed)
        await harness.session.start()
        await harness.session.signOut()
        #expect(harness.session.state == .signedOut)
        #expect(harness.session.catalog == nil)
        #expect(harness.session.newEpisodeInfo.isEmpty)
        #expect(harness.credentials.stored == nil)
        #expect(await harness.details.clearCalls == 1)
        #expect(await harness.catalog.clearCalls == 1)
        #expect(await harness.library.eraseCount == 0)
        #expect(await harness.library.snapshot() == listed)
    }

    // MARK: - errors

    @Test func reportUnauthorizedSetsNeedsReauth() async {
        let harness = Harness(cached: Samples.catalog)
        await harness.session.start()
        harness.session.report(APIError.unauthorized)
        #expect(harness.session.needsReauth)
        #expect(harness.session.state == .ready)
    }

    @Test func reportOtherErrorDoesNot() async {
        let harness = Harness(cached: Samples.catalog)
        await harness.session.start()
        harness.session.report(APIError.offline)
        harness.session.report(APIError.server(status: 500))
        harness.session.report(APIError.notFound)
        harness.session.report(CancellationError())
        #expect(harness.session.needsReauth == false)
        #expect(harness.session.state == .ready)
    }

    // MARK: - refresh

    @Test func refreshBumpsCatalogVersionOnlyWhenChanged() async {
        let harness = Harness(cached: Samples.catalog)
        await harness.session.start()
        #expect(await eventually { await harness.catalog.refreshCalls == 1 })
        let version = harness.session.catalogVersion

        await harness.session.refresh(force: true)
        #expect(harness.session.catalogVersion == version)
        #expect(harness.session.catalog == Samples.catalog)
        #expect(await harness.catalog.lastRefreshForce == true)

        let changed = Self.changedCatalog
        await harness.catalog.configure {
            $0.refreshResult = .success(true)
            $0.refreshedCatalog = changed
        }
        await harness.session.refresh(force: true)
        #expect(harness.session.catalogVersion == version + 1)
        #expect(harness.session.catalog == Self.changedCatalog)
    }

    @Test func refreshResolvesNewEpisodes() async throws {
        let show = try #require(Samples.catalog.shows.first { $0.newestVideo != nil })
        let library = Library(followed: [show.id.id: FollowState(seenNewestVideo: .distantPast, started: true)])
        let info = NewEpisodeInfo(first: EpisodeRef(episodeID: show.id.id * 10_000 + 101, season: 1, number: 1), count: 2)
        let harness = Harness(cached: Samples.catalog, library: library, newEpisodes: [show.id.id: info])
        await harness.session.start()
        #expect(await eventually { await harness.catalog.refreshCalls == 1 })

        await harness.session.refresh(force: true)
        #expect(harness.session.newEpisodeInfo == [show.id.id: info])
        #expect(await harness.newEpisodes.lastShows.map(\.id) == [show.id])
    }

    @Test func failedBackgroundRefreshKeepsReady() async {
        let harness = Harness(cached: Samples.catalog)
        await harness.catalog.configure { $0.refreshResult = .failure(.offline) }
        await harness.session.start()
        #expect(await eventually { await harness.catalog.refreshCalls == 1 })
        await harness.session.refresh(force: true)
        #expect(harness.session.state == .ready)
        #expect(harness.session.catalog == Samples.catalog)
        #expect(harness.session.needsReauth == false)
    }

    @Test func refreshUnauthorizedAsksForReauth() async {
        let harness = Harness(cached: Samples.catalog)
        await harness.catalog.configure { $0.refreshResult = .failure(.unauthorized) }
        await harness.session.start()
        #expect(await eventually { harness.session.needsReauth })
        #expect(harness.session.state == .ready)
    }
}
