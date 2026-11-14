import Foundation
import OroroCore
import OroroTestSupport
import Testing

@Suite struct LibraryRulesTests {
    let showID = TitleID(kind: .show, id: 101)
    let movieID = TitleID(kind: .movie, id: 1001)
    let episode1 = PlayableID(kind: .episode, id: 1_010_101)
    let episode2 = PlayableID(kind: .episode, id: 1_010_102)
    let movie = PlayableID(kind: .movie, id: 1001)

    func context(_ number: Int, newestVideo: Date? = nil) -> ShowContext {
        ShowContext(showID: 101, season: 1, number: number, episodeName: "Episode \(number)", newestVideo: newestVideo)
    }

    @Test func toggleMyListAddsThenRemoves() {
        var lib = Library()
        lib.toggleMyList(movieID, newestVideo: nil, now: Samples.now)
        #expect(lib.isInMyList(movieID))
        #expect(lib.myList == [MyListItem(title: movieID, addedAt: Samples.now)])
        #expect(lib.followed.isEmpty)
        lib.toggleMyList(movieID, newestVideo: nil, now: Samples.now)
        #expect(!lib.isInMyList(movieID))
        #expect(lib.myList.isEmpty)
    }

    @Test func addingShowFollowsIt() {
        var lib = Library()
        let seen = Samples.now.addingTimeInterval(-Samples.day)
        lib.toggleMyList(showID, newestVideo: seen, now: Samples.now)
        #expect(lib.followed[101] == FollowState(seenNewestVideo: seen, started: false))

        var noDate = Library()
        noDate.toggleMyList(showID, newestVideo: nil, now: Samples.now)
        #expect(noDate.followed[101] == FollowState(seenNewestVideo: Samples.now, started: false))
    }

    @Test func removingUnstartedShowUnfollows() {
        var lib = Library()
        lib.toggleMyList(showID, newestVideo: Samples.now, now: Samples.now)
        lib.toggleMyList(showID, newestVideo: Samples.now, now: Samples.now)
        #expect(lib.followed[101] == nil)
    }

    @Test func removingStartedShowStaysFollowed() {
        var lib = Library()
        let seen = Samples.now.addingTimeInterval(-Samples.day)
        lib.toggleMyList(showID, newestVideo: seen, now: Samples.now)
        lib.recordProgress(episode1, show: context(1, newestVideo: seen), position: 120, duration: 2700, now: Samples.now)
        lib.toggleMyList(showID, newestVideo: seen, now: Samples.now)
        #expect(!lib.isInMyList(showID))
        #expect(lib.followed[101] == FollowState(seenNewestVideo: seen, started: true))
    }

    @Test func recordProgressFollowsShowWithExistingOrNow() {
        var lib = Library()
        let seen = Samples.now.addingTimeInterval(-Samples.day)
        lib.toggleMyList(showID, newestVideo: seen, now: Samples.now)
        lib.recordProgress(episode1, show: context(1, newestVideo: nil), position: 120, duration: 2700, now: Samples.now)
        #expect(lib.followed[101] == FollowState(seenNewestVideo: seen, started: true))

        var fresh = Library()
        fresh.recordProgress(episode1, show: context(1, newestVideo: nil), position: 120, duration: 2700, now: Samples.now)
        #expect(fresh.followed[101] == FollowState(seenNewestVideo: Samples.now, started: true))
    }

    @Test func recordProgressReplacesSamePlayableAndOtherEpisodeOfShow() {
        var lib = Library()
        lib.recordProgress(movie, show: nil, position: 100, duration: 6000, now: Samples.now)
        lib.recordProgress(episode1, show: context(1), position: 100, duration: 2700, now: Samples.now)
        lib.recordProgress(episode1, show: context(1), position: 200, duration: 2700, now: Samples.now.addingTimeInterval(10))
        #expect(lib.progress.count == 2)
        #expect(lib.progress.first { $0.playable == episode1 }?.position == 200)

        let later = Samples.now.addingTimeInterval(20)
        lib.recordProgress(episode2, show: context(2), position: 300, duration: 2700, now: later)
        #expect(lib.progress.map(\.playable) == [movie, episode2])
        #expect(lib.progress.last == ProgressEntry(
            playable: episode2, showID: 101, season: 1, number: 2, episodeName: "Episode 2",
            position: 300, duration: 2700, updatedAt: later
        ))
    }

    @Test func finishMarksWatchedSetsUpNext() {
        var lib = Library()
        lib.recordProgress(episode1, show: context(1), position: 2650, duration: 2700, now: Samples.now)
        let next = EpisodeRef(episodeID: episode2.id, season: 1, number: 2)
        let later = Samples.now.addingTimeInterval(60)
        lib.finish(episode1, show: context(1), next: next, now: later)
        #expect(lib.isWatched(episode1))
        #expect(lib.watchedEpisodes == [episode1.id])
        #expect(lib.progress.isEmpty)
        #expect(lib.upNext[101] == UpNextEntry(ref: next, setAt: later))
        #expect(LibraryQueries.resumeTarget(showID: 101, library: lib) == next)
    }

    @Test func finishLastEpisodeRemovesShowFromContinueWatching() {
        var lib = Library()
        lib.recordProgress(episode1, show: context(1), position: 2650, duration: 2700, now: Samples.now)
        lib.finish(episode1, show: context(1), next: EpisodeRef(episodeID: episode2.id, season: 1, number: 2), now: Samples.now)
        lib.recordProgress(episode2, show: context(2), position: 2650, duration: 2700, now: Samples.now)
        lib.finish(episode2, show: context(2), next: nil, now: Samples.now)
        #expect(lib.upNext[101] == nil)
        #expect(lib.progress.isEmpty)
        #expect(LibraryQueries.continueWatching(lib, catalog: Samples.catalog).isEmpty)
        #expect(lib.followed[101]?.started == true)
    }

    @Test func finishMovieLeavesContinueWatching() {
        var lib = Library()
        lib.recordProgress(movie, show: nil, position: 3000, duration: 6000, now: Samples.now)
        #expect(LibraryQueries.continueWatching(lib, catalog: Samples.catalog).map(\.title.id) == [movieID])
        lib.finish(movie, show: nil, next: nil, now: Samples.now)
        #expect(lib.watchedMovies == [1001])
        #expect(lib.isWatched(movie))
        #expect(LibraryQueries.continueWatching(lib, catalog: Samples.catalog).isEmpty)
    }

    @Test func markWatchedAndUnwatched() {
        var lib = Library()
        lib.recordProgress(movie, show: nil, position: 300, duration: 6000, now: Samples.now)
        lib.markWatched(movie)
        lib.markWatched(movie)
        lib.markWatched(episode1)
        #expect(lib.watchedMovies == [1001])
        #expect(lib.watchedEpisodes == [episode1.id])
        #expect(lib.progress.isEmpty)
        lib.markUnwatched(movie)
        #expect(!lib.isWatched(movie))
        #expect(lib.isWatched(episode1))
    }

    @Test func markWatchedUpNextEpisodeLeavesContinueWatching() {
        var lib = Library()
        lib.finish(episode1, show: context(1), next: EpisodeRef(episodeID: episode2.id, season: 1, number: 2), now: Samples.now)
        #expect(LibraryQueries.continueWatching(lib, catalog: Samples.catalog).map(\.playable) == [episode2])
        lib.markWatched(episode2)
        #expect(lib.upNext[101] == nil)
        #expect(LibraryQueries.continueWatching(lib, catalog: Samples.catalog).isEmpty)
    }

    @Test func markWatchedAgainMovesIdToEnd() {
        var lib = Library()
        lib.markWatched(movie)
        lib.markWatched(PlayableID(kind: .movie, id: 1002))
        lib.markWatched(movie)
        #expect(lib.watchedMovies == [1002, 1001])
        lib.markWatched(episode1)
        lib.markWatched(episode2)
        lib.markWatched(episode1)
        #expect(lib.watchedEpisodes == [episode2.id, episode1.id])
    }

    @Test func removeFromContinueWatchingKeepsWatchedFlags() {
        var lib = Library()
        lib.finish(episode1, show: context(1), next: EpisodeRef(episodeID: episode2.id, season: 1, number: 2), now: Samples.now)
        lib.recordProgress(episode2, show: context(2), position: 300, duration: 2700, now: Samples.now)
        lib.recordProgress(movie, show: nil, position: 300, duration: 6000, now: Samples.now)
        lib.removeFromContinueWatching(showID)
        #expect(lib.upNext[101] == nil)
        #expect(lib.progress.map(\.playable) == [movie])
        #expect(lib.isWatched(episode1))
        lib.removeFromContinueWatching(movieID)
        #expect(lib.progress.isEmpty)
    }

    @Test func resumePositionOnlyBetween60sAnd95Percent() {
        var lib = Library()
        lib.recordProgress(movie, show: nil, position: 59, duration: 6000, now: Samples.now)
        #expect(lib.resumePosition(movie) == nil)
        lib.recordProgress(movie, show: nil, position: 61, duration: 6000, now: Samples.now)
        #expect(lib.resumePosition(movie) == 61)
        lib.recordProgress(movie, show: nil, position: 5760, duration: 6000, now: Samples.now)
        #expect(lib.fraction(movie) == 0.96)
        #expect(lib.resumePosition(movie) == nil)
        #expect(lib.resumePosition(episode1) == nil)
        #expect(lib.fraction(episode1) == nil)
    }

    @Test func resumePositionExactBoundariesAreExcluded() {
        var lib = Library()
        lib.recordProgress(movie, show: nil, position: 60, duration: 6000, now: Samples.now)
        #expect(lib.resumePosition(movie) == nil)
        lib.recordProgress(movie, show: nil, position: 5700, duration: 6000, now: Samples.now)
        #expect(lib.fraction(movie) == 0.95)
        #expect(lib.resumePosition(movie) == nil)
        lib.recordProgress(movie, show: nil, position: 5699, duration: 6000, now: Samples.now)
        #expect(lib.resumePosition(movie) == 5699)
    }

    @Test func shouldMarkWatchedAtThreshold() {
        let lib = Library()
        #expect(lib.shouldMarkWatched(position: 95, duration: 100))
        #expect(!lib.shouldMarkWatched(position: 94.9, duration: 100))
        #expect(lib.shouldMarkWatched(position: 120, duration: 100))
        #expect(!lib.shouldMarkWatched(position: .nan, duration: 100))
        #expect(!lib.shouldMarkWatched(position: 50, duration: -10))
        #expect(!lib.shouldMarkWatched(position: 50, duration: .infinity))
    }

    @Test func zeroOrNaNDurationIsSafe() {
        var lib = Library(); let p = PlayableID(kind: .movie, id: 1)
        lib.recordProgress(p, show: nil, position: 500, duration: 0, now: Samples.now)
        #expect(lib.fraction(p) == nil); #expect(lib.resumePosition(p) == nil)
        #expect(!lib.shouldMarkWatched(position: 500, duration: 0))
        #expect(!lib.shouldMarkWatched(position: 500, duration: .nan))
        #expect(LibraryQueries.continueWatching(lib, catalog: Samples.catalog).first?.progress == nil)
    }

    @Test func nanAndNegativeValuesAreSanitized() {
        var lib = Library()
        lib.recordProgress(movie, show: nil, position: .nan, duration: .nan, now: Samples.now)
        #expect(lib.progress.first?.position == 0)
        #expect(lib.progress.first?.duration == 0)
        #expect(lib.fraction(movie) == nil)
        lib.recordProgress(movie, show: nil, position: -30, duration: 6000, now: Samples.now)
        #expect(lib.fraction(movie) == 0)
        #expect(lib.resumePosition(movie) == nil)
        // A decoded library may carry out-of-range values; reads still clamp.
        lib.progress = [ProgressEntry(playable: movie, position: 9000, duration: 6000, updatedAt: Samples.now)]
        #expect(lib.fraction(movie) == 1)
        lib.progress = [ProgressEntry(playable: movie, position: 100, duration: -5, updatedAt: Samples.now)]
        #expect(lib.fraction(movie) == nil)
        let item = LibraryQueries.continueWatching(lib, catalog: Samples.catalog).first
        #expect(item?.title.id == movieID)
        #expect(item?.progress == nil)
    }

    @Test func dismissClearsNewFlag() throws {
        var lib = Library()
        let old = Samples.now.addingTimeInterval(-30 * Samples.day)
        lib.toggleMyList(showID, newestVideo: old, now: Samples.now)
        let catalogNewest = try #require(Samples.catalog.title(showID)?.newestVideo)
        #expect(LibraryQueries.showsWithNewEpisodes(lib, catalog: Samples.catalog).map(\.id) == [showID])
        lib.dismissNewEpisodes(showID: 101, newestVideo: catalogNewest)
        #expect(lib.followed[101] == FollowState(seenNewestVideo: catalogNewest, started: false))
        #expect(LibraryQueries.showsWithNewEpisodes(lib, catalog: Samples.catalog).isEmpty)
        // Dismissing an unfollowed show does not follow it.
        lib.dismissNewEpisodes(showID: 102, newestVideo: catalogNewest)
        #expect(lib.followed[102] == nil)
    }

    @Test func pruneEnforcesCapsOldestFirst() {
        var lib = Library()
        let base = Samples.now
        // My List: 502 items added in shuffled time order; ids 0 and 1 are the oldest.
        lib.myList = (0..<502).reversed().map { MyListItem(title: TitleID(kind: .movie, id: $0), addedAt: base.addingTimeInterval(Double($0))) }
        lib.progress = (0..<202).reversed().map {
            ProgressEntry(playable: PlayableID(kind: .movie, id: $0), position: 100, duration: 6000, updatedAt: base.addingTimeInterval(Double($0)))
        }
        lib.watchedEpisodes = Array(0..<5_003)
        lib.watchedMovies = Array(0..<5_001)
        // Followed: 1 started (kept), 2 in My List (kept), 3 in progress (kept), 4 up-next (kept), 5 nothing (dropped).
        for id in 1...5 { lib.followed[id] = FollowState(seenNewestVideo: base, started: id == 1) }
        lib.myList.append(MyListItem(title: TitleID(kind: .show, id: 2), addedAt: base.addingTimeInterval(10_000)))
        lib.progress.append(ProgressEntry(
            playable: PlayableID(kind: .episode, id: 30_101), showID: 3, position: 1, duration: 10, updatedAt: base.addingTimeInterval(10_000)
        ))
        lib.upNext[4] = UpNextEntry(ref: EpisodeRef(episodeID: 40_101, season: 1, number: 1), setAt: base)

        lib.prune()

        #expect(lib.myList.count == Library.maxMyList)
        #expect(!lib.myList.contains { $0.title.id <= 2 && $0.title.kind == .movie })
        #expect(lib.myList.first?.title.id == 501) // original order kept
        #expect(lib.progress.count == Library.maxProgress)
        #expect(!lib.progress.contains { $0.playable.kind == .movie && $0.playable.id <= 2 })
        #expect(lib.watchedEpisodes.count == Library.maxWatched)
        #expect(lib.watchedEpisodes.first == 3)
        #expect(lib.watchedMovies.first == 1)
        #expect(lib.watchedMovies.last == 5_000)
        #expect(Set(lib.followed.keys) == [1, 2, 3, 4])
    }

    @Test func pruneLeavesSmallLibraryUnchanged() {
        var lib = Library()
        lib.toggleMyList(showID, newestVideo: Samples.now, now: Samples.now)
        lib.recordProgress(movie, show: nil, position: 100, duration: 6000, now: Samples.now)
        lib.markWatched(episode1)
        let before = lib
        lib.prune()
        #expect(lib == before)
    }
}
