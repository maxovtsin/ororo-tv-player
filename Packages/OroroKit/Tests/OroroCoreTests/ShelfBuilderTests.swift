import Foundation
import Testing
import OroroTestSupport
@testable import OroroCore

@Suite struct ShelfBuilderTests {
    private func home(
        _ catalog: Catalog = Samples.catalog,
        continueWatching: [ShelfItem] = [],
        newEpisodes: [ShelfItem] = [],
        myList: [Title] = []
    ) -> HomeContent {
        ShelfBuilder.home(catalog: catalog, hero: [], continueWatching: continueWatching,
                          newEpisodes: newEpisodes, myList: myList, now: Samples.now)
    }

    @Test func homeOrderAndHiddenRows() {
        let c = home()
        #expect(c.shelves.map(\.id).prefix(4) == ["popularShows", "latestReleases", "topRatedMovies", "recentlyUpdatedMovies"])
        #expect(c.shelves.count == 8)
        #expect(c.shelves.map(\.id).suffix(4) == ["genre-Drama", "genre-Comedy", "genre-Crime", "genre-Sci-Fi"])
    }

    @Test func personalRowsComeFirstWhenPresent() {
        let t = Samples.catalog.shows[0]
        let item = ShelfItem(title: t, progress: 0.4)
        let c = home(continueWatching: [item], newEpisodes: [item], myList: [t])
        #expect(c.shelves.count == 11)
        #expect(c.shelves[0].id == "continueWatching")
        #expect(c.shelves[0].kind == .continueWatching)
        #expect(c.shelves[1].id == "newEpisodes")
        #expect(c.shelves[2].id == "popularShows")
        #expect(c.shelves[5].id == "recentlyUpdatedMovies")
        #expect(c.shelves[6].id == "myList")
        #expect(c.shelves[6].items.map(\.title) == [t])
        #expect(c.shelves[7].id.hasPrefix("genre-"))
    }

    @Test func shelvesAreCappedAt30ButReportTotal() {
        let popular = home().shelves[0]
        #expect(popular.items.count == 30)
        #expect(popular.totalCount == 48)
        #expect(popular.seeAll == BrowseQuery(kind: .show, sort: .popular))
    }

    @Test func popularShowsSortedByPopularityDesc() {
        let pops = home().shelves[0].items.map(\.title.popularity)
        #expect(pops == pops.sorted(by: >))
        #expect(pops.first == 4800)
    }

    @Test func latestReleasesSortedByNewestVideoDesc() {
        let latest = home().shelves[1]
        let dates = latest.items.compactMap(\.title.newestVideo)
        #expect(dates.count == 30)
        #expect(dates == dates.sorted(by: >))
        #expect(latest.seeAll?.sort == .recentlyUpdated)
    }

    @Test func topRatedMoviesUseNowYear() {
        let movies = home().shelves[2]
        #expect(movies.items.allSatisfy { ($0.title.year ?? 0) >= 2005 })
        #expect(movies.totalCount <= 26)
        #expect(movies.totalCount > 0)
        let ratings = movies.items.compactMap(\.title.imdbRating)
        #expect(ratings == ratings.sorted(by: >))
        // A later "now" moves the cutoff.
        let later = ShelfBuilder.home(catalog: Samples.catalog, hero: [], continueWatching: [], newEpisodes: [], myList: [],
                                      now: Samples.now.addingTimeInterval(5 * 365 * Samples.day))
        #expect(later.shelves[2].items.allSatisfy { ($0.title.year ?? 0) >= 2010 })
    }

    @Test func showTopRatedExcludesZeroPopularity() {
        let top = ShelfBuilder.browseTab(kind: .show, catalog: Samples.catalog)[2]
        #expect(top.id == "topRated")
        #expect(!top.items.isEmpty)
        #expect(top.items.allSatisfy { $0.title.popularity > 0 && ($0.title.year ?? 0) >= 2005 })
        #expect(top.totalCount <= 34)
    }

    @Test func heroHasThreeShowsThreeMoviesAllWithBackdropAndDesc() {
        let hero = ShelfBuilder.hero(catalog: Samples.catalog, now: Samples.now)
        #expect(hero.count == 6)
        #expect(hero.map(\.id.kind) == [.show, .movie, .show, .movie, .show, .movie])
        #expect(hero.allSatisfy { $0.backdropURL != nil && !($0.desc ?? "").isEmpty })
        let cutoff = Samples.now.addingTimeInterval(-30 * Samples.day)
        let shows = hero.filter { $0.id.kind == .show }
        #expect(shows.allSatisfy { ($0.newestVideo ?? .distantPast) >= cutoff })
        #expect(shows.map(\.popularity) == shows.map(\.popularity).sorted(by: >))
        let movies = hero.filter { $0.id.kind == .movie }
        #expect(movies.allSatisfy { ($0.updatedAt ?? .distantPast) >= cutoff })
        let ratings = movies.map { $0.imdbRating ?? 0 }
        #expect(ratings == ratings.sorted(by: >))
    }

    @Test func heroWidensWindowWhenNothingRecent() {
        let future = Samples.now.addingTimeInterval(1000 * Samples.day)
        let hero = ShelfBuilder.hero(catalog: Samples.catalog, now: future)
        #expect(hero.count == 6)
        #expect(hero.allSatisfy { $0.backdropURL != nil && !($0.desc ?? "").isEmpty })
        let best = Samples.catalog.shows.filter { $0.backdropURL != nil && !($0.desc ?? "").isEmpty }
            .map(\.popularity).max()
        #expect(hero[0].popularity == best)
    }

    @Test func browseTabShows() {
        let shelves = ShelfBuilder.browseTab(kind: .show, catalog: Samples.catalog)
        #expect(shelves.map(\.id).prefix(3) == ["popularNow", "latestReleases", "topRated"])
        #expect(shelves.dropFirst(3).map(\.id) == ["genre-Drama", "genre-Sci-Fi", "genre-Comedy", "genre-Crime", "genre-Thriller",
                                                   "genre-Animation", "genre-Documentary", "genre-Romance"])
        #expect(shelves[3].totalCount == 14)
    }

    @Test func browseTabMovies() {
        let shelves = ShelfBuilder.browseTab(kind: .movie, catalog: Samples.catalog)
        #expect(shelves.map(\.id).prefix(2) == ["recentlyUpdated", "topRated"])
        #expect(shelves.dropFirst(2).map(\.id).first == "genre-Drama")
        #expect(shelves.dropFirst(2).count == 8)
        #expect(shelves.allSatisfy { $0.items.count <= 30 })
    }

    @Test func seeAllQueryMatchesRow() {
        for kind in TitleKind.allCases {
            for shelf in ShelfBuilder.browseTab(kind: kind, catalog: Samples.catalog) {
                #expect(shelf.seeAll?.kind == kind)
                if case .genre(let name) = shelf.kind {
                    #expect(shelf.seeAll?.genre == name)
                    #expect(shelf.id == "genre-\(name)")
                    #expect(shelf.items.allSatisfy { $0.title.genres.contains(name) })
                }
            }
        }
        #expect(home().shelves[2].seeAll == BrowseQuery(kind: .movie, sort: .rating))
    }

    @Test func genresByCountOrdersByCountThenName() {
        let counts = ShelfBuilder.genresByCount(Samples.catalog.shows + Samples.catalog.movies)
        #expect(counts.map(\.genre) == ["Drama", "Comedy", "Crime", "Sci-Fi", "Romance", "Thriller", "Animation", "Documentary"])
        #expect(counts.map(\.count) == [28, 20, 16, 15, 13, 12, 4, 4])
    }
}
