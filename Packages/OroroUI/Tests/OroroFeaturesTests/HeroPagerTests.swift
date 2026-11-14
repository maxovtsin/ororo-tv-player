import Foundation
import OroroCore
import Testing
@testable import OroroFeatures

@Suite struct HeroPagerTests {
    private func tick(_ pager: inout HeroPager, at time: TimeInterval, focus: Bool = true, active: Bool = true, reduce: Bool = false) -> Bool {
        pager.tick(at: time, focusInHero: focus, sceneActive: active, reduceMotion: reduce)
    }

    @Test func advancesAfterDwellWhenIdleAndFocused() {
        var pager = HeroPager(count: 6)
        #expect(tick(&pager, at: 8))
        #expect(pager.index == 1)
        // The advance restarts the dwell.
        #expect(!tick(&pager, at: 15.9))
        #expect(tick(&pager, at: 16))
        #expect(pager.index == 2)
    }

    @Test func doesNotAdvanceBeforeDwell() {
        var pager = HeroPager(count: 6)
        #expect(!tick(&pager, at: 7.9))
        #expect(pager.index == 0)
    }

    @Test func interactionResetsDwell() {
        var pager = HeroPager(count: 6)
        pager.userInteracted(at: 5)
        #expect(!tick(&pager, at: 12.9))
        #expect(pager.index == 0)
        #expect(tick(&pager, at: 13))
        #expect(pager.index == 1)
    }

    @Test func noAdvanceWhenFocusOutsideHero() {
        var pager = HeroPager(count: 6)
        #expect(!tick(&pager, at: 30, focus: false))
        #expect(pager.index == 0)
    }

    @Test func noAdvanceWhenSceneInactive() {
        var pager = HeroPager(count: 6)
        #expect(!tick(&pager, at: 30, active: false))
        #expect(pager.index == 0)
    }

    @Test func noAdvanceWithReduceMotion() {
        var pager = HeroPager(count: 6)
        #expect(!tick(&pager, at: 30, reduce: true))
        #expect(pager.index == 0)
    }

    @Test func nextAndPreviousWrap() {
        var pager = HeroPager(count: 3)
        pager.previous()
        #expect(pager.index == 2)
        pager.next()
        #expect(pager.index == 0)
        pager.next()
        pager.next()
        #expect(pager.index == 2)
        pager.next()
        #expect(pager.index == 0)
    }

    @Test func singleItemNeverAdvances() {
        var pager = HeroPager(count: 1)
        #expect(!tick(&pager, at: 100))
        pager.next()
        pager.previous()
        #expect(pager.index == 0)
    }

    @Test func zeroItemsIsSafe() {
        var pager = HeroPager(count: 0)
        #expect(!tick(&pager, at: 100))
        pager.next()
        pager.previous()
        pager.userInteracted(at: 1)
        #expect(pager.index == 0)
    }

    @Test func playButtonTitlesFollowAction() {
        let ref = EpisodeRef(episodeID: 7, season: 2, number: 3)
        #expect(HeroView.playTitle(.playMovie) == "Play")
        #expect(HeroView.playTitle(.playFirstEpisode) == "Play S1 E1")
        #expect(HeroView.playTitle(.playEpisode(ref)) == "Play S2 E3")
        #expect(HeroView.playTitle(.resumeEpisode(ref)) == "Resume S2 E3")
    }
}
