import Foundation
import Observation
import OroroCore

/// Home's content (spec: Screens → Home).
///
/// The catalog rows are rebuilt only in `appear`, so a catalog swapped in while Home is visible never reorders
/// what the user is looking at; library changes update only the personal rows and the hero buttons.
@MainActor @Observable final class HomeViewModel {
    /// Nil → skeleton shelves.
    private(set) var content: HomeContent?
    /// The latest library seen (backs the hero's My List state and the tile menus).
    private(set) var library = Library()

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private let now: @MainActor () -> Date
    /// Inputs of the current `content` when it was built from a catalog; nil while showing the snapshot.
    @ObservationIgnored private var built: (catalog: Catalog, newEpisodeInfo: [Int: NewEpisodeInfo])?
    @ObservationIgnored private var savedSnapshot: HomeContent?
    /// The last queued `appear` / `catalogArrived`.
    @ObservationIgnored private var queue: Task<Void, Never>?

    private static let personalShelves: Set<String> = ["continueWatching", "newEpisodes", "myList"]

    init(environment: AppEnvironment, now: @escaping @MainActor () -> Date = Date.init) {
        self.environment = environment
        self.now = now
    }

    /// Rebuilds only here, never while visible.
    func appear(catalog: Catalog?, newEpisodeInfo: [Int: NewEpisodeInfo]) async {
        await serialized { await self.performAppear(catalog: catalog, newEpisodeInfo: newEpisodeInfo) }
    }

    /// A catalog became available while Home is visible. It is applied at once only over skeletons
    /// (`content == nil`): nothing moves under the user's focus. Over a snapshot it waits for the next `appear`,
    /// which also refreshes the snapshot's personal rows.
    func catalogArrived(_ catalog: Catalog?, newEpisodeInfo: [Int: NewEpisodeInfo]) async {
        await serialized {
            guard self.content == nil, catalog != nil else { return }
            await self.performAppear(catalog: catalog, newEpisodeInfo: newEpisodeInfo)
        }
    }

    /// Runs `work` after every earlier `appear` / `catalogArrived`, so overlapping calls never build twice.
    private func serialized(_ work: @escaping @MainActor () async -> Void) async {
        let previous = queue
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        queue = task
        await task.value
    }

    private func performAppear(catalog: Catalog?, newEpisodeInfo: [Int: NewEpisodeInfo]) async {
        library = await environment.library.snapshot()
        guard let catalog else {
            if content == nil {
                content = await environment.catalog.homeSnapshot()
            } else {
                refreshHeroActions()
            }
            return
        }
        if let built, built.catalog == catalog, built.newEpisodeInfo == newEpisodeInfo {
            libraryChanged(library)
        } else {
            build(catalog: catalog, newEpisodeInfo: newEpisodeInfo)
        }
        if let content, content != savedSnapshot {
            savedSnapshot = content
            await environment.catalog.saveHomeSnapshot(content)
        }
    }

    /// Updates personal rows + hero actions only; catalog rows keep their order.
    func libraryChanged(_ library: Library) {
        self.library = library
        guard content != nil else { return }
        guard let built else {
            refreshHeroActions()
            return
        }
        var updated = content ?? HomeContent(hero: [], shelves: [])
        updated.hero = heroItems(updated.hero.map(\.title))
        updated.shelves = splicePersonalShelves(into: updated.shelves, catalog: built.catalog, newEpisodeInfo: built.newEpisodeInfo)
        if updated != content { content = updated }
    }

    /// A playable item (Continue Watching, started New Episodes) plays; anything else opens the detail.
    func select(_ item: ShelfItem, shelf: Shelf, router: TabRouter, launcher: PlaybackLauncher) {
        guard let playable = item.playable else {
            router.open(item.title.id, zoomSourceID: "\(shelf.id)/\(item.id)")
            return
        }
        switch playable.kind {
        case .movie: launcher.play(.movie(playable.id))
        case .episode: launcher.play(.episode(id: playable.id, showID: item.title.id.id))
        }
    }

    func heroPlay(_ item: HeroItem, launcher: PlaybackLauncher) {
        let id = item.title.id.id
        switch item.action {
        case .playMovie: launcher.play(.movie(id))
        case .playFirstEpisode: launcher.play(.show(id))
        case .playEpisode(let ref), .resumeEpisode(let ref): launcher.play(.episode(id: ref.episodeID, showID: id))
        }
    }

    func toggleList(_ title: Title) async {
        let id = title.id, newestVideo = title.newestVideo, now = now()
        await environment.library.update { $0.toggleMyList(id, newestVideo: newestVideo, now: now) }
        libraryChanged(await environment.library.snapshot())
    }

    // MARK: - Building

    private func build(catalog: Catalog, newEpisodeInfo: [Int: NewEpisodeInfo]) {
        let now = now()
        content = ShelfBuilder.home(
            catalog: catalog,
            hero: heroItems(ShelfBuilder.hero(catalog: catalog, now: now)),
            continueWatching: LibraryQueries.continueWatching(library, catalog: catalog),
            newEpisodes: LibraryQueries.newEpisodes(library, catalog: catalog, resolved: newEpisodeInfo),
            myList: LibraryQueries.myList(library, catalog: catalog),
            now: now
        )
        built = (catalog, newEpisodeInfo)
    }

    private func heroItems(_ titles: [Title]) -> [HeroItem] {
        titles.map { HeroItem(title: $0, action: LibraryQueries.heroAction(for: $0, library: library)) }
    }

    private func refreshHeroActions() {
        guard var updated = content else { return }
        updated.hero = heroItems(updated.hero.map(\.title))
        if updated != content { content = updated }
    }

    /// Replaces the personal rows in `shelves`, keeping every catalog row where it is:
    /// Continue Watching and New Episodes first, My List before the genre rows (as `ShelfBuilder.home` orders them).
    private func splicePersonalShelves(into shelves: [Shelf], catalog: Catalog, newEpisodeInfo: [Int: NewEpisodeInfo]) -> [Shelf] {
        var result = shelves.filter { !Self.personalShelves.contains($0.id) }
        let myListIndex = result.firstIndex { if case .genre = $0.kind { true } else { false } } ?? result.endIndex
        if let myList = personalShelf("myList", .myList, LibraryQueries.myList(library, catalog: catalog).map { ShelfItem(title: $0) }) {
            result.insert(myList, at: myListIndex)
        }
        let leading = [
            personalShelf("continueWatching", .continueWatching, LibraryQueries.continueWatching(library, catalog: catalog)),
            personalShelf("newEpisodes", .newEpisodes,
                          LibraryQueries.newEpisodes(library, catalog: catalog, resolved: newEpisodeInfo))
        ].compactMap(\.self)
        result.insert(contentsOf: leading, at: 0)
        return result
    }

    /// Same capping as `ShelfBuilder.home`; nil (hidden) when empty.
    private func personalShelf(_ id: String, _ kind: ShelfKind, _ items: [ShelfItem]) -> Shelf? {
        guard !items.isEmpty else { return nil }
        return Shelf(id: id, kind: kind, items: Array(items.prefix(ShelfBuilder.shelfCap)), totalCount: items.count)
    }
}

/// Where focus is on Home, published by the hero and each shelf as a focused value (focus anywhere inside them).
enum HomeFocusArea: Hashable, Sendable {
    case hero, shelf(String)

    /// The hero is expanded unless focus is in a shelf. With focus outside Home (nil: tab bar, pushed Detail,
    /// player, context menu) it keeps the state of where focus last was, so it never springs open behind a
    /// screen pushed from a shelf. `lastFocusInHero` starts true, so launch and tab bar → hero stay expanded.
    static func isExpanded(_ area: HomeFocusArea?, lastFocusInHero: Bool) -> Bool {
        guard let area else { return lastFocusInHero }
        return !isInShelf(area)
    }

    /// Menu at the root goes to the tab bar from the hero; from a shelf it scrolls to the top first.
    /// Nil falls back to where focus last was, as in `isExpanded`.
    static func isAtTop(_ area: HomeFocusArea?, lastFocusInHero: Bool) -> Bool {
        guard let area else { return lastFocusInHero }
        return !isInShelf(area)
    }

    /// Whether focus was last in the hero; leaving the screen (nil) keeps the previous value.
    static func lastFocusInHero(after area: HomeFocusArea?, previous: Bool) -> Bool {
        switch area {
        case .hero: true
        case .shelf: false
        case nil: previous
        }
    }

    /// Where focus returns on re-appear: the hero, unless focus was last in a shelf and that shelf is remembered.
    static func restoreTarget(lastFocusInHero: Bool, anchor: String?) -> HomeFocusArea {
        guard !lastFocusInHero, let anchor else { return .hero }
        return .shelf(anchor)
    }

    private static func isInShelf(_ area: HomeFocusArea?) -> Bool {
        if case .shelf = area { true } else { false }
    }
}
