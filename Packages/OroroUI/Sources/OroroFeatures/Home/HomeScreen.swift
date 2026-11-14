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

/// Where focus is on Home. Bound to the hero and each shelf as containers, so it reads "focus is inside".
private enum HomeFocusArea: Hashable {
    case hero, shelf(String)

    var isShelf: Bool {
        if case .shelf = self { true } else { false }
    }
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
    #if os(tvOS)
    @Environment(\.resetFocus) private var resetFocus
    #endif

    @State private var model: HomeViewModel
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    @FocusState private var focusArea: HomeFocusArea?
    /// Whether focus was last in the hero (true) or in a shelf (false); decides where focus returns on re-appear.
    @State private var lastFocusInHero = true
    @State private var hasAppeared = false
    @Namespace private var focusNamespace

    init(environment: AppEnvironment) {
        self.environment = environment
        _model = State(initialValue: HomeViewModel(environment: environment))
    }

    /// Expanded while focus is in the hero (or outside the screen, e.g. in the tab bar); collapsed in the shelves.
    private var isExpanded: Bool {
        !(focusArea?.isShelf ?? false)
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Spacing.shelfGap) {
                if let content = model.content {
                    if !content.hero.isEmpty { hero(content.hero) }
                    ForEach(Array(content.shelves.enumerated()), id: \.element.id) { index, shelf in
                        row(shelf)
                            .focused($focusArea, equals: .shelf(shelf.id))
                            .homeDefaultFocus(!lastFocusInHero && anchor == shelf.id, in: focusNamespace)
                            .staggeredAppearance(index: index)
                            .id(shelf.id)
                    }
                } else {
                    ForEach(0..<Self.skeletonRows, id: \.self) { index in
                        SkeletonShelf(tiles: Self.skeletonTiles)
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
        .task { await run() }
        .onAppear(perform: reappear)
        .onChange(of: focusArea) { _, area in focusAreaChanged(area) }
        .onChange(of: router.scrollToTopToken) { scrollToTop() }
        .onChange(of: session.catalogVersion) {
            // The first catalog replaces the snapshot / skeleton; later ones wait for the next appear.
            guard !model.isBuiltFromCatalog else { return }
            Task { await model.appear(catalog: session.catalog, newEpisodeInfo: session.newEpisodeInfo) }
        }
    }

    private var anchor: String? {
        router.focus.verticalAnchor(screen: Self.screen)
    }

    // MARK: - Pieces

    private func hero(_ items: [HeroItem]) -> some View {
        HeroView(
            items: items,
            isExpanded: isExpanded,
            isInList: { [model] title in model.library.isInMyList(title.id) },
            onPlay: { [model, launcher] item in model.heroPlay(item, launcher: launcher) },
            onToggleList: { [model] title in Task { await model.toggleList(title) } }
        )
        .focused($focusArea, equals: .hero)
        .homeDefaultFocus(lastFocusInHero || anchor == nil, in: focusNamespace)
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
            model.libraryChanged(library)
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
        switch area {
        case .hero: lastFocusInHero = true
        case .shelf: lastFocusInHero = false
        case nil: break
        }
        router.isAtTop = !(area?.isShelf ?? false)
    }

    /// Menu at a scrolled root: scroll to top and focus the hero.
    private func scrollToTop() {
        lastFocusInHero = true
        withAnimation(Motion.standard) {
            scrollPosition.scrollTo(edge: .top)
        }
        focusArea = model.content?.hero.isEmpty == false ? .hero : model.content?.shelves.first.map { .shelf($0.id) }
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
                String(localized: "home.shelf.genreMovies", defaultValue: "\(genre) Movies", bundle: .module)
            } else {
                String(localized: "home.shelf.genreShows", defaultValue: "\(genre) Shows", bundle: .module)
            }
        }
    }
}

/// Loading placeholder for one shelf: a title bar and a row of landscape skeleton tiles (with caption space).
private struct SkeletonShelf: View {
    let tiles: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            RoundedRectangle(cornerRadius: Spacing.xs)
                .fill(.white.opacity(0.08))
                .frame(width: 280, height: Spacing.m)
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
