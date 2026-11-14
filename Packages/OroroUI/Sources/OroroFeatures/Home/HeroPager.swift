import Foundation

/// Pure state machine behind the hero's paging. Time is injected (seconds on any monotonic scale),
/// so it is deterministic to test; the view drives `tick` from a clock loop.
struct HeroPager: Equatable {
    static let dwell: TimeInterval = 8

    private(set) var index = 0
    private let count: Int
    /// Latest of: creation (time 0), last user interaction, last advance.
    private var lastChange: TimeInterval

    /// `startTime` is the current time on the caller's clock, so a rebuilt pager gets a fresh dwell.
    init(count: Int, startTime: TimeInterval = 0) {
        self.count = max(count, 0)
        self.lastChange = startTime
    }

    mutating func next() {
        guard count >= 1 else { return }
        index = (index + 1) % count
    }

    mutating func previous() {
        guard count >= 1 else { return }
        index = (index + count - 1) % count
    }

    /// Jumps to `index` (focus moved onto another page); out-of-range indices are ignored.
    mutating func show(_ index: Int) {
        guard (0..<count).contains(index) else { return }
        self.index = index
    }

    mutating func userInteracted(at time: TimeInterval) {
        lastChange = time
    }

    /// Returns true when it advanced to the next item.
    mutating func tick(at time: TimeInterval, focusInHero: Bool, sceneActive: Bool, reduceMotion: Bool) -> Bool {
        guard count > 1, focusInHero, sceneActive, !reduceMotion, time - lastChange >= Self.dwell else { return false }
        next()
        lastChange = time
        return true
    }

    /// The page an edge click wraps to: forward from the last page's trailing button to the first page,
    /// back from the first page's leading button to the last. Elsewhere the focus engine moves on its own (nil).
    static func wrapTarget(from page: Int, count: Int, forward: Bool, onEdgeButton: Bool) -> Int? {
        guard count > 1, onEdgeButton else { return nil }
        if forward { return page == count - 1 ? 0 : nil }
        return page == 0 ? count - 1 : nil
    }
}
