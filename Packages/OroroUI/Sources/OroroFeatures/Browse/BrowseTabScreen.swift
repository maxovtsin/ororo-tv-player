import OroroCore
import OroroDesign
import SwiftUI

/// The Shows / Movies tab: Browse All button, then poster shelves (spec: Shows / Movies tabs).
///
/// Reads `AppSession` and the tab's `TabRouter` from the environment (both injected by `TabRootView`).
public struct BrowseTabScreen: View {
    private let kind: TitleKind

    @Environment(AppSession.self) private var session
    @Environment(TabRouter.self) private var router
    @Environment(\.appEnvironment) private var environment
    @Environment(\.detailZoomNamespace) private var zoomNamespace

    @State private var model: BrowseTabViewModel
    @State private var library = Library()
    @State private var position = ScrollPosition(idType: String.self)
    @FocusState private var browseAllFocused: Bool
    @Namespace private var focusScope

    public init(kind: TitleKind) {
        self.kind = kind
        _model = State(initialValue: BrowseTabViewModel(kind: kind))
    }

    private var screen: String {
        kind == .show ? "shows" : "movies"
    }

    private static let browseAllID = "browseAll"

    public var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Spacing.shelfGap) {
                ActionButton(String(localized: "browse.browseAll", defaultValue: "Browse All", bundle: .module),
                             systemImage: "square.grid.3x3") {
                    model.browseAll(router: router)
                }
                .focused($browseAllFocused)
                .padding(.horizontal, Spacing.screenEdge)
                .id(Self.browseAllID)

                if let shelves = model.shelves {
                    ForEach(shelves) { shelf in
                        row(shelf)
                            .id(shelf.id)
                    }
                } else {
                    ForEach(0..<3, id: \.self) { _ in
                        skeletonRow
                    }
                }
            }
            .padding(.vertical, Spacing.l)
        }
        .scrollPosition($position)
        .scrollClipDisabled()
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top <= 1
        } action: { _, atTop in
            router.isAtTop = atTop
        }
        #if os(tvOS)
        .focusScope(focusScope)
        #endif
        .onAppear {
            model.appear(catalog: session.catalog, version: session.catalogVersion)
            restoreVerticalPosition()
        }
        .onChange(of: session.catalogVersion) { _, version in
            // Needed because the catalog can arrive while the skeleton is showing and no appear follows.
            // Later versions rebuild on the next appearance, never under the user's focus;
            // only the skeleton is replaced as soon as the first catalog arrives.
            if model.shelves == nil { model.appear(catalog: session.catalog, version: version) }
        }
        .onChange(of: router.scrollToTopToken) { _, _ in
            scrollToTop()
        }
        .task {
            library = await environment.library.snapshot()
            for await updated in await environment.library.updates() { library = updated }
        }
    }

    private func row(_ shelf: Shelf) -> some View {
        ShelfRow(
            screen: screen, shelf: shelf.id, title: Self.title(for: shelf), count: shelf.totalCount,
            items: shelf.items.map { TileModel($0) }, shape: .poster, memory: router.focus,
            zoomNamespace: zoomNamespace, showsSeeAll: true,
            onSeeAll: { model.seeAll(shelf, router: router) },
            onSelect: { tile in
                guard let item = shelf.items.first(where: { $0.id == tile.id }) else { return }
                model.select(item, in: shelf, router: router)
            },
            menu: { tile in
                guard let item = shelf.items.first(where: { $0.id == tile.id }) else { return AnyView(EmptyView()) }
                return titleMenu(for: item, context: .plain, library: library, environment: environment, router: router)
            }
        )
        #if os(tvOS)
        .prefersDefaultFocus(router.focus.verticalAnchor(screen: screen) == shelf.id, in: focusScope)
        #endif
    }

    private var skeletonRow: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: 240, height: 24)
                .padding(.horizontal, Spacing.screenEdge)
            ScrollView(.horizontal) {
                LazyHStack(spacing: Spacing.l) {
                    ForEach(0..<8, id: \.self) { _ in
                        SkeletonTile(shape: .poster)
                    }
                }
                .padding(.vertical, Spacing.l)
            }
            .scrollDisabled(true)
            .scrollClipDisabled()
            .contentMargins(.horizontal, Spacing.screenEdge, for: .scrollContent)
        }
        .accessibilityHidden(true)
    }

    /// Back or a tab switch: bring the shelf that held focus into view.
    private func restoreVerticalPosition() {
        guard let anchor = router.focus.verticalAnchor(screen: screen) else { return }
        position.scrollTo(id: anchor, anchor: .center)
    }

    private func scrollToTop() {
        position.scrollTo(edge: .top)
        browseAllFocused = true
    }

    static func title(for shelf: Shelf) -> String {
        switch shelf.kind {
        case .popularNow:
            String(localized: "browse.shelf.popularNow", defaultValue: "Popular Now", bundle: .module)
        case .latestReleases:
            String(localized: "browse.shelf.latestReleases", defaultValue: "Latest Releases", bundle: .module)
        case .topRated:
            String(localized: "browse.shelf.topRated", defaultValue: "Top Rated", bundle: .module)
        case .recentlyUpdated:
            String(localized: "browse.shelf.recentlyUpdated", defaultValue: "Recently Updated", bundle: .module)
        case .genre(let name):
            GenreName.localized(name)
        case .continueWatching:
            String(localized: "browse.shelf.continueWatching", defaultValue: "Continue Watching", bundle: .module)
        case .newEpisodes:
            String(localized: "browse.shelf.newEpisodes", defaultValue: "New Episodes", bundle: .module)
        case .popularShows:
            String(localized: "browse.shelf.popularShows", defaultValue: "Popular Shows", bundle: .module)
        case .topRatedMovies:
            String(localized: "browse.shelf.topRatedMovies", defaultValue: "Top Rated Movies", bundle: .module)
        case .recentlyUpdatedMovies:
            String(localized: "browse.shelf.recentlyUpdatedMovies", defaultValue: "Recently Updated Movies", bundle: .module)
        case .myList:
            String(localized: "browse.shelf.myList", defaultValue: "My List", bundle: .module)
        }
    }
}

#if DEBUG
#Preview("Shows") {
    NavigationStack {
        BrowseTabScreen(kind: .show)
    }
    .environment(AppSession(environment: .preview()))
    .environment(TabRouter())
}

#Preview("Movies") {
    NavigationStack {
        BrowseTabScreen(kind: .movie)
    }
    .environment(AppSession(environment: .preview()))
    .environment(TabRouter())
}
#endif
