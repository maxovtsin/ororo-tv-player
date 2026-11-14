import Foundation
import OroroCore
import OroroTestSupport
import Testing
@testable import OroroAPI

@Suite struct DecodersTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func utc(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    @Test func decodesShowList() throws {
        let titles = try Decoders.shows(Fixtures.data("shows"))
        #expect(titles.count == 200)
        let first = try #require(titles.first)
        #expect(first.id == TitleID(kind: .show, id: 805))
        #expect(first.name == "The Nightmare Worlds of H.G. Wells")
        #expect(first.imdbRating == 5.9)
        #expect(first.year == 2016)
        #expect(first.genres == ["Sci-Fi"])
        #expect(first.countries == ["GB"])
        #expect(first.lengthMinutes == 23)
        #expect(first.ended == true)
        #expect(first.popularity == 0)
        #expect(first.resolution == nil)
        #expect(first.backdropURL == nil)
        #expect(first.posterURL?.host == "front.ororo-mirror.tv")
        #expect(first.newestVideo == Date(timeIntervalSince1970: 1_456_784_291))
        #expect(first.updatedAt == Date(timeIntervalSince1970: 1_791_510_998))
        #expect(titles.allSatisfy { $0.id.kind == .show })
        #expect(titles.filter { $0.backdropURL == nil }.count >= 3)
    }

    @Test func decodesMovieListWithResolution() throws {
        let titles = try Decoders.movies(Fixtures.data("movies"))
        #expect(titles.count == 200)
        let first = try #require(titles.first)
        #expect(first.name == "Léon")
        #expect(first.resolution == .hd)
        #expect(first.year == 1994)
        #expect(first.popularity == 0)
        #expect(first.ended == nil)
        #expect(titles.allSatisfy { $0.id.kind == .movie })
    }

    @Test func decodesShowDetailWith19Episodes() throws {
        let detail = try Decoders.show(Fixtures.data("show"))
        #expect(detail.title.id == TitleID(kind: .show, id: 3952))
        #expect(detail.title.name == "MobLand")
        #expect(detail.title.imdbRating == 8.3)
        #expect(detail.title.year == 2025)
        #expect(detail.title.lengthMinutes == nil)
        #expect(detail.seasonCount == 2)
        #expect(detail.episodes.count == 19)
        #expect(Set(detail.episodes.map(\.season)) == [1, 2])
        let first = try #require(detail.episodes.first)
        #expect(first.id == 94_397)
        #expect(first.showID == 3952)
        #expect(first.name == "Stick or Twist")
        #expect(first.season == 1)
        #expect(first.number == 1)
        #expect(first.airdate == utc(2025, 3, 30))
        #expect(first.resolution == .hd)
        #expect(first.qualities == ["240p", "360p", "480p", "720p", "1080p"])
        #expect(detail.episodes[1].number == 10)
    }

    @Test func decodesMovieDetail() throws {
        let detail = try Decoders.movie(Fixtures.data("movie"), now: now)
        #expect(detail.title.id == TitleID(kind: .movie, id: 6936))
        #expect(detail.title.name == "Dune Part One")
        #expect(detail.title.resolution == .hd)
        #expect(detail.trailerYouTubeID == "n9xhJrPXop4")
        #expect(detail.qualities == ["240p", "360p", "480p", "720p", "1080p"])
        #expect(detail.subtitleLanguages == ["ru", "en", "it", "de", "pl", "tr", "fr", "pt", "cs", "es"])
        let playback = try #require(detail.playback)
        #expect(playback.streamURL.host == "example.invalid")
        #expect(playback.subtitles.count == 10)
        #expect(playback.fetchedAt == now)
    }

    @Test func decodesEpisodeDetail() throws {
        let detail = try Decoders.episode(Fixtures.data("episode"), showID: 805, now: now)
        #expect(detail.episode.id == 30_010)
        #expect(detail.episode.showID == 805)
        #expect(detail.episode.season == 1)
        #expect(detail.episode.number == 1)
        #expect(detail.episode.qualities == ["240p", "360p", "480p"])
        #expect(detail.showName == "The Nightmare Worlds of H.G. Wells")
        #expect(detail.subtitleLanguages == ["en"])
        #expect(detail.playback?.streamURL.host == "example.invalid")
        #expect(detail.playback?.subtitles.first?.url.host == "ororo.tv")
        #expect(detail.playback?.fetchedAt == now)
    }

    @Test func nilShowIDGivesZero() throws {
        let detail = try Decoders.episode(Fixtures.data("episode"), showID: nil, now: now)
        #expect(detail.episode.showID == 0)
    }

    @Test func missingURLGivesNilPlayback() throws {
        let episode = Data(#"{"id":7,"name":"E","season":1,"number":"2","subtitles":[{"lang":"en","url":"/s.vtt"}]}"#.utf8)
        let detail = try Decoders.episode(episode, showID: 1, now: now)
        #expect(detail.playback == nil)
        #expect(detail.subtitleLanguages == ["en"])
        let notURL = Data(#"{"id":6936,"name":"M","url":"","subtitles":[]}"#.utf8)
        #expect(try Decoders.movie(notURL, now: now).playback == nil)
        let wrongType = Data(#"{"id":6936,"name":"M","url":42}"#.utf8)
        #expect(try Decoders.movie(wrongType, now: now).playback == nil)
    }

    @Test func relativeURLsResolveAgainstOrigin() throws {
        let data = Data(#"{"shows":[{"id":1,"name":"A","poster_thumb":"/uploads/p.jpg"}]}"#.utf8)
        let title = try #require(try Decoders.shows(data).first)
        #expect(title.posterURL?.absoluteString == "https://ororo.tv/uploads/p.jpg")
    }

    @Test func qualitiesSortNumericallyAndSubtitleLanguagesDedupe() throws {
        let data = Data("""
        {"id":1,"name":"M","versions":{"1080p":"a","240p":"b","720p":"c","360p":"d"},
         "subtitles":[{"lang":"fr","url":"/a.vtt"},{"lang":"en","url":"/b.vtt"},{"lang":"fr","url":"/c.vtt"}]}
        """.utf8)
        let detail = try Decoders.movie(data, now: now)
        #expect(detail.qualities == ["240p", "360p", "720p", "1080p"])
        #expect(detail.subtitleLanguages == ["fr", "en"])
        #expect(detail.playback == nil)
    }

    @Test func wrongTopLevelShapeThrowsDecoding() {
        #expect(throws: APIError.decoding) { try Decoders.shows(Data("[]".utf8)) }
        #expect(throws: APIError.decoding) { try Decoders.shows(Data(#"{"movies":[]}"#.utf8)) }
        #expect(throws: APIError.decoding) { try Decoders.shows(Data(#"{"shows":{}}"#.utf8)) }
        #expect(throws: APIError.decoding) { try Decoders.movies(Fixtures.data("shows")) }
        #expect(throws: APIError.decoding) { try Decoders.show(Data("garbage".utf8)) }
        #expect(throws: APIError.decoding) { try Decoders.show(Data(#"{"id":1}"#.utf8)) }
        #expect(throws: APIError.decoding) { try Decoders.movie(Data("{}".utf8), now: now) }
        #expect(throws: APIError.decoding) { try Decoders.episode(Data("[]".utf8), showID: nil, now: now) }
    }

    @Test func malformedItemsDegradeNotFail() throws {
        let titles = try Decoders.shows(Fixtures.data("malformed-shows"))
        #expect(titles.count == 2) // valid one + the one with bad fields; no-name and bad-id are skipped
        let odd = try #require(titles.first { $0.year == nil })
        #expect(odd.imdbRating == nil)
        #expect(odd.genres.isEmpty)
        #expect(!odd.name.isEmpty)
        #expect(odd.countries == ["us"])
    }

    @Test func decodesFullCatalogQuickly() throws {
        // 4,000 shows + 8,000 movies, built from the fixtures with unique ids.
        func inflate(_ fixture: String, key: String, copies: Int) throws -> Data {
            let root = try #require(try JSONSerialization.jsonObject(with: Fixtures.data(fixture)) as? [String: Any])
            let items = try #require(root[key] as? [[String: Any]])
            var all: [[String: Any]] = []
            for copy in 0..<copies {
                all += items.map { item in
                    var item = item
                    item["id"] = (item["id"] as? Int ?? 0) + copy * 1_000_000
                    return item
                }
            }
            return try JSONSerialization.data(withJSONObject: [key: all])
        }
        let shows = try inflate("shows", key: "shows", copies: 20)
        let movies = try inflate("movies", key: "movies", copies: 40)
        let start = ContinuousClock.now
        let decodedShows = try Decoders.shows(shows)
        let decodedMovies = try Decoders.movies(movies)
        let elapsed = ContinuousClock.now - start
        #expect(decodedShows.count == 4_000)
        #expect(decodedMovies.count == 8_000)
        #expect(elapsed < .seconds(2))
    }
}
