import Foundation
import OroroCore

// Wire-level types for the ororo.tv API. Everything except `id` / `name` decodes leniently:
// a wrong type or an unparseable value becomes nil / empty instead of failing the response.

extension KeyedDecodingContainer {
    /// Value for `key`, or nil when absent, null or of the wrong type.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

/// Decodes `T`, or becomes nil when the element is malformed; used to drop bad list items.
struct Lossy<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: any Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// Accepts any JSON value and keeps nothing; used to read only the keys of a dictionary.
struct Ignored: Decodable {
    init(from decoder: any Decoder) throws {}
}

enum WireParsing {
    private static let base = URL(string: "https://ororo.tv") ?? URL(fileURLWithPath: "/")

    /// Absolute URL; relative paths (`/uploads/...`) resolve against `https://ororo.tv`.
    static func url(_ string: String?) -> URL? {
        guard let string, !string.isEmpty,
              let url = URL(string: string, relativeTo: base)?.absoluteURL,
              url.scheme != nil, url.host != nil else { return nil }
        return url
    }

    static func date(unix: Double?) -> Date? {
        unix.map { Date(timeIntervalSince1970: $0) }
    }

    static func int(_ string: String?) -> Int? {
        guard let string else { return nil }
        return Int(string.trimmingCharacters(in: .whitespaces))
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// `YYYY-MM-DD` in UTC.
    static func airdate(_ string: String?) -> Date? {
        guard let string, string.utf8.count == 10 else { return nil }
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        return utc.date(from: DateComponents(year: year, month: month, day: day))
    }

    static func resolution(_ string: String?) -> Resolution? {
        string.flatMap { Resolution(rawValue: $0.uppercased()) }
    }

    /// Keys of a `versions` object sorted by their numeric value ("240p" < "1080p").
    static func qualities(_ versions: [String: Ignored]?) -> [String] {
        guard let versions else { return [] }
        func rank(_ key: String) -> Int { Int(key.filter(\.isNumber)) ?? Int.max }
        return versions.keys.sorted { (rank($0), $0) < (rank($1), $1) }
    }

    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

struct TitleDTO: Decodable {
    let id: Int
    let name: String
    let desc: String?
    let posterThumb: String?
    let backdropURL: String?
    let imdbRating: Double?
    let imdbID: String?
    let year: String?
    let genres: [String]?
    let countries: [String]?
    let length: Int?
    let resolution: String?
    let ended: Bool?
    let popularity: Int?
    let newestVideo: Double?
    let updatedAt: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, desc, year, length, resolution, ended
        case posterThumb = "poster_thumb"
        case backdropURL = "backdrop_url"
        case imdbRating = "imdb_rating"
        case imdbID = "imdb_id"
        case genres = "array_genres"
        case countries = "array_countries"
        case popularity = "user_popularity"
        case newestVideo = "newest_video"
        case updatedAt = "updated_at"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        desc = c.lenient(String.self, .desc)
        posterThumb = c.lenient(String.self, .posterThumb)
        backdropURL = c.lenient(String.self, .backdropURL)
        imdbRating = c.lenient(Double.self, .imdbRating)
        imdbID = c.lenient(String.self, .imdbID)
        year = c.lenient(String.self, .year)
        genres = c.lenient([String].self, .genres)
        countries = c.lenient([String].self, .countries)
        length = c.lenient(Int.self, .length)
        resolution = c.lenient(String.self, .resolution)
        ended = c.lenient(Bool.self, .ended)
        popularity = c.lenient(Int.self, .popularity)
        newestVideo = c.lenient(Double.self, .newestVideo)
        updatedAt = c.lenient(Double.self, .updatedAt)
    }

    func title(kind: TitleKind) -> Title {
        Title(
            id: TitleID(kind: kind, id: id),
            name: name,
            desc: desc,
            posterURL: WireParsing.url(posterThumb),
            backdropURL: WireParsing.url(backdropURL),
            imdbRating: imdbRating,
            imdbID: imdbID,
            year: WireParsing.int(year),
            genres: genres ?? [],
            countries: countries ?? [],
            lengthMinutes: length,
            resolution: WireParsing.resolution(resolution),
            ended: ended,
            popularity: popularity ?? 0,
            newestVideo: WireParsing.date(unix: newestVideo),
            updatedAt: WireParsing.date(unix: updatedAt)
        )
    }
}

struct SubtitleDTO: Decodable {
    let subtitle: Subtitle

    enum CodingKeys: String, CodingKey { case lang, url }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let lang = try c.decode(String.self, forKey: .lang)
        guard let url = WireParsing.url(try c.decode(String.self, forKey: .url)) else {
            throw APIError.decoding
        }
        subtitle = Subtitle(lang: lang, url: url)
    }
}

extension Array where Element == Lossy<SubtitleDTO> {
    var subtitles: [Subtitle] { compactMap { $0.value?.subtitle } }
}

struct EpisodeDTO: Decodable {
    let id: Int
    let name: String?
    let plot: String?
    let season: Int?
    let number: String?
    let airdate: String?
    let resolution: String?
    let versions: [String: Ignored]?
    let showName: String?
    let url: String?
    let subtitles: [Lossy<SubtitleDTO>]?

    enum CodingKeys: String, CodingKey {
        case id, name, plot, season, number, airdate, resolution, versions, url, subtitles
        case showName = "show_name"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = c.lenient(String.self, .name)
        plot = c.lenient(String.self, .plot)
        season = c.lenient(Int.self, .season)
        // The API sends `number` as a string; tolerate a bare integer too.
        number = c.lenient(String.self, .number) ?? c.lenient(Int.self, .number).map(String.init)
        airdate = c.lenient(String.self, .airdate)
        resolution = c.lenient(String.self, .resolution)
        versions = c.lenient([String: Ignored].self, .versions)
        showName = c.lenient(String.self, .showName)
        url = c.lenient(String.self, .url)
        subtitles = c.lenient([Lossy<SubtitleDTO>].self, .subtitles)
    }

    func episode(showID: Int) -> Episode {
        Episode(
            id: id,
            showID: showID,
            name: name,
            plot: plot,
            season: season ?? 0,
            number: WireParsing.int(number),
            airdate: WireParsing.airdate(airdate),
            resolution: WireParsing.resolution(resolution),
            qualities: WireParsing.qualities(versions)
        )
    }
}

struct ShowDTO: Decodable {
    let title: TitleDTO
    let seasons: Int?
    let episodes: [Lossy<EpisodeDTO>]?

    enum CodingKeys: String, CodingKey { case seasons, episodes }

    init(from decoder: any Decoder) throws {
        title = try TitleDTO(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seasons = c.lenient(Int.self, .seasons)
        episodes = c.lenient([Lossy<EpisodeDTO>].self, .episodes)
    }
}

struct MovieDTO: Decodable {
    let title: TitleDTO
    let trailer: String?
    let versions: [String: Ignored]?
    let url: String?
    let subtitles: [Lossy<SubtitleDTO>]?

    enum CodingKeys: String, CodingKey { case trailer, versions, url, subtitles }

    init(from decoder: any Decoder) throws {
        title = try TitleDTO(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trailer = c.lenient(String.self, .trailer)
        versions = c.lenient([String: Ignored].self, .versions)
        url = c.lenient(String.self, .url)
        subtitles = c.lenient([Lossy<SubtitleDTO>].self, .subtitles)
    }
}

/// `{ "shows": [...] }` or `{ "movies": [...] }`; items that are malformed or lack id/name are dropped.
struct ShowListDTO: Decodable {
    let items: [Lossy<TitleDTO>]
    enum CodingKeys: String, CodingKey { case items = "shows" }
}

struct MovieListDTO: Decodable {
    let items: [Lossy<TitleDTO>]
    enum CodingKeys: String, CodingKey { case items = "movies" }
}
