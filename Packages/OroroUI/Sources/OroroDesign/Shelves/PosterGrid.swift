import SwiftUI

/// Columns for a poster grid `width` points wide: as many as fit at `minTileWidth`, then widened to fill the row
/// between the screen edges.
struct PosterGridLayout: Equatable {
    static var minTileWidth: CGFloat {
        #if os(tvOS)
        TileMetrics.size(.poster).width
        #else
        104
        #endif
    }

    /// Before the grid has been measured.
    static var fallbackWidth: CGFloat {
        #if os(tvOS)
        1920
        #else
        390
        #endif
    }

    let columns: Int
    let tileWidth: CGFloat
    let spacing: CGFloat

    init(width: CGFloat) {
        #if os(tvOS)
        spacing = Spacing.l
        #else
        spacing = Spacing.m
        #endif
        let available = max(width - 2 * Spacing.screenEdge, 1)
        columns = max(1, Int(((available + spacing) / (Self.minTileWidth + spacing)).rounded(.down)))
        tileWidth = ((available - CGFloat(columns - 1) * spacing) / CGFloat(columns)).rounded(.down)
    }
}

/// A lazy grid of captioned poster tiles with the same focus memory as `ShelfRow` (shelf id `"grid"`).
/// Zoom source ids are `"grid/<item>"`.
///
/// `header` scrolls with the grid and is kept when the items change; only the grid crossfades, keyed on
/// `contentVersion`, so focus stays on a header control that changed the items. Bumping `focusRequest`
/// moves focus to the first tile.
public struct PosterGrid<Header: View>: View {
    static var shelf: String { "grid" }

    private let screen: String
    private let items: [TileModel]
    private let isLoading: Bool
    private let contentVersion: Int
    private let focusRequest: Int
    private let memory: FocusMemory
    private let zoomNamespace: Namespace.ID?
    private let onFocusChange: (TileModel?) -> Void
    private let onSelect: (TileModel) -> Void
    private let menu: (TileModel) -> AnyView
    private let header: Header

    @FocusState private var focused: String?
    @State private var scrollPosition: ScrollPosition
    @State private var defaultTarget: String?
    @State private var width = PosterGridLayout.fallbackWidth

    public init(screen: String, items: [TileModel], isLoading: Bool = false, contentVersion: Int = 0, focusRequest: Int = 0,
                memory: FocusMemory, zoomNamespace: Namespace.ID? = nil,
                onFocusChange: @escaping (TileModel?) -> Void, onSelect: @escaping (TileModel) -> Void,
                menu: @escaping (TileModel) -> AnyView = { _ in AnyView(EmptyView()) },
                @ViewBuilder header: () -> Header) {
        self.screen = screen
        self.items = items
        self.isLoading = isLoading
        self.contentVersion = contentVersion
        self.focusRequest = focusRequest
        self.memory = memory
        self.zoomNamespace = zoomNamespace
        self.onFocusChange = onFocusChange
        self.onSelect = onSelect
        self.menu = menu
        self.header = header()
        // Runs on every parent update so `memory` knows the current ids; @State initial values apply once.
        let restoration = memory.restoration(screen: screen, shelf: Self.shelf, ids: items.map(\.id))
        _scrollPosition = State(initialValue: ShelfScroll.initialPosition(restoration.scroll, anchor: .top))
        _defaultTarget = State(initialValue: restoration.focus ?? items.first?.id)
    }

    public var body: some View {
        let layout = PosterGridLayout(width: width)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Group {
                    if isLoading && items.isEmpty {
                        skeleton(layout)
                    } else {
                        grid(layout)
                    }
                }
                .id(contentVersion)
                .transition(.opacity)
            }
            .motion(Motion.quick, value: contentVersion)
        }
        .scrollClipDisabled()
        .scrollPosition($scrollPosition)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: scrollPosition.viewID(type: String.self)) { _, leading in
            if let leading { memory.setScrollAnchor(leading, screen: screen, shelf: Self.shelf) }
        }
        .tileFocusSection()
        .defaultFocus($focused, defaultTarget, priority: .userInitiated)
        .onAppear(perform: restore)
        .onChange(of: focused) { _, id in
            focusChanged(to: id)
        }
        .onChange(of: contentVersion) { _, _ in
            defaultTarget = memory.restoration(screen: screen, shelf: Self.shelf, ids: items.map(\.id)).focus ?? items.first?.id
        }
        .onChange(of: focusRequest) { _, _ in
            // The new tiles appear in this update; focus them on the next turn.
            Task { @MainActor in focused = items.first?.id }
        }
    }

    private func grid(_ layout: PosterGridLayout) -> some View {
        LazyVGrid(columns: columns(layout), alignment: .leading, spacing: Spacing.l) {
            ForEach(items) { item in
                tile(item, width: layout.tileWidth)
            }
        }
        .scrollTargetLayout()
        .padding(.horizontal, Spacing.screenEdge)
        .padding(.vertical, Spacing.l)
    }

    private func skeleton(_ layout: PosterGridLayout) -> some View {
        LazyVGrid(columns: columns(layout), alignment: .leading, spacing: Spacing.l) {
            ForEach(0..<layout.columns * 2, id: \.self) { _ in
                SkeletonTile(shape: .poster, width: layout.tileWidth)
            }
        }
        .padding(.horizontal, Spacing.screenEdge)
        .padding(.vertical, Spacing.l)
        .accessibilityHidden(true)
    }

    private func columns(_ layout: PosterGridLayout) -> [GridItem] {
        Array(repeating: GridItem(.fixed(layout.tileWidth), spacing: layout.spacing, alignment: .top), count: layout.columns)
    }

    private func tile(_ item: TileModel, width: CGFloat) -> some View {
        Button {
            onSelect(item)
        } label: {
            PosterTile(item, isFocused: focused == item.id, width: width, showsCaption: true)
        }
        .tileButtonStyle()
        .focused($focused, equals: item.id)
        .contextMenu { menu(item) }
        .detailZoomSource(id: "\(Self.shelf)/\(item.id)", in: zoomNamespace)
        .id(item.id)
    }

    private func restore() {
        let restoration = memory.restoration(screen: screen, shelf: Self.shelf, ids: items.map(\.id))
        defaultTarget = restoration.focus ?? items.first?.id
        if let target = restoration.scroll, scrollPosition.viewID(type: String.self) != target {
            scrollPosition.scrollTo(id: target, anchor: .top)
        }
    }

    private func focusChanged(to id: String?) {
        guard let id, let index = items.firstIndex(where: { $0.id == id }) else {
            onFocusChange(nil)
            return
        }
        memory.remember(FocusID(screen: screen, shelf: Self.shelf, item: id))
        defaultTarget = id
        onFocusChange(items[index])
        // Prefetch the next rows (spec: Images).
        let columns = PosterGridLayout(width: width).columns
        let nextRowStart = (index / columns + 1) * columns
        if nextRowStart < items.count {
            ShelfScroll.prefetch(after: items[nextRowStart - 1].id, in: items, shape: .poster, count: columns * 2)
        }
    }
}

public extension PosterGrid where Header == EmptyView {
    init(screen: String, items: [TileModel], isLoading: Bool = false, memory: FocusMemory, zoomNamespace: Namespace.ID? = nil,
         onFocusChange: @escaping (TileModel?) -> Void, onSelect: @escaping (TileModel) -> Void,
         menu: @escaping (TileModel) -> AnyView = { _ in AnyView(EmptyView()) }) {
        self.init(screen: screen, items: items, isLoading: isLoading, memory: memory, zoomNamespace: zoomNamespace,
                  onFocusChange: onFocusChange, onSelect: onSelect, menu: menu) { EmptyView() }
    }
}

#if DEBUG
#Preview("Poster grid") {
    @Previewable @State var memory = FocusMemory()
    PosterGrid(screen: "preview", items: (1...120).map { index in
        TileModel(id: "title-\(index)", title: "Title \(index)", subtitle: "2024 · ★ 7.\(index % 10)",
                  accessibilityLabel: "Title \(index)")
    }, memory: memory, onFocusChange: { _ in }, onSelect: { _ in },
       header: { Text(verbatim: "Header").font(Typography.title).padding(.horizontal, Spacing.screenEdge) })
}
#endif
