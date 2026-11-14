import Observation
import OroroCore

/// Shelves for the Shows / Movies tab. Rebuilt only from `appear`, and only when the catalog version changed,
/// so a background refresh never reshuffles shelves under the user's focus.
@MainActor @Observable public final class BrowseTabViewModel {
    /// Nil until a catalog has been seen: the screen shows skeleton shelves.
    public private(set) var shelves: [Shelf]?

    private let kind: TitleKind
    @ObservationIgnored private var builtVersion: Int?

    public init(kind: TitleKind) {
        self.kind = kind
    }

    public func appear(catalog: Catalog?, version: Int) {
        guard let catalog, version != builtVersion else { return }
        builtVersion = version
        shelves = ShelfBuilder.browseTab(kind: kind, catalog: catalog)
    }

    /// Pushes the shelf's preset query; shelves without one do nothing.
    public func seeAll(_ shelf: Shelf, router: TabRouter) {
        guard let query = shelf.seeAll else { return }
        router.push(.browse(query))
    }

    public func browseAll(router: TabRouter) {
        router.push(.browse(.default(kind)))
    }

    public func select(_ item: ShelfItem, router: TabRouter) {
        select(item, in: nil, router: router)
    }

    /// Opens the detail; `shelf` makes the zoom source id `"<shelf>/<item>"`, as `ShelfRow` builds it.
    func select(_ item: ShelfItem, in shelf: Shelf?, router: TabRouter) {
        router.open(item.title.id, zoomSourceID: shelf.map { "\($0.id)/\(item.id)" })
    }
}
