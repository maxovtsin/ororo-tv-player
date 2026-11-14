import OroroCore
import OroroDesign
import SwiftUI

/// Right column for shows: season pills + episode rows; six skeleton rows until the show arrives,
/// "No episodes yet" when it has none, inline Retry on failure.
struct EpisodeList: View {
    let model: DetailViewModel
    var focus: FocusState<DetailFocus?>.Binding
    /// tvOS scrolls the list inside the column; iOS lets the page scroll.
    let scrolls: Bool
    let onPlay: (Episode, _ startOver: Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Rows stagger in only when the data first arrives, not on season switches.
    @State private var hasSwitchedSeason = false

    private static let skeletonRows = 6

    var body: some View {
        Group {
            switch model.load {
            case .loading:
                skeleton.transition(.opacity)
            case .failed:
                DetailFailureView(focus: focus) { Task { await model.retry() } }
            case .loaded:
                if model.seasons.isEmpty {
                    Text(String(localized: "detail.noEpisodes", defaultValue: "No episodes yet", bundle: .module))
                        .font(Typography.headline)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.top, Spacing.l)
                } else {
                    content.transition(.opacity)
                }
            }
        }
        .motion(Motion.quick, value: model.load)
    }

    // MARK: - Loaded

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            seasonPills
            rows
                .id(model.selectedSeason)
                .transition(seasonTransition)
        }
        .motion(Motion.standard, value: model.selectedSeason)
    }

    private var seasonPills: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.s) {
                ForEach(model.seasons, id: \.self) { season in
                    Chip(DetailViewModel.seasonTitle(season), isSelected: season == model.selectedSeason) {
                        hasSwitchedSeason = true
                        model.selectSeason(season)
                    }
                    .focused(focus, equals: .season(season))
                }
            }
            .padding(.vertical, Spacing.s)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    @ViewBuilder private var rows: some View {
        if scrolls {
            ScrollView {
                rowStack.padding(.vertical, Spacing.s)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        } else {
            rowStack
        }
    }

    private var rowStack: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Array(model.episodes.enumerated()), id: \.element.id) { index, episode in
                row(episode)
                    .modifier(FirstLoadStagger(index: index, enabled: !hasSwitchedSeason))
            }
        }
    }

    private func row(_ episode: Episode) -> some View {
        let watched = model.isWatched(episode)
        return Button {
            onPlay(episode, false)
        } label: {
            EpisodeRow(
                episode: episode,
                isFocused: focus.wrappedValue == .episode(episode.id),
                fraction: model.fraction(episode),
                isWatched: watched
            )
        }
        .buttonStyle(EpisodeRowButtonStyle())
        .focused(focus, equals: .episode(episode.id))
        .contextMenu {
            Button {
                onPlay(episode, true)
            } label: {
                Label(String(localized: "detail.playFromBeginning", defaultValue: "Play from Beginning", bundle: .module),
                      systemImage: "backward.end.fill")
            }
            Button {
                Task { await model.setWatched(episode, !watched) }
            } label: {
                if watched {
                    Label(String(localized: "detail.markUnwatched", defaultValue: "Mark as Unwatched", bundle: .module), systemImage: "eye.slash")
                } else {
                    Label(String(localized: "detail.markWatched", defaultValue: "Mark as Watched", bundle: .module), systemImage: "eye")
                }
            }
        }
        .id(episode.id)
    }

    /// Slides in the direction of the change and fades; a plain crossfade with Reduce Motion.
    private var seasonTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let distance: CGFloat = 80 * CGFloat(model.seasonDirection)
        return .asymmetric(
            insertion: .offset(x: distance).combined(with: .opacity),
            removal: .offset(x: -distance).combined(with: .opacity)
        )
    }

    // MARK: - Loading

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Capsule()
                .fill(.white.opacity(0.08))
                .frame(width: 180, height: 44)
                .padding(.vertical, Spacing.s)
            ForEach(0..<Self.skeletonRows, id: \.self) { _ in
                SkeletonEpisodeRow()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "detail.loadingEpisodes", defaultValue: "Loading episodes", bundle: .module))
    }
}

private struct FirstLoadStagger: ViewModifier {
    let index: Int
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.staggeredAppearance(index: index)
        } else {
            content
        }
    }
}

/// Placeholder row with the shimmer loop (static under Reduce Motion).
private struct SkeletonEpisodeRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            bar(width: 40, height: 32)
            VStack(alignment: .leading, spacing: Spacing.s) {
                bar(width: 320, height: 24)
                bar(width: nil, height: 18)
                bar(width: 420, height: 18)
            }
        }
        .padding(Spacing.m)
        .opacity(dimmed ? 0.5 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Motion.shimmer) { dimmed = true }
        }
    }

    private func bar(width: CGFloat?, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.white.opacity(0.08))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}
