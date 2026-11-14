import OroroCore
import OroroDesign
import SwiftUI

/// Screen geometry for the hero: the full screen height (safe area included) and the safe-area insets the
/// backdrop extends into while the text and buttons stay clear of them.
public struct HeroLayout: Equatable, Sendable {
    public var screenHeight: CGFloat?
    public var insets: EdgeInsets

    public init(screenHeight: CGFloat? = nil, insets: EdgeInsets = EdgeInsets()) {
        self.screenHeight = screenHeight
        self.insets = insets
    }
}

/// Full-screen paging banner at the top of Home: a horizontal strip of pages, each a backdrop with its own
/// text and buttons. Focus moving right off a page's last button (a swipe or a click on the Siri Remote) lands
/// on the next page's first button and the strip slides with it, backdrop included; an edge click wraps around.
/// Dimmed while focus is in the shelves. On tvOS the backdrop is full-bleed (behind the tab bar) and the first
/// shelf's header peeks below it.
public struct HeroView: View {
    private let items: [HeroItem]
    private let isActive: Bool
    private let layout: HeroLayout
    /// Each change moves focus onto the current page's Play button (Home's Menu-to-top).
    private let focusRequest: Int
    private let isInList: (Title) -> Bool
    private let onPlay: (HeroItem) -> Void
    private let onToggleList: (Title) -> Void

    private enum Field: Hashable { case play, list }

    /// A button on a page.
    private struct Target: Hashable {
        let page: Int
        let field: Field
    }

    private struct TickConditions: Equatable {
        let sceneActive: Bool
        let reduceMotion: Bool
    }

    /// An edge click this soon after a focus move is the click that made the move, not one at the edge.
    private static let edgeClickDelay: TimeInterval = 0.3

    @State private var pager: HeroPager
    @State private var position = ScrollPosition(idType: Int.self)
    @State private var clockStart = ContinuousClock.now
    @State private var focusMovedAt: TimeInterval = 0
    @FocusState private var focused: Target?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(items: [HeroItem], isActive: Bool, layout: HeroLayout = HeroLayout(), focusRequest: Int = 0,
                isInList: @escaping (Title) -> Bool, onPlay: @escaping (HeroItem) -> Void, onToggleList: @escaping (Title) -> Void) {
        self.items = items
        self.isActive = isActive
        self.layout = layout
        self.focusRequest = focusRequest
        self.isInList = isInList
        self.onPlay = onPlay
        self.onToggleList = onToggleList
        _pager = State(initialValue: HeroPager(count: items.count))
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                // Not lazy: the focus engine can only move onto a neighbouring page whose buttons exist.
                ForEach(items.indices, id: \.self) { index in
                    page(items[index], index: index)
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition($position)
        .overlay(alignment: .bottomTrailing) { pageDots }
        .overlay { Color.black.opacity(isActive ? 0 : 0.5).allowsHitTesting(false) }
        .motion(Motion.standard, value: isActive)
        .modifier(HeroHeight(screenHeight: layout.screenHeight))
        .clipped()
        .heroFocusSection()
        .defaultFocus($focused, Target(page: pager.index, field: .play), priority: .userInitiated)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(positionLabel)
        .onChange(of: items.map(\.id)) {
            pager = HeroPager(count: items.count, startTime: elapsed)
            position.scrollTo(id: 0)
        }
        .onChange(of: focused) { _, target in focusMoved(to: target) }
        .onChange(of: focusRequest) { focused = Target(page: pager.index, field: .play) }
        // iOS: a swipe pages the strip directly.
        .onChange(of: position.viewID(type: Int.self)) { _, page in
            if let page, page != pager.index { pager.show(page) }
        }
        // Restarted when the scene phase or Reduce Motion changes: the loop reads the environment values captured
        // when it started (a loop started at launch would otherwise see the scene as inactive for good).
        .task(id: TickConditions(sceneActive: scenePhase == .active, reduceMotion: reduceMotion)) { await runTicks() }
    }

    // MARK: Pieces

    private func page(_ item: HeroItem, index: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            textBlock(for: item)
            buttons(for: item, page: index)
        }
        .padding(.leading, Spacing.screenEdge + layout.insets.leading)
        .padding(.trailing, Spacing.screenEdge + layout.insets.trailing)
        .padding(.bottom, Spacing.xl)
        // The backdrop never sizes the page (an aspect-filled image is taller than the hero and would push the
        // buttons below its clipped bottom edge).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background { BackdropView(url: item.title.backdropURL, dim: .hero, drift: true) }
    }

    private func textBlock(for item: HeroItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(verbatim: item.title.name)
                .font(Typography.heroTitle)
                .lineLimit(2)
            MetadataLine(Self.metadata(for: item.title))
            if let desc = item.title.desc, !desc.isEmpty {
                Text(verbatim: desc)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(3)
                    .frame(maxWidth: Self.textWidth, alignment: .leading)
            }
        }
    }

    private func buttons(for item: HeroItem, page: Int) -> some View {
        HStack(spacing: Spacing.m) {
            ActionButton(Self.playTitle(item.action), systemImage: "play.fill", style: .prominent) { onPlay(item) }
                .focused($focused, equals: Target(page: page, field: .play))
            ToggleListButton(isInList: isInList(item.title)) { onToggleList(item.title) }
                .focused($focused, equals: Target(page: page, field: .list))
        }
        .padding(.top, Spacing.s)
        #if os(tvOS)
        .onMoveCommand(perform: edgeClick)
        #endif
    }

    /// Decorative; the container's accessibility label carries "n of m".
    private var pageDots: some View {
        HStack(spacing: Spacing.s) {
            ForEach(items.indices, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(index == pager.index ? 0.95 : 0.35))
                    .frame(width: Spacing.s, height: Spacing.s)
            }
        }
        .padding(.trailing, Spacing.screenEdge + layout.insets.trailing)
        .padding(.bottom, Spacing.l)
        .motion(Motion.quick, value: pager.index)
        .accessibilityHidden(true)
    }

    private var positionLabel: String {
        let position = pager.index + 1
        let total = items.count
        return String(localized: "hero.accessibility.position", defaultValue: "\(position) of \(total)", bundle: .module)
    }

    // MARK: Paging

    /// Focus moved, by the focus engine or by `go(to:)`: a move onto another page brings that page in.
    private func focusMoved(to target: Target?) {
        guard let target else { return }
        focusMovedAt = elapsed
        pager.userInteracted(at: elapsed)
        if target.page != pager.index { slide(to: target.page) }
    }

    /// Shows `page` and moves focus onto the same button there (auto-advance, wrap-around).
    private func go(to page: Int) {
        slide(to: page)
        if let field = focused?.field { focused = Target(page: page, field: field) }
    }

    private func slide(to page: Int) {
        pager.show(page)
        withAnimation(Motion.resolved(Motion.cinematic, reduceMotion: reduceMotion)) {
            position.scrollTo(id: page)
        }
    }

    #if os(tvOS)
    /// A click right on the last page's "+" (or left on the first page's Play) has nowhere to move focus: wrap.
    /// Move commands also arrive for clicks that did move focus (before or after the move), hence the delay check.
    private func edgeClick(_ direction: MoveCommandDirection) {
        guard let target = focused, elapsed - focusMovedAt >= Self.edgeClickDelay else { return }
        let forward = direction == .right
        guard forward || direction == .left else { return }
        let edgeField: Field = forward ? .list : .play
        guard let page = HeroPager.wrapTarget(from: target.page, count: items.count, forward: forward,
                                              onEdgeButton: target.field == edgeField) else { return }
        slide(to: page)
        focused = Target(page: page, field: forward ? .play : .list)
    }
    #endif

    // MARK: Auto-advance

    private var elapsed: TimeInterval {
        let parts = clockStart.duration(to: .now).components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    private func runTicks() async {
        let clock = ContinuousClock()
        while !Task.isCancelled {
            try? await clock.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            if pager.tick(at: elapsed, focusInHero: focused != nil, sceneActive: scenePhase == .active, reduceMotion: reduceMotion) {
                go(to: pager.index)
            }
        }
    }

    // MARK: Pure helpers

    #if os(tvOS)
    static let heightFraction: CGFloat = 1, textWidth: CGFloat = 900
    /// The hero stops this far above the screen bottom so the first shelf's header shows.
    static let shelfPeek: CGFloat = 150
    #else
    static let heightFraction: CGFloat = 0.55, textWidth: CGFloat = 600
    static let shelfPeek: CGFloat = 0
    #endif

    /// Hero height for a known full-screen height.
    nonisolated static func height(screenHeight: CGFloat) -> CGFloat {
        max(screenHeight * heightFraction - shelfPeek, 0)
    }

    /// "Play", "Play S2 E4", "Resume S2 E3"
    nonisolated static func playTitle(_ action: HeroAction) -> String {
        switch action {
        case .playMovie, .playFirstEpisode:
            // The show's real first episode isn't known here (it may not be S1 E1).
            return String(localized: "hero.play", defaultValue: "Play", bundle: .module)
        case .playEpisode(let ref):
            let label = Display.episodeLabel(season: ref.season, number: ref.number)
            return String(localized: "hero.play.episode", defaultValue: "Play \(label)", bundle: .module)
        case .resumeEpisode(let ref):
            let label = Display.episodeLabel(season: ref.season, number: ref.number)
            return String(localized: "hero.resume.episode", defaultValue: "Resume \(label)", bundle: .module)
        }
    }

    /// IMDb badge, year, genres, then Ongoing/Ended (shows) or runtime and HD (movies). No CC badge.
    nonisolated static func metadata(for title: Title, locale: Locale = .current) -> [MetadataItem] {
        var items: [MetadataItem] = []
        if let rating = title.imdbRating { items.append(.badge(.imdb(rating))) }
        if let year = title.year { items.append(.text(String(year))) }
        items += title.genres.prefix(3).map { MetadataItem.text(GenreName.localized($0, locale: locale)) }
        switch title.id.kind {
        case .show:
            if let ended = title.ended {
                items.append(.text(ended
                    ? String(localized: "hero.status.ended", defaultValue: "Ended", bundle: .module)
                    : String(localized: "hero.status.ongoing", defaultValue: "Ongoing", bundle: .module)))
            }
        case .movie:
            if let minutes = title.lengthMinutes { items.append(.text(Display.runtime(minutes: minutes, locale: locale))) }
            if title.resolution == .hd { items.append(.badge(.hd)) }
        }
        return items
    }
}

/// Sizes the hero from the screen height when known, else from its container (previews).
private struct HeroHeight: ViewModifier {
    let screenHeight: CGFloat?

    func body(content: Content) -> some View {
        if let screenHeight {
            content.frame(height: HeroView.height(screenHeight: screenHeight))
        } else {
            content.containerRelativeFrame(.vertical) { length, _ in HeroView.height(screenHeight: length) }
        }
    }
}

private extension View {
    /// `focusSection()` on tvOS (unavailable on iOS).
    @ViewBuilder func heroFocusSection() -> some View {
        #if os(tvOS)
        focusSection()
        #else
        self
        #endif
    }
}

#Preview("Hero") {
    HeroView(items: HeroPreviewData.items, isActive: true, isInList: { $0.id.id == 2 }, onPlay: { _ in }, onToggleList: { _ in })
        .ignoresSafeArea()
}

#Preview("Hero dimmed") {
    HeroView(items: HeroPreviewData.items, isActive: false, isInList: { _ in false }, onPlay: { _ in }, onToggleList: { _ in })
}

private enum HeroPreviewData {
    static let items: [HeroItem] = [
        HeroItem(
            title: Title(id: TitleID(kind: .movie, id: 1), name: "The Long Dark Night", desc: "A detective returns home to a town that never forgot.",
                         imdbRating: 8.3, year: 2025, genres: ["Crime", "Drama"], lengthMinutes: 130, resolution: .hd),
            action: .playMovie
        ),
        HeroItem(
            title: Title(id: TitleID(kind: .show, id: 2), name: "Harbor Lights", desc: "Two families, one ferry.",
                         imdbRating: 7.9, year: 2024, genres: ["Drama"], ended: false),
            action: .resumeEpisode(EpisodeRef(episodeID: 5, season: 2, number: 3))
        )
    ]
}
