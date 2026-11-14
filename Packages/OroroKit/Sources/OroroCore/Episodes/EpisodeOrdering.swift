import Foundation

public enum EpisodeOrdering {
    /// Ascending, 0 ("Specials") last.
    public static func seasons(_ episodes: [Episode]) -> [Int] {
        let all = Set(episodes.map(\.season))
        let regular = all.filter { $0 != 0 }.sorted()
        return all.contains(0) ? regular + [0] : regular
    }

    /// By number; nil numbers last in original order. Ties keep original order.
    public static func episodes(_ episodes: [Episode], season: Int) -> [Episode] {
        episodes
            .enumerated()
            .filter { $0.element.season == season }
            .sorted { lhs, rhs in
                switch (lhs.element.number, rhs.element.number) {
                case let (left?, right?):
                    left != right ? left < right : lhs.offset < rhs.offset
                case (nil, nil): lhs.offset < rhs.offset
                case (_?, nil): true
                case (nil, _?): false
                }
            }
            .map(\.element)
    }

    /// All seasons in play order, specials excluded.
    public static func ordered(_ episodes: [Episode]) -> [Episode] {
        seasons(episodes)
            .filter { $0 != 0 }
            .flatMap { Self.episodes(episodes, season: $0) }
    }

    /// Nil at the end, or if id is a special/unknown.
    public static func next(after episodeID: Int, in episodes: [Episode]) -> Episode? {
        let playOrder = ordered(episodes)
        guard let index = playOrder.firstIndex(where: { $0.id == episodeID }),
              playOrder.index(after: index) < playOrder.endIndex else { return nil }
        return playOrder[playOrder.index(after: index)]
    }

    public static func first(in episodes: [Episode]) -> Episode? {
        ordered(episodes).first
    }

    /// Episodes in play order after `lastWatchedID` (all when nil or unknown), excluding watched ones.
    public static func unwatched(after lastWatchedID: Int?, in episodes: [Episode], watched: Set<Int>) -> [Episode] {
        let playOrder = ordered(episodes)
        var tail = playOrder[...]
        if let lastWatchedID, let index = playOrder.firstIndex(where: { $0.id == lastWatchedID }) {
            tail = playOrder[playOrder.index(after: index)...]
        }
        return tail.filter { !watched.contains($0.id) }
    }

    /// The resume season when present, else the first season; nil when there are no episodes.
    public static func initialSeason(episodes: [Episode], resume: EpisodeRef?) -> Int? {
        let all = seasons(episodes)
        if let resume, all.contains(resume.season) { return resume.season }
        return all.first
    }

    /// By numeric value of "720p".
    public static func qualityRange(_ episodes: [Episode]) -> (lowest: String, highest: String)? {
        let values = episodes.flatMap(\.qualities).compactMap { quality -> (value: Int, label: String)? in
            Int(quality.prefix { $0.isNumber }).map { ($0, quality) }
        }
        guard let lowest = values.min(by: { $0.value < $1.value }),
              let highest = values.max(by: { $0.value < $1.value }) else { return nil }
        return (lowest.label, highest.label)
    }

    /// Nil when number is nil.
    public static func ref(_ episode: Episode) -> EpisodeRef? {
        episode.number.map { EpisodeRef(episodeID: episode.id, season: episode.season, number: $0) }
    }
}
