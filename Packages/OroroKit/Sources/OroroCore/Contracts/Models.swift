import Foundation

public enum TitleKind: String, CaseIterable, Hashable, Codable, Sendable { case show, movie }

public struct TitleID: Hashable, Codable, Sendable {
    public let kind: TitleKind
    public let id: Int

    public init(kind: TitleKind, id: Int) {
        self.kind = kind
        self.id = id
    }
}

public enum Resolution: String, Hashable, Codable, Sendable {
    case sd = "SD"
    case hd = "HD"
}

public struct Title: Identifiable, Hashable, Codable, Sendable {
    public let id: TitleID
    public var name: String
    public var desc: String?
    public var posterURL: URL?
    public var backdropURL: URL?
    public var imdbRating: Double?
    public var imdbID: String?
    public var year: Int?
    public var genres: [String]
    public var countries: [String]          // ISO-2
    public var lengthMinutes: Int?
    public var resolution: Resolution?      // movies only
    public var ended: Bool?                 // shows only
    public var popularity: Int              // 0 = unknown; always 0 for movies
    public var newestVideo: Date?           // shows only
    public var updatedAt: Date?

    public init(
        id: TitleID,
        name: String,
        desc: String? = nil,
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        imdbRating: Double? = nil,
        imdbID: String? = nil,
        year: Int? = nil,
        genres: [String] = [],
        countries: [String] = [],
        lengthMinutes: Int? = nil,
        resolution: Resolution? = nil,
        ended: Bool? = nil,
        popularity: Int = 0,
        newestVideo: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.desc = desc
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.imdbRating = imdbRating
        self.imdbID = imdbID
        self.year = year
        self.genres = genres
        self.countries = countries
        self.lengthMinutes = lengthMinutes
        self.resolution = resolution
        self.ended = ended
        self.popularity = popularity
        self.newestVideo = newestVideo
        self.updatedAt = updatedAt
    }
}

public struct Episode: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let showID: Int
    public var name: String?
    public var plot: String?
    public var season: Int
    public var number: Int?                 // nil when the API string is not numeric
    public var airdate: Date?
    public var resolution: Resolution?
    public var qualities: [String]          // keys of `versions`, e.g. ["240p","720p"]

    public init(
        id: Int,
        showID: Int,
        name: String? = nil,
        plot: String? = nil,
        season: Int,
        number: Int?,
        airdate: Date? = nil,
        resolution: Resolution? = nil,
        qualities: [String] = []
    ) {
        self.id = id
        self.showID = showID
        self.name = name
        self.plot = plot
        self.season = season
        self.number = number
        self.airdate = airdate
        self.resolution = resolution
        self.qualities = qualities
    }
}

public struct Subtitle: Hashable, Codable, Sendable {
    public let lang: String
    public let url: URL

    public init(lang: String, url: URL) {
        self.lang = lang
        self.url = url
    }
}

/// Not Codable: a playback URL is never persisted.
public struct Playback: Hashable, Sendable {
    public let streamURL: URL
    public let subtitles: [Subtitle]
    public let fetchedAt: Date

    public init(streamURL: URL, subtitles: [Subtitle], fetchedAt: Date) {
        self.streamURL = streamURL
        self.subtitles = subtitles
        self.fetchedAt = fetchedAt
    }
}

public struct ShowDetail: Hashable, Codable, Sendable {
    public var title: Title
    public var seasonCount: Int?
    public var episodes: [Episode]

    public init(title: Title, seasonCount: Int?, episodes: [Episode]) {
        self.title = title
        self.seasonCount = seasonCount
        self.episodes = episodes
    }
}

/// Not Codable (carries `Playback`).
public struct MovieDetail: Hashable, Sendable {
    public var title: Title
    public var trailerYouTubeID: String?
    public var qualities: [String]
    public var subtitleLanguages: [String]
    public var playback: Playback?

    public init(title: Title, trailerYouTubeID: String?, qualities: [String], subtitleLanguages: [String], playback: Playback?) {
        self.title = title
        self.trailerYouTubeID = trailerYouTubeID
        self.qualities = qualities
        self.subtitleLanguages = subtitleLanguages
        self.playback = playback
    }
}

/// Not Codable (carries `Playback`).
///
/// `episode.showID` is 0 when unknown (the endpoint does not return it); consumers take the show id from
/// `PlayRequest.Target.episode(showID:)` or the show detail, never from `EpisodeDetail`.
public struct EpisodeDetail: Hashable, Sendable {
    public var episode: Episode
    public var showName: String?
    public var subtitleLanguages: [String]
    public var playback: Playback?

    public init(episode: Episode, showName: String?, subtitleLanguages: [String], playback: Playback?) {
        self.episode = episode
        self.showName = showName
        self.subtitleLanguages = subtitleLanguages
        self.playback = playback
    }
}

/// Not Codable. Equality and hashing use `shows`, `movies` and `fetchedAt`.
public struct Catalog: Hashable, Sendable {
    public let shows: [Title]
    public let movies: [Title]
    public let fetchedAt: Date
    private let index: [TitleID: Int]

    public init(shows: [Title], movies: [Title], fetchedAt: Date) {
        self.shows = shows
        self.movies = movies
        self.fetchedAt = fetchedAt
        var index: [TitleID: Int] = [:]
        index.reserveCapacity(shows.count + movies.count)
        for (offset, title) in shows.enumerated() where index[title.id] == nil { index[title.id] = offset }
        for (offset, title) in movies.enumerated() where index[title.id] == nil { index[title.id] = offset }
        self.index = index
    }

    public func title(_ id: TitleID) -> Title? {
        guard let offset = index[id] else { return nil }
        return titles(id.kind)[offset]
    }

    public func titles(_ kind: TitleKind) -> [Title] {
        switch kind {
        case .show: shows
        case .movie: movies
        }
    }

    public static func == (lhs: Catalog, rhs: Catalog) -> Bool {
        lhs.fetchedAt == rhs.fetchedAt && lhs.shows == rhs.shows && lhs.movies == rhs.movies
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(shows)
        hasher.combine(movies)
        hasher.combine(fetchedAt)
    }
}

/// Equatable, not Codable: credentials only live in the Keychain.
public struct Credentials: Equatable, Sendable {
    public let email: String
    public let password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

public enum APIError: Error, Equatable {
    case unauthorized, offline, notFound, server(status: Int), decoding
}
