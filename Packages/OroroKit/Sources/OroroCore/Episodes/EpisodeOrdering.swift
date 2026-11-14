import Foundation

// STUB (T3) — implemented by Task C4.
public enum EpisodeOrdering {
    /// Ascending, 0 ("Specials") last.
    public static func seasons(_ episodes: [Episode]) -> [Int] {
        []
    }

    /// By number; nil numbers last in original order.
    public static func episodes(_ episodes: [Episode], season: Int) -> [Episode] {
        []
    }

    /// All seasons in play order, specials excluded.
    public static func ordered(_ episodes: [Episode]) -> [Episode] {
        []
    }

    /// Nil at the end, or if id is a special/unknown.
    public static func next(after episodeID: Int, in episodes: [Episode]) -> Episode? {
        nil
    }

    public static func first(in episodes: [Episode]) -> Episode? {
        nil
    }

    public static func unwatched(after lastWatchedID: Int?, in episodes: [Episode], watched: Set<Int>) -> [Episode] {
        []
    }

    public static func initialSeason(episodes: [Episode], resume: EpisodeRef?) -> Int? {
        nil
    }

    /// By numeric value of "720p".
    public static func qualityRange(_ episodes: [Episode]) -> (lowest: String, highest: String)? {
        nil
    }

    /// Nil when number is nil.
    public static func ref(_ episode: Episode) -> EpisodeRef? {
        nil
    }
}
