import SwiftUI

/// Remembers where focus was, per screen and per shelf, so that a pop, tab switch or player dismissal
/// lands back on the same tile (spec: Navigation → Focus memory).
///
/// Storage is deliberately not observation-tracked: `ShelfRow` / `PosterGrid` read the memory in their
/// initialisers, which run inside the parent screen's `body`. Tracked reads would invalidate the whole
/// screen on every focus move.
@MainActor @Observable public final class FocusMemory {
    private struct ShelfKey: Hashable {
        let screen: String
        let shelf: String
    }

    private struct Entry {
        var item: String
        var index: Int?
    }

    @ObservationIgnored private var lastFocus: [String: FocusID] = [:]
    @ObservationIgnored private var entries: [ShelfKey: Entry] = [:]
    /// The most recent id list each shelf passed to `resolve`; `remember` takes the index from it.
    @ObservationIgnored private var available: [ShelfKey: [String]] = [:]
    /// Leading visible item per shelf (horizontal scroll position), kept by `ShelfRow` / `PosterGrid`.
    @ObservationIgnored private var scrollAnchors: [ShelfKey: String] = [:]

    public init() {}

    public func remember(_ id: FocusID) {
        let key = ShelfKey(screen: id.screen, shelf: id.shelf)
        lastFocus[id.screen] = id
        entries[key] = Entry(item: id.item, index: available[key]?.firstIndex(of: id.item))
    }

    public func last(screen: String) -> FocusID? {
        lastFocus[screen]
    }

    public func item(screen: String, shelf: String) -> String? {
        entries[ShelfKey(screen: screen, shelf: shelf)]?.item
    }

    /// Index of the remembered item when stored.
    public func index(screen: String, shelf: String) -> Int? {
        entries[ShelfKey(screen: screen, shelf: shelf)]?.index
    }

    /// Remembered id if present; else same index clamped; else first; nil if empty.
    public func resolve(screen: String, shelf: String, available ids: [String]) -> String? {
        let key = ShelfKey(screen: screen, shelf: shelf)
        available[key] = ids
        guard let first = ids.first else { return nil }
        guard let entry = entries[key] else { return first }
        if ids.contains(entry.item) { return entry.item }
        if let index = entry.index { return ids[min(index, ids.count - 1)] }
        return first
    }

    /// Shelf id to restore vertical scroll to.
    public func verticalAnchor(screen: String) -> String? {
        lastFocus[screen]?.shelf
    }

    public func reset(screen: String) {
        lastFocus[screen] = nil
        entries = entries.filter { $0.key.screen != screen }
        available = available.filter { $0.key.screen != screen }
        scrollAnchors = scrollAnchors.filter { $0.key.screen != screen }
    }

    // MARK: Scroll anchors (internal, used by ShelfRow / PosterGrid)

    func setScrollAnchor(_ item: String?, screen: String, shelf: String) {
        scrollAnchors[ShelfKey(screen: screen, shelf: shelf)] = item
    }

    /// Where a shelf starts when its view is (re)created. Nothing remembered → (nil, nil): no focus preference,
    /// scrolled to the start. Otherwise focus goes to `resolve(…)`, and the scroll position goes to the stored
    /// leading item when the remembered item is still there (so the shelf looks as it did), else to the focus
    /// target. Always records `ids` for `remember`'s index.
    func restoration(screen: String, shelf: String, ids: [String]) -> (focus: String?, scroll: String?) {
        let resolved = resolve(screen: screen, shelf: shelf, available: ids)
        guard let remembered = item(screen: screen, shelf: shelf) else { return (nil, nil) }
        let key = ShelfKey(screen: screen, shelf: shelf)
        if remembered == resolved, let anchor = scrollAnchors[key], ids.contains(anchor) {
            return (resolved, anchor)
        }
        return (resolved, resolved)
    }
}
