import Foundation
import OroroCore
import OroroTestSupport
import Testing
@testable import OroroFeatures

@Suite @MainActor struct TitleMenuTests {
    let show = Samples.show(7, newestVideo: Samples.now)
    let movie = Samples.movie(3)
    let episode = EpisodeRef(episodeID: 701, season: 1, number: 2)

    func showItem(episode: EpisodeRef? = nil) -> ShelfItem { ShelfItem(title: show, episode: episode) }
    func movieItem() -> ShelfItem { ShelfItem(title: movie) }

    func environment(_ library: InMemoryLibraryStore) -> AppEnvironment {
        AppEnvironment(api: FakeAPI(), catalog: FakeCatalog(), library: library, details: FakeDetails(),
                       credentials: InMemoryCredentialStore(), newEpisodes: FakeNewEpisodes())
    }

    func progressLibrary() -> Library {
        var library = Library()
        library.recordProgress(
            PlayableID(kind: .episode, id: 701),
            show: ShowContext(showID: 7, season: 1, number: 2, episodeName: nil, newestVideo: nil),
            position: 300, duration: 1_000, now: Samples.now
        )
        return library
    }

    @Test func plainOffersAddOrRemove() {
        #expect(TitleMenuModel.actions(for: showItem(), context: .plain, library: Library()) == [.addToList])
        var library = Library()
        library.toggleMyList(show.id, newestVideo: nil, now: Samples.now)
        #expect(TitleMenuModel.actions(for: showItem(), context: .plain, library: library) == [.removeFromList])
    }

    @Test func continueWatchingActionsForMovieAndShow() {
        #expect(TitleMenuModel.actions(for: movieItem(), context: .continueWatching, library: Library())
            == [.addToList, .removeFromContinueWatching, .markWatched])
        #expect(TitleMenuModel.actions(for: showItem(episode: episode), context: .continueWatching, library: Library())
            == [.addToList, .removeFromContinueWatching, .markWatched, .goToShow])
    }

    @Test func newEpisodesActions() {
        var library = Library()
        library.toggleMyList(show.id, newestVideo: nil, now: Samples.now)
        #expect(TitleMenuModel.actions(for: showItem(episode: episode), context: .newEpisodes, library: library)
            == [.removeFromList, .dismissNew, .markWatched, .goToShow])
    }

    @Test func performAddAndRemove() async {
        let store = InMemoryLibraryStore()
        let env = environment(store)
        let router = TabRouter()
        await TitleMenuModel.perform(.addToList, item: showItem(), environment: env, router: router)
        #expect(await store.snapshot().isInMyList(show.id))
        await TitleMenuModel.perform(.addToList, item: showItem(), environment: env, router: router)
        #expect(await store.snapshot().myList.count == 1)
        await TitleMenuModel.perform(.removeFromList, item: showItem(), environment: env, router: router)
        #expect(await store.snapshot().myList.isEmpty)
    }

    @Test func performRemoveFromContinueWatching() async {
        let store = InMemoryLibraryStore(progressLibrary())
        await TitleMenuModel.perform(.removeFromContinueWatching, item: showItem(episode: episode),
                                     environment: environment(store), router: TabRouter())
        let result = await store.snapshot()
        #expect(result.progress.isEmpty)
        #expect(result.upNext[7] == nil)
        #expect(result.watchedEpisodes.isEmpty)
    }

    @Test func performMarkWatched() async {
        var library = progressLibrary()
        library.upNext[7] = UpNextEntry(ref: episode, setAt: Samples.now)
        let store = InMemoryLibraryStore(library)
        let env = environment(store)
        await TitleMenuModel.perform(.markWatched, item: showItem(episode: episode), environment: env, router: TabRouter())
        let result = await store.snapshot()
        #expect(result.watchedEpisodes == [701])
        #expect(result.progress.isEmpty)

        await TitleMenuModel.perform(.markWatched, item: movieItem(), environment: env, router: TabRouter())
        #expect(await store.snapshot().watchedMovies == [3])
    }

    @Test func performDismissNew() async {
        var library = Library()
        library.followed[7] = FollowState(seenNewestVideo: Samples.now.addingTimeInterval(-Samples.day), started: true)
        let store = InMemoryLibraryStore(library)
        await TitleMenuModel.perform(.dismissNew, item: showItem(episode: episode),
                                     environment: environment(store), router: TabRouter())
        #expect(await store.snapshot().followed[7]?.seenNewestVideo == Samples.now)
    }

    @Test func performGoToShowPushesRoute() async {
        let router = TabRouter()
        await TitleMenuModel.perform(.goToShow, item: showItem(episode: episode),
                                     environment: environment(InMemoryLibraryStore()), router: router)
        #expect(router.path == [.show(7)])
    }

    func detailEnvironment(_ store: InMemoryLibraryStore, details: FakeDetails) -> AppEnvironment {
        AppEnvironment(api: FakeAPI(), catalog: FakeCatalog(), library: store, details: details,
                       credentials: InMemoryCredentialStore(), newEpisodes: FakeNewEpisodes())
    }

    func threeEpisodes() -> ShowDetail {
        ShowDetail(title: show, seasonCount: 1, episodes: (1...3).map {
            Episode(id: 700 + $0, showID: 7, season: 1, number: $0)
        })
    }

    func detailsReturning(_ result: Result<ShowDetail, APIError>) async -> FakeDetails {
        let details = FakeDetails()
        await details.configure { $0.showResults[7] = result }
        return details
    }

    @Test func markWatchedAdvancesToNextEpisode() async {
        let store = InMemoryLibraryStore(progressLibrary())
        let details = await detailsReturning(.success(threeEpisodes()))
        let e1 = EpisodeRef(episodeID: 701, season: 1, number: 1)
        await TitleMenuModel.perform(.markWatched, item: showItem(episode: e1),
                                     environment: detailEnvironment(store, details: details), router: TabRouter())
        let result = await store.snapshot()
        #expect(result.upNext[7]?.ref == EpisodeRef(episodeID: 702, season: 1, number: 2))
        let catalog = Catalog(shows: [show], movies: [], fetchedAt: Samples.now)
        let rows = LibraryQueries.continueWatching(result, catalog: catalog)
        #expect(rows.map(\.title.id) == [show.id])
        #expect(rows.first?.episode?.episodeID == 702)
    }

    @Test func markWatchedOnLastEpisodeLeavesContinueWatching() async {
        let store = InMemoryLibraryStore(progressLibrary())
        let details = await detailsReturning(.success(threeEpisodes()))
        let e3 = EpisodeRef(episodeID: 703, season: 1, number: 3)
        await TitleMenuModel.perform(.markWatched, item: showItem(episode: e3),
                                     environment: detailEnvironment(store, details: details), router: TabRouter())
        let result = await store.snapshot()
        #expect(result.upNext[7] == nil)
        #expect(result.watchedEpisodes == [703])
    }

    @Test func markWatchedFetchFailureFallsBack() async {
        let store = InMemoryLibraryStore(progressLibrary())
        let details = await detailsReturning(.failure(.offline))
        await TitleMenuModel.perform(.markWatched, item: showItem(episode: episode),
                                     environment: detailEnvironment(store, details: details), router: TabRouter())
        let result = await store.snapshot()
        #expect(result.watchedEpisodes == [701])
        #expect(result.upNext[7] == nil)
        #expect(result.progress.isEmpty)
    }

    @Test func markWatchedNotOfferedForShowWithoutEpisode() {
        #expect(TitleMenuModel.actions(for: showItem(), context: .continueWatching, library: Library())
            == [.addToList, .removeFromContinueWatching, .goToShow])
    }

    @Test func dismissNewNoOpWithoutNewestVideo() async {
        var library = Library()
        let seen = Samples.now.addingTimeInterval(-Samples.day)
        library.followed[7] = FollowState(seenNewestVideo: seen, started: true)
        let store = InMemoryLibraryStore(library)
        let item = ShelfItem(title: Samples.show(7), episode: episode)
        await TitleMenuModel.perform(.dismissNew, item: item, environment: environment(store), router: TabRouter())
        #expect(await store.snapshot().followed[7]?.seenNewestVideo == seen)
    }
}
