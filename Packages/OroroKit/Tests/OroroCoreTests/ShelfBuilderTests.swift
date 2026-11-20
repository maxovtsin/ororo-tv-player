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
    }

    // MARK: Hero rotation

    private static let rotation: TimeInterval = 3 * 3600

    /// 100 fresh shows and movies with ratings 5.0…9.9; shows' popularity rises with id.
    private static let heroCatalog = Catalog(
        shows: (1...100).map {
            Samples.show($0, popularity: $0 * 10, newestVideo: Samples.now.addingTimeInterval(-Samples.day),
                         imdbRating: 5 + Double($0 % 50) / 10)
        },
        movies: (1...100).map {
            Samples.movie($0, imdbRating: 5 + Double($0 % 50) / 10, updatedAt: Samples.now.addingTimeInterval(-Samples.day))
        },
        fetchedAt: Samples.now
    )

    private func heroIDs(at now: Date, catalog: Catalog = heroCatalog) -> Set<TitleID> {
        Set(ShelfBuilder.hero(catalog: catalog, now: now).map(\.id))
    }

    @Test func heroOnlyFeaturesWellRatedTitles() {
        for slot in 0..<40 {
            let hero = ShelfBuilder.hero(catalog: Self.heroCatalog, now: Samples.now.addingTimeInterval(Double(slot) * Self.rotation))
            #expect(hero.count == 6)
            #expect(hero.allSatisfy { ($0.imdbRating ?? 0) >= 7 }, "slot \(slot)")
        }
    }

    @Test func heroIsStableWithinARotationSlot() {
        let start = Date(timeIntervalSince1970: (Samples.now.timeIntervalSince1970 / Self.rotation).rounded(.down) * Self.rotation)
        #expect(heroIDs(at: start) == heroIDs(at: start.addingTimeInterval(Self.rotation - 1)))
    }

    @Test func heroChangesEverySlotWithoutRepeatsInACycle() {
        let start = Date(timeIntervalSince1970: (Samples.now.timeIntervalSince1970 / Self.rotation).rounded(.down) * Self.rotation)
        var seen: [TitleID: Int] = [:]
        var previous: Set<TitleID> = []
        // A cycle shows each pooled title once; look at the slots of one full cycle.
        let cycle = Int(start.timeIntervalSince1970 / Self.rotation) / 15 * 15
        for slot in cycle..<(cycle + 15) {
            let ids = heroIDs(at: Date(timeIntervalSince1970: Double(slot) * Self.rotation))
            #expect(ids.isDisjoint(with: previous), "slot \(slot) repeats the slot before")
            ids.forEach { seen[$0, default: 0] += 1 }
            previous = ids
        }
        #expect(seen.values.allSatisfy { $0 == 1 })
        #expect(seen.count == 90)
    }

    @Test func heroPrefersPopularShowsAndTopRatedMovies() {
        // Over a cycle the pool is the 45 best per kind: shows by popularity, movies by rating.
        let cycle = Int(Samples.now.timeIntervalSince1970 / Self.rotation) / 15 * 15
        let featured = (cycle..<(cycle + 15)).flatMap {
            ShelfBuilder.hero(catalog: Self.heroCatalog, now: Date(timeIntervalSince1970: Double($0) * Self.rotation))
        }
        let shows = featured.filter { $0.id.kind == .show }
        let movies = featured.filter { $0.id.kind == .movie }
        let goodShows = Self.heroCatalog.shows.filter { ($0.imdbRating ?? 0) >= 7 }.sorted { $0.popularity > $1.popularity }
        #expect(Set(shows.map(\.id)) == Set(goodShows.prefix(45).map(\.id)))
        let goodMovies = Self.heroCatalog.movies.sorted {
            ($0.imdbRating ?? 0) != ($1.imdbRating ?? 0) ? ($0.imdbRating ?? 0) > ($1.imdbRating ?? 0) : $0.id.id < $1.id.id
        }
        #expect(Set(movies.map(\.id)) == Set(goodMovies.prefix(45).map(\.id)))
    }

    @Test func heroPrefersFreshTitles() {
        var shows = Self.heroCatalog.shows
        // The 10 most popular stopped airing; the rest are fresh.
        for index in shows.indices where shows[index].id.id > 90 {
            shows[index].newestVideo = Samples.now.addingTimeInterval(-365 * Samples.day)
        }
        let catalog = Catalog(shows: shows, movies: Self.heroCatalog.movies, fetchedAt: Samples.now)
        for slot in 0..<15 {
            let hero = ShelfBuilder.hero(catalog: catalog, now: Samples.now.addingTimeInterval(Double(slot) * Self.rotation))
            #expect(hero.filter { $0.id.kind == .show }.allSatisfy { $0.id.id <= 90 })
        }
    }

    @Test func heroFallsBackWhenFewGoodOrFreshTitles() {
        // Nothing fresh, nothing rated 7+: still six titles with backdrop and description.
        let future = Samples.now.addingTimeInterval(1000 * Samples.day)
        let weak = Catalog(
            shows: (1...5).map { Samples.show($0, popularity: $0, imdbRating: 6.0) },
            movies: (1...5).map { Samples.movie($0, imdbRating: 5.5) } + [Samples.movie(9, imdbRating: 8, hasBackdrop: false)],
            fetchedAt: future
        )
        let hero = ShelfBuilder.hero(catalog: weak, now: future)
        #expect(hero.count == 6)
        #expect(hero.allSatisfy { $0.backdropURL != nil })
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
