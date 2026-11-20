import Foundation

/// An animation's own time, paced by the frames a `TimelineView` draws (the CRT power-on and hand-off).
///
/// It starts at the first steady frame (two ticks less than `steadyGap` apart): startup, building a screen and a
/// shader's first compile can hold the main thread after the first tick, and starting earlier would play the
/// start off screen. Each frame advances it by at most `maxStep`, so a stall slows the animation down instead of
/// skipping part of it. Not observed: advancing it from a view body changes nothing on screen.
@MainActor final class FrameClock {
    static let steadyGap: Duration = .milliseconds(50)
    /// Starts anyway if frames never become steady.
    static let latestStart: Duration = .seconds(1)
    /// The most one frame may advance the animation (about two frames at 60 Hz).
    static let maxStep: Duration = .milliseconds(34)

    private var time: Duration?
    private var firstTick: ContinuousClock.Instant?
    private var lastTick: ContinuousClock.Instant?
    private struct Waiter {
        let id: UUID
        let point: Duration
        let continuation: CheckedContinuation<Void, Never>
    }

    private var waiters: [Waiter] = []

    /// Seconds played so far; 0 until frames are steady. Call once per drawn frame.
    func elapsed() -> TimeInterval {
        let now = ContinuousClock.now
        defer { lastTick = now }
        if let time, let lastTick {
            advance(to: time + min(now - lastTick, Self.maxStep))
        } else {
            let first = firstTick ?? now
            firstTick = first
            if let lastTick, now - lastTick < Self.steadyGap || now - first >= Self.latestStart {
                advance(to: .zero)
            }
        }
        return time.map(Self.seconds) ?? 0
    }

    /// Returns once the animation has played up to `point` (or the task is cancelled).
    func reached(_ point: Duration) async {
        if let time, time >= point { return }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume() } else { waiters.append(Waiter(id: id, point: point, continuation: continuation)) }
            }
        } onCancel: {
            Task { @MainActor in self.release(id) }
        }
    }

    private func advance(to newTime: Duration) {
        time = newTime
        let due = waiters.filter { $0.point <= newTime }
        waiters.removeAll { $0.point <= newTime }
        due.forEach { $0.continuation.resume() }
    }

    private func release(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume()
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
