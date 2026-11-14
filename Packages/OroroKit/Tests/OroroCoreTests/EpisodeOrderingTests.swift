import Foundation
import OroroCore
import OroroTestSupport
import Testing

@Suite struct EpisodeOrderingTests {
    @Test func seasonsSortedWithSpecialsLast() {
        let eps = Samples.episodes(showID: 1, seasons: [0: 2, 3: 1, 1: 2, 2: 1])
        #expect(EpisodeOrdering.seasons(eps) == [1, 2, 3, 0])
    }

    @Test func episodesSortedNumerically() {
        var eps = Samples.episodes(showID: 1, seasons: [1: 10])
        eps.reverse()
        let numbers = EpisodeOrdering.episodes(eps, season: 1).compactMap(\.number)
        #expect(numbers == Array(1...10))
        #expect(numbers[9] == 10 && numbers[8] == 9)
    }

    @Test func nilNumbersLastInOriginalOrder() {
        var eps = Samples.episodes(showID: 1, seasons: [1: 4])
        eps[0].number = nil
        eps[2].number = nil
        let ids = EpisodeOrdering.episodes(eps, season: 1).map(\.id)
        #expect(ids == [eps[1].id, eps[3].id, eps[0].id, eps[2].id])
    }

    @Test func nextWithinSeason() {
        let eps = Samples.episodes(showID: 1, seasons: [1: 3])
        #expect(EpisodeOrdering.next(after: eps[0].id, in: eps)?.id == eps[1].id)
    }

    @Test func nextCrossesToNextSeason() {
        let eps = Samples.episodes(showID: 1, seasons: [1: 2, 2: 2])
        let next = EpisodeOrdering.next(after: eps[1].id, in: eps)
        #expect(next?.season == 2 && next?.number == 1)
    }

    @Test func nextAtSeriesEndIsNil() {
        let eps = Samples.episodes(showID: 1, seasons: [1: 2])
        #expect(EpisodeOrdering.next(after: eps[1].id, in: eps) == nil)
        #expect(EpisodeOrdering.next(after: -1, in: eps) == nil)
    }

    @Test func nextNeverReturnsSpecial() {
        let eps = Samples.episodes(showID: 1, seasons: [0: 2, 1: 2])
        let last = EpisodeOrdering.ordered(eps).last!
        #expect(EpisodeOrdering.next(after: last.id, in: eps) == nil)
        let special = eps.first { $0.season == 0 }!
        #expect(EpisodeOrdering.next(after: special.id, in: eps) == nil)
        #expect(EpisodeOrdering.ordered(eps).count == 2)
        #expect(EpisodeOrdering.ordered(eps).allSatisfy { $0.season == 1 })
    }

    @Test func initialSeasonUsesResumeElseFirst() {
        let eps = Samples.episodes(showID: 1, seasons: [0: 1, 1: 2, 2: 2])
        #expect(EpisodeOrdering.initialSeason(episodes: eps, resume: nil) == 1)
        let resume = EpisodeOrdering.ref(eps.first { $0.season == 2 }!)
        #expect(EpisodeOrdering.initialSeason(episodes: eps, resume: resume) == 2)
        let stale = EpisodeRef(episodeID: 9, season: 7, number: 1)
        #expect(EpisodeOrdering.initialSeason(episodes: eps, resume: stale) == 1)
        #expect(EpisodeOrdering.initialSeason(episodes: [], resume: nil) == nil)
    }

    @Test func qualityRangeAcrossEpisodes() {
        var eps = Samples.episodes(showID: 1, seasons: [1: 3])
        eps[0].qualities = ["240p", "720p"]
        eps[1].qualities = ["480p", "1080p"]
        eps[2].qualities = ["720p"]
        let range = EpisodeOrdering.qualityRange(eps)
        #expect(range?.lowest == "240p")
        #expect(range?.highest == "1080p")
        #expect(EpisodeOrdering.qualityRange([]) == nil)
    }

    @Test func refNilWithoutNumber() {
        var eps = Samples.episodes(showID: 1, seasons: [1: 1])
        #expect(EpisodeOrdering.ref(eps[0]) == EpisodeRef(episodeID: eps[0].id, season: 1, number: 1))
        eps[0].number = nil
        #expect(EpisodeOrdering.ref(eps[0]) == nil)
    }

    @Test func unwatchedAfterLastWatched() {
        let eps = Samples.episodes(showID: 1, seasons: [1: 4])
        let result = EpisodeOrdering.unwatched(after: eps[0].id, in: eps, watched: [eps[2].id])
        #expect(result.map(\.id) == [eps[1].id, eps[3].id])
        #expect(EpisodeOrdering.unwatched(after: nil, in: eps, watched: [eps[0].id]).count == 3)
    }

    @Test func oddNumberingIsStableAndNeverLoops() {
        var eps = Samples.episodes(showID: 1, seasons: [1: 4])
        eps[1].number = eps[0].number
        eps[2].number = nil
        var seen = Set<Int>()
        var cur = EpisodeOrdering.first(in: eps)
        while let e = cur {
            #expect(seen.insert(e.id).inserted)
            cur = EpisodeOrdering.next(after: e.id, in: eps)
        }
        #expect(seen.count == 4)
        #expect(EpisodeOrdering.ordered(eps) == EpisodeOrdering.ordered(eps.reversed().reversed()))
    }

    @Test func onlySpecialsShow() {
        let eps = Samples.episodes(showID: 1, seasons: [0: 3])
        #expect(EpisodeOrdering.seasons(eps) == [0])
        #expect(EpisodeOrdering.first(in: eps) == nil)
        #expect(EpisodeOrdering.initialSeason(episodes: eps, resume: nil) == 0)
    }
}
