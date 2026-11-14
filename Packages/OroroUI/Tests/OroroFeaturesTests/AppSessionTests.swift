import Foundation
import OroroCore
import OroroStore
@testable import OroroFeatures
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
                        library: Library = Library(), newEpisodes: [Int: NewEpisodeInfo] = [:],
                        now: @escaping @MainActor () -> Date = { Samples.now }) {
            credentials = InMemoryCredentialStore(stored)
            catalog = FakeCatalog(cached: cached, signInResult: signInResult, credentials: credentials)
            self.library = InMemoryLibraryStore(library)
            self.newEpisodes = FakeNewEpisodes(result: newEpisodes)
            session = AppSession(environment: AppEnvironment(
                api: api, catalog: catalog, library: self.library, details: details,
                credentials: credentials, newEpisodes: self.newEpisodes
            ), now: now)
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

    /// The sign-in sheet waits for the player cover to go away (it can't present over it).
    @Test func reauthSheetWaitsForThePlayerToClose() {
        #expect(ReauthGate.presents(needsReauth: true, playerActive: false))
        #expect(!ReauthGate.presents(needsReauth: true, playerActive: true))
        #expect(!ReauthGate.presents(needsReauth: false, playerActive: false))
        #expect(!ReauthGate.presents(needsReauth: false, playerActive: true))
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

    @Test func newEpisodeResolutionSkipsContinueWatchingShows() async throws {
        let candidates = Samples.catalog.shows.filter { $0.newestVideo != nil }
        let inProgress = try #require(candidates.first), followedOnly = try #require(candidates.dropFirst().first)
        var library = Library(followed: [
            inProgress.id.id: FollowState(seenNewestVideo: .distantPast, started: true),
            followedOnly.id.id: FollowState(seenNewestVideo: .distantPast, started: true)
        ])
        library.recordProgress(PlayableID(kind: .episode, id: inProgress.id.id * 10_000 + 102),
                               show: ShowContext(showID: inProgress.id.id, season: 1, number: 2, episodeName: nil, newestVideo: nil),
                               position: 300, duration: 2_400, now: Samples.now)
        let harness = Harness(cached: Samples.catalog, library: library)
        await harness.session.start()
        #expect(await eventually { await harness.catalog.refreshCalls == 1 })

        await harness.session.refresh(force: true)
        #expect(await harness.newEpisodes.lastShows.map(\.id) == [followedOnly.id])
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

    // MARK: - fix round 1

    @Test func signOutDuringLaunchDecodeStaysSignedOut() async {
        let gated = GatedCatalog(snapshot: HomeContent(hero: [], shelves: []))
        let credentials = InMemoryCredentialStore(Samples.credentials)
        let session = Self.session(catalog: gated, credentials: credentials)
        await session.start()
        #expect(session.state == .ready)
        #expect(await eventually { await gated.isWaiting(.loadCached) })

        await session.signOut()
        await gated.open(.loadCached)  // resolves with no cache
        #expect(await eventually { !session.isLaunching })
        #expect(session.state == .signedOut)
        #expect(await gated.signInCalls == 0)
    }

    @Test func signInStaysSignedOutUntilShowsSucceedThenShowsProgress() async throws {
        let credentials = InMemoryCredentialStore()
        let gated = GatedCatalog(credentials: credentials)
        let session = Self.session(catalog: gated, credentials: credentials)
        await session.start()
        let signIn = Task { try await session.signIn(email: "user@example.invalid", password: "placeholder") }

        #expect(await eventually { await gated.isWaiting(.shows) })
        for _ in 0..<100 { await Task.yield() }  // let the 0.25 progress hop land
        #expect(session.state == .signedOut)

        await gated.open(.shows)
        #expect(await eventually { await gated.isWaiting(.movies) })
        #expect(await eventually { session.state == .loadingCatalog(CatalogRepository.showsCompletedProgress) })

        await gated.open(.movies)
        try await signIn.value
        #expect(session.state == .ready)
        #expect(session.catalog == Samples.catalog)
        #expect(credentials.stored == Samples.credentials)
    }

    @Test func signInUnauthorizedNeverLeavesSignedOut() async {
        let gated = GatedCatalog(showsError: .unauthorized)
        let session = Self.session(catalog: gated, credentials: InMemoryCredentialStore())
        await session.start()
        let signIn = Task { try await session.signIn(email: "user@example.invalid", password: "wrong") }
        #expect(await eventually { await gated.isWaiting(.shows) })
        #expect(session.state == .signedOut)
        await gated.open(.shows)
        await #expect(throws: APIError.unauthorized) { try await signIn.value }
        for _ in 0..<100 { await Task.yield() }
        #expect(session.state == .signedOut)
    }

    @Test func signInFailingAfterShowsIsFailedAndRepeatedRetriesUseTheEnteredCredentials() async throws {
        let credentials = InMemoryCredentialStore()
        let gated = GatedCatalog(credentials: credentials, moviesError: .offline)
        let session = Self.session(catalog: gated, credentials: credentials)
        await session.start()
        await gated.open(.shows)
        await gated.open(.movies)
        await #expect(throws: APIError.offline) {
            try await session.signIn(email: "user@example.invalid", password: "placeholder")
        }
        #expect(session.state == .failed(.offline))
        #expect(credentials.stored == nil)

        await session.retry()  // still offline
        #expect(session.state == .failed(.offline))
        await session.retry()  // and again
        #expect(session.state == .failed(.offline))
        #expect(await gated.signInCalls == 3)
        #expect(credentials.stored == nil)

        await gated.setMoviesError(nil)
        await session.retry()
        #expect(session.state == .ready)
        #expect(await gated.signInCalls == 4)
        #expect(session.storedEmail == Samples.credentials.email)
        #expect(await gated.lastSignInCredentials == Samples.credentials)
        #expect(credentials.stored == Samples.credentials)
    }

    @Test func sceneBecameActiveRefreshesOnlyWhenStale() async {
        var clock = Samples.now.addingTimeInterval(3_600)
        let harness = Harness(cached: Samples.catalog, now: { clock })
        await harness.session.start()
        #expect(await eventually { !harness.session.isLaunching })
        #expect(await harness.catalog.refreshCalls == 1)

        await harness.session.sceneBecameActive()  // 1 h old: fresh
        #expect(await harness.catalog.refreshCalls == 1)

        clock = Samples.now.addingTimeInterval(7 * 3_600)  // FakeCatalog's lastUpdated is still fetchedAt
        await harness.catalog.configure { $0.lastUpdatedDate = Samples.now }
        await harness.session.sceneBecameActive()
        #expect(await harness.catalog.refreshCalls == 2)
    }

    @Test func sceneBecameActiveIsSkippedDuringLaunch() async {
        let gated = GatedCatalog(snapshot: HomeContent(hero: [], shelves: []), cached: Samples.catalog)
        let session = Self.session(catalog: gated, credentials: InMemoryCredentialStore(Samples.credentials),
                                   now: { Samples.now.addingTimeInterval(7 * 3_600) })
        await session.start()
        #expect(await eventually { await gated.isWaiting(.loadCached) })
        await session.sceneBecameActive()
        #expect(await gated.loadCachedCalls == 1)
        #expect(await gated.refreshCalls == 0)
        await gated.open(.loadCached)
        #expect(await eventually { !session.isLaunching })
        #expect(await gated.refreshCalls == 1)
    }

    private static func session(catalog: GatedCatalog, credentials: InMemoryCredentialStore,
                                now: @escaping @MainActor () -> Date = { Samples.now }) -> AppSession {
        AppSession(environment: AppEnvironment(
            api: FakeAPI(), catalog: catalog, library: InMemoryLibraryStore(), details: FakeDetails(),
            credentials: credentials, newEpisodes: FakeNewEpisodes()
        ), now: now)
    }
}

/// A catalog whose `loadCached` and sign-in downloads wait for the test to open them. Sign-in mirrors
/// `CatalogRepository`: `/shows` then `/movies`, progress is the mean of the two downloads, and the
/// credentials are saved only after both succeed.
actor GatedCatalog: CatalogProviding {
    enum Step: Hashable { case loadCached, shows, movies }

    private var catalog: Catalog?
    private let snapshot: HomeContent?
    private var cached: Catalog?
    private let showsError: APIError?
    private var moviesError: APIError?
    private var opened: Set<Step> = []
    private var waiters: [Step: CheckedContinuation<Void, Never>] = [:]
    private(set) var signInCalls = 0, loadCachedCalls = 0, refreshCalls = 0
    private(set) var lastSignInCredentials: Credentials?

    private let storedCredentials: (any CredentialStoring)?

    init(credentials: (any CredentialStoring)? = nil, snapshot: HomeContent? = nil, cached: Catalog? = nil,
         showsError: APIError? = nil, moviesError: APIError? = nil) {
        storedCredentials = credentials
        self.snapshot = snapshot
        self.cached = cached
        self.showsError = showsError
        self.moviesError = moviesError
    }

    func open(_ step: Step) {
        opened.insert(step)
        waiters.removeValue(forKey: step)?.resume()
    }

    func isWaiting(_ step: Step) -> Bool { waiters[step] != nil }

    func setMoviesError(_ error: APIError?) { moviesError = error }

    private func wait(_ step: Step) async {
        guard !opened.contains(step) else { return }
        await withCheckedContinuation { waiters[step] = $0 }
    }

    func current() async -> Catalog? { catalog }
    func lastUpdated() async -> Date? { catalog?.fetchedAt }

    func signIn(_ c: Credentials, progress: (@Sendable (Double) -> Void)?) async throws -> Catalog {
        signInCalls += 1
        lastSignInCredentials = c
        progress?(0.25)
        await wait(.shows)
        progress?(0.5)  // like the transport, the /shows body is reported before its status is checked
        if let showsError { throw showsError }
        // The repository's explicit tick once `/shows` succeeded (no byte progress: no Content-Length).
        progress?(CatalogRepository.showsCompletedProgress)
        await wait(.movies)
        if let moviesError { throw moviesError }
        progress?(1)
        try storedCredentials?.save(c)
        catalog = Samples.catalog
        return Samples.catalog
    }

    func loadCached() async -> Catalog? {
        loadCachedCalls += 1
        await wait(.loadCached)
        catalog = cached ?? catalog
        return cached
    }

    func refresh(force: Bool, now: Date) async throws -> Bool {
        refreshCalls += 1
        return false
    }

    func homeSnapshot() async -> HomeContent? { snapshot }
    func saveHomeSnapshot(_ content: HomeContent) async {}

    func clear() async {
        catalog = nil
        cached = nil
    }
}
