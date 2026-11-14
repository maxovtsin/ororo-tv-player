import Foundation

public enum PlayableKind: String, Hashable, Codable, Sendable { case movie, episode }

public struct PlayableID: Hashable, Codable, Sendable {
    public let kind: PlayableKind
    public let id: Int

    public init(kind: PlayableKind, id: Int) {
        self.kind = kind
        self.id = id
    }
}

public struct MyListItem: Hashable, Codable, Sendable {
    public let title: TitleID
    public let addedAt: Date

    public init(title: TitleID, addedAt: Date) {
        self.title = title
        self.addedAt = addedAt
    }
}

public struct ProgressEntry: Hashable, Codable, Sendable {
    public let playable: PlayableID
    public var showID: Int?
    public var season: Int?
    public var number: Int?
    public var episodeName: String?
    public var position: TimeInterval
    public var duration: TimeInterval
    public var updatedAt: Date

    public init(
        playable: PlayableID,
        showID: Int? = nil,
        season: Int? = nil,
        number: Int? = nil,
        episodeName: String? = nil,
        position: TimeInterval,
        duration: TimeInterval,
        updatedAt: Date
    ) {
        self.playable = playable
        self.showID = showID
        self.season = season
        self.number = number
        self.episodeName = episodeName
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
    }
}

public struct EpisodeRef: Hashable, Codable, Sendable {
    public let episodeID: Int
    public let season: Int
    public let number: Int

    public init(episodeID: Int, season: Int, number: Int) {
        self.episodeID = episodeID
        self.season = season
        self.number = number
    }
}

public struct UpNextEntry: Hashable, Codable, Sendable {
    public let ref: EpisodeRef
    public let setAt: Date

    public init(ref: EpisodeRef, setAt: Date) {
        self.ref = ref
        self.setAt = setAt
    }
}

public struct FollowState: Hashable, Codable, Sendable {
    public var seenNewestVideo: Date
    public var started: Bool

    public init(seenNewestVideo: Date, started: Bool) {
        self.seenNewestVideo = seenNewestVideo
        self.started = started
    }
}

public struct Preferences: Hashable, Codable, Sendable {
    public var subtitleLanguage: String?    // nil = Off
    public var autoplayNext: Bool
    /// Generates 5.1 for stereo titles when the output supports it (tvOS).
    public var simulatedSurround: Bool

    public init(subtitleLanguage: String? = "en", autoplayNext: Bool = true, simulatedSurround: Bool = true) {
        self.subtitleLanguage = subtitleLanguage
        self.autoplayNext = autoplayNext
        self.simulatedSurround = simulatedSurround
    }

    // Hand-written so a library saved before `simulatedSurround` existed still decodes: a decode failure would
    // make the store back the data up and start empty.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subtitleLanguage = try container.decodeIfPresent(String.self, forKey: .subtitleLanguage)
        autoplayNext = try container.decode(Bool.self, forKey: .autoplayNext)
        simulatedSurround = try container.decodeIfPresent(Bool.self, forKey: .simulatedSurround) ?? true
    }
}

public struct Library: Hashable, Codable, Sendable {
    public var schemaVersion: Int
    public var myList: [MyListItem]
    public var progress: [ProgressEntry]
    public var watchedEpisodes: [Int]       // insertion order, no duplicates
    public var watchedMovies: [Int]         // insertion order, no duplicates
    public var upNext: [Int: UpNextEntry]   // key: show id
    public var followed: [Int: FollowState] // key: show id
    public var preferences: Preferences

    public init(
        schemaVersion: Int = 1,
        myList: [MyListItem] = [],
        progress: [ProgressEntry] = [],
        watchedEpisodes: [Int] = [],
        watchedMovies: [Int] = [],
        upNext: [Int: UpNextEntry] = [:],
        followed: [Int: FollowState] = [:],
        preferences: Preferences = Preferences()
    ) {
        self.schemaVersion = schemaVersion
        self.myList = myList
        self.progress = progress
        self.watchedEpisodes = watchedEpisodes
        self.watchedMovies = watchedMovies
        self.upNext = upNext
        self.followed = followed
        self.preferences = preferences
    }
}

public struct ShowContext: Hashable, Codable, Sendable {
    public let showID: Int
    public let season: Int
    public let number: Int
    public let episodeName: String?
    public let newestVideo: Date?

    public init(showID: Int, season: Int, number: Int, episodeName: String?, newestVideo: Date?) {
        self.showID = showID
        self.season = season
        self.number = number
        self.episodeName = episodeName
        self.newestVideo = newestVideo
    }
}

public struct NewEpisodeInfo: Hashable, Codable, Sendable {
    public let first: EpisodeRef
    public let count: Int

    public init(first: EpisodeRef, count: Int) {
        self.first = first
        self.count = count
    }
}
