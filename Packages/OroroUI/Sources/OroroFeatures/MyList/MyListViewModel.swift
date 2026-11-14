import Foundation
import Observation
import OroroCore

/// State behind the My List tab: Continue Watching, New Episodes (both capped at 30) and the saved titles.
@MainActor @Observable public final class MyListViewModel {
    static let rowCap = 30

    public private(set) var continueWatching: [ShelfItem] = []
    public private(set) var newEpisodes: [ShelfItem] = []
    public private(set) var titles: [Title] = []
    /// The library the rows were built from; menus read it.
    public private(set) var library = Library()
    /// True once the first library snapshot has been applied.
    public private(set) var hasLoaded = false

    public var isEmpty: Bool { continueWatching.isEmpty && newEpisodes.isEmpty && titles.isEmpty }

    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public func update(library: Library, catalog: Catalog?, newEpisodeInfo: [Int: NewEpisodeInfo]) {
        self.library = library
        hasLoaded = true
        guard let catalog else {
            continueWatching = []
            newEpisodes = []
            titles = []
            return
        }
        continueWatching = Array(LibraryQueries.continueWatching(library, catalog: catalog).prefix(Self.rowCap))
        newEpisodes = Array(LibraryQueries.newEpisodes(library, catalog: catalog, resolved: newEpisodeInfo).prefix(Self.rowCap))
        titles = LibraryQueries.myList(library, catalog: catalog)
    }

    /// Applies the current library, then every change, until cancelled. `updates()` does not replay, so snapshot first.
    public func observe(catalog: Catalog?, newEpisodeInfo: [Int: NewEpisodeInfo]) async {
        let store = environment.library
        // Subscribe before the snapshot so a change in between is not lost.
        let updates = await store.updates()
        update(library: await store.snapshot(), catalog: catalog, newEpisodeInfo: newEpisodeInfo)
        for await library in updates {
            if Task.isCancelled { return }
            update(library: library, catalog: catalog, newEpisodeInfo: newEpisodeInfo)
        }
    }

    /// Items with a `playable` play directly; the rest open the title's detail.
    public func select(_ item: ShelfItem, router: TabRouter, launcher: PlaybackLauncher) {
        select(item, shelf: nil, router: router, launcher: launcher)
    }

    func select(_ item: ShelfItem, shelf: String?, router: TabRouter, launcher: PlaybackLauncher) {
        if let playable = item.playable {
            switch playable.kind {
            case .movie: launcher.play(.movie(playable.id))
            case .episode: launcher.play(.episode(id: playable.id, showID: item.title.id.id))
            }
        } else {
            router.open(item.title.id, zoomSourceID: shelf.map { "\($0)/\(item.id)" })
        }
    }
}
