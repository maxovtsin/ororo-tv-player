import OroroCore
import OroroDesign
import SwiftUI

/// Split detail for a show or movie (spec: Screens → Detail, direction B).
///
/// tvOS: fixed info column on the left, season pills + episode list on the right, over a full-bleed backdrop.
/// iOS: the same pieces stacked in one scroll view.
public struct DetailScreen: View {
    private let id: TitleID
    @Environment(\.appEnvironment) private var environment
    @Environment(AppSession.self) private var session

    public init(id: TitleID) {
        self.id = id
    }

    public var body: some View {
        DetailContent(id: id, catalog: session.catalog, environment: environment, session: session)
            .id(id)
    }
}

/// What can hold focus on the detail screen.
enum DetailFocus: Hashable {
    case primary, trailer, myList, subtitles, retry
    case season(Int), episode(Int)

    var isButton: Bool {
        switch self {
        case .primary, .trailer, .myList, .subtitles: true
        case .retry, .season, .episode: false
        }
    }
}

private struct DetailContent: View {
    @State private var model: DetailViewModel
    @Environment(TabRouter.self) private var router
    @Environment(PlaybackLauncher.self) private var launcher
    @Environment(\.detailZoomNamespace) private var zoomNamespace

    @FocusState private var focus: DetailFocus?
    /// Left column: where focus returns when moving left.
    @State private var lastButton: DetailFocus = .primary
    /// Right column: the last focused row, where focus returns when moving right.
    @State private var lastEpisode: Int?
    /// Set once the backdrop is in the image cache, so it never fades in from an empty frame.
    @State private var backdropURL: URL?

    private static let backdropSize = CGSize(width: 1920, height: 1080)

    init(id: TitleID, catalog: Catalog?, environment: AppEnvironment, session: AppSession) {
        // The initial value is only used when the view is first created; building it is a dictionary lookup.
        _model = State(initialValue: DetailViewModel(id: id, catalog: catalog, environment: environment, session: session))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            BackdropView(url: backdropURL, dim: model.id.kind == .movie ? .detailLight : .detail)
                .ignoresSafeArea()
            layout
        }
        .background(Color.black)
        .detailZoomDestination(id: router.zoomSourceID ?? "", in: router.zoomSourceID == nil ? nil : zoomNamespace)
        .defaultFocus($focus, .primary)
        .onChange(of: focus) { _, newValue in
            remember(newValue)
        }
        .onChange(of: launcher.active == nil) { wasIdle, isIdle in
            if isIdle, !wasIdle { playerDismissed() }
        }
        .task { await model.appear() }
        .task { await model.observeLibrary() }
        .task(id: model.title?.backdropURL) { await preloadBackdrop() }
    }

    // MARK: - Layout

    @ViewBuilder private var layout: some View {
        #if os(tvOS)
        HStack(alignment: .top, spacing: Spacing.xl) {
            infoColumn
                .frame(width: 760, alignment: .topLeading)
                .focusSection()
                .defaultFocus($focus, lastButton, priority: .userInitiated)
            rightColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .focusSection()
                .defaultFocus($focus, preferredEpisode.map(DetailFocus.episode), priority: .userInitiated)
        }
        .padding(.horizontal, Spacing.screenEdge)
        .padding(.vertical, Spacing.xl)
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                infoColumn
                rightColumn
            }
            .padding(.horizontal, Spacing.screenEdge)
            .padding(.vertical, Spacing.l)
        }
        #endif
    }

    private var infoColumn: some View {
        DetailInfoColumn(
            model: model,
            focus: $focus,
            onPlay: { model.playPrimary(launcher: launcher) }
        )
    }

    @ViewBuilder private var rightColumn: some View {
        switch model.id.kind {
        case .show:
            EpisodeList(
                model: model,
                focus: $focus,
                scrolls: Self.listScrolls,
                onPlay: { episode, startOver in model.play(episode, startOver: startOver, launcher: launcher) }
            )
        case .movie:
            if model.load == .failed {
                DetailFailureView(focus: $focus) { Task { await model.retry() } }
            } else {
                Color.clear
            }
        }
    }

    private static var listScrolls: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }

    /// Last focused row when it is in the selected season, else the resume episode, else the first row.
    private var preferredEpisode: Int? {
        if let lastEpisode, model.episodes.contains(where: { $0.id == lastEpisode }) { return lastEpisode }
        return model.episodeForFocus
    }

    // MARK: - Behaviour

    private func remember(_ newValue: DetailFocus?) {
        guard let newValue else { return }
        if newValue.isButton { lastButton = newValue }
        if case .episode(let id) = newValue { lastEpisode = id }
    }

    /// After autoplay the last played episode may be in another season: switch to it and focus it.
    private func playerDismissed() {
        Task {
            await model.refreshLibrary()
            guard let episodeID = model.returnedFromPlayer(lastPlayed: launcher.lastPlayed) else { return }
            lastEpisode = episodeID
            await Task.yield()
            focus = .episode(episodeID)
        }
    }

    private func preloadBackdrop() async {
        guard let url = model.title?.backdropURL else {
            backdropURL = nil
            return
        }
        await ImageCache.preload(url, pointSize: Self.backdropSize)
        guard !Task.isCancelled else { return }
        backdropURL = url
    }
}

/// Inline error for the right column; the left column stays usable.
struct DetailFailureView: View {
    var focus: FocusState<DetailFocus?>.Binding
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(String(localized: "detail.error", defaultValue: "Couldn't load this title.", bundle: .module))
                .font(Typography.headline)
                .foregroundStyle(Palette.textPrimary)
            ActionButton(String(localized: "detail.retry", defaultValue: "Retry", bundle: .module), systemImage: "arrow.clockwise",
                         action: onRetry)
                .focused(focus, equals: .retry)
        }
        .padding(.top, Spacing.l)
    }
}

#if DEBUG
/// Canned details so the previews show a filled screen.
private struct DetailPreviewDetails: DetailProviding {
    static let show = Title(
        id: TitleID(kind: .show, id: 1), name: "MobLand",
        desc: "Power is up for grabs as the Harrigans and Stevensons, two warring London crime families, clash in a "
            + "kill-or-be-killed battle that threatens to topple empires and end lives.",
        imdbRating: 8.3, year: 2025, genres: ["Crime", "Drama"], countries: ["GB", "US"], ended: false,
        newestVideo: Date().addingTimeInterval(-2 * 86_400)
    )
    static let movie = Title(
        id: TitleID(kind: .movie, id: 2), name: "The Last Lantern", desc: "A lighthouse keeper finds a letter from the future.",
        imdbRating: 7.4, year: 2021, genres: ["Drama"], countries: ["FR"], lengthMinutes: 128, resolution: .hd
    )

    func show(id: Int) async throws -> ShowDetail {
        let names = ["Stick or Twist", "Jigsaw Puzzle", "Plan B", nil, "Blood Ties"]
        let episodes = [1, 2].flatMap { season in
            names.enumerated().map { offset, name in
                Episode(id: season * 100 + offset + 1, showID: 1, name: name,
                        plot: "Harry has to make a problem vanish after a night out goes awry for the sons of two warring families.",
                        season: season, number: offset + 1, airdate: Date(timeIntervalSince1970: 1_743_292_800 + Double(offset) * 604_800),
                        resolution: .hd, qualities: ["240p", "720p"])
            }
        }
        return ShowDetail(title: Self.show, seasonCount: 2, episodes: episodes)
    }

    func movie(id: Int) async throws -> MovieDetail {
        MovieDetail(title: Self.movie, trailerYouTubeID: "preview", qualities: ["480p", "1080p"], subtitleLanguages: ["en", "ru", "es"],
                    playback: nil)
    }

    func episode(id: Int) async throws -> EpisodeDetail {
        EpisodeDetail(episode: Episode(id: id, showID: 0, season: 1, number: 1), showName: "MobLand",
                      subtitleLanguages: ["en", "ru", "es", "de"], playback: nil)
    }

    func moviePlayback(id: Int) async throws -> MovieDetail { throw APIError.offline }
    func episodePlayback(id: Int) async throws -> EpisodeDetail { throw APIError.offline }
    func clear() async {}

    static func environment() -> AppEnvironment {
        let base = AppEnvironment.preview()
        return AppEnvironment(api: base.api, catalog: base.catalog, library: base.library, details: DetailPreviewDetails(),
                              credentials: base.credentials, newEpisodes: base.newEpisodes)
    }
}

#Preview("Detail · show") {
    let environment = DetailPreviewDetails.environment()
    DetailScreen(id: TitleID(kind: .show, id: 1))
        .environment(\.appEnvironment, environment)
        .environment(AppSession(environment: environment))
        .environment(TabRouter())
        .environment(PlaybackLauncher())
}

#Preview("Detail · movie") {
    let environment = DetailPreviewDetails.environment()
    DetailScreen(id: TitleID(kind: .movie, id: 2))
        .environment(\.appEnvironment, environment)
        .environment(AppSession(environment: environment))
        .environment(TabRouter())
        .environment(PlaybackLauncher())
}

#Preview("Detail · error") {
    let environment = AppEnvironment.preview()
    DetailScreen(id: TitleID(kind: .show, id: 1))
        .environment(\.appEnvironment, environment)
        .environment(AppSession(environment: environment))
        .environment(TabRouter())
        .environment(PlaybackLauncher())
}
#endif
