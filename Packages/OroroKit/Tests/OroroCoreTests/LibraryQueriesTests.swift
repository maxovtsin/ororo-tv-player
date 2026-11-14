import Foundation
import OroroCore
import OroroTestSupport
import Testing

@Suite struct LibraryQueriesTests {
    let catalog = Samples.catalog

    func show(_ id: Int) throws -> Title {
        try #require(catalog.title(TitleID(kind: .show, id: id)))
    }

    func newest(_ id: Int) throws -> Date {
        try #require(show(id).newestVideo)
    }

    func episode(show: Int, season: Int = 1, number: Int) -> PlayableID {
        PlayableID(kind: .episode, id: show * 10_000 + season * 100 + number)
    }

    func ref(show: Int, season: Int = 1, number: Int) -> EpisodeRef {
        EpisodeRef(episodeID: show * 10_000 + season * 100 + number, season: season, number: number)
    }

    func context(show: Int, season: Int = 1, number: Int, newestVideo: Date?) -> ShowContext {
        ShowContext(showID: show, season: season, number: number, episodeName: nil, newestVideo: newestVideo)
    }

    @Test func continueWatchingOneEntryPerShowSortedByActivity() throws {
        var lib = Library()
        let t0 = Samples.now
        // Show 101: two episodes started; only the latest counts.
        lib.recordProgress(episode(show: 101, number: 1), show: context(show: 101, number: 1, newestVideo: try newest(101)),
                           position: 900, duration: 2700, now: t0)
        lib.recordProgress(episode(show: 101, number: 2), show: context(show: 101, number: 2, newestVideo: try newest(101)),
                           position: 270, duration: 2700, now: t0.addingTimeInterval(30))
        // Movie 1001 in progress.
        lib.recordProgress(PlayableID(kind: .movie, id: 1001), show: nil, position: 600, duration: 6000, now: t0.addingTimeInterval(20))
        // Show 102: up-next only, most recent activity.
        lib.finish(episode(show: 102, number: 1), show: context(show: 102, number: 1, newestVideo: try newest(102)),
                   next: ref(show: 102, number: 2), now: t0.addingTimeInterval(40))

        let items = LibraryQueries.continueWatching(lib, catalog: catalog)
        #expect(items.map(\.id) == ["show-102", "show-101", "movie-1001"])
        #expect(items[0] == ShelfItem(title: try show(102), progress: nil, episode: ref(show: 102, number: 2), badge: nil,
                                      playable: episode(show: 102, number: 2)))
        #expect(items[1] == ShelfItem(title: try show(101), progress: 0.1, episode: ref(show: 101, number: 2), badge: nil,
                                      playable: episode(show: 101, number: 2)))
        #expect(items[2].progress == 0.1)
        #expect(items[2].playable == PlayableID(kind: .movie, id: 1001))
        #expect(items[2].episode == nil)
    }

    @Test func continueWatchingHandBuiltLibraryPrefersLatestInProgress() throws {
        let t0 = Samples.now
        var lib = Library()
        // Show 101: two progress entries (latest wins) and an up-next (in-progress wins, activity = max of both).
        lib.progress = [
            ProgressEntry(playable: episode(show: 101, number: 2), showID: 101, season: 1, number: 2,
                          position: 300, duration: 3000, updatedAt: t0.addingTimeInterval(10)),
            ProgressEntry(playable: episode(show: 101, number: 1), showID: 101, season: 1, number: 1,
                          position: 600, duration: 3000, updatedAt: t0),
            ProgressEntry(playable: PlayableID(kind: .movie, id: 1001), position: 600, duration: 6000, updatedAt: t0.addingTimeInterval(20))
        ]
        lib.upNext[101] = UpNextEntry(ref: ref(show: 101, number: 5), setAt: t0.addingTimeInterval(30))

        let items = LibraryQueries.continueWatching(lib, catalog: catalog)
        #expect(items.map(\.id) == ["show-101", "movie-1001"])
        #expect(items[0] == ShelfItem(title: try show(101), progress: 0.1, episode: ref(show: 101, number: 2),
                                      playable: episode(show: 101, number: 2)))
        #expect(LibraryQueries.resumeTarget(showID: 101, library: lib) == ref(show: 101, number: 2))
    }

    @Test func newEpisodeDetectedWhenNewestVideoAdvances() throws {
        var lib = Library()
        let seen = try newest(101)
        lib.toggleMyList(TitleID(kind: .show, id: 101), newestVideo: seen, now: Samples.now)
        #expect(LibraryQueries.showsWithNewEpisodes(lib, catalog: catalog).isEmpty)

        let advanced = seen.addingTimeInterval(Samples.day)
        var shows = catalog.shows
        shows[0].newestVideo = advanced
        let refreshed = Catalog(shows: shows, movies: catalog.movies, fetchedAt: Samples.now)
        #expect(LibraryQueries.showsWithNewEpisodes(lib, catalog: refreshed).map(\.id.id) == [101])

        let items = LibraryQueries.newEpisodes(lib, catalog: refreshed, resolved: [:])
        #expect(items.count == 1)
        #expect(items.first?.badge == .newSince(advanced))
        #expect(items.first?.playable == nil)
        #expect(items.first?.episode == nil)
    }

    @Test func newEpisodesSortedByNewestVideoAndCapped() throws {
        var lib = Library()
        let old = Samples.now.addingTimeInterval(-365 * Samples.day)
        for title in catalog.shows { lib.toggleMyList(title.id, newestVideo: old, now: Samples.now) }
        let items = LibraryQueries.newEpisodes(lib, catalog: catalog, resolved: [:])
        #expect(items.count == 30)
        let dates = items.compactMap(\.title.newestVideo)
        #expect(dates == dates.sorted(by: >))
        let all = LibraryQueries.showsWithNewEpisodes(lib, catalog: catalog)
        #expect(all.count == 48)
        #expect(Array(all.prefix(30)).map(\.id) == items.map(\.title.id))
    }

    @Test func showInContinueWatchingGetsBadgeNotSecondRow() throws {
        var lib = Library()
        let seen = try newest(101).addingTimeInterval(-Samples.day)
        lib.recordProgress(episode(show: 101, number: 3), show: context(show: 101, number: 3, newestVideo: seen),
                           position: 300, duration: 2700, now: Samples.now)
        #expect(LibraryQueries.showsWithNewEpisodes(lib, catalog: catalog).map(\.id.id) == [101])
        let continueWatching = LibraryQueries.continueWatching(lib, catalog: catalog)
        #expect(continueWatching.map(\.id) == ["show-101"])
        #expect(continueWatching.first?.badge == .new)
        let resolved = [101: NewEpisodeInfo(first: ref(show: 101, number: 4), count: 1)]
        #expect(LibraryQueries.newEpisodes(lib, catalog: catalog, resolved: resolved).isEmpty)
    }

    @Test func resolvedNewEpisodeIsPlayableWithCountBadge() throws {
        var lib = Library()
        let seen = try newest(101).addingTimeInterval(-Samples.day)
        lib.finish(episode(show: 101, number: 3), show: context(show: 101, number: 3, newestVideo: seen), next: nil, now: Samples.now)
        lib.toggleMyList(TitleID(kind: .show, id: 102), newestVideo: try newest(102).addingTimeInterval(-Samples.day), now: Samples.now)
        lib.finish(episode(show: 102, number: 1), show: context(show: 102, number: 1, newestVideo: nil), next: nil, now: Samples.now)

        let resolved = [
            101: NewEpisodeInfo(first: ref(show: 101, number: 4), count: 3),
            102: NewEpisodeInfo(first: ref(show: 102, number: 2), count: 1)
        ]
        let items = LibraryQueries.newEpisodes(lib, catalog: catalog, resolved: resolved)
        #expect(items == [
            ShelfItem(title: try show(101), episode: ref(show: 101, number: 4), badge: .newCount(3), playable: episode(show: 101, number: 4)),
            ShelfItem(title: try show(102), episode: ref(show: 102, number: 2), badge: .new, playable: episode(show: 102, number: 2))
        ])
    }

    @Test func unstartedMyListShowIsNotDirectlyPlayable() throws {
        var lib = Library()
        lib.toggleMyList(TitleID(kind: .show, id: 101), newestVideo: try newest(101).addingTimeInterval(-Samples.day), now: Samples.now)
        let resolved = [101: NewEpisodeInfo(first: ref(show: 101, number: 4), count: 2)]
        let items = LibraryQueries.newEpisodes(lib, catalog: catalog, resolved: resolved)
        #expect(items.count == 1)
        #expect(items.first?.playable == nil)
        #expect(items.first?.episode == ref(show: 101, number: 4))
        #expect(items.first?.badge == .newCount(2))
    }

    @Test func startingNewEpisodeMovesShowToContinueWatching() throws {
        var lib = Library()
        let current = try newest(101)
        lib.finish(episode(show: 101, number: 3), show: context(show: 101, number: 3, newestVideo: current.addingTimeInterval(-Samples.day)),
                   next: nil, now: Samples.now)
        #expect(LibraryQueries.newEpisodes(lib, catalog: catalog, resolved: [:]).map(\.id) == ["show-101"])
        #expect(LibraryQueries.continueWatching(lib, catalog: catalog).isEmpty)

        lib.recordProgress(episode(show: 101, number: 4), show: context(show: 101, number: 4, newestVideo: current),
                           position: 120, duration: 2700, now: Samples.now.addingTimeInterval(60))
        #expect(LibraryQueries.newEpisodes(lib, catalog: catalog, resolved: [:]).isEmpty)
        #expect(LibraryQueries.showsWithNewEpisodes(lib, catalog: catalog).isEmpty)
        let continueWatching = LibraryQueries.continueWatching(lib, catalog: catalog)
        #expect(continueWatching.map(\.id) == ["show-101"])
        #expect(continueWatching.first?.badge == nil)
    }

    @Test func myListNewestFirst() {
        var lib = Library()
        lib.toggleMyList(TitleID(kind: .movie, id: 1001), newestVideo: nil, now: Samples.now)
        lib.toggleMyList(TitleID(kind: .show, id: 105), newestVideo: nil, now: Samples.now.addingTimeInterval(20))
        lib.toggleMyList(TitleID(kind: .movie, id: 1002), newestVideo: nil, now: Samples.now.addingTimeInterval(10))
        #expect(LibraryQueries.myList(lib, catalog: catalog).map(\.id) == [
            TitleID(kind: .show, id: 105), TitleID(kind: .movie, id: 1002), TitleID(kind: .movie, id: 1001)
        ])
    }

    @Test func heroActionForEachState() throws {
        var lib = Library()
        let movie = try #require(catalog.title(TitleID(kind: .movie, id: 1001)))
        #expect(LibraryQueries.heroAction(for: movie, library: lib) == .playMovie)
        lib.recordProgress(PlayableID(kind: .movie, id: 1001), show: nil, position: 600, duration: 6000, now: Samples.now)
        #expect(LibraryQueries.heroAction(for: movie, library: lib) == .playMovie)

        let title = try show(101)
        #expect(LibraryQueries.heroAction(for: title, library: lib) == .playFirstEpisode)
        #expect(LibraryQueries.resumeTarget(showID: 101, library: lib) == nil)

        lib.finish(episode(show: 101, number: 1), show: context(show: 101, number: 1, newestVideo: nil),
                   next: ref(show: 101, number: 2), now: Samples.now)
        #expect(LibraryQueries.heroAction(for: title, library: lib) == .playEpisode(ref(show: 101, number: 2)))

        lib.recordProgress(episode(show: 101, number: 2), show: context(show: 101, number: 2, newestVideo: nil),
                           position: 300, duration: 2700, now: Samples.now)
        #expect(LibraryQueries.heroAction(for: title, library: lib) == .resumeEpisode(ref(show: 101, number: 2)))
        #expect(LibraryQueries.resumeTarget(showID: 101, library: lib) == ref(show: 101, number: 2))
    }

    @Test func titleMissingFromCatalogIsHiddenThenReturns() {
        var lib = Library(); let ghost = TitleID(kind: .movie, id: 999_999)
        lib.toggleMyList(ghost, newestVideo: nil, now: Samples.now)
        lib.recordProgress(PlayableID(kind: .movie, id: 999_999), show: nil, position: 120, duration: 6000, now: Samples.now)
        #expect(LibraryQueries.myList(lib, catalog: Samples.catalog).isEmpty)
        #expect(LibraryQueries.continueWatching(lib, catalog: Samples.catalog).isEmpty)
        let bigger = Catalog(shows: Samples.catalog.shows, movies: Samples.catalog.movies + [Samples.movie(999_999)], fetchedAt: Samples.now)
        #expect(LibraryQueries.myList(lib, catalog: bigger).count == 1)
        #expect(LibraryQueries.continueWatching(lib, catalog: bigger).first?.progress == 0.02)
    }

    @Test func missingShowIsHiddenButKept() {
        var lib = Library()
        lib.toggleMyList(TitleID(kind: .show, id: 999), newestVideo: Samples.now.addingTimeInterval(-Samples.day), now: Samples.now)
        lib.finish(PlayableID(kind: .episode, id: 9_990_101), show: context(show: 999, number: 1, newestVideo: nil),
                   next: ref(show: 999, number: 2), now: Samples.now)
        #expect(LibraryQueries.continueWatching(lib, catalog: catalog).isEmpty)
        #expect(LibraryQueries.showsWithNewEpisodes(lib, catalog: catalog).isEmpty)
        #expect(LibraryQueries.newEpisodes(lib, catalog: catalog, resolved: [:]).isEmpty)
        #expect(lib.followed[999] != nil)
        #expect(lib.upNext[999] != nil)
        #expect(lib.isInMyList(TitleID(kind: .show, id: 999)))
    }
}
