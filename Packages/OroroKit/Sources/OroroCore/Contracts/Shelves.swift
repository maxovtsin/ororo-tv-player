import Foundation

public enum ShelfKind: Hashable, Codable, Sendable {
    case continueWatching, newEpisodes, popularShows, latestReleases, topRatedMovies,
         recentlyUpdatedMovies, myList, popularNow, topRated, recentlyUpdated, genre(String)
}

public enum ShelfBadge: Hashable, Codable, Sendable {
    case new, newCount(Int), newSince(Date)
}

public struct ShelfItem: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(title.id.kind.rawValue)-\(title.id.id)" }
    public let title: Title
    public var progress: Double?            // 0...1
    public var episode: EpisodeRef?
    public var badge: ShelfBadge?
    public var playable: PlayableID?        // set when Select should play directly

    public init(title: Title, progress: Double? = nil, episode: EpisodeRef? = nil, badge: ShelfBadge? = nil, playable: PlayableID? = nil) {
        self.title = title
        self.progress = progress
        self.episode = episode
        self.badge = badge
        self.playable = playable
    }
}

public struct Shelf: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let kind: ShelfKind
    public var items: [ShelfItem]
    public var totalCount: Int
    public var seeAll: BrowseQuery?

    public init(id: String, kind: ShelfKind, items: [ShelfItem], totalCount: Int, seeAll: BrowseQuery? = nil) {
        self.id = id
        self.kind = kind
        self.items = items
        self.totalCount = totalCount
        self.seeAll = seeAll
    }
}

public enum HeroAction: Hashable, Codable, Sendable {
    case playMovie, playFirstEpisode, playEpisode(EpisodeRef), resumeEpisode(EpisodeRef)
}

public struct HeroItem: Identifiable, Hashable, Codable, Sendable {
    public var id: TitleID { title.id }
    public let title: Title
    public var action: HeroAction

    public init(title: Title, action: HeroAction) {
        self.title = title
        self.action = action
    }
}

public struct HomeContent: Hashable, Codable, Sendable {
    public var hero: [HeroItem]
    public var shelves: [Shelf]

    public init(hero: [HeroItem], shelves: [Shelf]) {
        self.hero = hero
        self.shelves = shelves
    }
}

public struct BrowseQuery: Hashable, Codable, Sendable {
    public enum Status: String, Hashable, Codable, Sendable { case ongoing, ended }
    public enum Sort: String, CaseIterable, Hashable, Codable, Sendable { case topPicks, popular, rating, year, recentlyUpdated, alphabetical }

    public var kind: TitleKind
    public var genre: String?
    public var decade: Int?
    public var minRating: Double?
    public var status: Status?
    public var sort: Sort

    public init(kind: TitleKind, genre: String? = nil, decade: Int? = nil, minRating: Double? = nil, status: Status? = nil, sort: Sort) {
        self.kind = kind
        self.genre = genre
        self.decade = decade
        self.minRating = minRating
        self.status = status
        self.sort = sort
    }

    /// `.popular` for shows, `.recentlyUpdated` for movies, no filters.
    public static func `default`(_ kind: TitleKind) -> BrowseQuery {
        BrowseQuery(kind: kind, sort: kind == .show ? .popular : .recentlyUpdated)
    }
}

public struct SearchResults: Hashable, Codable, Sendable {
    public var shows: [Title]
    public var movies: [Title]

    public init(shows: [Title], movies: [Title]) {
        self.shows = shows
        self.movies = movies
    }
}
