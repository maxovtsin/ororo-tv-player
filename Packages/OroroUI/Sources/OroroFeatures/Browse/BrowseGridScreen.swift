import OroroCore
import OroroDesign
import SwiftUI

/// The filter grid pushed by "See All" and "Browse All" (spec: Shows / Movies tabs).
///
/// Reads `AppSession` and the tab's `TabRouter` from the environment (both injected by `TabRootView`).
/// The catalog snapshot is taken when the screen first appears and kept while it is visible.
public struct BrowseGridScreen: View {
    private let query: BrowseQuery

    @Environment(AppSession.self) private var session
    @Environment(TabRouter.self) private var router
    @Environment(\.appEnvironment) private var environment
    @Environment(\.detailZoomNamespace) private var zoomNamespace

    @State private var model: BrowseGridViewModel?
    @State private var library = Library()
    /// Index of this grid's entry in `router.path` and the query it was pushed with, captured at build.
    @State private var pathEntry: (index: Int?, query: BrowseQuery)?
    @State private var focusFirstTile = false
    @Namespace private var focusScope
    #if os(tvOS)
    @Environment(\.resetFocus) private var resetFocus
    #endif

    public init(query: BrowseQuery) {
        self.query = query
    }

    private var screen: String {
        "browse-\(query.kind.rawValue)"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let model {
                header(model)
                FilterBar(model: model)
                results(model)
                FooterStrip(model: model)
            } else {
                skeleton
            }
        }
        .padding(.top, Spacing.m)
        .onAppear(perform: buildModelIfNeeded)
        .onChange(of: session.catalogVersion) { _, _ in
            // Only the first catalog is used (it replaces the skeleton); the screen keeps that snapshot while it exists.
            buildModelIfNeeded()
        }
        .onDisappear(perform: writeQueryBack)
        .task {
            // Subscribe first so an update between the two calls is not lost.
            let updates = await environment.library.updates()
            library = await environment.library.snapshot()
            for await updated in updates {
                library = updated
            }
        }
    }

    // MARK: - Parts

    private func header(_ model: BrowseGridViewModel) -> some View {
        HStack(spacing: Spacing.s) {
            Text(verbatim: query.kind == .show
                 ? String(localized: "browse.grid.title.shows", defaultValue: "Shows", bundle: .module)
                 : String(localized: "browse.grid.title.movies", defaultValue: "Movies", bundle: .module))
                .font(Typography.title)
            if !model.isFiltering {
                let count = model.results.count
                Text(verbatim: String(localized: "browse.grid.count", defaultValue: "\(count) titles", bundle: .module))
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .transition(.opacity)
            }
            if model.isFiltering {
                ProgressView()
            }
            Spacer()
        }
        .motion(Motion.quick, value: model.isFiltering)
        .padding(.horizontal, Spacing.screenEdge)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func results(_ model: BrowseGridViewModel) -> some View {
        ZStack {
            if !model.isFiltering && model.results.isEmpty {
                emptyState(model)
                    .transition(.opacity)
            } else if model.resultsVersion > 0 {
                grid(model)
                    .id(model.resultsVersion)
                    .transition(.opacity)
            }
        }
        .motion(Motion.quick, value: model.resultsVersion)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(tvOS)
        .focusScope(focusScope)
        #endif
        .onChange(of: model.resultsVersion) { _, _ in
            // After Reset Filters the old focus target is gone: land on the first tile.
            guard focusFirstTile else { return }
            focusFirstTile = false
            #if os(tvOS)
            resetFocus(in: focusScope)
            #endif
        }
    }

    private func grid(_ model: BrowseGridViewModel) -> some View {
        PosterGrid(
            screen: screen, items: model.tiles, memory: router.focus, zoomNamespace: zoomNamespace,
            onFocusChange: { tile in model.focusChanged(tile?.id) },
            onSelect: { tile in
                guard let title = model.title(forTileID: tile.id) else { return }
                router.open(title.id, zoomSourceID: "grid/\(tile.id)")
            },
            menu: { tile in
                guard let title = model.title(forTileID: tile.id) else { return AnyView(EmptyView()) }
                return titleMenu(for: ShelfItem(title: title), context: .plain, library: library, environment: environment, router: router)
            }
        )
        #if os(tvOS)
        .prefersDefaultFocus(focusFirstTile, in: focusScope)
        #endif
    }

    private func emptyState(_ model: BrowseGridViewModel) -> some View {
        VStack(spacing: Spacing.m) {
            Text(verbatim: String(localized: "browse.grid.empty", defaultValue: "No titles match", bundle: .module))
                .font(Typography.title)
            ActionButton(String(localized: "browse.grid.reset", defaultValue: "Reset Filters", bundle: .module),
                         systemImage: "arrow.counterclockwise") {
                focusFirstTile = true
                model.reset()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var skeleton: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.l), count: 8), spacing: Spacing.xl) {
            ForEach(0..<16, id: \.self) { _ in
                SkeletonTile(shape: .poster)
            }
        }
        .padding(.horizontal, Spacing.screenEdge)
        .accessibilityHidden(true)
    }

    // MARK: - Model

    private func buildModelIfNeeded() {
        guard model == nil, let catalog = session.catalog else { return }
        let model = BrowseGridViewModel(query: query, catalog: catalog)
        pathEntry = (router.path.lastIndex { route in
            if case .browse = route { true } else { false }
        }, query)
        let screen = screen
        // A different grid: start from the first tile. The path entry is updated when the screen disappears,
        // because changing a pushed route's value while it is visible would re-create the screen.
        model.onQueryChange = { [router] _ in
            router.focus.reset(screen: screen)
        }
        self.model = model
    }

    /// Back, a tab switch or a detail push: keep the filters in the router's path entry.
    private func writeQueryBack() {
        guard let model, let pathEntry, model.query != pathEntry.query else { return }
        if BrowseGridViewModel.writeBack(model.query, replacing: pathEntry.query, into: &router.path, at: pathEntry.index) {
            self.pathEntry = (pathEntry.index, model.query)
        }
    }
}

/// The focused title's "name · IMDb x · year · status", crossfading as focus moves.
private struct FooterStrip: View {
    let model: BrowseGridViewModel

    var body: some View {
        Text(verbatim: model.footerText ?? " ")
            .font(Typography.body)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
            .id(model.footerText)
            .transition(.opacity)
            .motion(Motion.quick, value: model.footerText)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .padding(.horizontal, Spacing.screenEdge)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Browse grid") {
    NavigationStack {
        BrowseGridScreen(query: .default(.show))
    }
    .environment(AppSession(environment: .preview()))
    .environment(TabRouter())
}
#endif
