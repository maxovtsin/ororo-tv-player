import Foundation
import Observation
import OroroCore
import OroroDesign
import SwiftUI

public enum AppTab: Hashable, CaseIterable, Sendable { case home, shows, movies, myList, search, settings }

/// One per tab; owns the tab's navigation path and focus memory.
@MainActor @Observable public final class TabRouter {
    public var path: [Route] = []
    public let focus = FocusMemory()
    /// Each tab's root screen keeps this current.
    public var isAtTop = true
    /// F1 increments on Menu at a scrolled root; root screens observe it, scroll to top and focus their first element.
    public var scrollToTopToken = 0

    public init() {}

    public func push(_ route: Route) {
        path.append(route)
    }

    /// Pushes `.show` / `.movie`.
    public func open(_ id: TitleID) {
        switch id.kind {
        case .show: push(.show(id.id))
        case .movie: push(.movie(id.id))
        }
    }
}

extension EnvironmentValues {
    /// Provided by F1; no-op by default.
    @Entry public var selectTab: @MainActor (AppTab) -> Void = { _ in }
}

public struct PlayRequest: Identifiable, Hashable, Sendable {
    /// `.show` = resume, else up-next, else first.
    public enum Target: Hashable, Sendable { case movie(Int), episode(id: Int, showID: Int), show(Int) }

    public let id: UUID
    public let target: Target
    public var startOver: Bool

    public init(id: UUID = UUID(), target: Target, startOver: Bool = false) {
        self.id = id
        self.target = target
        self.startOver = startOver
    }
}

@MainActor @Observable public final class PlaybackLauncher {
    /// AppRoot presents PlayerScreen while non-nil.
    public var active: PlayRequest?
    /// Set by the player on dismissal.
    public var lastPlayed: PlayableID?

    public init() {}

    public func play(_ target: PlayRequest.Target, startOver: Bool = false) {
        active = PlayRequest(target: target, startOver: startOver)
    }
}
