import OroroCore
import OroroDesign
import SwiftUI

/// Home (spec: Screens → Home): the hero, then a vertical lazy stack of landscape shelves.
public struct HomeScreen: View {
    @Environment(\.appEnvironment) private var environment

    public init() {}

    public var body: some View {
        HomeContentView(environment: environment)
    }
}

extension FocusedValues {
    /// Set by the hero and each Home shelf; present while focus is anywhere inside them.
    @Entry var homeFocusArea: HomeFocusArea?
}

private struct HomeContentView: View {
    static let screen = "home"
    private static let heroID = "hero"
    private static let skeletonRows = 3, skeletonTiles = 6

    let environment: AppEnvironment

    @Environment(TabRouter.self) private var router
    @Environment(PlaybackLauncher.self) private var launcher
    @Environment(AppSession.self) private var session
    @Environment(\.detailZoomNamespace) private var zoomNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(tvOS)
    @Environment(\.resetFocus) private var resetFocus
    #endif

    @State private var model: HomeViewModel
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    /// Where focus is, read from the focused values the hero and the shelves publish.
    @FocusedValue(\.homeFocusArea) private var focusArea
    /// Whether focus was last in the hero (true) or in a shelf (false); decides where focus returns on re-appear.
    @State private var lastFocusInHero = true
    @State private var hasAppeared = false
    /// Becomes true once the first rows have appeared; rows created later (lazily, while scrolling) don't stagger.
    @State private var hasStaggered = false
    @Namespace private var focusNamespace

    init(environment: AppEnvironment) {
        self.environment = environment
        _model = State(initialValue: HomeViewModel(environment: environment))
    }

    private var isExpanded: Bool {
        HomeFocusArea.isExpanded(focusArea, lastFocusInHero: lastFocusInHero)
    }

    private var restoreTarget: HomeFocusArea {
        HomeFocusArea.restoreTarget(lastFocusInHero: lastFocusInHero, anchor: anchor)
    }

    var body: some View {
        GeometryReader { proxy in
            scrollContent(layout: Self.heroLayout(proxy))
        }
        .task { await run() }
        .onAppear(perform: reappear)
        .onChange(of: focusArea) { _, area in focusAreaChanged(area) }
        .onChange(of: router.scrollToTopToken) { scrollToTop() }
        .onChange(of: session.catalogVersion) {
            // Applied at once only over skeletons; over a snapshot (or built content) it waits for the next appear.
            // The model serializes this with `appear`, so the two never build twice.
            Task { await model.catalogArrived(session.catalog, newEpisodeInfo: session.newEpisodeInfo) }
        }
    }

    /// tvOS: the scroll view runs edge to edge (behind the tab bar) so the hero backdrop is full-bleed; the
    /// shelves get the horizontal safe area back as padding. iOS keeps the safe area.
    private static func heroLayout(_ proxy: GeometryProxy) -> HeroLayout {
        let insets = proxy.safeAreaInsets
        #if os(tvOS)
        return HeroLayout(screenHeight: proxy.size.height + insets.top + insets.bottom, insets: insets)
        #else
        return HeroLayout(screenHeight: proxy.size.height)
        #endif
    }

    private func scrollContent(layout: HeroLayout) -> some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Spacing.shelfGap) {
                if let content = model.content {
                    if content.hero.isEmpty { topInset(layout) } else { hero(content.hero, layout: layout) }
                    ForEach(Array(content.shelves.enumerated()), id: \.element.id) { index, shelf in
                        row(shelf)
                            .padding(.leading, layout.insets.leading)
                            .padding(.trailing, layout.insets.trailing)
                            .focusedValue(\.homeFocusArea, .shelf(shelf.id))
                            .homeDefaultFocus(restoreTarget == .shelf(shelf.id), in: focusNamespace)
                            .modifier(InitialStagger(index: index, enabled: !hasStaggered) { hasStaggered = true })
                            .id(shelf.id)
                    }
                } else {
                    topInset(layout)
                    ForEach(0..<Self.skeletonRows, id: \.self) { index in
                        SkeletonShelf(tiles: Self.skeletonTiles)
                            .padding(.leading, layout.insets.leading)
                            .padding(.trailing, layout.insets.trailing)
                            .staggeredAppearance(index: index)
                    }
                }
            }
            .padding(.bottom, Spacing.xl)
            .scrollTargetLayout()
            .motion(Motion.standard, value: isExpanded)
        }
        .scrollClipDisabled()
        .scrollPosition($scrollPosition)
        .homeFocusScope(focusNamespace)
        #if os(tvOS)
        .ignoresSafeArea(.container, edges: [.top, .horizontal])
        #endif
    }

    private var anchor: String? {
        router.focus.verticalAnchor(screen: Self.screen)
    }

    // MARK: - Pieces

    /// Without a hero nothing may sit under the tab bar: the top safe area the scroll view ignores comes back.
    private func topInset(_ layout: HeroLayout) -> some View {
        Color.clear.frame(height: max(layout.insets.top - Spacing.shelfGap, 0))
    }

    private func hero(_ items: [HeroItem], layout: HeroLayout) -> some View {
        HeroView(
            items: items,
            isExpanded: isExpanded,
            layout: layout,
            isInList: { [model] title in model.library.isInMyList(title.id) },
            onPlay: { [model, launcher] item in model.heroPlay(item, launcher: launcher) },
            onToggleList: { [model] title in Task { await model.toggleList(title) } }
        )
        .focusedValue(\.homeFocusArea, .hero)
        .homeDefaultFocus(restoreTarget == .hero, in: focusNamespace)
        .id(Self.heroID)
    }

    private func row(_ shelf: Shelf) -> some View {
        let context = Self.menuContext(shelf.kind)
        return ShelfRow(
            screen: Self.screen,
            shelf: shelf.id,
            title: Self.title(of: shelf),
            items: shelf.items.map { TileModel($0) },
            shape: .landscape,
            memory: router.focus,
            zoomNamespace: zoomNamespace,
            showsSeeAll: shelf.seeAll != nil,
            onSeeAll: shelf.seeAll.map { query in { [router] in router.push(.browse(query)) } },
            onSelect: { [model, router, launcher] tile in
                guard let item = shelf.items.first(where: { $0.id == tile.id }) else { return }
                model.select(item, shelf: shelf, router: router, launcher: launcher)
            },
            menu: { [model, router, environment] tile in
                guard let item = shelf.items.first(where: { $0.id == tile.id }) else { return AnyView(EmptyView()) }
                return titleMenu(for: item, context: context, library: model.library, environment: environment, router: router)
            }
        )
    }

    // MARK: - Lifecycle and focus

    /// Subscribes to library changes first (the stream does not replay), then builds, then follows the library.
    private func run() async {
        let updates = await environment.library.updates()
        await model.appear(catalog: session.catalog, newEpisodeInfo: session.newEpisodeInfo)
        for await library in updates {
            model.libraryChanged(library, catalog: session.catalog, newEpisodeInfo: session.newEpisodeInfo)
        }
    }

    /// After a pop, tab switch or player dismissal, steer focus back to the hero or the remembered shelf
    /// (several shelves offer a default focus target, so without this the topmost could win).
    private func reappear() {
        defer { hasAppeared = true }
        guard hasAppeared else { return }
        #if os(tvOS)
        resetFocus(in: focusNamespace)
        #endif
    }

    private func focusAreaChanged(_ area: HomeFocusArea?) {
        lastFocusInHero = HomeFocusArea.lastFocusInHero(after: area, previous: lastFocusInHero)
        router.isAtTop = HomeFocusArea.isAtTop(area, lastFocusInHero: lastFocusInHero)
    }

    /// Menu at a scrolled root: scroll to top and focus the hero (the default-focus target once
    /// `lastFocusInHero` is set; with no hero, the first shelf takes focus as the topmost).
    private func scrollToTop() {
        lastFocusInHero = true
        withAnimation(Motion.resolved(Motion.standard, reduceMotion: reduceMotion)) {
            scrollPosition.scrollTo(edge: .top)
        }
        #if os(tvOS)
        resetFocus(in: focusNamespace)
        #endif
        router.isAtTop = true
    }

    // MARK: - Mapping

    static func menuContext(_ kind: ShelfKind) -> MenuContext {
        switch kind {
        case .continueWatching: .continueWatching
        case .newEpisodes: .newEpisodes
        default: .plain
        }
    }

    static func title(of shelf: Shelf) -> String {
        switch shelf.kind {
        case .continueWatching:
            String(localized: "home.shelf.continueWatching", defaultValue: "Continue Watching", bundle: .module)
        case .newEpisodes:
            String(localized: "home.shelf.newEpisodes", defaultValue: "New Episodes", bundle: .module)
        case .popularShows:
            String(localized: "home.shelf.popularShows", defaultValue: "Popular Shows", bundle: .module)
        case .latestReleases:
            String(localized: "home.shelf.latestReleases", defaultValue: "Latest Releases", bundle: .module)
        case .topRatedMovies:
            String(localized: "home.shelf.topRatedMovies", defaultValue: "Top Rated Movies", bundle: .module)
        case .recentlyUpdatedMovies:
            String(localized: "home.shelf.recentlyUpdatedMovies", defaultValue: "Recently Updated Movies", bundle: .module)
        case .myList:
            String(localized: "home.shelf.myList", defaultValue: "My List", bundle: .module)
        case .popularNow:
            String(localized: "home.shelf.popularNow", defaultValue: "Popular Now", bundle: .module)
        case .topRated:
            String(localized: "home.shelf.topRated", defaultValue: "Top Rated", bundle: .module)
        case .recentlyUpdated:
            String(localized: "home.shelf.recentlyUpdated", defaultValue: "Recently Updated", bundle: .module)
        case .genre(let genre):
            // Home genre rows are single-kind; the row's kind is its See All query's kind.
            if shelf.seeAll?.kind == .movie {
                String(localized: "home.shelf.genreMovies", defaultValue: "\(GenreName.localized(genre)) Movies", bundle: .module)
            } else {
                String(localized: "home.shelf.genreShows", defaultValue: "\(GenreName.localized(genre)) Shows", bundle: .module)
            }
        }
    }
}

/// Loading placeholder for one shelf: a title bar and a row of landscape skeleton tiles (with caption space).
private struct SkeletonShelf: View {
    let tiles: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            // Redacted header text at the shelf-title font: the placeholder takes the real header's size.
            Text(verbatim: "Placeholder shelf")
                .font(Typography.headline)
                .redacted(reason: .placeholder)
                .padding(.horizontal, Spacing.screenEdge)
            HStack(spacing: Spacing.l) {
                ForEach(0..<tiles, id: \.self) { _ in
                    SkeletonTile(shape: .landscape)
                        .padding(.bottom, TileMetrics.captionHeight(.landscape))
                }
            }
            .padding(.horizontal, Spacing.screenEdge)
            .padding(.vertical, Spacing.l)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

/// `staggeredAppearance` for rows present in the first layout only. `enabled` is captured once when the row
/// is created, so the modifier's structure never changes afterwards (which would reset the row's state).
private struct InitialStagger: ViewModifier {
    let index: Int
    let didAppear: () -> Void
    @State private var enabled: Bool

    init(index: Int, enabled: Bool, didAppear: @escaping () -> Void) {
        self.index = index
        self.didAppear = didAppear
        _enabled = State(initialValue: enabled)
    }

    func body(content: Content) -> some View {
        if enabled {
            content
                .staggeredAppearance(index: index)
                .onAppear(perform: didAppear)
        } else {
            content
        }
    }
}

private extension View {
    /// `prefersDefaultFocus(_:in:)` on tvOS (unavailable on iOS).
    @ViewBuilder func homeDefaultFocus(_ prefers: Bool, in namespace: Namespace.ID) -> some View {
        #if os(tvOS)
        prefersDefaultFocus(prefers, in: namespace)
        #else
        self
        #endif
    }

    /// `focusScope(_:)` on tvOS (unavailable on iOS).
    @ViewBuilder func homeFocusScope(_ namespace: Namespace.ID) -> some View {
        #if os(tvOS)
        focusScope(namespace)
        #else
        self
        #endif
    }
}

#if DEBUG
/// Serves a hand-built Home snapshot so the preview shows shelves without a catalog.
private struct PreviewSnapshotCatalog: CatalogProviding {
    let content: HomeContent

    func current() async -> Catalog? { nil }
    func lastUpdated() async -> Date? { nil }
    func signIn(_ c: Credentials, progress: (@Sendable (Double) -> Void)?) async throws -> Catalog { throw APIError.offline }
    func loadCached() async -> Catalog? { nil }
    func refresh(force: Bool, now: Date) async throws -> Bool { false }
    func homeSnapshot() async -> HomeContent? { content }
    func saveHomeSnapshot(_ content: HomeContent) async {}
    func clear() async {}

    static let sample: HomeContent = {
        func title(_ kind: TitleKind, _ id: Int) -> Title {
            Title(id: TitleID(kind: kind, id: id), name: "\(kind == .show ? "Show" : "Movie") \(id)",
                  desc: "A preview description that runs to a couple of lines to show the hero text block.",
                  imdbRating: 7.8, year: 2024, genres: ["Drama"], lengthMinutes: 110, resolution: kind == .movie ? .hd : nil,
                  ended: kind == .show ? false : nil)
        }
        let shows = (1...12).map { title(.show, $0) }, movies = (1...12).map { title(.movie, $0) }
        return HomeContent(
            hero: [HeroItem(title: shows[0], action: .playFirstEpisode), HeroItem(title: movies[0], action: .playMovie)],
            shelves: [
                Shelf(id: "continueWatching", kind: .continueWatching,
                      items: shows.prefix(4).map { ShelfItem(title: $0, progress: 0.4, episode: EpisodeRef(episodeID: $0.id.id, season: 1, number: 3),
                                                             playable: PlayableID(kind: .episode, id: $0.id.id)) },
                      totalCount: 4),
                Shelf(id: "popularShows", kind: .popularShows, items: shows.map { ShelfItem(title: $0) }, totalCount: 12,
                      seeAll: BrowseQuery(kind: .show, sort: .popular)),
                Shelf(id: "topRatedMovies", kind: .topRatedMovies, items: movies.map { ShelfItem(title: $0) }, totalCount: 12,
                      seeAll: BrowseQuery(kind: .movie, sort: .rating)),
                Shelf(id: "genre-Drama", kind: .genre("Drama"), items: shows.map { ShelfItem(title: $0) }, totalCount: 12,
                      seeAll: BrowseQuery(kind: .show, genre: "Drama", sort: .popular))
            ]
        )
    }()
}

@MainActor private func previewHome(_ catalog: (any CatalogProviding)?) -> some View {
    let base = AppEnvironment.preview()
    let environment = catalog.map {
        AppEnvironment(api: base.api, catalog: $0, library: base.library, details: base.details,
                       credentials: base.credentials, newEpisodes: base.newEpisodes)
    } ?? base
    return HomeScreen()
        .environment(\.appEnvironment, environment)
        .environment(TabRouter())
        .environment(PlaybackLauncher())
        .environment(AppSession(environment: environment))
}

#Preview("Home: snapshot") {
    previewHome(PreviewSnapshotCatalog(content: PreviewSnapshotCatalog.sample))
}

#Preview("Home: skeleton") {
    previewHome(nil)
}
#endif
