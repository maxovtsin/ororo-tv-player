import Foundation
import OroroCore
import OroroDesign
@testable import OroroFeatures
import OroroTestSupport
import Testing

@Suite @MainActor struct DetailViewModelTests {
    // MARK: - Fixtures

    private nonisolated static let showID = 101
    private nonisolated static let movieID = 1001
    private static let show = TitleID(kind: .show, id: showID)
    private static let movie = TitleID(kind: .movie, id: movieID)
    private static let locale = Locale(identifier: "en_US")

    /// Samples episode id scheme: showID * 10_000 + season * 100 + number.
    private static func episodeID(season: Int, number: Int, showID: Int = showID) -> Int {
        showID * 10_000 + season * 100 + number
    }

    /// Records what the view model reports to the session.
    @MainActor final class Reports {
        var errors: [any Error] = []
    }

    private struct Harness {
        let model: DetailViewModel
        let store: InMemoryLibraryStore
        let details: FakeDetails
        let reports: Reports
    }

    private func makeHarness(
        _ id: TitleID,
        library: Library = Library(),
        catalog: Catalog = Samples.catalog,
        details: FakeDetails? = nil,
        now: Date = Samples.now
    ) -> Harness {
        let store = InMemoryLibraryStore(library)
        let details = details ?? FakeDetails(catalog: catalog)
        let environment = AppEnvironment(
            api: FakeAPI(catalog: catalog), catalog: FakeCatalog(current: catalog), library: store, details: details,
            credentials: InMemoryCredentialStore(Samples.credentials), newEpisodes: FakeNewEpisodes()
        )
        let session = AppSession(environment: environment)
        let reports = Reports()
        let model = DetailViewModel(
            id: id, catalog: catalog, environment: environment, session: session,
            now: { now }, locale: Self.locale, report: { reports.errors.append($0) }
        )
        return Harness(model: model, store: store, details: details, reports: reports)
    }

    private static func episodeProgress(season: Int, number: Int, position: TimeInterval = 600, duration: TimeInterval = 2_400) -> ProgressEntry {
        ProgressEntry(
            playable: PlayableID(kind: .episode, id: episodeID(season: season, number: number)),
            showID: showID, season: season, number: number, episodeName: "Episode \(number)",
            position: position, duration: duration, updatedAt: Samples.now
        )
    }

    private static func upNext(season: Int, number: Int) -> [Int: UpNextEntry] {
        [showID: UpNextEntry(ref: EpisodeRef(episodeID: episodeID(season: season, number: number), season: season, number: number),
                             setAt: Samples.now)]
    }

    // MARK: - Tests

    @Test func showsCatalogDataBeforeNetwork() async {
        let harness = makeHarness(Self.show)
        #expect(harness.model.title?.name == "Night Harbor")
        #expect(harness.model.load == .loading)
        #expect(harness.model.episodes.isEmpty)
        #expect(harness.model.metadata.contains(.text("Ongoing")))
        #expect(await harness.details.totalCalls == 0)
    }

    @Test func loadsShowSeasonsAndSelectsResumeSeason() async {
        let harness = makeHarness(Self.show, library: Library(progress: [Self.episodeProgress(season: 2, number: 3)]))
        await harness.model.appear()
        #expect(harness.model.load == .loaded)
        #expect(harness.model.seasons == [1, 2])
        #expect(harness.model.resume == EpisodeRef(episodeID: Self.episodeID(season: 2, number: 3), season: 2, number: 3))
        #expect(harness.model.selectedSeason == 2)
        #expect(harness.model.episodes.map(\.id) == (1...5).map { Self.episodeID(season: 2, number: $0) })
    }

    @Test func selectsFirstSeasonWithoutProgress() async {
        let harness = makeHarness(Self.show)
        await harness.model.appear()
        #expect(harness.model.resume == nil)
        #expect(harness.model.selectedSeason == 1)
        #expect(harness.model.episodes.map(\.season) == [1, 1, 1, 1, 1])
    }

    @Test func selectSeasonFiltersEpisodes() async {
        let title = Samples.catalog.title(Self.show)!
        let episodes = Samples.episodes(showID: Self.showID, seasons: [0: 2, 1: 3, 2: 4])
        let details = FakeDetails()
        await details.configure { $0.showResults[Self.showID] = .success(ShowDetail(title: title, seasonCount: 2, episodes: episodes)) }
        let harness = makeHarness(Self.show, details: details)
        await harness.model.appear()
        #expect(harness.model.seasons == [1, 2, 0])
        harness.model.selectSeason(2)
        #expect(harness.model.selectedSeason == 2)
        #expect(harness.model.episodes.map(\.number) == [1, 2, 3, 4])
        harness.model.selectSeason(0)
        #expect(harness.model.episodes.map(\.id) == [Self.episodeID(season: 0, number: 1), Self.episodeID(season: 0, number: 2)])
        #expect(DetailViewModel.seasonTitle(0) == "Specials")
        #expect(DetailViewModel.seasonTitle(2) == "Season 2")
        harness.model.selectSeason(7)
        #expect(harness.model.selectedSeason == 0, "unknown seasons are ignored")
    }

    @Test func primaryButtonTitleForEachState() async {
        let freshMovie = makeHarness(Self.movie)
        await freshMovie.model.appear()
        #expect(freshMovie.model.primaryButtonTitle == "Play")

        let movieProgress = ProgressEntry(playable: PlayableID(kind: .movie, id: Self.movieID), position: 600, duration: 6_000,
                                          updatedAt: Samples.now)
        let resumingMovie = makeHarness(Self.movie, library: Library(progress: [movieProgress]))
        await resumingMovie.model.appear()
        #expect(resumingMovie.model.primaryButtonTitle == "Resume")

        let freshShow = makeHarness(Self.show)
        #expect(freshShow.model.primaryButtonTitle == "Play", "before the episodes arrive")
        await freshShow.model.appear()
        #expect(freshShow.model.primaryButtonTitle == "Play S1 E1")

        let resumingShow = makeHarness(Self.show, library: Library(progress: [Self.episodeProgress(season: 2, number: 3)]))
        await resumingShow.model.appear()
        #expect(resumingShow.model.primaryButtonTitle == "Resume S2 E3")

        let upNextShow = makeHarness(Self.show, library: Library(upNext: Self.upNext(season: 2, number: 4)))
        await upNextShow.model.appear()
        #expect(upNextShow.model.resume == EpisodeRef(episodeID: Self.episodeID(season: 2, number: 4), season: 2, number: 4))
        #expect(upNextShow.model.primaryButtonTitle == "Play S2 E4")
    }

    @Test func playPrimaryTargets() async {
        let launcher = PlaybackLauncher()
        let movie = makeHarness(Self.movie)
        await movie.model.appear()
        movie.model.playPrimary(launcher: launcher)
        #expect(launcher.active?.target == .movie(Self.movieID))
        #expect(launcher.active?.startOver == false)

        let show = makeHarness(Self.show, library: Library(progress: [Self.episodeProgress(season: 2, number: 3)]))
        await show.model.appear()
        show.model.playPrimary(launcher: launcher)
        #expect(launcher.active?.target == .show(Self.showID))
    }

    @Test func playEpisodeStartOverFlag() async throws {
        let launcher = PlaybackLauncher()
        let harness = makeHarness(Self.show)
        await harness.model.appear()
        let episode = try #require(harness.model.episodes.dropFirst().first)
        harness.model.play(episode, startOver: false, launcher: launcher)
        #expect(launcher.active?.target == .episode(id: Self.episodeID(season: 1, number: 2), showID: Self.showID))
        #expect(launcher.active?.startOver == false)
        harness.model.play(episode, startOver: true, launcher: launcher)
        #expect(launcher.active?.startOver == true)
    }

    @Test func metadataForMovie() async {
        let title = Samples.movie(Self.movieID, imdbRating: 8.3, year: 2025, lengthMinutes: 155, resolution: .hd)
        let catalog = Catalog(shows: [], movies: [title], fetchedAt: Samples.now)
        let harness = makeHarness(Self.movie, catalog: catalog)
        #expect(harness.model.metadata == [.badge(.imdb(8.3)), .text("2025"), .text("2h 35m"), .badge(.hd)])

        let sdTitle = Samples.movie(Self.movieID, imdbRating: nil, year: nil, lengthMinutes: 45, resolution: .sd)
        let sd = makeHarness(Self.movie, catalog: Catalog(shows: [], movies: [sdTitle], fetchedAt: Samples.now))
        #expect(sd.model.metadata == [.text("45m")])
    }

    @Test func metadataForShowAddsNewEpisodeAgoWithin14Days() async {
        let recent = Samples.show(Self.showID, newestVideo: Samples.now.addingTimeInterval(-2 * Samples.day), imdbRating: 8.3, year: 2025)
        let recentHarness = makeHarness(Self.show, catalog: Catalog(shows: [recent], movies: [], fetchedAt: Samples.now))
        await recentHarness.model.appear()
        #expect(recentHarness.model.metadata == [
            .badge(.imdb(8.3)), .text("2025"), .text("2 Seasons"), .text("Ongoing"), .badge(.hd), .text("new ep. 2 days ago")
        ])

        let old = Samples.show(Self.showID, newestVideo: Samples.now.addingTimeInterval(-20 * Samples.day), imdbRating: nil, year: 2019, ended: true)
        let oldCatalog = Catalog(shows: [old], movies: [], fetchedAt: Samples.now)
        let sdEpisodes = Samples.episodes(showID: Self.showID, seasons: [1: 2]).map { episode in
            var episode = episode
            episode.resolution = .sd
            return episode
        }
        let details = FakeDetails(catalog: oldCatalog)
        await details.configure { $0.showResults[Self.showID] = .success(ShowDetail(title: old, seasonCount: nil, episodes: sdEpisodes)) }
        let oldHarness = makeHarness(Self.show, catalog: oldCatalog, details: details)
        await oldHarness.model.appear()
        #expect(oldHarness.model.metadata == [.text("2019"), .text("1 Season"), .text("Ended")])
    }

    @Test func subtitleLanguagesComeFromEpisodePrefetch() async {
        let resumeID = Self.episodeID(season: 2, number: 3)
        let details = FakeDetails()
        let episode = Episode(id: resumeID, showID: 0, season: 2, number: 3)
        let detail = EpisodeDetail(episode: episode, showName: nil, subtitleLanguages: ["en", "fr", "de"], playback: nil)
        await details.configure { $0.episodeResults[resumeID] = .success(detail) }
        let harness = makeHarness(Self.show, library: Library(progress: [Self.episodeProgress(season: 2, number: 3)]), details: details)
        #expect(harness.model.subtitleLanguages == nil)
        await harness.model.appear()
        #expect(harness.model.subtitleLanguages == ["en", "fr", "de"])
        #expect(await details.episodeCalls == 1)
        #expect(await details.episodePlaybackCalls == 0)

        let fresh = makeHarness(Self.show)
        await fresh.model.appear()
        #expect(fresh.model.subtitleLanguages == ["en", "ru"], "first episode's languages without progress")

        let movie = makeHarness(Self.movie)
        await movie.model.appear()
        #expect(movie.model.subtitleLanguages == ["en", "ru"])
        #expect(movie.model.trailerID == "trailer-\(Self.movieID)")
    }

    @Test func qualityTextFromEpisodes() async {
        let title = Samples.catalog.title(Self.show)!
        var episodes = Samples.episodes(showID: Self.showID, seasons: [1: 3])
        episodes[0].qualities = ["480p"]
        episodes[1].qualities = ["1080p", "240p"]
        episodes[2].qualities = []
        let detail = ShowDetail(title: title, seasonCount: 1, episodes: episodes)
        let details = FakeDetails()
        await details.configure { $0.showResults[Self.showID] = .success(detail) }
        let harness = makeHarness(Self.show, details: details)
        #expect(harness.model.qualityText == nil)
        await harness.model.appear()
        #expect(harness.model.qualityText == "240p–1080p")

        let movie = makeHarness(Self.movie)
        await movie.model.appear()
        #expect(movie.model.qualityText == "480p–1080p")
    }

    @Test func failedLoadReportsAndAllowsRetry() async {
        let details = FakeDetails()
        await details.configure { $0.error = .offline }
        let harness = makeHarness(Self.show, details: details)
        await harness.model.appear()
        #expect(harness.model.load == .failed)
        #expect(harness.model.title?.name == "Night Harbor", "the left column keeps the catalog data")
        #expect(harness.reports.errors.compactMap { $0 as? APIError } == [.offline])

        await details.configure { $0.error = nil }
        await harness.model.retry()
        #expect(harness.model.load == .loaded)
        #expect(harness.model.episodes.count == 5)
        #expect(harness.reports.errors.count == 1)
    }

    @Test func unauthorizedIsReportedToSession() async {
        let details = FakeDetails()
        await details.configure { $0.error = .unauthorized }
        let harness = makeHarness(Self.movie, details: details)
        await harness.model.appear()
        #expect(harness.model.load == .failed)
        #expect(harness.reports.errors.compactMap { $0 as? APIError } == [.unauthorized])
    }

    @Test func toggleListAndMarkWatchedUpdateLibrary() async throws {
        let harness = makeHarness(Self.show, library: Library(progress: [Self.episodeProgress(season: 1, number: 2)]))
        await harness.model.appear()
        #expect(harness.model.isInList == false)

        await harness.model.toggleList()
        #expect(harness.model.isInList)
        #expect(await harness.store.library.myList.map(\.title) == [Self.show])
        #expect(await harness.store.library.followed[Self.showID] != nil)

        let episode = try #require(harness.model.episodes.first { $0.number == 2 })
        #expect(harness.model.fraction(episode) == 0.25)
        await harness.model.setWatched(episode, true)
        #expect(harness.model.isWatched(episode))
        #expect(harness.model.fraction(episode) == nil)
        #expect(await harness.store.library.watchedEpisodes == [episode.id])
        let next = EpisodeRef(episodeID: Self.episodeID(season: 1, number: 3), season: 1, number: 3)
        #expect(await harness.store.library.upNext[Self.showID]?.ref == next, "marking the resume episode advances up next")
        #expect(harness.model.resume == next)

        await harness.model.setWatched(episode, false)
        #expect(harness.model.isWatched(episode) == false)
        #expect(await harness.store.library.watchedEpisodes.isEmpty)

        await harness.model.setPreferredSubtitle("ru")
        #expect(harness.model.preferredSubtitle == "ru")
        #expect(await harness.store.library.preferences.subtitleLanguage == "ru")
        await harness.model.setPreferredSubtitle(nil)
        #expect(await harness.store.library.preferences.subtitleLanguage == nil)

        await harness.model.toggleList()
        #expect(harness.model.isInList == false)
    }

    @Test func returnedFromPlayerSwitchesSeason() async {
        let harness = makeHarness(Self.show)
        await harness.model.appear()
        #expect(harness.model.selectedSeason == 1)
        let target = Self.episodeID(season: 2, number: 3)
        #expect(harness.model.returnedFromPlayer(lastPlayed: PlayableID(kind: .episode, id: target)) == target)
        #expect(harness.model.selectedSeason == 2)
        #expect(harness.model.episodes.contains { $0.id == target })
        #expect(harness.model.returnedFromPlayer(lastPlayed: nil) == nil)
        #expect(harness.model.returnedFromPlayer(lastPlayed: PlayableID(kind: .episode, id: 999)) == nil)
        #expect(harness.model.selectedSeason == 2)

        let movie = makeHarness(Self.movie)
        await movie.model.appear()
        #expect(movie.model.returnedFromPlayer(lastPlayed: PlayableID(kind: .movie, id: Self.movieID)) == nil)
    }

    @Test func showWithNoEpisodes() async {
        let title = Samples.catalog.title(Self.show)!
        let details = FakeDetails()
        await details.configure { $0.showResults[Self.showID] = .success(ShowDetail(title: title, seasonCount: 0, episodes: [])) }
        let harness = makeHarness(Self.show, details: details)
        await harness.model.appear()
        #expect(harness.model.load == .loaded)
        #expect(harness.model.seasons.isEmpty)
        #expect(harness.model.selectedSeason == nil)
        #expect(harness.model.episodes.isEmpty)
        #expect(harness.model.qualityText == nil)
        #expect(harness.model.primaryButtonTitle == "Play")
        #expect(await details.episodeCalls == 0)
        #expect(DetailViewModel.episodeTitle(Episode(id: 1, showID: Self.showID, name: nil, season: 1, number: 4)) == "Episode 4")
        #expect(DetailViewModel.episodeTitle(Episode(id: 1, showID: Self.showID, name: " ", season: 1, number: nil)) == "Episode")
    }
}
