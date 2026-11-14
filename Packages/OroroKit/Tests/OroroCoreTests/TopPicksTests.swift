import Foundation
import OroroCore
import OroroTestSupport
import Testing

@Suite struct TopPicksTests {
    private func ids(_ titles: [Title]) -> [Int] { titles.map(\.id.id) }

    @Test func showsWatchedOnOroroComeFirstByRating() {
        let shows = [
            Samples.show(1, popularity: 0, imdbRating: 9.4),   // obscure, high rating
            Samples.show(2, popularity: 50, imdbRating: 8.1),
            Samples.show(3, popularity: 900, imdbRating: 7.2),
            Samples.show(4, popularity: 10, imdbRating: 8.6),
            Samples.show(5, popularity: 0, imdbRating: 6.0)
        ]
        #expect(ids(TopPicks.ordered(shows, now: Samples.now)) == [4, 2, 3, 1, 5])
    }

    @Test func showRatingTieBreaksOnPopularity() {
        let shows = [
            Samples.show(1, popularity: 5, imdbRating: 8.0),
            Samples.show(2, popularity: 70, imdbRating: 8.0)
        ]
        #expect(ids(TopPicks.ordered(shows, now: Samples.now)) == [2, 1])
    }

    @Test func recentMoviesComeFirstByRating() {
        // Samples.now is in 2025: the last 15 years are 2011…2025.
        let movies = [
            Samples.movie(1, imdbRating: 9.0, year: 1972),
            Samples.movie(2, imdbRating: 7.4, year: 2023),
            Samples.movie(3, imdbRating: 8.3, year: 2011),
            Samples.movie(4, imdbRating: 8.8, year: 2010),
            Samples.movie(5, imdbRating: 7.9, year: nil)
        ]
        #expect(ids(TopPicks.ordered(movies, now: Samples.now)) == [3, 2, 1, 4, 5])
    }

    @Test func movieRatingTieBreaksOnNewerYear() {
        let movies = [
            Samples.movie(1, imdbRating: 8.0, year: 2015),
            Samples.movie(2, imdbRating: 8.0, year: 2022)
        ]
        #expect(ids(TopPicks.ordered(movies, now: Samples.now)) == [2, 1])
    }

    @Test func unratedTitlesGoLast() {
        let shows = [
            Samples.show(1, popularity: 999, imdbRating: nil),
            Samples.show(2, popularity: 0, imdbRating: 5.0),
            Samples.show(3, popularity: 1, imdbRating: 6.0)
        ]
        #expect(ids(TopPicks.ordered(shows, now: Samples.now)) == [3, 2, 1])
    }

    @Test func browseSortTopPicksMatchesRule() {
        let movies = [
            Samples.movie(1, imdbRating: 9.0, year: 1972),
            Samples.movie(2, imdbRating: 7.4, year: 2023)
        ]
        let catalog = Catalog(shows: [], movies: movies, fetchedAt: Samples.now)
        let result = BrowseEngine.apply(BrowseQuery(kind: .movie, sort: .topPicks), to: catalog)
        #expect(ids(result) == ids(TopPicks.ordered(movies, now: Samples.now)))
    }
}
