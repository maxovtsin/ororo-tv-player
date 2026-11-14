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
            // The first catalog replaces the skeleton; later versions wait for the next appearance.
            buildModelIfNeeded()
        }
        .task {
            library = await environment.library.snapshot()
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
    }

    private func grid(_ model: BrowseGridViewModel) -> some View {
        PosterGrid(
            screen: screen, items: model.tiles, memory: router.focus, zoomNamespace: zoomNamespace,
            onFocusChange: { tile in model.focusChanged(tile?.id) },
            onSelect: { tile in
                guard let title = model.results.first(where: { TileModel.tileID($0.id) == tile.id }) else { return }
                router.open(title.id, zoomSourceID: "grid/\(tile.id)")
            },
            menu: { tile in
                guard let title = model.results.first(where: { TileModel.tileID($0.id) == tile.id }) else { return AnyView(EmptyView()) }
                return titleMenu(for: ShelfItem(title: title), context: .plain, library: library, environment: environment, router: router)
            }
        )
    }

    private func emptyState(_ model: BrowseGridViewModel) -> some View {
        VStack(spacing: Spacing.m) {
            Text(verbatim: String(localized: "browse.grid.empty", defaultValue: "No titles match", bundle: .module))
                .font(Typography.title)
            ActionButton(String(localized: "browse.grid.reset", defaultValue: "Reset Filters", bundle: .module),
                         systemImage: "arrow.counterclockwise") {
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
        let entryIndex = router.path.lastIndex { route in
            if case .browse = route { true } else { false }
        }
        let screen = screen
        model.onQueryChange = { [router] query in
            // A different grid: start from the first tile, then keep the filters across Back and tab switches.
            router.focus.reset(screen: screen)
            BrowseGridViewModel.writeBack(query, into: &router.path, at: entryIndex)
        }
        self.model = model
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
