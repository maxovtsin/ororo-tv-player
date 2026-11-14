import Foundation
import OroroCore
import OroroTestSupport
import Synchronization
import Testing
@testable import OroroStore

@Suite struct DetailRepositoryTests {
    final class Clock: Sendable {
        private let value = Mutex(Samples.now)
        var date: Date { value.withLock { $0 } }
        func advance(_ seconds: TimeInterval) { value.withLock { $0 = $0.addingTimeInterval(seconds) } }
    }

    struct Rig {
        let repo: DetailRepository
        let api: FakeAPI
        let clock: Clock
    }

    private func make(credentials: Credentials? = Samples.credentials, ttl: TimeInterval = 600) -> Rig {
        let api = FakeAPI()
        let clock = Clock()
        let repo = DetailRepository(api: api, credentials: InMemoryCredentialStore(credentials), ttl: ttl, now: { clock.date })
        return Rig(repo: repo, api: api, clock: clock)
    }

    @Test func showIsCachedWithinTTL() async throws {
        let rig = make()
        let (repo, api) = (rig.repo, rig.api)
        let clock = rig.clock
        let first = try await repo.show(id: 101)
        clock.advance(599)
        let second = try await repo.show(id: 101)
        #expect(first == second)
        #expect(first.title.id.id == 101)
        #expect(await api.showCalls == 1)
        #expect(await api.lastCredentials == Samples.credentials)
    }

    @Test func cacheExpiresAfterTTL() async throws {
        let rig = make()
        let (repo, api) = (rig.repo, rig.api)
        let clock = rig.clock
        _ = try await repo.show(id: 101)
        _ = try await repo.movie(id: 1001)
        _ = try await repo.episode(id: 1_010_101)
        clock.advance(600)
        _ = try await repo.show(id: 101)
        _ = try await repo.movie(id: 1001)
        _ = try await repo.episode(id: 1_010_101)
        #expect(await api.showCalls == 2)
        #expect(await api.movieCalls == 2)
        #expect(await api.episodeCalls == 2)
    }

    @Test func cachedMovieHasNoPlayback() async throws {
        let rig = make()
        let (repo, api) = (rig.repo, rig.api)
        let movie = try await repo.movie(id: 1001)
        let episode = try await repo.episode(id: 1_010_101)
        #expect(movie.playback == nil)
        #expect(episode.playback == nil)
        #expect(movie.trailerYouTubeID == "trailer-1001")
        #expect(try await repo.movie(id: 1001).playback == nil)
        #expect(await api.movieCalls == 1)
    }

    @Test func playbackCallsAlwaysHitNetwork() async throws {
        let rig = make()
        let (repo, api) = (rig.repo, rig.api)
        let movie1 = try await repo.moviePlayback(id: 1001)
        let movie2 = try await repo.moviePlayback(id: 1001)
        let episode1 = try await repo.episodePlayback(id: 1_010_101)
        let episode2 = try await repo.episodePlayback(id: 1_010_101)
        #expect(movie1.playback != nil && movie2.playback != nil)
        #expect(episode1.playback != nil && episode2.playback != nil)
        #expect(await api.movieCalls == 2)
        #expect(await api.episodeCalls == 2)
    }

    @Test func playbackCallRefreshesStrippedCache() async throws {
        let rig = make()
        let (repo, api) = (rig.repo, rig.api)
        let clock = rig.clock
        _ = try await repo.movie(id: 1001)
        clock.advance(500)
        _ = try await repo.moviePlayback(id: 1001)
        _ = try await repo.episodePlayback(id: 1_010_101)
        clock.advance(500) // 1000 s after the first read, 500 s after the playback refresh
        let movie = try await repo.movie(id: 1001)
        let episode = try await repo.episode(id: 1_010_101)
        #expect(movie.playback == nil)
        #expect(episode.playback == nil)
        #expect(await api.movieCalls == 2)
        #expect(await api.episodeCalls == 1)
    }

    @Test func concurrentRequestsShareOneCall() async throws {
        let rig = make()
        let (repo, api) = (rig.repo, rig.api)
        await api.configure { $0.delay = .milliseconds(200) }
        async let a = repo.show(id: 101)
        async let b = repo.show(id: 101)
        async let c = repo.show(id: 101)
        let results = try await [a, b, c]
        #expect(results.allSatisfy { $0 == results[0] })
        #expect(await api.showCalls == 1)
    }

    @Test func cancellingOneCallerDoesNotCancelOthers() async throws {
        let rig = make()
        let (repo, api) = (rig.repo, rig.api)
        await api.configure { $0.delay = .milliseconds(200) }
        let cancelled = Task { try await repo.show(id: 101) }
        let survivor = Task { try await repo.show(id: 101) }
        try await Task.sleep(for: .milliseconds(50))
        cancelled.cancel()
        let detail = try await survivor.value
        #expect(detail.title.id.id == 101)
        #expect(await api.showCalls == 1)
    }

    @Test func noCredentialsThrowsUnauthorized() async {
        let rig = make(credentials: nil)
        let (repo, api) = (rig.repo, rig.api)
        await #expect(throws: APIError.unauthorized) { try await repo.show(id: 101) }
        await #expect(throws: APIError.unauthorized) { try await repo.movie(id: 1001) }
        await #expect(throws: APIError.unauthorized) { try await repo.episode(id: 1_010_101) }
        await #expect(throws: APIError.unauthorized) { try await repo.moviePlayback(id: 1001) }
        await #expect(throws: APIError.unauthorized) { try await repo.episodePlayback(id: 1_010_101) }
        #expect(await api.totalCalls == 0)
    }

    @Test func errorsAreNotCached() async throws {
        let rig = make()
        let (repo, api) = (rig.repo, rig.api)
        await api.configure { $0.detailError = .offline }
        await #expect(throws: APIError.offline) { try await repo.show(id: 101) }
        await api.configure { $0.detailError = nil }
        let detail = try await repo.show(id: 101)
        #expect(detail.title.id.id == 101)
        #expect(await api.showCalls == 2)
    }

    @Test func clearEmptiesCache() async throws {
        let rig = make()
        let (repo, api) = (rig.repo, rig.api)
        _ = try await repo.show(id: 101)
        _ = try await repo.movie(id: 1001)
        _ = try await repo.episode(id: 1_010_101)
        await repo.clear()
        _ = try await repo.show(id: 101)
        _ = try await repo.movie(id: 1001)
        _ = try await repo.episode(id: 1_010_101)
        #expect(await api.showCalls == 2)
        #expect(await api.movieCalls == 2)
        #expect(await api.episodeCalls == 2)
    }
}
