import Foundation

// STUB (T3) — implemented by Task C5. Constants are final values.
public extension Library {
    static let watchedThreshold = 0.95, resumeMinimum: TimeInterval = 60
    static let maxMyList = 500, maxProgress = 200, maxWatched = 5_000

    func isInMyList(_ id: TitleID) -> Bool {
        false
    }

    /// Adding a show follows it.
    mutating func toggleMyList(_ id: TitleID, newestVideo: Date?, now: Date) {}

    mutating func recordProgress(_ p: PlayableID, show: ShowContext?, position: TimeInterval, duration: TimeInterval, now: Date) {}

    mutating func finish(_ p: PlayableID, show: ShowContext?, next: EpisodeRef?, now: Date) {}

    mutating func markWatched(_ p: PlayableID) {}

    mutating func markUnwatched(_ p: PlayableID) {}

    /// Clears progress + upNext for that title; watched flags stay.
    mutating func removeFromContinueWatching(_ id: TitleID) {}

    mutating func dismissNewEpisodes(showID: Int, newestVideo: Date) {}

    /// Enforce caps, oldest first.
    mutating func prune() {}

    func isWatched(_ p: PlayableID) -> Bool {
        false
    }

    /// Nil when no entry or duration <= 0.
    func fraction(_ p: PlayableID) -> Double? {
        nil
    }

    /// Only when position > 60 and fraction < 0.95.
    func resumePosition(_ p: PlayableID) -> TimeInterval? {
        nil
    }

    func shouldMarkWatched(position: TimeInterval, duration: TimeInterval) -> Bool {
        false
    }
}
