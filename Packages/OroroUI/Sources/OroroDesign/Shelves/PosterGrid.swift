import SwiftUI

/// A lazy grid of poster tiles with the same focus memory as `ShelfRow` (shelf id `"grid"`).
/// Zoom source ids are `"grid/<item>"`.
public struct PosterGrid: View {
    static let shelf = "grid"

    private let screen: String
    private let items: [TileModel]
    private let columns: Int
    private let memory: FocusMemory
    private let zoomNamespace: Namespace.ID?
    private let onFocusChange: (TileModel?) -> Void
    private let onSelect: (TileModel) -> Void
    private let menu: (TileModel) -> AnyView

    @FocusState private var focused: String?
    @State private var scrollPosition: ScrollPosition
    @State private var defaultTarget: String?

    public init(screen: String, items: [TileModel], columns: Int = 8, memory: FocusMemory, zoomNamespace: Namespace.ID? = nil,
                onFocusChange: @escaping (TileModel?) -> Void, onSelect: @escaping (TileModel) -> Void,
                menu: @escaping (TileModel) -> AnyView = { _ in AnyView(EmptyView()) }) {
        self.screen = screen
        self.items = items
        self.columns = max(columns, 1)
        self.memory = memory
        self.zoomNamespace = zoomNamespace
        self.onFocusChange = onFocusChange
        self.onSelect = onSelect
        self.menu = menu
        // Runs on every parent update so `memory` knows the current ids; @State initial values apply once.
        let restoration = memory.restoration(screen: screen, shelf: Self.shelf, ids: items.map(\.id))
        _scrollPosition = State(initialValue: ShelfScroll.initialPosition(restoration.scroll, anchor: .top))
        _defaultTarget = State(initialValue: restoration.focus)
    }

    public var body: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.l), count: columns),
                      spacing: Spacing.xl) {
                ForEach(items) { item in
                    tile(item)
                }
            }
            .padding(.vertical, Spacing.l)
            .scrollTargetLayout()
        }
        .scrollClipDisabled()
        .contentMargins(.horizontal, Spacing.screenEdge, for: .scrollContent)
        .scrollPosition($scrollPosition)
        .onChange(of: scrollPosition.viewID(type: String.self)) { _, leading in
            if let leading { memory.setScrollAnchor(leading, screen: screen, shelf: Self.shelf) }
        }
        .tileFocusSection()
        .defaultFocus($focused, defaultTarget, priority: .userInitiated)
        .onAppear(perform: restore)
        .onChange(of: focused) { _, id in
            focusChanged(to: id)
        }
    }

    private func tile(_ item: TileModel) -> some View {
        Button {
            onSelect(item)
        } label: {
            PosterTile(item, isFocused: focused == item.id)
        }
        .tileButtonStyle()
        .focused($focused, equals: item.id)
        .contextMenu { menu(item) }
        .detailZoomSource(id: "\(Self.shelf)/\(item.id)", in: zoomNamespace)
        .id(item.id)
    }

    private func restore() {
        let restoration = memory.restoration(screen: screen, shelf: Self.shelf, ids: items.map(\.id))
        defaultTarget = restoration.focus
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
        // Prefetch the next row (spec: Images).
        let nextRowStart = (index / columns + 1) * columns
        if nextRowStart < items.count {
            ShelfScroll.prefetch(after: items[nextRowStart - 1].id, in: items, shape: .poster, count: columns)
        }
    }
}

#if DEBUG
#Preview("Poster grid") {
    @Previewable @State var memory = FocusMemory()
    PosterGrid(screen: "preview", items: (1...120).map { index in
        TileModel(id: "title-\(index)", title: "Title \(index)", subtitle: "2024", accessibilityLabel: "Title \(index)")
    }, memory: memory, onFocusChange: { _ in }, onSelect: { _ in })
}
#endif
