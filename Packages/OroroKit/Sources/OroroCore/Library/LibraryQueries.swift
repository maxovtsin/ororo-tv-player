import Foundation

/// Read-only views of a `Library` against the catalog. Ids missing from the catalog are skipped, never deleted.
public enum LibraryQueries {
    static let newEpisodesCap = 30

    /// One item per in-progress movie and one per show (its latest in-progress episode, else its up-next),
    /// sorted by last activity, newest first. A show with new episodes gets `badge: .new`.
    public static func continueWatching(_ library: Library, catalog: Catalog) -> [ShelfItem] {
        var rows: [(activity: Date, item: ShelfItem)] = []
        let newShows = Set(showsWithNewEpisodes(library, catalog: catalog).map(\.id.id))

        for entry in library.progress where entry.playable.kind == .movie {
            guard let title = catalog.title(TitleID(kind: .movie, id: entry.playable.id)) else { continue }
            let item = ShelfItem(
                title: title,
                progress: Library.fraction(position: entry.position, duration: entry.duration),
                playable: entry.playable
            )
            rows.append((entry.updatedAt, item))
        }

        let latest = latestEpisodeProgress(library)
        let showIDs = Set(latest.keys).union(library.upNext.keys)
        for showID in showIDs {
            guard let title = catalog.title(TitleID(kind: .show, id: showID)) else { continue }
            let badge: ShelfBadge? = newShows.contains(showID) ? .new : nil
            if let entry = latest[showID] {
                let item = ShelfItem(
                    title: title,
                    progress: Library.fraction(position: entry.position, duration: entry.duration),
                    episode: episodeRef(entry),
                    badge: badge,
                    playable: entry.playable
                )
                rows.append((entry.updatedAt, item))
            } else if let next = library.upNext[showID] {
                let item = ShelfItem(
                    title: title,
                    episode: next.ref,
                    badge: badge,
                    playable: PlayableID(kind: .episode, id: next.ref.episodeID)
                )
                rows.append((next.setAt, item))
            }
        }

        return rows
            .sorted { $0.activity != $1.activity ? $0.activity > $1.activity : $0.item.id < $1.item.id }
            .map(\.item)
    }

    /// Followed shows whose catalog `newestVideo` is newer than the stored `seenNewestVideo`, newest first.
    /// Includes those in Continue Watching.
    public static func showsWithNewEpisodes(_ library: Library, catalog: Catalog) -> [Title] {
        library.followed
            .compactMap { showID, state -> Title? in
                guard let title = catalog.title(TitleID(kind: .show, id: showID)),
                      let newest = title.newestVideo, newest > state.seenNewestVideo else { return nil }
                return title
            }
            .sorted(by: newestFirst)
    }

    /// `showsWithNewEpisodes` minus shows in Continue Watching, newest release first, max 30.
    public static func newEpisodes(_ library: Library, catalog: Catalog, resolved: [Int: NewEpisodeInfo]) -> [ShelfItem] {
        let inContinueWatching = Set(continueWatching(library, catalog: catalog).map(\.title.id))
        return showsWithNewEpisodes(library, catalog: catalog)
            .filter { !inContinueWatching.contains($0.id) }
            .prefix(newEpisodesCap)
            .map { title in
                let started = library.followed[title.id.id]?.started ?? false
                guard let info = resolved[title.id.id] else {
                    return ShelfItem(title: title, badge: title.newestVideo.map(ShelfBadge.newSince))
                }
                return ShelfItem(
                    title: title,
                    episode: info.first,
                    badge: info.count > 1 ? .newCount(info.count) : .new,
                    playable: started ? PlayableID(kind: .episode, id: info.first.episodeID) : nil
                )
            }
    }

    /// Newest first.
    public static func myList(_ library: Library, catalog: Catalog) -> [Title] {
        library.myList
            .enumerated()
            .sorted { $0.element.addedAt != $1.element.addedAt ? $0.element.addedAt > $1.element.addedAt : $0.offset > $1.offset }
            .compactMap { catalog.title($0.element.title) }
    }

    public static func heroAction(for title: Title, library: Library) -> HeroAction {
        guard title.id.kind == .show else { return .playMovie }
        if let entry = latestEpisodeProgress(library)[title.id.id], let ref = episodeRef(entry) {
            return .resumeEpisode(ref)
        }
        if let next = library.upNext[title.id.id] {
            return .playEpisode(next.ref)
        }
        return .playFirstEpisode
    }

    /// In-progress, else upNext.
    public static func resumeTarget(showID: Int, library: Library) -> EpisodeRef? {
        if let entry = latestEpisodeProgress(library)[showID], let ref = episodeRef(entry) {
            return ref
        }
        return library.upNext[showID]?.ref
    }

    // MARK: - Helpers

    /// The most recent in-progress episode entry per show id.
    static func latestEpisodeProgress(_ library: Library) -> [Int: ProgressEntry] {
        var latest: [Int: ProgressEntry] = [:]
        for entry in library.progress where entry.playable.kind == .episode {
            guard let showID = entry.showID else { continue }
            if let current = latest[showID], current.updatedAt > entry.updatedAt { continue }
            latest[showID] = entry
        }
        return latest
    }

    static func episodeRef(_ entry: ProgressEntry) -> EpisodeRef? {
        guard entry.playable.kind == .episode, let season = entry.season, let number = entry.number else { return nil }
        return EpisodeRef(episodeID: entry.playable.id, season: season, number: number)
    }

    static func newestFirst(_ lhs: Title, _ rhs: Title) -> Bool {
        let left = lhs.newestVideo ?? .distantPast, right = rhs.newestVideo ?? .distantPast
        return left != right ? left > right : lhs.id.id < rhs.id.id
    }
}
