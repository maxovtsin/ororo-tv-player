import Foundation
import OroroCore
import OroroTestSupport
import Testing

@Suite struct BrowseEngineTests {
    private func catalog(shows: [Title] = [], movies: [Title] = []) -> Catalog {
        Catalog(shows: shows, movies: movies, fetchedAt: Samples.now)
    }

    private func ids(_ titles: [Title]) -> [Int] { titles.map(\.id.id) }

    @Test func genreFilter() {
        let c = catalog(shows: [
            Samples.show(1, genres: ["Drama", "Crime"]),
            Samples.show(2, genres: ["Comedy"]),
            Samples.show(3, genres: ["Crime"])
        ])
        let result = BrowseEngine.apply(BrowseQuery(kind: .show, genre: "Crime", sort: .alphabetical), to: c)
        #expect(ids(result) == [1, 3])
    }

    @Test func decadeFilterBounds() {
        let c = catalog(shows: [
            Samples.show(1, year: 1989),
            Samples.show(2, year: 1990),
            Samples.show(3, year: 1999),
            Samples.show(4, year: 2000),
            Samples.show(5, year: nil)
        ])
        let result = BrowseEngine.apply(BrowseQuery(kind: .show, decade: 1990, sort: .alphabetical), to: c)
        #expect(ids(result) == [2, 3])
    }

    @Test func minRatingExcludesNil() {
        let c = catalog(movies: [
            Samples.movie(1, imdbRating: 8.0),
            Samples.movie(2, imdbRating: 7.9),
            Samples.movie(3, imdbRating: nil),
            Samples.movie(4, imdbRating: 9.1)
        ])
        let result = BrowseEngine.apply(BrowseQuery(kind: .movie, minRating: 8.0, sort: .rating), to: c)
        #expect(ids(result) == [4, 1])
    }

    @Test func statusOngoingAndEnded() {
        let c = catalog(shows: [
            Samples.show(1, ended: false),
            Samples.show(2, ended: true),
            Samples.show(3, ended: false)
        ])
        let ongoing = BrowseEngine.apply(BrowseQuery(kind: .show, status: .ongoing, sort: .alphabetical), to: c)
        let ended = BrowseEngine.apply(BrowseQuery(kind: .show, status: .ended, sort: .alphabetical), to: c)
        #expect(ids(ongoing) == [1, 3])
        #expect(ids(ended) == [2])
    }

    @Test func statusIgnoredForMovies() {
        let c = catalog(movies: [Samples.movie(1), Samples.movie(2)])
        let result = BrowseEngine.apply(BrowseQuery(kind: .movie, status: .ended, sort: .alphabetical), to: c)
        #expect(ids(result) == [1, 2])
    }

    @Test func popularSortPutsZeroPopularityLastByRating() {
        let c = catalog(shows: [
            Samples.show(1, popularity: 0, imdbRating: 6.0),
            Samples.show(2, popularity: 500, imdbRating: 5.0),
            Samples.show(3, popularity: 0, imdbRating: 9.0),
            Samples.show(4, popularity: 900, imdbRating: 5.0),
            Samples.show(5, popularity: 0, imdbRating: nil)
        ])
        let result = BrowseEngine.apply(BrowseQuery(kind: .show, sort: .popular), to: c)
        #expect(ids(result) == [4, 2, 3, 1, 5])
    }

    @Test func ratingSort() {
        let c = catalog(movies: [
            Samples.movie(1, imdbRating: 7.0),
            Samples.movie(2, imdbRating: nil),
            Samples.movie(3, imdbRating: 8.5)
        ])
        let result = BrowseEngine.apply(BrowseQuery(kind: .movie, sort: .rating), to: c)
        #expect(ids(result) == [3, 1, 2])
    }

    @Test func yearSort() {
        let old = Samples.now.addingTimeInterval(-10 * Samples.day)
        let c = catalog(movies: [
            Samples.movie(1, year: 2019, updatedAt: old),
            Samples.movie(2, year: 2023, updatedAt: old),
            Samples.movie(3, year: 2023, updatedAt: Samples.now),
            Samples.movie(4, year: nil)
        ])
        let result = BrowseEngine.apply(BrowseQuery(kind: .movie, sort: .year), to: c)
        #expect(ids(result) == [3, 2, 1, 4])
    }

    @Test func recentlyUpdatedSort() {
        let c = catalog(movies: [
            Samples.movie(1, updatedAt: Samples.now.addingTimeInterval(-3 * Samples.day)),
            Samples.movie(2, updatedAt: nil),
            Samples.movie(3, updatedAt: Samples.now)
        ])
        let result = BrowseEngine.apply(BrowseQuery(kind: .movie, sort: .recentlyUpdated), to: c)
        #expect(ids(result) == [3, 1, 2])
    }

    @Test func alphabeticalSortIsCaseAndDiacriticInsensitive() {
        let c = catalog(movies: [
            Samples.movie(1, name: "zebra"),
            Samples.movie(2, name: "Émile"),
            Samples.movie(3, name: "apple"),
            Samples.movie(4, name: "Eagle")
        ])
        let result = BrowseEngine.apply(BrowseQuery(kind: .movie, sort: .alphabetical), to: c)
        #expect(result.map(\.name) == ["apple", "Eagle", "Émile", "zebra"])
    }

    @Test func combinedFiltersIntersect() {
        let c = catalog(shows: [
            Samples.show(1, imdbRating: 8.0, year: 2015, genres: ["Drama"], ended: true),
            Samples.show(2, imdbRating: 8.0, year: 2015, genres: ["Drama"], ended: false),
            Samples.show(3, imdbRating: 6.0, year: 2015, genres: ["Drama"], ended: true),
            Samples.show(4, imdbRating: 8.0, year: 2005, genres: ["Drama"], ended: true),
            Samples.show(5, imdbRating: 8.0, year: 2015, genres: ["Comedy"], ended: true)
        ])
        let query = BrowseQuery(kind: .show, genre: "Drama", decade: 2010, minRating: 7.0, status: .ended, sort: .rating)
        #expect(ids(BrowseEngine.apply(query, to: c)) == [1])
    }

    @Test func noMatchReturnsEmpty() {
        let c = catalog(shows: [Samples.show(1)])
        #expect(BrowseEngine.apply(BrowseQuery(kind: .show, genre: "Nope", sort: .rating), to: c).isEmpty)
    }

    @Test func kindSelectsList() {
        let c = catalog(shows: [Samples.show(1)], movies: [Samples.movie(2)])
        #expect(ids(BrowseEngine.apply(.default(.movie), to: c)) == [2])
    }

    @Test func sortIsDeterministic() {
        var titles = (1...30).map { Samples.movie($0, name: "Same", imdbRating: 7.0, year: 2020) }
        let forward = BrowseEngine.apply(BrowseQuery(kind: .movie, sort: .rating), to: catalog(movies: titles))
        titles.reverse()
        let backward = BrowseEngine.apply(BrowseQuery(kind: .movie, sort: .rating), to: catalog(movies: titles))
        titles.shuffle()
        let shuffled = BrowseEngine.apply(BrowseQuery(kind: .movie, sort: .rating), to: catalog(movies: titles))
        #expect(forward == backward)
        #expect(forward == shuffled)
        #expect(ids(forward) == Array(1...30))
        for sort in BrowseQuery.Sort.allCases {
            let query = BrowseQuery(kind: .movie, sort: sort)
            let first = BrowseEngine.apply(query, to: catalog(movies: titles))
            let second = BrowseEngine.apply(query, to: catalog(movies: titles.reversed()))
            #expect(first == second)
        }
    }

    @Test func genresByCountDescending() {
        let c = catalog(shows: [
            Samples.show(1, genres: ["Drama", "Crime"]),
            Samples.show(2, genres: ["Drama"]),
            Samples.show(3, genres: ["Comedy"]),
            Samples.show(4, genres: ["Crime", "Drama"])
        ], movies: [Samples.movie(5, genres: ["Horror"])])
        #expect(BrowseEngine.genres(for: .show, in: c) == ["Drama", "Crime", "Comedy"])
        #expect(BrowseEngine.genres(for: .movie, in: c) == ["Horror"])
    }

    @Test func decadesDescendingDistinct() {
        let c = catalog(movies: [
            Samples.movie(1, year: 1994), Samples.movie(2, year: 2021),
            Samples.movie(3, year: 2015), Samples.movie(4, year: 2012), Samples.movie(5, year: nil)
        ])
        #expect(BrowseEngine.decades(for: .movie, in: c) == [2020, 2010, 1990])
    }
}
