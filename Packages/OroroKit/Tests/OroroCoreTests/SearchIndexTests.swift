import Foundation
import OroroCore
import OroroTestSupport
import Testing

@Suite struct SearchIndexTests {
    private func show(_ id: Int, _ name: String, popularity: Int = 0, year: Int? = nil, genres: [String] = []) -> Title {
        Title(id: TitleID(kind: .show, id: id), name: name, year: year, genres: genres, popularity: popularity)
    }

    private func movie(_ id: Int, _ name: String, rating: Double? = nil, year: Int? = nil, genres: [String] = []) -> Title {
        Title(id: TitleID(kind: .movie, id: id), name: name, imdbRating: rating, year: year, genres: genres)
    }

    private func index(shows: [Title] = [], movies: [Title] = []) -> SearchIndex {
        SearchIndex(catalog: Catalog(shows: shows, movies: movies, fetchedAt: Date(timeIntervalSince1970: 0)))
    }

    @Test func exactBeatsPrefixBeatsWordBeatsSubstring() {
        let idx = index(shows: [
            show(1, "Xbigdoor", popularity: 100),      // substring
            show(2, "The Big Bang", popularity: 90),   // word prefix
            show(3, "Big Bang Theory", popularity: 80), // prefix
            show(4, "Big", popularity: 1)               // exact
        ])
        #expect(idx.search("big").shows.map(\.id.id) == [4, 3, 2, 1])
    }

    @Test func diacriticsAndCaseIgnored() {
        let idx = index(movies: [movie(1, "Amélie")])
        #expect(idx.search("amelie").movies.map(\.name) == ["Amélie"])
        #expect(idx.search("AMÉLIE").movies.map(\.name) == ["Amélie"])
        #expect(idx.search("  am  ").movies.map(\.name) == ["Amélie"])
    }

    @Test func genreQueryReturnsGenreTitles() {
        let idx = index(
            shows: [show(1, "Alpha", genres: ["Drama"]), show(2, "Beta", genres: ["Comedy"])],
            movies: [movie(3, "Gamma", genres: ["drama"])]
        )
        let result = idx.search("DRAMA")
        #expect(result.shows.map(\.name) == ["Alpha"])
        #expect(result.movies.map(\.name) == ["Gamma"])
    }

    @Test func yearQueryReturnsThatYear() {
        let idx = index(
            shows: [show(1, "Old", year: 1999), show(2, "New", year: 2021)],
            movies: [movie(3, "Film", year: 2021), movie(4, "Other", year: 2020)]
        )
        let result = idx.search("2021")
        #expect(result.shows.map(\.name) == ["New"])
        #expect(result.movies.map(\.name) == ["Film"])
    }

    @Test func tieBreakByPopularityForShowsAndRatingForMovies() {
        let idx = index(
            shows: [show(1, "Star A", popularity: 5), show(2, "Star B", popularity: 50), show(3, "Star C", popularity: 20)],
            movies: [movie(1, "Star A", rating: 6.1), movie(2, "Star B", rating: 8.2), movie(3, "Star C", rating: nil)]
        )
        let result = idx.search("star")
        #expect(result.shows.map(\.name) == ["Star B", "Star C", "Star A"])
        #expect(result.movies.map(\.name) == ["Star B", "Star A", "Star C"])
    }

    @Test func limitApplied() {
        let shows = (1...80).map { show($0, "Show \($0)", popularity: $0) }
        let idx = index(shows: shows)
        #expect(idx.search("show").shows.count == 50)
        #expect(idx.search("show", limit: 3).shows.map(\.popularity) == [80, 79, 78])
    }

    @Test func emptyAndWhitespaceQueryReturnsNothing() {
        let idx = index(shows: [show(1, "A")], movies: [movie(2, "B")])
        #expect(idx.search("") == SearchResults(shows: [], movies: []))
        #expect(idx.search("   \n\t") == SearchResults(shows: [], movies: []))
    }

    @Test func specialCharactersDoNotCrash() {
        let idx = index(shows: [show(1, "(Parens)")], movies: [movie(2, "Back\\slash 🙂")])
        #expect(idx.search("(").shows.count == 1)
        #expect(idx.search("\\").movies.count == 1)
        #expect(idx.search("🙂").movies.count == 1)
        #expect(idx.search(String(repeating: "x", count: 500)) == SearchResults(shows: [], movies: []))
    }

    @Test func largeCatalogSearchesQuickly() {
        let shows = (0..<6000).map { show($0, "Show number \($0) Épisode", popularity: $0) }
        let movies = (0..<6000).map { movie($0, "Movie number \($0)", rating: Double($0 % 10)) }
        let idx = index(shows: shows, movies: movies)
        let start = ContinuousClock.now
        for _ in 0..<20 { _ = idx.search("episode 12") }
        let perQuery = (ContinuousClock.now - start) / 20
        #expect(perQuery < .milliseconds(250)) // loose debug-build bound; release target is < 16 ms
    }
}
