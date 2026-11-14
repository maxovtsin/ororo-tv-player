import Foundation
import OroroCore
import OroroFeatures
import OroroTestSupport
import Testing

@Suite @MainActor struct MyListViewModelTests {
    private let catalog = Samples.catalog
    private let now = Samples.now

    private func environment(_ store: InMemoryLibraryStore = InMemoryLibraryStore()) -> AppEnvironment {
        AppEnvironment(api: FakeAPI(), catalog: FakeCatalog(current: Samples.catalog), library: store, details: FakeDetails(),
                       credentials: InMemoryCredentialStore(), newEpisodes: FakeNewEpisodes())
    }

    private func entry(show: Int, season: Int = 1, number: Int = 2, age: TimeInterval) -> ProgressEntry {
        ProgressEntry(playable: PlayableID(kind: .episode, id: show * 10_000 + season * 100 + number), showID: show,
                      season: season, number: number, position: 300, duration: 1000, updatedAt: now.addingTimeInterval(-age))
    }

    private func richLibrary() -> Library {
        var library = Library()
        library.myList = [
            MyListItem(title: TitleID(kind: .show, id: 101), addedAt: now.addingTimeInterval(-300)),
            MyListItem(title: TitleID(kind: .movie, id: 1001), addedAt: now.addingTimeInterval(-100)),
            MyListItem(title: TitleID(kind: .show, id: 102), addedAt: now.addingTimeInterval(-200))
        ]
        library.progress = [
            ProgressEntry(playable: PlayableID(kind: .movie, id: 1002), position: 100, duration: 400, updatedAt: now.addingTimeInterval(-50)),
            entry(show: 103, age: 500)
        ]
        // Show 104 is followed with an older seen date than its catalog newestVideo and is not in Continue Watching.
        library.followed[104] = FollowState(seenNewestVideo: .distantPast, started: true)
        return library
    }

    @Test func emptyLibraryIsEmpty() {
        let model = MyListViewModel(environment: environment())
        model.update(library: Library(), catalog: catalog, newEpisodeInfo: [:])
        #expect(model.isEmpty)
        #expect(model.continueWatching.isEmpty && model.newEpisodes.isEmpty && model.titles.isEmpty)
        model.update(library: richLibrary(), catalog: nil, newEpisodeInfo: [:])
        #expect(model.isEmpty)
    }

    @Test func rowsReflectLibrary() {
        let model = MyListViewModel(environment: environment())
        let info = NewEpisodeInfo(first: EpisodeRef(episodeID: 1_040_101, season: 4, number: 1), count: 2)
        model.update(library: richLibrary(), catalog: catalog, newEpisodeInfo: [104: info])
        #expect(!model.isEmpty)
        #expect(model.continueWatching.map(\.id) == ["movie-1002", "show-103"])
        #expect(model.newEpisodes.map(\.id) == ["show-104"])
        #expect(model.newEpisodes.first?.badge == .newCount(2))
        #expect(model.titles.count == 3)
    }

    @Test func rowsAreCappedAtThirty() {
        var library = Library()
        library.progress = (101...140).map { entry(show: $0, age: Double($0)) }
        let model = MyListViewModel(environment: environment())
        model.update(library: library, catalog: catalog, newEpisodeInfo: [:])
        #expect(model.continueWatching.count == 30)
        #expect(model.continueWatching.first?.id == "show-101")
    }

    @Test func myListNewestFirst() {
        let model = MyListViewModel(environment: environment())
        model.update(library: richLibrary(), catalog: catalog, newEpisodeInfo: [:])
        #expect(model.titles.map(\.id) == [TitleID(kind: .movie, id: 1001), TitleID(kind: .show, id: 102), TitleID(kind: .show, id: 101)])
    }

    @Test func updatesWhenLibraryChanges() async {
        let store = InMemoryLibraryStore()
        let model = MyListViewModel(environment: environment(store))
        let observing = Task { await model.observe(catalog: catalog, newEpisodeInfo: [:]) }
        await waitUntil { model.hasLoaded }
        await store.update { $0.myList = [MyListItem(title: TitleID(kind: .movie, id: 1005), addedAt: Samples.now)] }
        await waitUntil { model.titles.count == 1 }
        #expect(model.titles.map(\.id) == [TitleID(kind: .movie, id: 1005)])
        await store.update { $0.myList = [] }
        await waitUntil { model.titles.isEmpty }
        #expect(model.isEmpty)
        observing.cancel()
    }

    @Test func selectPlayableVsOpenDetail() {
        let model = MyListViewModel(environment: environment())
        let router = TabRouter()
        let launcher = PlaybackLauncher()
        let movie = ShelfItem(title: catalog.title(TitleID(kind: .movie, id: 1002))!, playable: PlayableID(kind: .movie, id: 1002))
        model.select(movie, router: router, launcher: launcher)
        #expect(launcher.active?.target == .movie(1002))
        let show = catalog.title(TitleID(kind: .show, id: 103))!
        let episode = ShelfItem(title: show, episode: EpisodeRef(episodeID: 1_030_102, season: 1, number: 2),
                                playable: PlayableID(kind: .episode, id: 1_030_102))
        model.select(episode, router: router, launcher: launcher)
        #expect(launcher.active?.target == .episode(id: 1_030_102, showID: 103))
        #expect(router.path.isEmpty)
        model.select(ShelfItem(title: show, badge: .new), router: router, launcher: launcher)
        #expect(router.path == [.show(103)])
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<2000 where !condition() { try? await Task.sleep(for: .milliseconds(1)) }
    }
}
