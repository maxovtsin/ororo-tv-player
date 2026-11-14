import Foundation
import OroroCore
@testable import OroroFeatures
import OroroTestSupport
import Testing

@Suite @MainActor struct HomeViewModelTests {
    private struct Harness {
        let model: HomeViewModel
        let catalog: FakeCatalog
        let library: InMemoryLibraryStore
    }

    private func makeHarness(library: Library = Library(), snapshot: HomeContent? = nil) async -> Harness {
        let catalog = FakeCatalog()
        await catalog.configure { $0.snapshot = snapshot }
        let store = InMemoryLibraryStore(library)
        let environment = AppEnvironment(api: FakeAPI(), catalog: catalog, library: store, details: FakeDetails(),
                                         credentials: InMemoryCredentialStore(), newEpisodes: FakeNewEpisodes())
        return Harness(model: HomeViewModel(environment: environment, now: { Samples.now }), catalog: catalog, library: store)
    }

    private func title(_ kind: TitleKind, _ id: Int) -> Title {
        Samples.catalog.title(TitleID(kind: kind, id: id))!
    }

    private static let personalIDs: Set<String> = ["continueWatching", "newEpisodes", "myList"]

    private func catalogShelves(_ content: HomeContent?) -> [Shelf] {
        (content?.shelves ?? []).filter { !Self.personalIDs.contains($0.id) }
    }

    // MARK: - Appear

    @Test func showsSnapshotBeforeCatalog() async {
        let snapshot = HomeContent(
            hero: [HeroItem(title: title(.movie, 1001), action: .playMovie)],
            shelves: [Shelf(id: "popularShows", kind: .popularShows, items: [ShelfItem(title: title(.show, 101))], totalCount: 1)]
        )
        let harness = await makeHarness(snapshot: snapshot)
        #expect(harness.model.content == nil)

        await harness.model.appear(catalog: nil, newEpisodeInfo: [:])

        #expect(harness.model.content == snapshot)
        #expect(await harness.catalog.saveSnapshotCalls == 0)
    }

    @Test func buildsFromCatalogAndSavesSnapshot() async {
        let harness = await makeHarness(snapshot: HomeContent(hero: [], shelves: []))
        let catalog = Samples.catalog

        await harness.model.appear(catalog: catalog, newEpisodeInfo: [:])

        let hero = ShelfBuilder.hero(catalog: catalog, now: Samples.now).map {
            HeroItem(title: $0, action: LibraryQueries.heroAction(for: $0, library: Library()))
        }
        let expected = ShelfBuilder.home(catalog: catalog, hero: hero, continueWatching: [], newEpisodes: [], myList: [],
                                         now: Samples.now)
        #expect(harness.model.content == expected)
        #expect(harness.model.content?.hero.count == 6)
        #expect(Array((harness.model.content?.shelves ?? []).map(\.id).prefix(4))
            == ["popularShows", "latestReleases", "topRatedMovies", "recentlyUpdatedMovies"])
        #expect(await harness.catalog.saveSnapshotCalls == 1)
        #expect(await harness.catalog.snapshot == expected)
    }

    @Test func personalRowsHiddenWhenEmpty() async {
        let empty = await makeHarness()
        await empty.model.appear(catalog: Samples.catalog, newEpisodeInfo: [:])
        let emptyIDs = (empty.model.content?.shelves ?? []).map(\.id)
        #expect(emptyIDs.allSatisfy { !Self.personalIDs.contains($0) })
        #expect(emptyIDs.count == 8)

        var library = Library()
        library.recordProgress(PlayableID(kind: .movie, id: 1001), show: nil, position: 600, duration: 6_000, now: Samples.now)
        library.toggleMyList(TitleID(kind: .movie, id: 1002), newestVideo: nil, now: Samples.now)
        let filled = await makeHarness(library: library)
        await filled.model.appear(catalog: Samples.catalog, newEpisodeInfo: [:])
        let ids = (filled.model.content?.shelves ?? []).map(\.id)
        #expect(Array(ids.prefix(6))
            == ["continueWatching", "popularShows", "latestReleases", "topRatedMovies", "recentlyUpdatedMovies", "myList"])
        #expect(!ids.contains("newEpisodes"))
    }

    @Test func libraryChangeUpdatesContinueWatchingWithoutReorderingCatalogRows() async throws {
        let harness = await makeHarness()
        await harness.model.appear(catalog: Samples.catalog, newEpisodeInfo: [:])
        let before = catalogShelves(harness.model.content)
        let heroShow = try #require(harness.model.content?.hero.first { $0.title.id.kind == .show })
        #expect(heroShow.action == .playFirstEpisode)

        var library = Library()
        library.recordProgress(PlayableID(kind: .movie, id: 1001), show: nil, position: 1_500, duration: 6_000, now: Samples.now)
        let showID = heroShow.title.id.id
        let episodeID = showID * 10_000 + 203
        library.recordProgress(PlayableID(kind: .episode, id: episodeID),
                               show: ShowContext(showID: showID, season: 2, number: 3, episodeName: nil, newestVideo: nil),
                               position: 300, duration: 2_700, now: Samples.now.addingTimeInterval(-60))
        harness.model.libraryChanged(library)

        let shelves = harness.model.content?.shelves ?? []
        let continueWatching = try #require(shelves.first)
        #expect(continueWatching.id == "continueWatching")
        #expect(continueWatching.items.map(\.title.id) == [TitleID(kind: .movie, id: 1001), TitleID(kind: .show, id: showID)])
        #expect(continueWatching.items.first?.progress == 0.25)
        #expect(catalogShelves(harness.model.content) == before)
        let updatedHero = harness.model.content?.hero.first { $0.title.id.id == showID }
        #expect(updatedHero?.action == .resumeEpisode(EpisodeRef(episodeID: episodeID, season: 2, number: 3)))
        #expect(harness.model.library == library)
    }

    @Test func newCatalogAppliedOnlyOnNextAppear() async {
        let harness = await makeHarness()
        let first = Samples.catalog
        let newcomer = Samples.show(500, popularity: 999_999, newestVideo: Samples.now.addingTimeInterval(-3_600), name: "Newcomer")
        let second = Catalog(shows: [newcomer] + first.shows, movies: first.movies, fetchedAt: Samples.now.addingTimeInterval(3_600))

        await harness.model.appear(catalog: first, newEpisodeInfo: [:])
        let built = harness.model.content
        #expect(built?.shelves.first { $0.id == "popularShows" }?.items.first?.title.id != newcomer.id)

        // The session swapped in `second` while Home was visible: only library changes reach the model.
        harness.model.libraryChanged(Library())
        #expect(harness.model.content == built)

        // Re-appearing with the same catalog does not rebuild.
        await harness.model.appear(catalog: first, newEpisodeInfo: [:])
        #expect(await harness.catalog.saveSnapshotCalls == 1)

        await harness.model.appear(catalog: second, newEpisodeInfo: [:])
        #expect(harness.model.content?.shelves.first { $0.id == "popularShows" }?.items.first?.title.id == newcomer.id)
        #expect(await harness.catalog.saveSnapshotCalls == 2)
    }

    @Test func catalogArrivingOverSnapshotWaitsForNextAppear() async {
        let snapshot = HomeContent(
            hero: [HeroItem(title: title(.movie, 1001), action: .playMovie)],
            shelves: [Shelf(id: "popularShows", kind: .popularShows, items: [ShelfItem(title: title(.show, 101))], totalCount: 1)]
        )
        let harness = await makeHarness(snapshot: snapshot)
        await harness.model.appear(catalog: nil, newEpisodeInfo: [:])

        await harness.model.catalogArrived(Samples.catalog, newEpisodeInfo: [:])
        #expect(harness.model.content == snapshot)
        #expect(await harness.catalog.saveSnapshotCalls == 0)

        await harness.model.appear(catalog: Samples.catalog, newEpisodeInfo: [:])
        #expect(harness.model.content != snapshot)
        #expect(harness.model.content?.hero.count == 6)
        #expect(await harness.catalog.saveSnapshotCalls == 1)
    }

    @Test func catalogArrivingOverSkeletonBuildsOnce() async {
        let harness = await makeHarness()
        await harness.model.appear(catalog: nil, newEpisodeInfo: [:])
        #expect(harness.model.content == nil)

        // The screen's appear and the catalog-arrival callback may overlap; the second is a no-op.
        async let first: Void = harness.model.catalogArrived(Samples.catalog, newEpisodeInfo: [:])
        async let second: Void = harness.model.appear(catalog: Samples.catalog, newEpisodeInfo: [:])
        _ = await (first, second)

        #expect(harness.model.content?.hero.count == 6)
        #expect(await harness.catalog.saveSnapshotCalls == 1)
    }

    @Test func focusAreaDrivesExpansionTopAndRestoreTarget() {
        #expect(HomeFocusArea.isExpanded(.hero, lastFocusInHero: false))
        #expect(!HomeFocusArea.isExpanded(.shelf("popularShows"), lastFocusInHero: true))
        #expect(HomeFocusArea.isAtTop(.hero, lastFocusInHero: false))
        #expect(!HomeFocusArea.isAtTop(.shelf("popularShows"), lastFocusInHero: true))
        // Focus left Home from the hero (tab bar, launch): expanded and at top.
        #expect(HomeFocusArea.isExpanded(nil, lastFocusInHero: true))
        #expect(HomeFocusArea.isAtTop(nil, lastFocusInHero: true))

        // Leaving the screen (nil) keeps the last area; hero and shelves set it.
        #expect(HomeFocusArea.lastFocusInHero(after: .shelf("myList"), previous: true) == false)
        #expect(HomeFocusArea.lastFocusInHero(after: .hero, previous: false) == true)
        #expect(HomeFocusArea.lastFocusInHero(after: nil, previous: false) == false)

        // Restore: the hero when focus was last there or nothing is remembered, else the anchored shelf.
        #expect(HomeFocusArea.restoreTarget(lastFocusInHero: true, anchor: "popularShows") == .hero)
        #expect(HomeFocusArea.restoreTarget(lastFocusInHero: false, anchor: nil) == .hero)
        #expect(HomeFocusArea.restoreTarget(lastFocusInHero: false, anchor: "popularShows") == .shelf("popularShows"))
    }

    @Test func focusLeavingFromShelfStaysCollapsed() {
        // A shelf tile opened Detail / the player / a context menu: focus leaves Home (nil).
        let last = HomeFocusArea.lastFocusInHero(after: .shelf("continueWatching"), previous: true)
        let afterLeaving = HomeFocusArea.lastFocusInHero(after: nil, previous: last)
        #expect(!HomeFocusArea.isExpanded(nil, lastFocusInHero: afterLeaving))
        #expect(!HomeFocusArea.isAtTop(nil, lastFocusInHero: afterLeaving))
    }

    // MARK: - Actions

    @Test func selectPlayableItemPlays() async {
        let harness = await makeHarness()
        let router = TabRouter(), launcher = PlaybackLauncher()
        let shelf = Shelf(id: "continueWatching", kind: .continueWatching, items: [], totalCount: 0)

        let episode = ShelfItem(title: title(.show, 101), progress: 0.4, episode: EpisodeRef(episodeID: 1_010_203, season: 2, number: 3),
                                playable: PlayableID(kind: .episode, id: 1_010_203))
        harness.model.select(episode, shelf: shelf, router: router, launcher: launcher)
        #expect(launcher.active?.target == .episode(id: 1_010_203, showID: 101))
        #expect(launcher.active?.startOver == false)

        let movie = ShelfItem(title: title(.movie, 1001), progress: 0.2, playable: PlayableID(kind: .movie, id: 1001))
        harness.model.select(movie, shelf: shelf, router: router, launcher: launcher)
        #expect(launcher.active?.target == .movie(1001))
        #expect(router.path.isEmpty)
    }

    @Test func selectPlainItemOpensDetail() async {
        let harness = await makeHarness()
        let router = TabRouter(), launcher = PlaybackLauncher()
        let item = ShelfItem(title: title(.movie, 1002))
        let shelf = Shelf(id: "topRatedMovies", kind: .topRatedMovies, items: [item], totalCount: 1)

        harness.model.select(item, shelf: shelf, router: router, launcher: launcher)

        #expect(router.path == [.movie(1002)])
        #expect(router.zoomSourceID == "topRatedMovies/movie-1002")
        #expect(launcher.active == nil)
    }

    @Test func heroPlayFirstEpisodeTargetsShow() async {
        let harness = await makeHarness()
        let launcher = PlaybackLauncher()

        harness.model.heroPlay(HeroItem(title: title(.show, 101), action: .playFirstEpisode), launcher: launcher)
        #expect(launcher.active?.target == .show(101))

        harness.model.heroPlay(HeroItem(title: title(.movie, 1001), action: .playMovie), launcher: launcher)
        #expect(launcher.active?.target == .movie(1001))

        let ref = EpisodeRef(episodeID: 1_020_105, season: 1, number: 5)
        harness.model.heroPlay(HeroItem(title: title(.show, 102), action: .resumeEpisode(ref)), launcher: launcher)
        #expect(launcher.active?.target == .episode(id: 1_020_105, showID: 102))

        harness.model.heroPlay(HeroItem(title: title(.show, 102), action: .playEpisode(ref)), launcher: launcher)
        #expect(launcher.active?.target == .episode(id: 1_020_105, showID: 102))
    }

    @Test func toggleListUpdatesLibrary() async {
        let harness = await makeHarness()
        await harness.model.appear(catalog: Samples.catalog, newEpisodeInfo: [:])
        let movie = title(.movie, 1003)

        await harness.model.toggleList(movie)

        #expect(await harness.library.library.myList == [MyListItem(title: movie.id, addedAt: Samples.now)])
        #expect(harness.model.library.isInMyList(movie.id))
        let myList = harness.model.content?.shelves.first { $0.id == "myList" }
        #expect(myList?.items.map(\.title.id) == [movie.id])

        await harness.model.toggleList(movie)

        #expect(await harness.library.library.myList.isEmpty)
        #expect(!harness.model.library.isInMyList(movie.id))
        #expect(harness.model.content?.shelves.contains { $0.id == "myList" } == false)
    }
}
