import OroroCore
import SwiftUI

public enum MenuContext: Sendable { case plain, continueWatching, newEpisodes }

public enum TitleMenuAction: Hashable, Sendable { case addToList, removeFromList, removeFromContinueWatching, markWatched, dismissNew, goToShow }

enum TitleMenuModel {
    static func actions(for item: ShelfItem, context: MenuContext, library: Library) -> [TitleMenuAction] {
        var result: [TitleMenuAction] = [library.isInMyList(item.title.id) ? .removeFromList : .addToList]
        let isShow = item.title.id.kind == .show
        switch context {
        case .plain:
            break
        case .continueWatching:
            result.append(.removeFromContinueWatching)
            if playable(for: item) != nil { result.append(.markWatched) }
            if isShow { result.append(.goToShow) }
        case .newEpisodes:
            result.append(.dismissNew)
            if playable(for: item) != nil { result.append(.markWatched) }
            if isShow { result.append(.goToShow) }
        }
        return result
    }

    @MainActor
    static func perform(_ action: TitleMenuAction, item: ShelfItem, environment: AppEnvironment, router: TabRouter) async {
        let id = item.title.id
        let newestVideo = item.title.newestVideo
        switch action {
        case .addToList:
            await environment.library.update { library in
                if !library.isInMyList(id) { library.toggleMyList(id, newestVideo: newestVideo, now: Date()) }
            }
        case .removeFromList:
            await environment.library.update { library in
                if library.isInMyList(id) { library.toggleMyList(id, newestVideo: newestVideo, now: Date()) }
            }
        case .removeFromContinueWatching:
            await environment.library.update { $0.removeFromContinueWatching(id) }
        case .markWatched:
            guard let playable = playable(for: item) else { return }
            let show = showContext(for: item)
            let next = await nextEpisode(after: item, environment: environment)
            // `finish`: marks watched, clears progress and sets up-next to the following episode (nil at the end).
            await environment.library.update { $0.finish(playable, show: show, next: next, now: Date()) }
        case .dismissNew:
            guard let newestVideo, id.kind == .show else { return }
            await environment.library.update { $0.dismissNewEpisodes(showID: id.id, newestVideo: newestVideo) }
        case .goToShow:
            guard id.kind == .show else { return }
            router.open(id)
        }
    }

    /// Next episode of the item's show from the cached show detail; nil for movies, the last episode, or a failed fetch.
    private static func nextEpisode(after item: ShelfItem, environment: AppEnvironment) async -> EpisodeRef? {
        guard let episode = item.episode, item.title.id.kind == .show,
              let detail = try? await environment.details.show(id: item.title.id.id),
              let next = EpisodeOrdering.next(after: episode.episodeID, in: detail.episodes) else { return nil }
        return EpisodeOrdering.ref(next)
    }

    private static func playable(for item: ShelfItem) -> PlayableID? {
        if let episode = item.episode { return PlayableID(kind: .episode, id: episode.episodeID) }
        if item.title.id.kind == .movie { return PlayableID(kind: .movie, id: item.title.id.id) }
        return nil
    }

    private static func showContext(for item: ShelfItem) -> ShowContext? {
        guard let episode = item.episode, item.title.id.kind == .show else { return nil }
        return ShowContext(showID: item.title.id.id, season: episode.season, number: episode.number,
                           episodeName: nil, newestVideo: item.title.newestVideo)
    }

    static func label(_ action: TitleMenuAction) -> (title: String, systemImage: String) {
        switch action {
        case .addToList:
            (String(localized: "titleMenu.addToList", defaultValue: "Add to My List", bundle: .module), "plus")
        case .removeFromList:
            (String(localized: "titleMenu.removeFromList", defaultValue: "Remove from My List", bundle: .module), "checkmark")
        case .removeFromContinueWatching:
            (String(localized: "titleMenu.removeFromContinueWatching",
                    defaultValue: "Remove from Continue Watching", bundle: .module), "xmark.circle")
        case .markWatched:
            (String(localized: "titleMenu.markWatched", defaultValue: "Mark as Watched", bundle: .module), "eye")
        case .dismissNew:
            (String(localized: "titleMenu.dismissNew", defaultValue: "Dismiss", bundle: .module), "bell.slash")
        case .goToShow:
            (String(localized: "titleMenu.goToShow", defaultValue: "Go to Show", bundle: .module), "tv")
        }
    }
}

@MainActor public func titleMenu(
    for item: ShelfItem, context: MenuContext, library: Library, environment: AppEnvironment, router: TabRouter
) -> AnyView {
    let actions = TitleMenuModel.actions(for: item, context: context, library: library)
    return AnyView(
        ForEach(actions, id: \.self) { action in
            let label = TitleMenuModel.label(action)
            Button {
                Task { await TitleMenuModel.perform(action, item: item, environment: environment, router: router) }
            } label: {
                Label(label.title, systemImage: label.systemImage)
            }
        }
    )
}
