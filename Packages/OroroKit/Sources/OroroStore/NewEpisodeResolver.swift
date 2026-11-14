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
    /// Run number of each show's last fetch attempt (committed with `refs`); older first on the next run.
    private var fetchedInRun: [Int: Int] = [:]
    private var runCount = 0
    private var generation = 0

    public init(details: any DetailProviding, maxPerRun: Int = 10) {
        self.details = details
        self.maxPerRun = maxPerRun
    }

    public func cached() async -> [Int: NewEpisodeInfo] {
        results
    }

    /// Fetches at most `maxPerRun` shows — those without cached refs first (in `shows` order), then the
    /// least recently fetched — so successive runs rotate through every show. Then recomputes every show with known episode refs from
    /// the current `library`. Shows missing from `shows` are dropped. A superseded or cancelled
    /// run commits nothing and returns the latest committed results.
    public func resolve(shows: [Title], library: Library) async -> [Int: NewEpisodeInfo] {
        generation += 1
        let myGeneration = generation
        let ids = shows.map(\.id.id)
        let watched = Set(library.watchedEpisodes)
            .union(library.progress.filter { $0.playable.kind == .episode }.map(\.playable.id))
        var knownRefs = refs.filter { ids.contains($0.key) }
        var fetched = fetchedInRun.filter { ids.contains($0.key) }
        runCount += 1
        let run = runCount
        // Stable: uncached (-1) first, then by the run that last fetched them.
        let order = ids.enumerated()
            .sorted { (fetched[$0.element] ?? -1, $0.offset) < (fetched[$1.element] ?? -1, $1.offset) }
            .map(\.element)

        for showID in order.prefix(maxPerRun) {
            if Task.isCancelled { return results }
            // Attempts count, so shows that keep failing can't starve the rest.
            fetched[showID] = run
            guard let detail = try? await details.show(id: showID) else { continue }
            knownRefs[showID] = Self.orderedRefs(detail.episodes)
        }
        guard !Task.isCancelled, myGeneration == generation else { return results }

        refs = knownRefs
        fetchedInRun = fetched
        results = knownRefs.compactMapValues { Self.newEpisodes(in: $0, watched: watched) }
        return results
    }

    /// `EpisodeOrdering.ordered` (the player's "next" order), keeping numbered episodes only.
    private static func orderedRefs(_ episodes: [Episode]) -> [EpisodeRef] {
        EpisodeOrdering.ordered(episodes).compactMap(EpisodeOrdering.ref)
    }

    private static func newEpisodes(in ordered: [EpisodeRef], watched: Set<Int>) -> NewEpisodeInfo? {
        guard let last = ordered.lastIndex(where: { watched.contains($0.episodeID) }) else { return nil }
        let unwatched = ordered[(last + 1)...]
        guard let first = unwatched.first else { return nil }
        return NewEpisodeInfo(first: first, count: unwatched.count)
    }
}
