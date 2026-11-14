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

    @Test func heroHeightLeavesTheFirstShelfPeeking() {
        #if os(tvOS)
        #expect(HeroView.height(screenHeight: 1080) == 1080 - HeroView.shelfPeek)
        #else
        #expect(HeroView.height(screenHeight: 800) == 440)
        #endif
    }

    @Test func showJumpsToAPageAndIgnoresOutOfRange() {
        var pager = HeroPager(count: 4)
        pager.show(2)
        #expect(pager.index == 2)
        pager.show(4)
        pager.show(-1)
        #expect(pager.index == 2)
        pager.next()
        #expect(pager.index == 3)
    }

    @Test func edgeClicksWrapAround() {
        // Right on the last page's trailing button goes to the first page; left on the first page's leading one to the last.
        #expect(HeroPager.wrapTarget(from: 3, count: 4, forward: true, onEdgeButton: true) == 0)
        #expect(HeroPager.wrapTarget(from: 0, count: 4, forward: false, onEdgeButton: true) == 3)
    }

    @Test func noWrapAwayFromTheEdges() {
        // Inside the strip the focus engine moves between pages itself.
        #expect(HeroPager.wrapTarget(from: 2, count: 4, forward: true, onEdgeButton: true) == nil)
        #expect(HeroPager.wrapTarget(from: 1, count: 4, forward: false, onEdgeButton: true) == nil)
        // On the last page's leading button, right moves to its trailing button.
        #expect(HeroPager.wrapTarget(from: 3, count: 4, forward: true, onEdgeButton: false) == nil)
        #expect(HeroPager.wrapTarget(from: 0, count: 1, forward: true, onEdgeButton: true) == nil)
        #expect(HeroPager.wrapTarget(from: 0, count: 0, forward: false, onEdgeButton: true) == nil)
    }

    @Test func playButtonTitlesFollowAction() {
        let ref = EpisodeRef(episodeID: 7, season: 2, number: 3)
        #expect(HeroView.playTitle(.playMovie) == "Play")
        #expect(HeroView.playTitle(.playFirstEpisode) == "Play") // the first episode ref is unknown here
        #expect(HeroView.playTitle(.playEpisode(ref)) == "Play S2 E3")
        #expect(HeroView.playTitle(.resumeEpisode(ref)) == "Resume S2 E3")
    }

    @Test func rebuiltPagerStartsFreshDwell() {
        var pager = HeroPager(count: 6, startTime: 100)
        #expect(!tick(&pager, at: 101))
        #expect(!tick(&pager, at: 107.9))
        #expect(tick(&pager, at: 108))
    }

    @Test func ineligibleTicksDoNotTouchDwell() {
        var pager = HeroPager(count: 6)
        #expect(!tick(&pager, at: 30, focus: false))
        #expect(tick(&pager, at: 30))
        #expect(pager.index == 1)
    }

    @Test func showMetadata() {
        let title = Title(id: TitleID(kind: .show, id: 1), name: "S", imdbRating: 8.3, year: 2024,
                          genres: ["A", "B", "C", "D"], lengthMinutes: 45, resolution: .hd, ended: false)
        #expect(HeroView.metadata(for: title, locale: Locale(identifier: "en_US")) ==
                [.badge(.imdb(8.3)), .text("2024"), .text("A"), .text("B"), .text("C"), .text("Ongoing")])
        var ended = title
        ended.ended = true
        #expect(HeroView.metadata(for: ended).last == .text("Ended"))
    }

    @Test func movieMetadata() {
        let title = Title(id: TitleID(kind: .movie, id: 1), name: "M", imdbRating: 7.0, year: 2020,
                          genres: ["Drama"], lengthMinutes: 130, resolution: .hd)
        let items = HeroView.metadata(for: title, locale: Locale(identifier: "en_US"))
        #expect(items == [.badge(.imdb(7.0)), .text("2020"), .text("Drama"), .text("2h 10m"), .badge(.hd)])
        #expect(!items.contains(.badge(.cc)))
    }
}
