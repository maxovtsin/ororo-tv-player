import Foundation
import OroroCore
import OroroTestSupport
import Testing
@testable import OroroStore

@Suite struct NewEpisodeResolverTests {
    /// Sample catalog shows are 101...148; tests refer to them by index 1...48.
    private func sid(_ index: Int) -> Int { 100 + index }

    /// Sample episode id scheme: showID * 10_000 + season * 100 + number.
    private func id(_ index: Int, _ season: Int, _ number: Int) -> Int { sid(index) * 10_000 + season * 100 + number }

    private func shows(_ ids: ClosedRange<Int>) -> [Title] { ids.map { Samples.show(sid($0)) } }

    private func library(watched: [Int] = [], progress: [ProgressEntry] = []) -> Library {
        Library(progress: progress, watchedEpisodes: watched)
    }

    private func detail(_ index: Int, seasons: [Int: Int]) -> ShowDetail {
        ShowDetail(title: Samples.show(sid(index)), seasonCount: seasons.count,
                   episodes: Samples.episodes(showID: sid(index), seasons: seasons))
    }

    @Test func resolvesFirstUnwatchedAndCount() async {
        let details = FakeDetails()
        let show = detail(1, seasons: [1: 5])
        await details.configure { $0.showResults[sid(1)] = .success(show) }
        let resolver = NewEpisodeResolver(details: details)
        let result = await resolver.resolve(shows: shows(1...1), library: library(watched: [id(1, 1, 1), id(1, 1, 2), id(1, 1, 3)]))
        #expect(result == [sid(1): NewEpisodeInfo(first: EpisodeRef(episodeID: id(1, 1, 4), season: 1, number: 4), count: 2)])
    }

    @Test func progressCountsAsWatchedAndCrossesSeasons() async {
        let entry = ProgressEntry(playable: PlayableID(kind: .episode, id: id(1, 1, 5)), showID: sid(1), season: 1, number: 5,
                                  position: 100, duration: 1_000, updatedAt: Samples.now)
        let resolver = NewEpisodeResolver(details: FakeDetails())
        let result = await resolver.resolve(shows: shows(1...1), library: library(progress: [entry]))
        #expect(result[sid(1)] == NewEpisodeInfo(first: EpisodeRef(episodeID: id(1, 2, 1), season: 2, number: 1), count: 5))
    }

    @Test func specialsAndUnnumberedEpisodesAreIgnored() async {
        var episodes = Samples.episodes(showID: sid(1), seasons: [0: 2, 1: 2])
        episodes.append(Episode(id: 99_999, showID: sid(1), season: 1, number: nil))
        let show = ShowDetail(title: Samples.show(sid(1)), seasonCount: 1, episodes: episodes)
        let details = FakeDetails()
        await details.configure { $0.showResults[sid(1)] = .success(show) }
        let resolver = NewEpisodeResolver(details: details)
        let result = await resolver.resolve(shows: shows(1...1), library: library(watched: [id(1, 1, 1)]))
        #expect(result[sid(1)] == NewEpisodeInfo(first: EpisodeRef(episodeID: id(1, 1, 2), season: 1, number: 2), count: 1))
    }

    @Test func caughtUpShowHasNoEntry() async {
        let resolver = NewEpisodeResolver(details: FakeDetails())
        let result = await resolver.resolve(shows: shows(1...1), library: library(watched: [id(1, 2, 5)]))
        #expect(result.isEmpty)
    }

    @Test func neverStartedShowHasNoEntry() async {
        let resolver = NewEpisodeResolver(details: FakeDetails())
        let result = await resolver.resolve(shows: shows(1...1), library: library(watched: [id(2, 1, 1)]))
        #expect(result.isEmpty)
    }

    @Test func stopsAtMaxPerRun() async {
        let details = FakeDetails()
        let resolver = NewEpisodeResolver(details: details)
        let all = shows(1...12)
        let watched = all.map { id($0.id.id - 100, 1, 1) }
        let result = await resolver.resolve(shows: all, library: library(watched: watched))
        #expect(await details.showCalls == 10)
        #expect(await details.requestedShowIDs == Array(1...10).map(sid))
        #expect(Set(result.keys) == Set((1...10).map(sid)))
    }

    @Test func fetchesSequentially() async {
        let details = FakeDetails()
        await details.configure { $0.delay = .milliseconds(5) }
        let resolver = NewEpisodeResolver(details: details)
        let all = shows(1...4)
        _ = await resolver.resolve(shows: all, library: library(watched: all.map { id($0.id.id - 100, 1, 1) }))
        #expect(await details.showCalls == 4)
        #expect(await details.maxConcurrentCalls == 1)
    }

    @Test func failedFetchSkipsThatShow() async {
        let details = FakeDetails()
        await details.configure { $0.showResults[sid(1)] = .failure(.offline) }
        let resolver = NewEpisodeResolver(details: details)
        let result = await resolver.resolve(shows: shows(1...2), library: library(watched: [id(1, 1, 1), id(2, 1, 1)]))
        #expect(Set(result.keys) == [sid(2)])
    }

    @Test func cachedReturnsLastResults() async {
        let resolver = NewEpisodeResolver(details: FakeDetails())
        #expect(await resolver.cached().isEmpty)
        let result = await resolver.resolve(shows: shows(1...2), library: library(watched: [id(1, 1, 1), id(2, 2, 4)]))
        #expect(await resolver.cached() == result)
        #expect(result[sid(1)]?.count == 9)
        #expect(result[sid(2)]?.count == 1)
    }

    @Test func staleEntriesAreDropped() async {
        let resolver = NewEpisodeResolver(details: FakeDetails())
        let lib = library(watched: [id(1, 1, 1), id(2, 1, 1)])
        _ = await resolver.resolve(shows: shows(1...2), library: lib)
        let result = await resolver.resolve(shows: shows(2...2), library: lib)
        #expect(Set(result.keys) == [sid(2)])
        #expect(Set(await resolver.cached().keys) == [sid(2)])
    }

    @Test func keptEntryIsRecomputedAfterUserWatchesMore() async {
        let details = FakeDetails()
        let resolver = NewEpisodeResolver(details: details, maxPerRun: 1)
        let all = shows(1...2)
        _ = await resolver.resolve(shows: all, library: library(watched: [id(1, 1, 1)]))
        // Reversed order puts show 1 over the cap, so its refs are kept; the user has since watched its old first (E2).
        let second = await resolver.resolve(shows: all.reversed(), library: library(watched: [id(1, 1, 1), id(1, 1, 2)]))
        #expect(second[sid(1)] == NewEpisodeInfo(first: EpisodeRef(episodeID: id(1, 1, 3), season: 1, number: 3), count: 8))
        let third = await resolver.resolve(shows: all.reversed(), library: library(watched: [id(1, 2, 5)]))
        #expect(third[sid(1)] == nil)
    }

    @Test func freshFetchWithNothingUnwatchedRemovesOldEntry() async {
        let resolver = NewEpisodeResolver(details: FakeDetails())
        let all = shows(1...1)
        let first = await resolver.resolve(shows: all, library: library(watched: [id(1, 1, 1)]))
        #expect(first[sid(1)] != nil)
        let second = await resolver.resolve(shows: all, library: library(watched: [id(1, 2, 5)]))
        #expect(second.isEmpty)
        #expect(await resolver.cached().isEmpty)
    }

    @Test func supersededResolveDoesNotOverwrite() async {
        let details = FakeDetails()
        await details.configure { $0.delay = .milliseconds(30) }
        let resolver = NewEpisodeResolver(details: details)
        let lib = library(watched: [id(1, 1, 1), id(2, 1, 1), id(3, 1, 1)])
        let slow = Task { await resolver.resolve(shows: shows(1...2), library: lib) }
        try? await Task.sleep(for: .milliseconds(10))
        let fast = await resolver.resolve(shows: shows(3...3), library: lib)
        _ = await slow.value
        #expect(Set(fast.keys) == [sid(3)])
        #expect(Set(await resolver.cached().keys) == [sid(3)])
    }

    @Test func cancelledResolveDoesNotCommit() async {
        let details = FakeDetails()
        await details.configure { $0.delay = .milliseconds(30) }
        let resolver = NewEpisodeResolver(details: details)
        let all = shows(1...3)
        let lib = library(watched: all.map { id($0.id.id - 100, 1, 1) })
        let task = Task { await resolver.resolve(shows: all, library: lib) }
        try? await Task.sleep(for: .milliseconds(10))
        task.cancel()
        let result = await task.value
        #expect(result.isEmpty)
        #expect(await resolver.cached().isEmpty)
        #expect(await details.showCalls < 3)
    }

    @Test func runsRotateAcrossMoreThanMaxShows() async {
        let details = FakeDetails()
        let resolver = NewEpisodeResolver(details: details, maxPerRun: 10)
        let all = shows(1...25)
        let lib = library(watched: all.map { id($0.id.id - 100, 1, 1) })
        _ = await resolver.resolve(shows: all, library: lib)
        _ = await resolver.resolve(shows: all, library: lib)
        let third = await resolver.resolve(shows: all, library: lib)
        let requested = await details.requestedShowIDs
        #expect(requested.count == 30)
        // Runs 1–2 fetch the uncached shows 1–20, run 3 the uncached 21–25 then the oldest-refreshed 1–5.
        #expect(Array(requested.prefix(20)) == (1...20).map(sid))
        #expect(Array(requested.suffix(10)) == ((21...25).map(sid) + (1...5).map(sid)))
        #expect(Set(third.keys) == Set(all.map(\.id.id)))
    }

    @Test func uncachedShowsAreFetchedFirst() async {
        let details = FakeDetails()
        let resolver = NewEpisodeResolver(details: details, maxPerRun: 2)
        let lib = library(watched: (1...4).map { id($0, 1, 1) })
        _ = await resolver.resolve(shows: shows(1...2), library: lib)
        // Shows 1 and 2 are cached and listed first; the new shows 3 and 4 still go first.
        _ = await resolver.resolve(shows: shows(1...4), library: lib)
        #expect(Array(await details.requestedShowIDs.suffix(2)) == [sid(3), sid(4)])
    }

    @Test func orderedRefsFollowEpisodeOrdering() async {
        // Episodes listed out of order: the resolver's play order is EpisodeOrdering's.
        let episodes = Samples.episodes(showID: sid(1), seasons: [1: 3, 2: 2]).reversed()
        let show = ShowDetail(title: Samples.show(sid(1)), seasonCount: 2, episodes: Array(episodes))
        let details = FakeDetails()
        await details.configure { $0.showResults[sid(1)] = .success(show) }
        let resolver = NewEpisodeResolver(details: details)
        let result = await resolver.resolve(shows: shows(1...1), library: library(watched: [id(1, 1, 3)]))
        let next = EpisodeOrdering.next(after: id(1, 1, 3), in: Array(episodes))
        #expect(result[sid(1)]?.first.episodeID == next?.id)
        #expect(result[sid(1)]?.count == 2)
    }
}
