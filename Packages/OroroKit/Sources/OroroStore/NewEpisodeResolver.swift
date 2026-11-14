import Foundation
import OroroCore

/// Resolves, for followed shows, the first unwatched episode after the last watched one
/// (spec: *New Episodes rules*). Fetches `/shows/{id}` one at a time, at most `maxPerRun` per run.
public actor NewEpisodeResolver: NewEpisodeResolving {
    private let details: any DetailProviding
    private let maxPerRun: Int
    private var results: [Int: NewEpisodeInfo] = [:]
    /// Play-ordered refs (no season 0, no nil numbers) of every show fetched so far, so kept
    /// entries are recomputed against the current library on each run.
    private var refs: [Int: [EpisodeRef]] = [:]
    private var generation = 0

    public init(details: any DetailProviding, maxPerRun: Int = 10) {
        self.details = details
        self.maxPerRun = maxPerRun
    }

    public func cached() async -> [Int: NewEpisodeInfo] {
        results
    }

    /// Fetches at most `maxPerRun` shows, then recomputes every show with known episode refs from
    /// the current `library`. Shows missing from `shows` are dropped. A superseded or cancelled
    /// run commits nothing and returns the latest committed results.
    public func resolve(shows: [Title], library: Library) async -> [Int: NewEpisodeInfo] {
        generation += 1
        let myGeneration = generation
        let ids = shows.map(\.id.id)
        let watched = Set(library.watchedEpisodes)
            .union(library.progress.filter { $0.playable.kind == .episode }.map(\.playable.id))
        var knownRefs = refs.filter { ids.contains($0.key) }

        for showID in ids.prefix(maxPerRun) {
            if Task.isCancelled { return results }
            guard let detail = try? await details.show(id: showID) else { continue }
            knownRefs[showID] = Self.orderedRefs(detail.episodes)
        }
        guard !Task.isCancelled, myGeneration == generation else { return results }

        refs = knownRefs
        results = knownRefs.compactMapValues { Self.newEpisodes(in: $0, watched: watched) }
        return results
    }

    /// Play order: season, then number; season 0 and unnumbered episodes are ignored.
    private static func orderedRefs(_ episodes: [Episode]) -> [EpisodeRef] {
        episodes
            .compactMap { episode in
                episode.number.map { EpisodeRef(episodeID: episode.id, season: episode.season, number: $0) }
            }
            .filter { $0.season > 0 }
            .sorted { ($0.season, $0.number) < ($1.season, $1.number) }
    }

    private static func newEpisodes(in ordered: [EpisodeRef], watched: Set<Int>) -> NewEpisodeInfo? {
        guard let last = ordered.lastIndex(where: { watched.contains($0.episodeID) }) else { return nil }
        let unwatched = ordered[(last + 1)...]
        guard let first = unwatched.first else { return nil }
        return NewEpisodeInfo(first: first, count: unwatched.count)
    }
}
