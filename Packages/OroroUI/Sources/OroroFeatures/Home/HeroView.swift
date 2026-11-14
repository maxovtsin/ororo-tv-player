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

/// Full-screen paging banner at the top of Home. Expanded while focus is inside it, collapsed once
/// focus moves into the shelves; the collapse is one `standard` animation on `isExpanded`.
/// On tvOS the backdrop is full-bleed (behind the tab bar); expanded, it leaves the first shelf's header peeking.
public struct HeroView: View {
    private let items: [HeroItem]
    private let isExpanded: Bool
    private let layout: HeroLayout
    private let isInList: (Title) -> Bool
    private let onPlay: (HeroItem) -> Void
    private let onToggleList: (Title) -> Void

    private enum Field: Hashable { case play, list }

    @State private var pager: HeroPager
    @State private var clockStart = ContinuousClock.now
    @FocusState private var focused: Field?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(items: [HeroItem], isExpanded: Bool, layout: HeroLayout = HeroLayout(), isInList: @escaping (Title) -> Bool,
                onPlay: @escaping (HeroItem) -> Void, onToggleList: @escaping (Title) -> Void) {
        self.items = items
        self.isExpanded = isExpanded
        self.layout = layout
        self.isInList = isInList
        self.onPlay = onPlay
        self.onToggleList = onToggleList
        _pager = State(initialValue: HeroPager(count: items.count))
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let item = current {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    // Only the text block swaps per page; the buttons persist so focus survives paging.
                    textBlock(for: item)
                        .id(item.id)
                        .transition(textTransition)
                    buttons(for: item)
                }
                .padding(.leading, Spacing.screenEdge + layout.insets.leading)
                .padding(.trailing, Spacing.screenEdge + layout.insets.trailing)
                .padding(.bottom, Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // The backdrop never sizes the hero (an aspect-filled image is taller than the hero and would push the
        // buttons below its clipped bottom edge).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background {
            if let item = current {
                BackdropView(url: item.title.backdropURL, dim: .hero, drift: true)
            }
        }
        .motion(Motion.cinematic, value: pager.index)
        .overlay(alignment: .bottomTrailing) { pageDots }
        .overlay { Color.black.opacity(isExpanded ? 0 : 0.5).allowsHitTesting(false) }
        .scaleEffect(isExpanded ? 1 : 0.96, anchor: .top)
        .modifier(HeroHeight(screenHeight: layout.screenHeight, isExpanded: isExpanded))
        .clipped()
        .motion(Motion.standard, value: isExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(positionLabel)
        .onChange(of: items.map(\.id)) {
            pager = HeroPager(count: items.count, startTime: elapsed)
        }
        .onChange(of: focused != nil) { _, inHero in
            if inHero { pager.userInteracted(at: elapsed) }
        }
        .task { await runTicks() }
    }

    // MARK: Pieces

    private var current: HeroItem? {
        items.indices.contains(pager.index) ? items[pager.index] : nil
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

    private func buttons(for item: HeroItem) -> some View {
        HStack(spacing: Spacing.m) {
            ActionButton(Self.playTitle(item.action), systemImage: "play.fill", style: .prominent) { onPlay(item) }
                .focused($focused, equals: .play)
            ToggleListButton(isInList: isInList(item.title)) { onToggleList(item.title) }
                .focused($focused, equals: .list)
        }
        .padding(.top, Spacing.s)
        #if os(tvOS)
        .onMoveCommand { direction in
            switch (direction, focused) {
            case (.right, .list) where items.count > 1:
                pager.next()
                pager.userInteracted(at: elapsed)
                focused = .play
            case (.left, .play) where items.count > 1:
                pager.previous()
                pager.userInteracted(at: elapsed)
                focused = .list
            default:
                pager.userInteracted(at: elapsed)
            }
        }
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

    private var textTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(x: Spacing.l))
    }

    private var positionLabel: String {
        let position = pager.index + 1
        let total = items.count
        return String(localized: "hero.accessibility.position", defaultValue: "\(position) of \(total)", bundle: .module)
    }

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
            // The page change animates through `.motion(Motion.cinematic, value: pager.index)`.
            _ = pager.tick(at: elapsed, focusInHero: focused != nil, sceneActive: scenePhase == .active, reduceMotion: reduceMotion)
        }
    }

    // MARK: Pure helpers

    #if os(tvOS)
    static let expandedFraction: CGFloat = 1, collapsedFraction: CGFloat = 0.5, textWidth: CGFloat = 900
    /// Expanded, the hero stops this far above the screen bottom so the first shelf's header shows.
    static let shelfPeek: CGFloat = 150
    #else
    static let expandedFraction: CGFloat = 0.55, collapsedFraction: CGFloat = 0.35, textWidth: CGFloat = 600
    static let shelfPeek: CGFloat = 0
    #endif

    /// Hero height for a known full-screen height.
    nonisolated static func height(screenHeight: CGFloat, isExpanded: Bool) -> CGFloat {
        guard isExpanded else { return screenHeight * collapsedFraction }
        return max(screenHeight * expandedFraction - shelfPeek, screenHeight * collapsedFraction)
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
    let isExpanded: Bool

    func body(content: Content) -> some View {
        if let screenHeight {
            content.frame(height: HeroView.height(screenHeight: screenHeight, isExpanded: isExpanded))
        } else {
            content.containerRelativeFrame(.vertical) { length, _ in
                HeroView.height(screenHeight: length, isExpanded: isExpanded)
            }
        }
    }
}

#Preview("Hero expanded") {
    HeroView(items: HeroPreviewData.items, isExpanded: true, isInList: { $0.id.id == 2 }, onPlay: { _ in }, onToggleList: { _ in })
        .ignoresSafeArea()
}

#Preview("Hero collapsed") {
    HeroView(items: HeroPreviewData.items, isExpanded: false, isInList: { _ in false }, onPlay: { _ in }, onToggleList: { _ in })
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
