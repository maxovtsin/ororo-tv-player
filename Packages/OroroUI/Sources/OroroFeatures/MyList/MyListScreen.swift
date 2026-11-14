import OroroCore
import OroroDesign
import SwiftUI

/// Continue Watching, New Episodes and the saved titles (spec: My List).
public struct MyListScreen: View {
    static let screenID = "mylist"

    @Environment(AppSession.self) private var session
    @Environment(TabRouter.self) private var router
    @Environment(PlaybackLauncher.self) private var launcher
    @Environment(\.appEnvironment) private var environment
    @Environment(\.selectTab) private var selectTab
    @Environment(\.detailZoomNamespace) private var zoomNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model: MyListViewModel?
    @State private var scrollPosition = ScrollPosition()
    @State private var gridResetToken = 0
    #if os(tvOS)
    @Environment(\.resetFocus) private var resetFocus
    #endif
    @Namespace private var focusScope

    public init() {}

    private struct Inputs: Hashable {
        let version: Int
        let info: [Int: NewEpisodeInfo]
    }

    public var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .task(id: Inputs(version: session.catalogVersion, info: session.newEpisodeInfo)) {
            let model = self.model ?? MyListViewModel(environment: environment)
            self.model = model
            await model.observe(catalog: session.catalog, newEpisodeInfo: session.newEpisodeInfo)
        }
        .onChange(of: router.scrollToTopToken) {
            // Forget the remembered rows/grid position, recreate the grid at its top, scroll up and focus the first element.
            router.focus.reset(screen: Self.screenID)
            gridResetToken += 1
            withAnimation(Motion.resolved(Motion.standard, reduceMotion: reduceMotion)) { scrollPosition.scrollTo(edge: .top) }
            resetFocusToFirst()
        }
    }

    private func resetFocusToFirst() {
        #if os(tvOS)
        resetFocus(in: focusScope)
        #endif
    }

    @ViewBuilder
    private func content(_ model: MyListViewModel) -> some View {
        if model.hasLoaded && model.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.shelfGap) {
                    row(model, shelf: "continueWatching",
                        title: String(localized: "mylist.continueWatching", defaultValue: "Continue Watching", bundle: .module),
                        items: model.continueWatching, tiles: model.continueWatchingTiles, context: .continueWatching)
                    row(model, shelf: "newEpisodes",
                        title: String(localized: "mylist.newEpisodes", defaultValue: "New Episodes", bundle: .module),
                        items: model.newEpisodes, tiles: model.newEpisodeTiles, context: .newEpisodes)
                    if !model.titles.isEmpty {
                        grid(model)
                    }
                }
                .padding(.vertical, Spacing.l)
            }
            .scrollPosition($scrollPosition)
            .myListFocusScope(focusScope)
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y <= $0.contentInsets.top + 1 } action: { _, atTop in
                router.isAtTop = atTop
            }
        }
    }

    @ViewBuilder
    private func row(_ model: MyListViewModel, shelf: String, title: String, items: [ShelfItem], tiles: [TileModel],
                     context: MenuContext) -> some View {
        if !items.isEmpty {
            ShelfRow(screen: Self.screenID, shelf: shelf, title: title, count: items.count, items: tiles,
                     shape: .landscape, memory: router.focus, zoomNamespace: zoomNamespace,
                     onSelect: { tile in
                         if let item = items.first(where: { $0.id == tile.id }) {
                             model.select(item, shelf: shelf, router: router, launcher: launcher)
                         }
                     },
                     menu: { tile in
                         guard let item = items.first(where: { $0.id == tile.id }) else { return AnyView(EmptyView()) }
                         return titleMenu(for: item, context: context, library: model.library, environment: environment, router: router)
                     })
                     .myListDefaultFocus(router.focus.verticalAnchor(screen: Self.screenID) == shelf, in: focusScope)
        }
    }

    private func grid(_ model: MyListViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(String(localized: "mylist.title", defaultValue: "My List", bundle: .module))
                .font(Typography.headline)
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Spacing.screenEdge)
                .accessibilityAddTraits(.isHeader)
            PosterGrid(screen: Self.screenID, items: model.gridTiles, memory: router.focus,
                       zoomNamespace: zoomNamespace, onFocusChange: { _ in },
                       onSelect: { tile in
                           if let title = model.titles.first(where: { TileModel.tileID($0.id) == tile.id }) {
                               model.select(ShelfItem(title: title), shelf: "grid", router: router, launcher: launcher)
                           }
                       },
                       menu: { tile in
                           guard let title = model.titles.first(where: { TileModel.tileID($0.id) == tile.id }) else { return AnyView(EmptyView()) }
                           return titleMenu(for: ShelfItem(title: title), context: .plain, library: model.library,
                                          environment: environment, router: router)
                       })
                       .myListDefaultFocus(router.focus.verticalAnchor(screen: Self.screenID) == "grid", in: focusScope)
                       .id(gridResetToken)
        }
        // One screen tall: the grid's own scroller pages through titles while this one brings the section into view.
        .containerRelativeFrame(.vertical, alignment: .top)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.l) {
            Text(String(localized: "mylist.empty.title", defaultValue: "Nothing here yet", bundle: .module))
                .font(Typography.headline)
                .foregroundStyle(Palette.textPrimary)
            Text(String(localized: "mylist.empty.message",
                        defaultValue: "Add titles to My List, or start watching, and they show up here.", bundle: .module))
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            ActionButton(String(localized: "mylist.empty.browse", defaultValue: "Browse Shows", bundle: .module),
                         systemImage: "tv", style: .prominent) {
                selectTab(.shows)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.screenEdge)
    }
}

/// tvOS-only focus steering (these modifiers do not exist on iOS).
private extension View {
    @ViewBuilder func myListFocusScope(_ scope: Namespace.ID) -> some View {
        #if os(tvOS)
        focusScope(scope)
        #else
        self
        #endif
    }

    @ViewBuilder func myListDefaultFocus(_ preferred: Bool, in scope: Namespace.ID) -> some View {
        #if os(tvOS)
        prefersDefaultFocus(preferred, in: scope)
        #else
        self
        #endif
    }
}
