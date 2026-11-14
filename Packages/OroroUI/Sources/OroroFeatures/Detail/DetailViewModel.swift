import Foundation
import Observation
import OroroCore
import OroroDesign

/// State of the split detail screen (spec: Screens → Detail).
///
/// Opens instantly from catalog data; `appear()` fills in the show or movie detail, then (shows) prefetches the
/// resume/first episode's detail for the subtitle languages. Library-derived state (My List, progress, resume target,
/// subtitle preference) follows `observeLibrary()`.
@MainActor @Observable final class DetailViewModel {
    enum Load: Equatable { case loading, loaded, failed }

    let id: TitleID
    /// From the catalog immediately; replaced by the detail response's title.
    private(set) var title: Title?
    private(set) var load: Load = .loading
    private(set) var seasons: [Int] = []
    private(set) var selectedSeason: Int?
    /// Episodes of the selected season, in display order.
    private(set) var episodes: [Episode] = []
    /// In-progress episode, else up-next (shows only).
    private(set) var resume: EpisodeRef?
    private(set) var subtitleLanguages: [String]?
    private(set) var qualityText: String?
    private(set) var trailerID: String?
    private(set) var isInList = false
    private(set) var preferredSubtitle: String?
    /// +1 when the last season switch moved right (later season), -1 when it moved left; drives the slide direction.
    private(set) var seasonDirection = 1

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let report: @MainActor (any Error) -> Void
    private var library = Library()
    private var allEpisodes: [Episode] = []
    private var seasonCount: Int?

    init(
        id: TitleID,
        catalog: Catalog?,
        environment: AppEnvironment,
        session: AppSession,
        now: @escaping () -> Date = Date.init,
        locale: Locale = .current,
        report: (@MainActor (any Error) -> Void)? = nil
    ) {
        self.id = id
        self.environment = environment
        self.now = now
        self.locale = locale
        self.report = report ?? { error in session.report(error) }
        title = catalog?.title(id)
        preferredSubtitle = library.preferences.subtitleLanguage
    }

    // MARK: - Derived

    /// IMDb · year · runtime (movies) or seasons · Ongoing/Ended (shows) · HD; shows add "new ep. … ago" within 14 days.
    var metadata: [MetadataItem] {
        guard let title else { return [] }
        var items: [MetadataItem] = []
        if let rating = title.imdbRating { items.append(.badge(.imdb(rating))) }
        if let year = title.year { items.append(.text(String(year))) }
        switch id.kind {
        case .movie:
            if let minutes = title.lengthMinutes, minutes > 0 { items.append(.text(Display.runtime(minutes: minutes, locale: locale))) }
            if title.resolution == .hd { items.append(.badge(.hd)) }
        case .show:
            if let count = seasonCount ?? (allEpisodes.isEmpty ? nil : seasons.filter { $0 != 0 }.count), count > 0 {
                items.append(.text(String(localized: "detail.seasonCount", defaultValue: "\(count) Seasons", bundle: .module, locale: locale)))
            }
            if let ended = title.ended {
                items.append(.text(ended
                    ? String(localized: "detail.status.ended", defaultValue: "Ended", bundle: .module, locale: locale)
                    : String(localized: "detail.status.ongoing", defaultValue: "Ongoing", bundle: .module, locale: locale)))
            }
            if allEpisodes.contains(where: { $0.resolution == .hd }) { items.append(.badge(.hd)) }
            if let newest = title.newestVideo, let ago = Display.newEpisodeAgo(newest, now: now(), locale: locale) {
                items.append(.text(String(localized: "detail.newEpisodeAgo", defaultValue: "new ep. \(ago)", bundle: .module, locale: locale)))
            }
        }
        return items
    }

    /// "Play", "Resume" (movies); "Play S1 E1", "Resume S2 E3", "Play S2 E4" for up-next (shows).
    var primaryButtonTitle: String {
        switch id.kind {
        case .movie:
            return library.resumePosition(PlayableID(kind: .movie, id: id.id)) == nil ? Self.playTitle : Self.resumeTitle
        case .show:
            if let resume {
                let label = Display.episodeLabel(season: resume.season, number: resume.number)
                let inProgress = library.progress.contains { $0.playable == PlayableID(kind: .episode, id: resume.episodeID) }
                return inProgress
                    ? String(localized: "detail.resumeEpisode", defaultValue: "Resume \(label)", bundle: .module)
                    : String(localized: "detail.playEpisode", defaultValue: "Play \(label)", bundle: .module)
            }
            if let first = EpisodeOrdering.first(in: allEpisodes), let number = first.number {
                let label = Display.episodeLabel(season: first.season, number: number)
                return String(localized: "detail.playEpisode", defaultValue: "Play \(label)", bundle: .module)
            }
            return Self.playTitle
        }
    }

    /// Where focus lands when moving into the episode list for the first time: the resume episode when it is in the
    /// selected season, else the first row.
    var episodeForFocus: Int? {
        if let resume, episodes.contains(where: { $0.id == resume.episodeID }) { return resume.episodeID }
        return episodes.first?.id
    }

    func fraction(_ episode: Episode) -> Double? {
        library.fraction(PlayableID(kind: .episode, id: episode.id))
    }

    func isWatched(_ episode: Episode) -> Bool {
        library.isWatched(PlayableID(kind: .episode, id: episode.id))
    }

    // MARK: - Loading

    func appear() async {
        apply(await environment.library.snapshot())
        guard load != .loaded else { return }
        load = .loading
        do {
            switch id.kind {
            case .show: try await loadShow()
            case .movie: try await loadMovie()
            }
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            report(error)
            load = .failed
        }
    }

    func retry() async {
        load = .loading
        await appear()
    }

    /// Keeps library-derived state current. Runs until cancelled (the view's `.task`).
    func observeLibrary() async {
        let updates = await environment.library.updates()
        apply(await environment.library.snapshot())
        for await library in updates {
            apply(library)
        }
    }

    /// Re-reads the library (e.g. after the player was dismissed).
    func refreshLibrary() async {
        apply(await environment.library.snapshot())
    }

    private func loadShow() async throws {
        let detail = try await environment.details.show(id: id.id)
        title = detail.title
        seasonCount = detail.seasonCount
        allEpisodes = detail.episodes
        seasons = EpisodeOrdering.seasons(detail.episodes)
        selectedSeason = EpisodeOrdering.initialSeason(episodes: detail.episodes, resume: resume)
        episodes = selectedSeason.map { EpisodeOrdering.episodes(detail.episodes, season: $0) } ?? []
        qualityText = EpisodeOrdering.qualityRange(detail.episodes).map { Display.qualityRange(lowest: $0.lowest, highest: $0.highest) }
        load = .loaded
        await prefetchSubtitleLanguages()
    }

    private func loadMovie() async throws {
        let detail = try await environment.details.movie(id: id.id)
        title = detail.title
        trailerID = detail.trailerYouTubeID
        subtitleLanguages = detail.subtitleLanguages
        qualityText = Self.qualityText(detail.qualities)
        load = .loaded
    }

    /// The resume/first episode's detail carries the show's subtitle languages. Failures leave the footer without them.
    private func prefetchSubtitleLanguages() async {
        let target = resume.flatMap { ref in allEpisodes.first { $0.id == ref.episodeID } }
            ?? EpisodeOrdering.first(in: allEpisodes)
            ?? allEpisodes.first
        guard let target, let detail = try? await environment.details.episode(id: target.id) else { return }
        subtitleLanguages = detail.subtitleLanguages
    }

    // MARK: - Seasons

    func selectSeason(_ season: Int) {
        guard seasons.contains(season), season != selectedSeason else { return }
        if let current = selectedSeason, let from = seasons.firstIndex(of: current), let to = seasons.firstIndex(of: season) {
            seasonDirection = to >= from ? 1 : -1
        }
        selectedSeason = season
        episodes = EpisodeOrdering.episodes(allEpisodes, season: season)
    }

    /// The episode that was playing last, to focus after the player closes; switches season if needed.
    func returnedFromPlayer(lastPlayed: PlayableID?) -> Int? {
        guard let lastPlayed, lastPlayed.kind == .episode,
              let episode = allEpisodes.first(where: { $0.id == lastPlayed.id }) else { return nil }
        selectSeason(episode.season)
        return episode.id
    }

    // MARK: - Actions

    func playPrimary(launcher: PlaybackLauncher) {
        switch id.kind {
        case .movie: launcher.play(.movie(id.id))
        case .show: launcher.play(.show(id.id))
        }
    }

    func play(_ episode: Episode, startOver: Bool, launcher: PlaybackLauncher) {
        launcher.play(.episode(id: episode.id, showID: id.id), startOver: startOver)
    }

    func toggleList() async {
        let id = id, newestVideo = title?.newestVideo, now = now()
        await environment.library.update { $0.toggleMyList(id, newestVideo: newestVideo, now: now) }
        await refreshLibrary()
    }

    func setPreferredSubtitle(_ lang: String?) async {
        await environment.library.update { $0.preferences.subtitleLanguage = lang }
        await refreshLibrary()
    }

    /// Marking the resume episode watched moves up-next to the following episode (like finishing it in the player).
    func setWatched(_ episode: Episode, _ watched: Bool) async {
        let playable = PlayableID(kind: .episode, id: episode.id)
        guard watched else {
            await environment.library.update { $0.markUnwatched(playable) }
            await refreshLibrary()
            return
        }
        if episode.id == resume?.episodeID, let number = episode.number {
            let show = ShowContext(showID: id.id, season: episode.season, number: number, episodeName: episode.name,
                                   newestVideo: title?.newestVideo)
            let next = EpisodeOrdering.next(after: episode.id, in: allEpisodes).flatMap(EpisodeOrdering.ref)
            let now = now()
            await environment.library.update { $0.finish(playable, show: show, next: next, now: now) }
        } else {
            await environment.library.update { $0.markWatched(playable) }
        }
        await refreshLibrary()
    }

    // MARK: - Helpers

    private func apply(_ library: Library) {
        self.library = library
        isInList = library.isInMyList(id)
        preferredSubtitle = library.preferences.subtitleLanguage
        resume = id.kind == .show ? LibraryQueries.resumeTarget(showID: id.id, library: library) : nil
    }

    static var playTitle: String {
        String(localized: "detail.play", defaultValue: "Play", bundle: .module)
    }

    static var resumeTitle: String {
        String(localized: "detail.resume", defaultValue: "Resume", bundle: .module)
    }

    /// "Season 2"; season 0 is "Specials".
    static func seasonTitle(_ season: Int) -> String {
        season == 0
            ? String(localized: "detail.season.specials", defaultValue: "Specials", bundle: .module)
            : String(localized: "detail.season", defaultValue: "Season \(season)", bundle: .module)
    }

    /// The episode's name, else "Episode N".
    static func episodeTitle(_ episode: Episode) -> String {
        if let name = episode.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        if let number = episode.number {
            return String(localized: "detail.episode.unnamed", defaultValue: "Episode \(number)", bundle: .module)
        }
        return String(localized: "detail.episode.unnamedNoNumber", defaultValue: "Episode", bundle: .module)
    }

    /// "480p–1080p" from quality keys, ordered by their numeric value.
    static func qualityText(_ qualities: [String]) -> String? {
        let values = qualities.compactMap { quality in Int(quality.prefix { $0.isNumber }).map { (value: $0, label: quality) } }
        guard let lowest = values.min(by: { $0.value < $1.value }),
              let highest = values.max(by: { $0.value < $1.value }) else { return nil }
        return Display.qualityRange(lowest: lowest.label, highest: highest.label)
    }
}
