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
    /// Set by Reset; the first tile takes focus when the new results land.
    @State private var focusFirstTile = false
    @State private var focusRequest = 0

    public init(query: BrowseQuery) {
        self.query = query
    }

    private var screen: String {
        "browse-\(query.kind.rawValue)"
    }

    public var body: some View {
        content
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

    /// One scroller: the header and filters scroll away with the grid and come back when focus moves up.
    @ViewBuilder private var content: some View {
        if let model {
            PosterGrid(
                screen: screen, items: model.tiles, isLoading: model.resultsVersion == 0,
                contentVersion: model.resultsVersion, focusRequest: focusRequest, scrollsToTopOnExit: true,
                memory: router.focus, zoomNamespace: zoomNamespace,
                onFocusChange: { _ in },
                onSelect: { tile in
                    guard let title = model.title(forTileID: tile.id) else { return }
                    router.open(title.id, zoomSourceID: "grid/\(tile.id)")
                },
                menu: { tile in
                    guard let title = model.title(forTileID: tile.id) else { return AnyView(EmptyView()) }
                    return titleMenu(for: ShelfItem(title: title), context: .plain, library: library, environment: environment, router: router)
                },
                header: {
                    filtersHeader(model)
                }
            )
            .onChange(of: model.resultsVersion) { _, _ in
                // After Reset the focused control is gone: land on the first tile.
                guard focusFirstTile else { return }
                focusFirstTile = false
                focusRequest += 1
            }
        } else {
            PosterGrid(screen: screen, items: [], isLoading: true, memory: router.focus,
                       onFocusChange: { _ in }, onSelect: { _ in },
                       header: { title.padding(.top, Spacing.m).padding(.horizontal, Spacing.screenEdge) })
        }
    }

    // MARK: - Parts

    private func filtersHeader(_ model: BrowseGridViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            header(model)
            FilterBar(model: model, onReset: { reset(model) })
            if !model.isFiltering && model.results.isEmpty {
                emptyState(model)
                    .transition(.opacity)
            }
        }
        .padding(.top, Spacing.m)
    }

    private var title: some View {
        Text(verbatim: query.kind == .show
             ? String(localized: "browse.grid.title.shows", defaultValue: "Shows", bundle: .module)
             : String(localized: "browse.grid.title.movies", defaultValue: "Movies", bundle: .module))
            .font(Typography.title)
            .accessibilityAddTraits(.isHeader)
    }

    private func header(_ model: BrowseGridViewModel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            title
            if !model.isFiltering {
                let count = model.results.count
                Text(verbatim: String(localized: "browse.grid.count", defaultValue: "\(count) titles", bundle: .module))
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } else {
                ProgressView()
            }
            Spacer()
        }
        .motion(Motion.quick, value: model.results.count)
        .padding(.horizontal, Spacing.screenEdge)
        .accessibilityElement(children: .combine)
    }

    private func emptyState(_ model: BrowseGridViewModel) -> some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(Typography.heroTitle)
                .foregroundStyle(Palette.textSecondary)
            Text(verbatim: String(localized: "browse.grid.empty", defaultValue: "No titles match", bundle: .module))
                .font(Typography.title)
            Text(verbatim: String(localized: "browse.grid.empty.hint",
                                  defaultValue: "Try another genre, or loosen the decade or rating.", bundle: .module))
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            ActionButton(String(localized: "browse.grid.reset", defaultValue: "Reset Filters", bundle: .module),
                         systemImage: "arrow.counterclockwise") {
                reset(model)
            }
            .padding(.top, Spacing.s)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .padding(.horizontal, Spacing.screenEdge)
    }

    private func reset(_ model: BrowseGridViewModel) {
        focusFirstTile = true
        model.reset()
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

#if DEBUG
#Preview("Browse grid") {
    NavigationStack {
        BrowseGridScreen(query: .default(.show))
    }
    .environment(AppSession(environment: .preview()))
    .environment(TabRouter())
}
#endif
