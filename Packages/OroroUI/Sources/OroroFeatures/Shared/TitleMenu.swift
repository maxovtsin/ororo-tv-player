import OroroCore
import SwiftUI

// STUB (T3) — implemented by Task F13. `MenuContext` and `TitleMenuAction` are final.
public enum MenuContext: Sendable { case plain, continueWatching, newEpisodes }

public enum TitleMenuAction: Hashable, Sendable { case addToList, removeFromList, removeFromContinueWatching, markWatched, dismissNew, goToShow }

@MainActor public func titleMenu(for item: ShelfItem, context: MenuContext, library: Library, environment: AppEnvironment, router: TabRouter) -> AnyView {
    AnyView(EmptyView())
}
