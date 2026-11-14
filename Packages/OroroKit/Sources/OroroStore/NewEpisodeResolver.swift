import Foundation
import OroroCore

/// Resolves, for followed shows, the first unwatched episode after the last watched one
/// (spec: *New Episodes rules*). Fetches `/shows/{id}` one at a time, at most `maxPerRun` per run.
public actor NewEpisodeResolver: NewEpisodeResolving {
    private let details: any DetailProviding
    private let maxPerRun: Int
    private var results: [Int: NewEpisodeInfo] = [:]

    public init(details: any DetailProviding, maxPerRun: Int = 10) {
        self.details = details
        self.maxPerRun = maxPerRun
    }

    public func cached() async -> [Int: NewEpisodeInfo] {
        results
    }

    /// Entries of shows not in `shows` are dropped. Shows that are not fetched this run
    /// (over the cap, or a failed fetch) keep their previous entry; fetched shows are replaced
    /// by the fresh result, or removed when nothing is unwatched.
    public func resolve(shows: [Title], library: Library) async -> [Int: NewEpisodeInfo] {
        let ids = shows.map(\.id.id)
        var merged = results.filter { ids.contains($0.key) }
        let watched = Set(library.watchedEpisodes)
            .union(library.progress.filter { $0.playable.kind == .episode }.map(\.playable.id))

        for showID in ids.prefix(maxPerRun) {
            guard let detail = try? await details.show(id: showID) else { continue }
            merged[showID] = Self.newEpisodes(in: detail.episodes, watched: watched)
        }
        results = merged
        return merged
    }

    /// Play order: season, then number; season 0 and unnumbered episodes are ignored.
    private static func newEpisodes(in episodes: [Episode], watched: Set<Int>) -> NewEpisodeInfo? {
        let ordered = episodes
            .filter { $0.season > 0 && $0.number != nil }
            .sorted { ($0.season, $0.number ?? 0) < ($1.season, $1.number ?? 0) }
        guard let last = ordered.lastIndex(where: { watched.contains($0.id) }) else { return nil }
        let unwatched = ordered[(last + 1)...]
        guard let first = unwatched.first, let number = first.number else { return nil }
        return NewEpisodeInfo(first: EpisodeRef(episodeID: first.id, season: first.season, number: number),
                              count: unwatched.count)
    }
}
