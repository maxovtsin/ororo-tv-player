import Foundation
import Observation
import OroroCore

// STUB (T3) — implemented by Task F9.
@MainActor @Observable public final class PlaybackSession {
    public enum Phase: Equatable {
        case preparing, askResume(position: TimeInterval), playing, countdown(next: EpisodeRef, secondsLeft: Int),
             stillWatching, failed(Failure), finished
    }

    public enum Failure: Equatable { case fetch, notPlayable, stream }

    public private(set) var phase: Phase = .preparing
    public private(set) var current: PlayableID?
    public private(set) var nextEpisode: Episode?
    public private(set) var showsNextEpisodeAction = false

    public init(request: PlayRequest, environment: AppEnvironment, session: AppSession, engine: any PlayerEngine,
                clock: any Clock<Duration> = ContinuousClock(), now: @escaping () -> Date = Date.init) {}

    public func start() async {}

    public func chooseResume(_ resume: Bool) async {}

    public func playNextNow() async {}

    public func cancelCountdown() {}

    public func confirmStillWatching(_ yes: Bool) async {}

    public func retry() async {}

    /// Records + flushes; returns what the caller stores in `launcher.lastPlayed`.
    @discardableResult
    public func willDismiss() async -> PlayableID? {
        nil
    }

    public func sceneBecameActive() async {}
}
