import OroroCore
import OroroFeatures
import Testing

@Suite @MainActor struct NavigationContractsTests {
    @Test func openRecordsZoomSourceID() {
        let router = TabRouter()
        router.open(TitleID(kind: .show, id: 101), zoomSourceID: "popularShows/show-101")
        #expect(router.path == [.show(101)])
        #expect(router.zoomSourceID == "popularShows/show-101")
        router.open(TitleID(kind: .movie, id: 1001))
        #expect(router.path == [.show(101), .movie(1001)])
        #expect(router.zoomSourceID == nil)
    }

    @Test func selectTabActionRuns() {
        var selected: AppTab?
        let action = SelectTabAction { selected = $0 }
        action(.shows)
        #expect(selected == .shows)
    }
}
