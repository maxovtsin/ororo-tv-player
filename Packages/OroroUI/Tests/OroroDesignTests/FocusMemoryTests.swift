import Testing
@testable import OroroDesign

@Suite struct FocusMemoryTests {
    @Test @MainActor func remembersPerShelfAndScreen() {
        let m = FocusMemory()
        m.remember(FocusID(screen: "home", shelf: "popular", item: "show-3"))
        #expect(m.item(screen: "home", shelf: "popular") == "show-3")
        #expect(m.last(screen: "home")?.shelf == "popular")
        #expect(m.item(screen: "shows", shelf: "popular") == nil)
    }

    @Test @MainActor func lastAndItemTrackTheMostRecentFocusPerShelf() {
        let m = FocusMemory()
        m.remember(FocusID(screen: "home", shelf: "popular", item: "a"))
        m.remember(FocusID(screen: "home", shelf: "new", item: "b"))
        m.remember(FocusID(screen: "home", shelf: "popular", item: "c"))
        #expect(m.last(screen: "home") == FocusID(screen: "home", shelf: "popular", item: "c"))
        #expect(m.item(screen: "home", shelf: "popular") == "c")
        #expect(m.item(screen: "home", shelf: "new") == "b")
        #expect(m.last(screen: "shows") == nil)
    }

    @Test @MainActor func resolveFallsBackToSameIndexThenFirst() {
        let m = FocusMemory()
        let ids = ["a", "b", "c", "d"]
        _ = m.resolve(screen: "s", shelf: "x", available: ids)
        m.remember(FocusID(screen: "s", shelf: "x", item: "c"))
        #expect(m.resolve(screen: "s", shelf: "x", available: ids) == "c")
        #expect(m.resolve(screen: "s", shelf: "x", available: ["a", "b", "z", "d"]) == "z")   // c gone → index 2
        #expect(m.resolve(screen: "s", shelf: "x", available: ["a"]) == "a")                   // clamped
        #expect(m.resolve(screen: "s", shelf: "x", available: []) == nil)
    }

    @Test @MainActor func resolveWithNothingRememberedReturnsFirst() {
        let m = FocusMemory()
        #expect(m.resolve(screen: "s", shelf: "x", available: ["p", "q"]) == "p")
        #expect(m.resolve(screen: "s", shelf: "x", available: []) == nil)
    }

    @Test @MainActor func resolveWithoutKnownIndexFallsBackToFirst() {
        let m = FocusMemory()
        // Remembered before any `available` list was seen: no index is known.
        m.remember(FocusID(screen: "s", shelf: "x", item: "gone"))
        #expect(m.index(screen: "s", shelf: "x") == nil)
        #expect(m.resolve(screen: "s", shelf: "x", available: ["a", "b", "c"]) == "a")
    }

    @Test @MainActor func indexComesFromTheLastAvailableListOfThatShelf() {
        let m = FocusMemory()
        _ = m.resolve(screen: "s", shelf: "x", available: ["a", "b", "c", "d"])
        _ = m.resolve(screen: "s", shelf: "y", available: ["d", "c"])
        m.remember(FocusID(screen: "s", shelf: "x", item: "d"))
        m.remember(FocusID(screen: "s", shelf: "y", item: "d"))
        #expect(m.index(screen: "s", shelf: "x") == 3)
        #expect(m.index(screen: "s", shelf: "y") == 0)
        #expect(m.index(screen: "s", shelf: "z") == nil)
    }

    @Test @MainActor func verticalAnchorIsTheLastFocusedShelf() {
        let m = FocusMemory()
        #expect(m.verticalAnchor(screen: "home") == nil)
        m.remember(FocusID(screen: "home", shelf: "popular", item: "a"))
        m.remember(FocusID(screen: "home", shelf: "continue", item: "b"))
        #expect(m.verticalAnchor(screen: "home") == "continue")
    }

    @Test @MainActor func restorationPrefersTheStoredScrollAnchorWhileTheItemStillExists() {
        let m = FocusMemory()
        let ids = (0..<30).map { "t\($0)" }
        #expect(m.restoration(screen: "home", shelf: "s4", ids: ids) == (nil, nil))   // nothing remembered
        m.remember(FocusID(screen: "home", shelf: "s4", item: "t19"))
        #expect(m.restoration(screen: "home", shelf: "s4", ids: ids) == ("t19", "t19"))
        m.setScrollAnchor("t14", screen: "home", shelf: "s4")
        #expect(m.restoration(screen: "home", shelf: "s4", ids: ids) == ("t19", "t14"))
        // Remembered item gone → focus and scroll both go to the same-index fallback.
        var refreshed = ids
        refreshed[19] = "new"
        #expect(m.restoration(screen: "home", shelf: "s4", ids: refreshed) == ("new", "new"))
    }

    @Test @MainActor func resetForgetsOnlyThatScreen() {
        let m = FocusMemory()
        _ = m.resolve(screen: "home", shelf: "popular", available: ["a", "b"])
        m.remember(FocusID(screen: "home", shelf: "popular", item: "b"))
        m.remember(FocusID(screen: "shows", shelf: "popular", item: "x"))
        m.reset(screen: "home")
        #expect(m.last(screen: "home") == nil)
        #expect(m.item(screen: "home", shelf: "popular") == nil)
        #expect(m.index(screen: "home", shelf: "popular") == nil)
        #expect(m.verticalAnchor(screen: "home") == nil)
        #expect(m.resolve(screen: "home", shelf: "popular", available: ["a", "b"]) == "a")
        #expect(m.item(screen: "shows", shelf: "popular") == "x")
        #expect(m.last(screen: "shows")?.item == "x")
    }
}
