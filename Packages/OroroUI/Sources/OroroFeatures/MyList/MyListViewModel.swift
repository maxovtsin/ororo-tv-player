import Foundation
import Observation
import OroroCore
import OroroDesign

/// State behind the My List tab: Continue Watching, New Episodes (both capped at 30) and the saved titles.
@MainActor @Observable public final class MyListViewModel {
    static let rowCap = 30

    public private(set) var continueWatching: [ShelfItem] = []
    public private(set) var newEpisodes: [ShelfItem] = []
    public private(set) var titles: [Title] = []
    /// Tiles for the three sections, built once per update.
    public private(set) var continueWatchingTiles: [TileModel] = []
    public private(set) var newEpisodeTiles: [TileModel] = []
    public private(set) var gridTiles: [TileModel] = []
    /// The library the rows were built from; menus read it.
    public private(set) var library = Library()
    /// True once a library snapshot has been applied against a loaded catalog.
    public private(set) var hasLoaded = false

    public var isEmpty: Bool { continueWatching.isEmpty && newEpisodes.isEmpty && titles.isEmpty }

    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public func update(library: Library, catalog: Catalog?, newEpisodeInfo: [Int: NewEpisodeInfo]) {
        self.library = library
        // No catalog yet means "not loaded", never "empty" (avoids an empty-state flash on cold start).
        guard let catalog else {
            hasLoaded = false
            continueWatching = []
            newEpisodes = []
            titles = []
            continueWatchingTiles = []
            newEpisodeTiles = []
            gridTiles = []
            return
        }
        hasLoaded = true
        continueWatching = Array(LibraryQueries.continueWatching(library, catalog: catalog).prefix(Self.rowCap))
        newEpisodes = Array(LibraryQueries.newEpisodes(library, catalog: catalog, resolved: newEpisodeInfo).prefix(Self.rowCap))
        titles = LibraryQueries.myList(library, catalog: catalog)
        continueWatchingTiles = continueWatching.map { TileModel($0) }
        newEpisodeTiles = newEpisodes.map { TileModel($0) }
        gridTiles = titles.map { TileModel($0) }
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
