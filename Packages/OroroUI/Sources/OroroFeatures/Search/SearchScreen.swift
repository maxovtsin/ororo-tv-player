import OroroCore
import OroroDesign
import SwiftUI

public struct SearchScreen: View {
    private static let screenID = "search"
    private static let topID = "search-top"

    @Environment(AppSession.self) private var session
    @Environment(TabRouter.self) private var router
    @Environment(\.appEnvironment) private var environment
    @Environment(\.detailZoomNamespace) private var zoomNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = SearchViewModel()
    @State private var library = Library()
    @Namespace private var focusScope
    #if os(tvOS)
    @Environment(\.resetFocus) private var resetFocus
    #endif

    public init() {}

    public var body: some View {
        @Bindable var model = model
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: Spacing.shelfGap) {
                    Color.clear.frame(height: 1).id(Self.topID)
                    content
                }
            }
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y <= $0.contentInsets.top + 1 } action: { _, atTop in
                router.isAtTop = atTop
            }
            .onChange(of: router.scrollToTopToken) {
                scrollToTopAndFocus(proxy)
            }
        }
        .searchable(text: $model.query, prompt: Text(String(localized: "search.prompt", defaultValue: "Shows and movies", bundle: .module)))
        .scopedFocus(focusScope)
        .task(id: model.query) { await model.queryChanged() }
        .task(id: session.catalogVersion) { model.setCatalog(session.catalog, version: session.catalogVersion)
            await model.queryChanged()
        }
        .task {
            library = await environment.library.snapshot()
            for await updated in await environment.library.updates() { library = updated }
        }
    }

    /// F1 contract: scroll to top and focus the first element. Forgetting the remembered row makes the top
    /// of the scope (the search field, else the first row) the default focus target.
    private func scrollToTopAndFocus(_ proxy: ScrollViewProxy) {
        withAnimation(Motion.resolved(Motion.standard, reduceMotion: reduceMotion)) { proxy.scrollTo(Self.topID, anchor: .top) }
        router.focus.reset(screen: Self.screenID)
        #if os(tvOS)
        resetFocus(in: focusScope)
        #endif
    }

    @ViewBuilder private var content: some View {
        if let results = model.results {
            if model.showsNoResults {
                noResults
            } else {
                row(shelf: "shows", title: String(localized: "search.shows", defaultValue: "Shows", bundle: .module),
                    items: results.shows.map { ShelfItem(title: $0) })
                row(shelf: "movies", title: String(localized: "search.movies", defaultValue: "Movies", bundle: .module),
                    items: results.movies.map { ShelfItem(title: $0) })
            }
        } else {
            ForEach(model.suggestions) { shelf in
                row(shelf: shelf.id, title: Self.suggestionTitle(shelf), items: shelf.items)
            }
        }
    }

    private var noResults: some View {
        let text = model.resultsQuery
        return Text(String(localized: "search.noResults", defaultValue: "No results for '\(text)'", bundle: .module))
            .font(Typography.headline)
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.shelfGap)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func row(shelf: String, title: String, items: [ShelfItem]) -> some View {
        if !items.isEmpty {
            let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            ShelfRow(
                screen: Self.screenID, shelf: shelf, title: title, items: items.map { TileModel($0) }, shape: .poster,
                memory: router.focus, zoomNamespace: zoomNamespace,
                onSelect: { tile in
                    guard let item = byID[tile.id] else { return }
                    router.open(item.title.id, zoomSourceID: "\(shelf)/\(tile.id)")
                },
                menu: { tile in
                    guard let item = byID[tile.id] else { return AnyView(EmptyView()) }
                    return titleMenu(for: item, context: .plain, library: library, environment: environment, router: router)
                }
            )
            .id(shelf)
            .anchorDefaultFocus(shelf == router.focus.verticalAnchor(screen: Self.screenID), in: focusScope)
        }
    }

    private static func suggestionTitle(_ shelf: Shelf) -> String {
        switch shelf.kind {
        case .popularShows: String(localized: "search.popularShows", defaultValue: "Popular Shows", bundle: .module)
        case .topRatedMovies: String(localized: "search.topRatedMovies", defaultValue: "Top Rated Movies", bundle: .module)
        default: shelf.id
        }
    }
}

private extension View {
    @ViewBuilder func scopedFocus(_ scope: Namespace.ID) -> some View {
        #if os(tvOS)
        focusScope(scope)
        #else
        self
        #endif
    }

    /// Makes this row the preferred default focus target (tvOS) so Back / tab return lands on the remembered row.
    @ViewBuilder func anchorDefaultFocus(_ isAnchor: Bool, in scope: Namespace.ID) -> some View {
        #if os(tvOS)
        prefersDefaultFocus(isAnchor, in: scope)
        #else
        self
        #endif
    }
}

#if DEBUG
#Preview("Search") {
    SearchScreen()
        .environment(AppSession(environment: .preview()))
        .environment(TabRouter())
}
#endif
