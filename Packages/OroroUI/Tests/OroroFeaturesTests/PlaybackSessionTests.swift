import Foundation
import OroroCore
@testable import OroroFeatures
import OroroTestSupport
import Synchronization
import Testing

@Suite @MainActor struct PlaybackSessionTests {
    // Samples show 101: seasons 1 and 2, five episodes each; id = 101 * 10_000 + season * 100 + number.
    static let s1e1 = 1_010_101, s1e2 = 1_010_102, s1e3 = 1_010_103, s1e4 = 1_010_104, s1e5 = 1_010_105
    static let s2e1 = 1_010_201, s2e3 = 1_010_203, s2e5 = 1_010_205
    static let movie = PlayableID(kind: .movie, id: 1001)

    // MARK: - Start

    @Test func movieStartsPlayingFromZero() async {
        let harness = Harness(.movie(1001))
        await harness.session.start()

        #expect(harness.session.phase == .playing)
        #expect(harness.session.current == Self.movie)
        #expect(harness.session.nextEpisode == nil)
        #expect(harness.engine.loads.count == 1)
        #expect(harness.engine.loads.first?.startAt == 0)
        #expect(harness.engine.loads.first?.playback.streamURL.absoluteString == "https://example.invalid/movies/1001/master.m3u8")
        #expect(harness.engine.playCount == 1)
        #expect(await harness.details.moviePlaybackCalls == 1)
    }

    @Test func showTargetResolvesResumeThenUpNextThenFirst() async {
        // In progress wins over up-next.
        var library = Library()
        library.recordProgress(PlayableID(kind: .episode, id: Self.s2e3),
                               show: ShowContext(showID: 101, season: 2, number: 3, episodeName: nil, newestVideo: nil),
                               position: 300, duration: 2400, now: Samples.now)
        library.upNext[101] = UpNextEntry(ref: EpisodeRef(episodeID: Self.s1e5, season: 1, number: 5), setAt: Samples.now)
        let resumed = Harness(.show(101), library: library)
        await resumed.session.start()
        #expect(resumed.session.current == PlayableID(kind: .episode, id: Self.s2e3))
        #expect(resumed.session.phase == .askResume(position: 300))

        // Up-next when nothing is in progress.
        var upNextOnly = Library()
        upNextOnly.upNext[101] = UpNextEntry(ref: EpisodeRef(episodeID: Self.s1e5, season: 1, number: 5), setAt: Samples.now)
        let upNext = Harness(.show(101), library: upNextOnly)
        await upNext.session.start()
        #expect(upNext.session.current == PlayableID(kind: .episode, id: Self.s1e5))
        #expect(upNext.session.phase == .playing)
        #expect(upNext.session.nextEpisode?.id == Self.s2e1)
        #expect(upNext.engine.loads.first?.playback.streamURL.absoluteString == "https://example.invalid/episodes/1010105/master.m3u8")

        // Otherwise the first episode.
        let first = Harness(.show(101))
        await first.session.start()
        #expect(first.session.current == PlayableID(kind: .episode, id: Self.s1e1))
        #expect(first.session.nextEpisode?.id == Self.s1e2)
        #expect(first.engine.loads.first?.startAt == 0)
    }

    @Test func asksResumeBetween60sAnd95Percent() async {
        let inRange = Harness(.movie(1001), library: Self.movieProgress(120, of: 1000))
        await inRange.session.start()
        #expect(inRange.session.phase == .askResume(position: 120))
        #expect(inRange.engine.loads.isEmpty)
        await inRange.session.chooseResume(true)
        #expect(inRange.session.phase == .playing)
        #expect(inRange.engine.loads.map(\.startAt) == [120])

        let declined = Harness(.movie(1001), library: Self.movieProgress(120, of: 1000))
        await declined.session.start()
        await declined.session.chooseResume(false)
        #expect(declined.engine.loads.map(\.startAt) == [0])

        for position: TimeInterval in [30, 960] {
            let outside = Harness(.movie(1001), library: Self.movieProgress(position, of: 1000))
            await outside.session.start()
            #expect(outside.session.phase == .playing)
            #expect(outside.engine.loads.map(\.startAt) == [0])
        }
    }

    @Test func startOverSkipsPrompt() async {
        let harness = Harness(.movie(1001), startOver: true, library: Self.movieProgress(120, of: 1000))
        await harness.session.start()
        #expect(harness.session.phase == .playing)
        #expect(harness.engine.loads.map(\.startAt) == [0])
    }

    @Test func missingURLIsNotPlayable() async {
        let harness = Harness(.movie(1001))
        let noURL = Samples.movieDetail(1001, withPlayback: false)!
        await harness.details.configure { $0.movieResults[1001] = .success(noURL) }
        await harness.session.start()
        #expect(harness.session.phase == .failed(.notPlayable))
        #expect(harness.engine.loads.isEmpty)
    }

    @Test func fetchErrorFailsAndReports() async {
        let harness = Harness(.episode(id: Self.s1e1, showID: 101))
        await harness.details.configure { $0.error = .offline }
        await harness.session.start()
        #expect(harness.session.phase == .failed(.fetch))
        #expect(harness.engine.loads.isEmpty)

        // Retry starts over once the network is back.
        await harness.details.configure { $0.error = nil }
        await harness.session.retry()
        #expect(harness.session.phase == .playing)
        #expect(harness.engine.loads.count == 1)
    }

    // MARK: - Progress

    @Test func progressWrittenAtMostEvery10s() async {
        let harness = Harness(.movie(1001))
        await harness.session.start()

        await harness.session.handle(.time(position: 5, duration: 1000))
        await harness.clock.advance(by: .seconds(9))
        await harness.session.handle(.time(position: 14, duration: 1000))
        #expect(await harness.library.updateCount == 0)

        await harness.clock.advance(by: .seconds(1))
        await harness.session.handle(.time(position: 15, duration: 1000))
        #expect(await harness.library.updateCount == 1)
        #expect(await harness.library.library.progress.first?.position == 15)

        await harness.clock.advance(by: .seconds(5))
        await harness.session.handle(.time(position: 20, duration: 1000))
        #expect(await harness.library.updateCount == 1)

        await harness.clock.advance(by: .seconds(5))
        await harness.session.handle(.time(position: 25, duration: 1000))
        #expect(await harness.library.updateCount == 2)
        let entry = await harness.library.library.progress.first
        #expect(entry?.playable == Self.movie)
        #expect(entry?.position == 25)
        #expect(entry?.duration == 1000)
    }

    @Test func pauseFlushes() async {
        let harness = Harness(.movie(1001))
        await harness.session.start()
        // Through the engine's event stream, as the real player delivers them.
        harness.engine.send(.time(position: 30, duration: 1000))
        harness.engine.send(.paused)
        #expect(await eventually { await harness.library.flushCount == 1 })
        #expect(await harness.library.library.progress.first?.position == 30)
    }

    @Test func marksWatchedOnceAt95Percent() async {
        let harness = Harness(.episode(id: Self.s1e1, showID: 101))
        await harness.session.start()

        await harness.session.handle(.time(position: 949, duration: 1000))
        #expect(await harness.library.library.watchedEpisodes.isEmpty)

        await harness.session.handle(.time(position: 950, duration: 1000))
        let library = await harness.library.library
        #expect(library.watchedEpisodes == [Self.s1e1])
        #expect(library.upNext[101]?.ref == EpisodeRef(episodeID: Self.s1e2, season: 1, number: 2))
        #expect(library.followed[101]?.started == true)
        let updates = await harness.library.updateCount

        await harness.clock.advance(by: .seconds(20))
        await harness.session.handle(.time(position: 980, duration: 1000))
        await harness.session.handle(.ended)
        #expect(await harness.library.updateCount == updates)
        #expect(await harness.library.library.progress.isEmpty)
    }

    @Test func nextActionAppearsInLast40s() async {
        let episode = Harness(.episode(id: Self.s1e1, showID: 101))
        await episode.session.start()
        await episode.session.handle(.time(position: 959, duration: 1000))
        #expect(episode.session.showsNextEpisodeAction == false)
        await episode.session.handle(.time(position: 960, duration: 1000))
        #expect(episode.session.showsNextEpisodeAction == true)

        let movie = Harness(.movie(1001))
        await movie.session.start()
        await movie.session.handle(.time(position: 990, duration: 1000))
        #expect(movie.session.showsNextEpisodeAction == false)
    }

    // MARK: - Next episode

    @Test func endStartsCountdownThenPlaysNext() async {
        let harness = Harness(.episode(id: Self.s1e1, showID: 101))
        await harness.session.start()
        await harness.session.handle(.time(position: 990, duration: 1000))
        await harness.session.handle(.ended)
        let next = EpisodeRef(episodeID: Self.s1e2, season: 1, number: 2)
        #expect(harness.session.phase == .countdown(next: next, secondsLeft: 5))

        await harness.clock.advance(by: .seconds(1))
        #expect(await eventually { harness.session.phase == .countdown(next: next, secondsLeft: 4) })

        await harness.clock.advance(by: .seconds(4))
        #expect(await eventually { harness.session.phase == .playing })
        #expect(harness.session.current == PlayableID(kind: .episode, id: Self.s1e2))
        #expect(harness.session.nextEpisode?.id == Self.s1e3)
        #expect(harness.session.showsNextEpisodeAction == false)
        #expect(harness.engine.loads.count == 2)
        #expect(harness.engine.loads.last?.startAt == 0)
        #expect(harness.engine.loads.last?.playback.streamURL.absoluteString == "https://example.invalid/episodes/1010102/master.m3u8")
        #expect(await harness.details.episodePlaybackCalls == 2)
    }

    @Test func cancelCountdownFinishes() async {
        let harness = Harness(.episode(id: Self.s1e1, showID: 101))
        await harness.session.start()
        await harness.session.handle(.ended)
        harness.session.cancelCountdown()
        #expect(harness.session.phase == .finished)

        await harness.clock.advance(by: .seconds(10))
        await settle()
        #expect(harness.session.phase == .finished)
        #expect(harness.engine.loads.count == 1)
    }

    @Test func autoplayOffFinishes() async {
        var library = Library()
        library.preferences.autoplayNext = false
        let harness = Harness(.episode(id: Self.s1e1, showID: 101), library: library)
        await harness.session.start()
        await harness.session.handle(.ended)
        #expect(harness.session.phase == .finished)
    }

    /// Spec: "After three consecutive autoplays with no remote input, ask Still watching?" (before the 4th).
    @Test func threeAutoplaysAskStillWatching() async {
        let harness = Harness(.episode(id: Self.s1e1, showID: 101))
        await harness.session.start()
        #expect(await harness.autoplay(to: Self.s1e2))
        #expect(await harness.autoplay(to: Self.s1e3))
        #expect(await harness.autoplay(to: Self.s1e4))

        await harness.session.handle(.ended)
        #expect(harness.session.phase == .stillWatching)
        #expect(harness.engine.loads.count == 4)

        await harness.session.confirmStillWatching(true)
        #expect(harness.session.phase == .playing)
        #expect(harness.session.current == PlayableID(kind: .episode, id: Self.s1e5))

        // The confirmation counts as input: the next end counts down again.
        await harness.session.handle(.ended)
        #expect(harness.session.phase == .countdown(next: EpisodeRef(episodeID: Self.s2e1, season: 2, number: 1), secondsLeft: 5))
    }

    @Test func declinedStillWatchingFinishes() async {
        let harness = Harness(.episode(id: Self.s1e1, showID: 101))
        await harness.session.start()
        #expect(await harness.autoplay(to: Self.s1e2))
        #expect(await harness.autoplay(to: Self.s1e3))
        #expect(await harness.autoplay(to: Self.s1e4))
        await harness.session.handle(.ended)
        await harness.session.confirmStillWatching(false)
        #expect(harness.session.phase == .finished)
        #expect(harness.engine.loads.count == 4)
    }

    @Test func userInputResetsAutoplayCount() async {
        let harness = Harness(.episode(id: Self.s1e1, showID: 101))
        await harness.session.start()
        #expect(await harness.autoplay(to: Self.s1e2))
        #expect(await harness.autoplay(to: Self.s1e3))
        #expect(await harness.autoplay(to: Self.s1e4))
        await harness.session.handle(.userInput)

        await harness.session.handle(.ended)
        #expect(harness.session.phase == .countdown(next: EpisodeRef(episodeID: Self.s1e5, season: 1, number: 5), secondsLeft: 5))
    }

    @Test func lastEpisodeFinishes() async {
        let harness = Harness(.episode(id: Self.s2e5, showID: 101))
        await harness.session.start()
        #expect(harness.session.nextEpisode == nil)
        await harness.session.handle(.time(position: 990, duration: 1000))
        #expect(harness.session.showsNextEpisodeAction == false)
        await harness.session.handle(.ended)
        #expect(harness.session.phase == .finished)
        #expect(await harness.library.library.watchedEpisodes == [Self.s2e5])
    }

}

// MARK: - Failures and subtitles

extension PlaybackSessionTests {

    @Test func streamFailureRefetchesOnceThenFails() async {
        let harness = Harness(.episode(id: Self.s1e1, showID: 101))
        await harness.session.start()
        await harness.session.handle(.time(position: 300, duration: 1000))

        await harness.session.handle(.failed)
        #expect(harness.session.phase == .playing)
        #expect(await harness.details.episodePlaybackCalls == 2)
        #expect(harness.engine.loads.map(\.startAt) == [0, 300])

        await harness.session.handle(.failed)
        #expect(harness.session.phase == .failed(.stream))
        #expect(harness.engine.loads.count == 2)

        await harness.session.retry()
        #expect(harness.session.phase == .playing)
        #expect(harness.engine.loads.map(\.startAt) == [0, 300, 300])
        #expect(await harness.details.episodePlaybackCalls == 3)
    }

    @Test func automaticRecoveryRearmsAfter10sOfPlayback() async {
        let harness = Harness(.movie(1001))
        await harness.session.start()
        await harness.session.handle(.time(position: 300, duration: 1000))
        await harness.session.handle(.failed)
        #expect(harness.engine.loads.map(\.startAt) == [0, 300])

        // 10 s of clock time playing after the recovery: the next failure gets its own automatic attempt.
        await harness.clock.advance(by: .seconds(10))
        await harness.session.handle(.time(position: 310, duration: 1000))
        await harness.session.handle(.failed)
        #expect(harness.session.phase == .playing)
        #expect(harness.engine.loads.map(\.startAt) == [0, 300, 310])

        // Less than 10 s after that recovery: no further automatic attempt.
        await harness.clock.advance(by: .seconds(9))
        await harness.session.handle(.time(position: 319, duration: 1000))
        await harness.session.handle(.failed)
        #expect(harness.session.phase == .failed(.stream))
        #expect(harness.engine.loads.count == 3)
        #expect(await harness.details.moviePlaybackCalls == 3)
    }

    @Test func loadFailureRetriesOnceThenFails() async {
        let once = Harness(.movie(1001), library: Self.movieProgress(120, of: 1000))
        once.engine.loadErrors = [APIError.server(status: 403)]
        await once.session.start()
        await once.session.chooseResume(true)
        #expect(once.session.phase == .playing)
        #expect(once.engine.loads.map(\.startAt) == [120, 120])
        #expect(await once.details.moviePlaybackCalls == 2)

        let twice = Harness(.movie(1001))
        twice.engine.loadErrors = [APIError.server(status: 403), APIError.server(status: 403)]
        await twice.session.start()
        #expect(twice.session.phase == .failed(.stream))
        #expect(twice.engine.loads.count == 2)
        #expect(twice.engine.playCount == 0)
    }

    @Test func stallOf30sIsAFailure() async {
        let harness = Harness(.movie(1001))
        await harness.session.start()
        await harness.session.handle(.time(position: 200, duration: 1000))

        await harness.session.handle(.stalled(seconds: 29))
        #expect(harness.engine.loads.count == 1)

        await harness.session.handle(.stalled(seconds: 30))
        #expect(harness.session.phase == .playing)
        #expect(harness.engine.loads.map(\.startAt) == [0, 200])
        #expect(await harness.details.moviePlaybackCalls == 2)
    }

    @Test func expiredURLRefetchedOnForeground() async {
        let harness = Harness(.movie(1001))
        await harness.session.start()
        await harness.session.handle(.time(position: 500, duration: 1000))

        harness.now.set(Samples.now.addingTimeInterval(30 * 3600))
        await harness.session.sceneBecameActive()
        #expect(harness.engine.loads.count == 1)

        harness.now.set(Samples.now.addingTimeInterval(30 * 3600 + 1))
        await harness.session.sceneBecameActive()
        #expect(harness.session.phase == .playing)
        #expect(harness.engine.loads.map(\.startAt) == [0, 500])
        #expect(await harness.details.moviePlaybackCalls == 2)
    }

    // MARK: - Subtitles

    @Test func preferredSubtitleOnlyWhenAvailable() async {
        let english = Harness(.movie(1001))
        await english.session.start()
        #expect(english.engine.loads.first?.subtitleLanguage == "en")

        var russianPreferred = Library()
        russianPreferred.preferences.subtitleLanguage = "ru"
        let russian = Harness(.movie(1001), library: russianPreferred)
        await russian.session.start()
        #expect(russian.engine.loads.first?.subtitleLanguage == "ru")

        var off = Library()
        off.preferences.subtitleLanguage = nil
        let none = Harness(.movie(1001), library: off)
        await none.session.start()
        #expect(none.engine.loads.first?.subtitleLanguage == nil)

        // The title lacks English: subtitles off, silently.
        let missing = Harness(.movie(1001))
        var russianOnly = Samples.movieDetail(1001, withPlayback: true)!
        let source = russianOnly.playback!
        russianOnly.subtitleLanguages = ["ru"]
        russianOnly.playback = Playback(streamURL: source.streamURL, subtitles: source.subtitles.filter { $0.lang == "ru" },
                                        fetchedAt: source.fetchedAt)
        let override = russianOnly
        await missing.details.configure { $0.movieResults[1001] = .success(override) }
        await missing.session.start()
        #expect(missing.session.phase == .playing)
        #expect(missing.engine.loads.count == 1)
        #expect(missing.engine.loads.first?.subtitleLanguage == nil)
    }

    @Test func changingSubtitleUpdatesPreference() async {
        let harness = Harness(.movie(1001))
        await harness.session.start()
        await harness.session.handle(.subtitleChanged("ru"))
        #expect(await harness.library.library.preferences.subtitleLanguage == "ru")
        await harness.session.handle(.subtitleChanged(nil))
        #expect(await harness.library.library.preferences.subtitleLanguage == nil)
    }

    @Test func zeroDurationNeverMarksWatched() async {
        let harness = Harness(.movie(1001))
        await harness.session.start()
        await harness.clock.advance(by: .seconds(10))
        await harness.session.handle(.time(position: 100, duration: 0))
        await harness.session.handle(.ended)
        #expect(harness.session.phase == .finished)
        let library = await harness.library.library
        #expect(library.watchedMovies.isEmpty)
        #expect(library.isWatched(Self.movie) == false)
    }

    @Test func nonFiniteDurationIsIgnored() async {
        let harness = Harness(.episode(id: Self.s1e1, showID: 101))
        await harness.session.start()
        await harness.clock.advance(by: .seconds(10))
        await harness.session.handle(.time(position: 990, duration: .nan))
        await harness.session.handle(.time(position: .infinity, duration: .infinity))
        #expect(harness.session.showsNextEpisodeAction == false)
        #expect(await harness.library.updateCount == 0)
        await harness.session.handle(.ended)
        let library = await harness.library.library
        #expect(library.watchedEpisodes.isEmpty)
        #expect(library.progress.isEmpty)
    }

    @Test func willDismissRecordsAndFlushes() async {
        let harness = Harness(.movie(1001))
        await harness.session.start()
        await harness.session.handle(.time(position: 42, duration: 1000))
        #expect(await harness.library.updateCount == 0)

        let played = await harness.session.willDismiss()
        #expect(played == Self.movie)
        let entry = await harness.library.library.progress.first
        #expect(entry?.playable == Self.movie)
        #expect(entry?.position == 42)
        #expect(await harness.library.flushCount == 1)
    }

    // MARK: - Helpers

    static func movieProgress(_ position: TimeInterval, of duration: TimeInterval) -> Library {
        var library = Library()
        library.recordProgress(movie, show: nil, position: position, duration: duration, now: Samples.now)
        return library
    }
}

// MARK: - Dismissal and show ids

extension PlaybackSessionTests {
    @Test func dismissDuringNextEpisodeFetchStartsNothing() async {
        let harness = Harness(.episode(id: Self.s1e1, showID: 101))
        await harness.session.start()
        await harness.session.handle(.ended)
        await harness.details.configure { $0.delay = .milliseconds(100) }
        await harness.clock.advance(by: .seconds(5))
        #expect(await eventually { await harness.details.episodePlaybackCalls == 2 })

        let phase = harness.session.phase
        let played = await harness.session.willDismiss()
        #expect(played == PlayableID(kind: .episode, id: Self.s1e1))
        try? await Task.sleep(for: .milliseconds(300)) // let the in-flight fetch return
        await settle()

        #expect(harness.engine.loads.count == 1)
        #expect(harness.engine.playCount == 1)
        #expect(harness.session.phase == phase)
        #expect(harness.session.current == PlayableID(kind: .episode, id: Self.s1e1))
        await harness.session.playNextNow()
        await harness.session.retry()
        #expect(harness.engine.loads.count == 1)
    }

    @Test func nextEpisodeFetchFailureKeepsCurrent() async {
        let harness = Harness(.episode(id: Self.s1e1, showID: 101))
        await harness.session.start()
        await harness.details.configure { $0.error = .offline }
        await harness.session.playNextNow()
        #expect(harness.session.phase == .failed(.fetch))
        #expect(harness.session.current == PlayableID(kind: .episode, id: Self.s1e1))

        await harness.details.configure { $0.error = nil }
        await harness.session.retry()
        #expect(harness.session.phase == .playing)
        #expect(harness.session.current == PlayableID(kind: .episode, id: Self.s1e2))
    }

    /// `EpisodeDetail.episode.showID` is unreliable (0 when unknown): the show id always comes from the request.
    @Test func showIDComesFromTargetNotEpisodeDetail() async {
        // An episode the show detail does not list, whose detail claims another show.
        let episodeID = 1_010_109
        let harness = Harness(.episode(id: episodeID, showID: 101))
        var detail = Samples.episodeDetail(episodeID, withPlayback: true)!
        detail.episode = Episode(id: episodeID, showID: 555, name: "Episode 9", season: 1, number: 9)
        let override = detail
        await harness.details.configure { $0.episodeResults[episodeID] = .success(override) }
        await harness.session.start()
        #expect(harness.session.phase == .playing)

        await harness.clock.advance(by: .seconds(10))
        await harness.session.handle(.time(position: 120, duration: 1000))
        let entry = await harness.library.library.progress.first
        #expect(entry?.showID == 101)
        #expect(entry?.season == 1)
        #expect(entry?.number == 9)

        await harness.session.handle(.time(position: 990, duration: 1000))
        let library = await harness.library.library
        #expect(library.watchedEpisodes == [episodeID])
        #expect(library.followed[101]?.started == true)
        #expect(library.followed[555] == nil)
    }
}

// MARK: - Harness

@MainActor private struct Harness {
    let details = FakeDetails()
    let library: InMemoryLibraryStore
    let engine = FakeEngine()
    let clock = TestClock()
    let now = NowBox(Samples.now)
    let session: PlaybackSession

    init(_ target: PlayRequest.Target, startOver: Bool = false, library: Library = Library()) {
        self.library = InMemoryLibraryStore(library)
        let environment = AppEnvironment(api: FakeAPI(), catalog: FakeCatalog(current: Samples.catalog), library: self.library,
                                         details: details, credentials: InMemoryCredentialStore(Samples.credentials),
                                         newEpisodes: FakeNewEpisodes())
        let now = now
        session = PlaybackSession(request: PlayRequest(target: target, startOver: startOver), environment: environment,
                                  session: AppSession(environment: environment), engine: engine, clock: clock,
                                  now: { now.value })
    }

    /// Ends the current episode and lets the 5 s countdown run out; true once `episodeID` plays.
    func autoplay(to episodeID: Int) async -> Bool {
        await session.handle(.ended)
        guard case .countdown = session.phase else { return false }
        await clock.advance(by: .seconds(5))
        return await eventually {
            session.phase == .playing && session.current == PlayableID(kind: .episode, id: episodeID)
        }
    }
}

@MainActor private final class FakeEngine: PlayerEngine {
    struct Load {
        let playback: Playback
        let startAt: TimeInterval
        let subtitleLanguage: String?
    }

    let events: AsyncStream<PlayerEvent>
    private let continuation: AsyncStream<PlayerEvent>.Continuation
    private(set) var loads: [Load] = []
    private(set) var playCount = 0, pauseCount = 0
    var position: TimeInterval = 0
    var duration: TimeInterval = 0

    init() {
        (events, continuation) = AsyncStream<PlayerEvent>.makeStream()
    }

    func send(_ event: PlayerEvent) {
        continuation.yield(event)
    }

    /// Consumed one per `load`; a non-nil entry makes that load throw (after recording it).
    var loadErrors: [(any Error)?] = []

    func load(_ playback: Playback, startAt: TimeInterval, subtitleLanguage: String?) async throws {
        loads.append(Load(playback: playback, startAt: startAt, subtitleLanguage: subtitleLanguage))
        if !loadErrors.isEmpty, let error = loadErrors.removeFirst() { throw error }
        position = startAt
    }

    func play() { playCount += 1 }
    func pause() { pauseCount += 1 }
    func seek(to: TimeInterval) async { position = to }
}

private final class NowBox: Sendable {
    private let date: Mutex<Date>

    init(_ date: Date) {
        self.date = Mutex(date)
    }

    var value: Date { date.withLock { $0 } }

    func set(_ value: Date) {
        date.withLock { $0 = value }
    }
}

/// A clock that only moves when the test calls `advance(by:)`.
private final class TestClock: Clock {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let id: UUID
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [Sleeper] = []
    }

    private let state = Mutex(State())

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let outcome: Result<Void, any Error>? = state.withLock { state in
                    if Task.isCancelled { return .failure(CancellationError()) }
                    if deadline <= state.now { return .success(()) }
                    state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return nil
                }
                if let outcome { continuation.resume(with: outcome) }
            }
        } onCancel: {
            let sleeper = state.withLock { state -> Sleeper? in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return state.sleepers.remove(at: index)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward deadline by deadline, letting each woken sleeper run before the next.
    func advance(by duration: Duration) async {
        await settle() // Let freshly started tasks register their sleeps first.
        let target = now.advanced(by: duration)
        while true {
            let due = state.withLock { state -> [Sleeper] in
                guard let earliest = state.sleepers.map(\.deadline).min(), earliest <= target else { return [] }
                state.now = earliest
                let due = state.sleepers.filter { $0.deadline <= earliest }
                state.sleepers.removeAll { $0.deadline <= earliest }
                return due
            }
            if due.isEmpty { break }
            for sleeper in due { sleeper.continuation.resume() }
            await settle()
        }
        state.withLock { $0.now = target }
    }
}

/// Lets other main-actor work and actor hops run.
@MainActor private func settle() async {
    for index in 0..<200 {
        if index.isMultiple(of: 20) { try? await Task.sleep(for: .milliseconds(1)) } else { await Task.yield() }
    }
}

/// Polls `condition` until it holds (bounded), interleaving yields so background work can progress.
@MainActor private func eventually(_ condition: () async -> Bool) async -> Bool {
    for index in 0..<2000 {
        if await condition() { return true }
        if index.isMultiple(of: 20) { try? await Task.sleep(for: .milliseconds(1)) } else { await Task.yield() }
    }
    return await condition()
}
