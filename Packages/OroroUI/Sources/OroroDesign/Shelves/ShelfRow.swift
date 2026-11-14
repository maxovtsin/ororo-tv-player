import SwiftUI

/// A titled horizontal shelf of tiles that remembers and restores focus (spec: Navigation → Focus memory).
///
/// The row is one `.focusSection()` (tvOS). When it is created it scrolls to where it was and offers the remembered
/// tile as its default focus (also for focus moving into it vertically); every focus change is written back
/// to `memory`. Tiles are zoom sources with id `"<shelf>/<item>"`.
public struct ShelfRow: View {
    private let screen: String
    private let shelf: String
    private let title: String
    private let count: Int?
    private let items: [TileModel]
    private let shape: TileShape
    private let memory: FocusMemory
    private let zoomNamespace: Namespace.ID?
    private let showsSeeAll: Bool
    private let onSeeAll: (() -> Void)?
    private let onSelect: (TileModel) -> Void
    private let menu: (TileModel) -> AnyView

    @FocusState private var focused: String?
    @State private var scrollPosition: ScrollPosition
    @State private var defaultTarget: String?

    public init(screen: String, shelf: String, title: String, count: Int? = nil, items: [TileModel], shape: TileShape,
                memory: FocusMemory, zoomNamespace: Namespace.ID? = nil, showsSeeAll: Bool = false, onSeeAll: (() -> Void)? = nil,
                onSelect: @escaping (TileModel) -> Void, menu: @escaping (TileModel) -> AnyView = { _ in AnyView(EmptyView()) }) {
        self.screen = screen
        self.shelf = shelf
        self.title = title
        self.count = count
        self.items = items
        self.shape = shape
        self.memory = memory
        self.zoomNamespace = zoomNamespace
        self.showsSeeAll = showsSeeAll
        self.onSeeAll = onSeeAll
        self.onSelect = onSelect
        self.menu = menu
        // Runs on every parent update, so `memory` always knows the current ids (needed for the index fallback).
        // The @State initial values only take effect when the row is first created.
        let restoration = memory.restoration(screen: screen, shelf: shelf, ids: items.map(\.id))
        _scrollPosition = State(initialValue: ShelfScroll.initialPosition(restoration.scroll, anchor: .leading))
        _defaultTarget = State(initialValue: restoration.focus)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            header
            ScrollView(.horizontal) {
                LazyHStack(spacing: Spacing.l) {
                    ForEach(items) { item in
                        tile(item)
                    }
                    if showsSeeAll {
                        Button {
                            onSeeAll?()
                        } label: {
                            SeeAllTile(shape: shape)
                        }
                        .tileButtonStyle()
                    }
                }
                .padding(.vertical, Spacing.l)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .contentMargins(.horizontal, Spacing.screenEdge, for: .scrollContent)
            .scrollPosition($scrollPosition)
            .onChange(of: scrollPosition.viewID(type: String.self)) { _, leading in
                if let leading { memory.setScrollAnchor(leading, screen: screen, shelf: shelf) }
            }
            .tileFocusSection()
            .defaultFocus($focused, defaultTarget, priority: .userInitiated)
            .onAppear(perform: restore)
            .onChange(of: focused) { _, id in
                focusChanged(to: id)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(verbatim: title)
                .font(Typography.headline)
                .foregroundStyle(Palette.textPrimary)
            if let count {
                Text(count, format: .number)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.horizontal, Spacing.screenEdge)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func tile(_ item: TileModel) -> some View {
        Button {
            onSelect(item)
        } label: {
            switch shape {
            case .poster: PosterTile(item, isFocused: focused == item.id)
            case .landscape: LandscapeTile(item, isFocused: focused == item.id)
            }
        }
        .tileButtonStyle()
        .focused($focused, equals: item.id)
        .contextMenu { menu(item) }
        .detailZoomSource(id: "\(shelf)/\(item.id)", in: zoomNamespace)
        .id(item.id)
    }

    /// Re-applies the remembered position when the row comes back (pop, tab switch) in case it moved.
    private func restore() {
        let restoration = memory.restoration(screen: screen, shelf: shelf, ids: items.map(\.id))
        defaultTarget = restoration.focus
        if let target = restoration.scroll, scrollPosition.viewID(type: String.self) != target {
            scrollPosition.scrollTo(id: target, anchor: .leading)
        }
        if let focus = restoration.focus { ShelfScroll.prefetch(after: focus, in: items, shape: shape, count: 6) }
    }

    private func focusChanged(to id: String?) {
        guard let id, items.contains(where: { $0.id == id }) else { return }
        memory.remember(FocusID(screen: screen, shelf: shelf, item: id))
        defaultTarget = id
        ShelfScroll.prefetch(after: id, in: items, shape: shape, count: 6)
    }
}

/// Helpers shared by `ShelfRow` and `PosterGrid`.
enum ShelfScroll {
    static func initialPosition(_ id: String?, anchor: UnitPoint) -> ScrollPosition {
        guard let id else { return ScrollPosition(idType: String.self) }
        return ScrollPosition(id: id, anchor: anchor)
    }

    /// Prefetches artwork for the `count` items after `id`, at the tile's size.
    @MainActor static func prefetch(after id: String, in items: [TileModel], shape: TileShape, count: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let upcoming = items.dropFirst(index + 1).prefix(count)
        let urls = upcoming.compactMap { artworkURL($0, shape: shape) }
        guard !urls.isEmpty else { return }
        ImageCache.prefetch(urls, pointSize: TileMetrics.size(shape))
    }

    static func artworkURL(_ item: TileModel, shape: TileShape) -> URL? {
        switch shape {
        case .poster: item.posterURL
        case .landscape: item.backdropURL ?? item.posterURL
        }
    }
}

extension View {
    /// `.focusSection()` on tvOS (unavailable on iOS).
    func tileFocusSection() -> some View {
        #if os(tvOS)
        focusSection()
        #else
        self
        #endif
    }

    /// System card lift and parallax on tvOS; plain on iOS.
    func tileButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.card)
        #else
        buttonStyle(.plain)
        #endif
    }
}

#if DEBUG
/// Focus-memory harness (spec Phase 0 S1 / D5 step 5): 8 shelves × 30 tiles in a TabView + NavigationStack.
/// Check: move to the 20th tile of shelf 4, select, press Menu → focus returns to that tile;
/// switch tab and back → same.
private struct FocusMemoryHarness: View {
    @State private var memory = FocusMemory()
    @State private var path: [String] = []
    @Namespace private var zoom

    var body: some View {
        TabView {
            Tab(Self.homeTab, systemImage: "house") {
                NavigationStack(path: $path) {
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: Spacing.shelfGap) {
                            ForEach(1...8, id: \.self) { shelf in
                                ShelfRow(screen: "home", shelf: "shelf-\(shelf)", title: "Shelf \(shelf)", count: 30,
                                         items: Self.items(shelf: shelf), shape: shelf.isMultiple(of: 2) ? .landscape : .poster,
                                         memory: memory, zoomNamespace: zoom, showsSeeAll: true, onSeeAll: {},
                                         onSelect: { item in path.append("shelf-\(shelf)/\(item.id)") })
                                    .id("shelf-\(shelf)")
                            }
                        }
                    }
                    .navigationDestination(for: String.self) { sourceID in
                        Text(verbatim: sourceID)
                            .font(Typography.heroTitle)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.indigo)
                            .detailZoomDestination(id: sourceID, in: zoom)
                    }
                }
            }
            Tab(Self.otherTab, systemImage: "square") {
                Button {} label: { Text(verbatim: "Button") }
            }
        }
    }

    // Preview-only strings stay out of the string catalog.
    private static let homeTab = "Home", otherTab = "Other"

    static func items(shelf: Int) -> [TileModel] {
        (1...30).map { index in
            TileModel(id: "title-\(index)", title: "Title \(shelf).\(index)", subtitle: "2024",
                      progress: index.isMultiple(of: 5) ? 0.4 : nil, accessibilityLabel: "Title \(shelf).\(index)")
        }
    }
}

#Preview("Focus memory: 8 shelves × 30") {
    FocusMemoryHarness()
}

#Preview("Shelf row") {
    ShelfRow(screen: "preview", shelf: "popular", title: "Popular", count: 30,
             items: FocusMemoryHarness.items(shelf: 1), shape: .poster, memory: FocusMemory(), onSelect: { _ in })
}
#endif
