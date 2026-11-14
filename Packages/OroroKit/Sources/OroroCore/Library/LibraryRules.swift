import Foundation

/// Mutation and read rules for `Library` (spec: My List, Continue Watching rules, New Episodes rules, Persistence).
///
/// Every function tolerates NaN, infinite and negative positions or durations: values are sanitized on write
/// (non-finite or negative → 0) and checked again on read, because a decoded library may carry anything.
public extension Library {
    static let watchedThreshold = 0.95, resumeMinimum: TimeInterval = 60
    static let maxMyList = 500, maxProgress = 200, maxWatched = 5_000

    func isInMyList(_ id: TitleID) -> Bool {
        myList.contains { $0.title == id }
    }

    /// Adding a show follows it.
    ///
    /// Removing a show un-follows it only when it was never started.
    mutating func toggleMyList(_ id: TitleID, newestVideo: Date?, now: Date) {
        if isInMyList(id) {
            myList.removeAll { $0.title == id }
            if id.kind == .show, followed[id.id]?.started == false {
                followed[id.id] = nil
            }
            return
        }
        myList.append(MyListItem(title: id, addedAt: now))
        if id.kind == .show, followed[id.id] == nil {
            followed[id.id] = FollowState(seenNewestVideo: newestVideo ?? now, started: false)
        }
    }

    mutating func recordProgress(_ p: PlayableID, show: ShowContext?, position: TimeInterval, duration: TimeInterval, now: Date) {
        progress.removeAll { entry in
            entry.playable == p || (show != nil && entry.showID == show?.showID)
        }
        progress.append(ProgressEntry(
            playable: p,
            showID: show?.showID,
            season: show?.season,
            number: show?.number,
            episodeName: show?.episodeName,
            position: Self.sanitized(position),
            duration: Self.sanitized(duration),
            updatedAt: now
        ))
        if let show { markStarted(show, now: now) }
    }

    mutating func finish(_ p: PlayableID, show: ShowContext?, next: EpisodeRef?, now: Date) {
        markWatched(p)
        guard let show else { return }
        upNext[show.showID] = next.map { UpNextEntry(ref: $0, setAt: now) }
        markStarted(show, now: now)
    }

    /// Sets the watched flag (moving an already-watched id to the end, so pruning drops the least recent first),
    /// drops any in-progress position for that playable, and clears any up-next pointing at that episode.
    ///
    /// For Continue Watching use `finish(_:show:next:now:)` when the next episode is known;
    /// for New Episodes also call `dismissNewEpisodes(showID:newestVideo:)`.
    mutating func markWatched(_ p: PlayableID) {
        switch p.kind {
        case .episode:
            watchedEpisodes.removeAll { $0 == p.id }
            watchedEpisodes.append(p.id)
            upNext = upNext.filter { $0.value.ref.episodeID != p.id }
        case .movie:
            watchedMovies.removeAll { $0 == p.id }
            watchedMovies.append(p.id)
        }
        progress.removeAll { $0.playable == p }
    }

    mutating func markUnwatched(_ p: PlayableID) {
        switch p.kind {
        case .episode: watchedEpisodes.removeAll { $0 == p.id }
        case .movie: watchedMovies.removeAll { $0 == p.id }
        }
    }

    /// Clears progress + upNext for that title; watched flags stay.
    mutating func removeFromContinueWatching(_ id: TitleID) {
        switch id.kind {
        case .movie:
            progress.removeAll { $0.playable == PlayableID(kind: .movie, id: id.id) }
        case .show:
            progress.removeAll { $0.playable.kind == .episode && $0.showID == id.id }
            upNext[id.id] = nil
        }
    }

    /// Only affects a followed show; dismissing never follows a show.
    mutating func dismissNewEpisodes(showID: Int, newestVideo: Date) {
        followed[showID]?.seenNewestVideo = newestVideo
    }

    /// Enforce caps, oldest first.
    ///
    /// My List drops the oldest `addedAt`, progress the oldest `updatedAt`, watched ids the earliest in the array;
    /// survivors keep their order. `followed` has no count cap: an entry is dropped only when the show was never
    /// started and is in neither My List, progress nor up-next (it can no longer become "new" for the user).
    mutating func prune() {
        if myList.count > Self.maxMyList {
            myList = Self.keepingNewest(myList, limit: Self.maxMyList) { $0.addedAt }
        }
        if progress.count > Self.maxProgress {
            progress = Self.keepingNewest(progress, limit: Self.maxProgress) { $0.updatedAt }
        }
        if watchedEpisodes.count > Self.maxWatched {
            watchedEpisodes.removeFirst(watchedEpisodes.count - Self.maxWatched)
        }
        if watchedMovies.count > Self.maxWatched {
            watchedMovies.removeFirst(watchedMovies.count - Self.maxWatched)
        }
        let listedShows = Set(myList.lazy.filter { $0.title.kind == .show }.map(\.title.id))
        let progressShows = Set(progress.compactMap(\.showID))
        followed = followed.filter { showID, state in
            state.started || listedShows.contains(showID) || progressShows.contains(showID) || upNext[showID] != nil
        }
    }

    func isWatched(_ p: PlayableID) -> Bool {
        switch p.kind {
        case .episode: watchedEpisodes.contains(p.id)
        case .movie: watchedMovies.contains(p.id)
        }
    }

    /// Nil when no entry or duration <= 0 (or not finite). Clamped to 0...1.
    func fraction(_ p: PlayableID) -> Double? {
        guard let entry = progress.last(where: { $0.playable == p }) else { return nil }
        return Self.fraction(position: entry.position, duration: entry.duration)
    }

    /// Only when position > 60 and fraction < 0.95.
    func resumePosition(_ p: PlayableID) -> TimeInterval? {
        guard let entry = progress.last(where: { $0.playable == p }),
              let fraction = Self.fraction(position: entry.position, duration: entry.duration),
              entry.position > Self.resumeMinimum, fraction < Self.watchedThreshold else { return nil }
        return entry.position
    }

    func shouldMarkWatched(position: TimeInterval, duration: TimeInterval) -> Bool {
        Self.shouldMarkWatched(position: position, duration: duration)
    }

    /// The watched rule (finite position, finite duration > 0, fraction >= 0.95); the one source of truth,
    /// also used by the player each tick without building a `Library`.
    static func shouldMarkWatched(position: TimeInterval, duration: TimeInterval) -> Bool {
        guard position.isFinite, let fraction = fraction(position: position, duration: duration) else { return false }
        return fraction >= watchedThreshold
    }
}

extension Library {
    /// `position / duration` clamped to 0...1; nil unless the duration is finite and > 0.
    static func fraction(position: TimeInterval, duration: TimeInterval) -> Double? {
        guard duration.isFinite, duration > 0 else { return nil }
        let position = sanitized(position)
        return min(max(position / duration, 0), 1)
    }

    static func sanitized(_ value: TimeInterval) -> TimeInterval {
        value.isFinite && value > 0 ? value : 0
    }

    /// Keeps the `limit` elements with the latest dates, in their original order.
    static func keepingNewest<Element>(_ elements: [Element], limit: Int, date: (Element) -> Date) -> [Element] {
        let kept = Set(
            elements.indices
                .sorted { date(elements[$0]) != date(elements[$1]) ? date(elements[$0]) > date(elements[$1]) : $0 > $1 }
                .prefix(limit)
        )
        return elements.indices.filter(kept.contains).map { elements[$0] }
    }

    mutating func markStarted(_ show: ShowContext, now: Date) {
        let seen = show.newestVideo ?? followed[show.showID]?.seenNewestVideo ?? now
        followed[show.showID] = FollowState(seenNewestVideo: seen, started: true)
    }
}
