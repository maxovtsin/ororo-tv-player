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
}
