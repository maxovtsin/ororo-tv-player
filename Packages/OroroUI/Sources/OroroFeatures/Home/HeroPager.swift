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
}
