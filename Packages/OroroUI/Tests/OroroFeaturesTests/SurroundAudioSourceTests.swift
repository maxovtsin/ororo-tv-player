import Foundation
import OroroCore
@testable import OroroFeatures
import OroroTestSupport
import Synchronization
import Testing

@Suite struct SurroundAudioSourceTests {
    private final class Failures: Sendable {
        private let values = Mutex<[SurroundFailure]>([])
        var all: [SurroundFailure] { values.withLock { $0 } }
        func record(_ failure: SurroundFailure) { values.withLock { $0.append(failure) } }
    }
    private struct Started { var source: SurroundAudioSource; var base: URL; var authored: String?; var failures: Failures }

    private static func start(_ origin: FixtureOrigin, transcode: SurroundTranscode? = nil,
                              now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) async throws -> Started {
        let failures = Failures()
        let source = SurroundAudioSource(fetch: origin.fetch, transcode: transcode ?? SurroundAudioSource.liveTranscode(signal: nil),
                                         now: now, onFailure: failures.record)
        let base = try await source.start()
        return Started(source: source, base: base, authored: await source.author(multivariant: origin.multivariant), failures: failures)
    }

    @Test func servesAPlayableSurroundRenditionOverHTTP() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 8))
        let started = try await Self.start(origin)
        defer { started.source.stop() }
        let authored = try #require(started.authored)
        #expect(authored.contains("\(started.base.absoluteString)audio/0.m3u8") && authored.contains(#"CHANNELS="6""#))
        let playlistBody = try await LoopbackServerTests.get(started.base.appending(path: "audio/0.m3u8")).body
        let playlist = try #require(String(bytes: playlistBody, encoding: .utf8))
        #expect(!playlist.contains("origin.invalid") && !playlist.contains("wmsAuthSign") && !authored.contains("/a/audio.m3u8"))
        let initSegment = try await LoopbackServerTests.get(started.base.appending(path: "audio/0/init.mp4")).body
        var segments: [Data] = []
        for index in 0..<origin.segmentCount {
            let response = try await LoopbackServerTests.get(started.base.appending(path: "audio/0/\(index).m4s"))
            #expect(response.status == 200)
            segments.append(response.body)
        }
        let channels = try await SurroundProbe.readContainer(initSegment: initSegment, segments: segments)
        #expect(channels.count == 6 && abs(channels[0].count - 8 * 48_000) < 4096)
        #expect(started.failures.all.isEmpty)
    }

    @Test func resolvesSegmentsAgainstTheRedirectedPlaylistURL() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 4), redirectAudioPlaylistTo: "edge7.invalid")
        let started = try await Self.start(origin)
        defer { started.source.stop() }
        #expect(started.authored != nil)
        #expect(await started.source.respond(to: "audio/0/1.m4s").status == 200)
    }

    @Test func neighboursAreFetchedOnceAcrossSequentialRequests() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 8))
        let started = try await Self.start(origin)
        defer { started.source.stop() }
        for index in 0..<origin.segmentCount { #expect(await started.source.respond(to: "audio/0/\(index).m4s").status == 200) }
        for index in 0..<origin.segmentCount { #expect(origin.fetchCount(pathSuffix: "seg-\(index).mp4") == 1) }
    }

    @Test func concurrentRequestsForOneSegmentTranscodeOnce() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 6))
        let calls = Mutex(0)
        let live = SurroundAudioSource.liveTranscode(signal: nil)
        let started = try await Self.start(origin, transcode: { previous, current, next, start in
            calls.withLock { $0 += 1 }
            return try live(previous, current, next, start)
        })
        defer { started.source.stop() }
        let bodies = await withTaskGroup(of: Data.self) { group in
            for _ in 0..<4 { group.addTask { await started.source.respond(to: "audio/0/1.m4s").body } }
            return await group.reduce(into: [Data]()) { $0.append($1) }
        }
        #expect(calls.withLock { $0 } == 1 && Set(bodies).count == 1 && !bodies[0].isEmpty)
    }

    @Test func unknownAndOutOfRangeRequestsAre404WithoutFallback() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 4))
        let started = try await Self.start(origin)
        defer { started.source.stop() }
        for path in ["audio/0/999.m4s", "audio/5.m3u8", "audio/5/0.m4s", "bogus"] {
            #expect(await started.source.respond(to: path).status == 404)
        }
        #expect(started.failures.all.isEmpty)
    }

    @Test func nothingIsServedBeforeAuthoring() async throws {
        let failures = Failures()
        let source = SurroundAudioSource(fetch: FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 2)).fetch,
                                         onFailure: failures.record)
        _ = try await source.start()
        defer { source.stop() }
        #expect(await source.respond(to: "audio/0.m3u8").status == 404)
    }

    @Test func transportErrorsAre502WithoutFallbackAndRecover() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 8))
        let started = try await Self.start(origin)
        defer { started.source.stop() }
        origin.failRequests(pathSuffix: "seg-2.mp4", true)
        #expect(await started.source.respond(to: "audio/0/2.m4s").status == 502)
        #expect(await started.source.respond(to: "audio/0/1.m4s").status == 200) // only a neighbour is missing
        origin.failRequests(pathSuffix: "seg-2.mp4", false)
        #expect(await started.source.respond(to: "audio/0/2.m4s").status == 200)
        #expect(started.failures.all.isEmpty)
    }

    @Test func preflightDeclinesUnsupportedAudioWithoutFailure() async throws {
        let mono = try await HLSAudioFixture.make(seconds: 2, channels: 1)
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 4))
        origin.replaceInit(with: mono.initSegment)
        let started = try await Self.start(origin)
        defer { started.source.stop() }
        #expect(started.authored == nil && started.failures.all.isEmpty)
    }

    @Test func preflightDeclinesMuxedAudioAndUnreachableOrigins() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 4))
        let started = try await Self.start(origin)
        defer { started.source.stop() }
        let muxed = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nhttps://origin.invalid/v.m3u8\n"
        #expect(await started.source.author(multivariant: muxed) == nil)
        origin.failRequests(pathSuffix: "audio.m3u8", true)
        let second = try await Self.start(origin)
        defer { second.source.stop() }
        #expect(second.authored == nil && second.failures.all.isEmpty)
    }

    @Test func aBrokenSegmentReportsAFormatFailureOnce() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 8))
        let started = try await Self.start(origin, transcode: { _, _, _, _ in throw SurroundTranscoder.Failure.decodeFailed })
        defer { started.source.stop() }
        #expect(await started.source.respond(to: "audio/0/1.m4s").status == 404)
        #expect(await started.source.respond(to: "audio/0/2.m4s").status == 404)
        #expect(started.failures.all == [.format])
    }

    @Test func aDeviceTooSlowToTranscodeIsReportedAfterThreeSlowSegments() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 12))
        let clock = Mutex(ContinuousClock.now)
        let live = SurroundAudioSource.liveTranscode(signal: nil)
        let started = try await Self.start(origin, transcode: { previous, current, next, start in
            clock.withLock { $0 += .seconds(1.5) } // 1.5 s for a ~2 s segment: over half real time
            return try live(previous, current, next, start)
        }, now: { clock.withLock { $0 } })
        defer { started.source.stop() }
        _ = await started.source.respond(to: "audio/0/0.m4s")
        _ = await started.source.respond(to: "audio/0/1.m4s")
        #expect(started.failures.all.isEmpty)
        _ = await started.source.respond(to: "audio/0/2.m4s")
        #expect(started.failures.all == [.slowDevice])
    }

    @Test func slowFetchingIsReportedAsStarvedNotAsASlowDevice() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 12))
        let clock = Mutex(ContinuousClock.now)
        let slowFetch: SubtitleResourceResponder.ResolvingFetch = { url in
            if url.path.contains("seg-") { clock.withLock { $0 += .seconds(3) } }
            return try await origin.fetch(url)
        }
        let failures = Failures()
        let source = SurroundAudioSource(fetch: slowFetch, now: { clock.withLock { $0 } }, onFailure: failures.record)
        _ = try await source.start()
        defer { source.stop() }
        #expect(await source.author(multivariant: origin.multivariant) != nil)
        for index in 1...3 { _ = await source.respond(to: "audio/0/\(index).m4s") }
        #expect(failures.all == [.starved])
    }

    @Test func repeatedPreflightsAreAnsweredFromTheFirst() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 4))
        let started = try await Self.start(origin)
        defer { started.source.stop() }
        #expect(started.authored != nil)
        // A later failure must not change the answer: asset and item see the same playlist.
        origin.failRequests(pathSuffix: "audio.m3u8", true)
        #expect(await started.source.author(multivariant: origin.multivariant) == started.authored)
        #expect(await started.source.accepted)
        for path in ["audio.m3u8", "init.mp4", "seg-0.mp4"] { #expect(origin.fetchCount(pathSuffix: path) == 1) }
    }

    @Test func concurrentFirstPreflightsShareOneRun() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 4))
        let source = SurroundAudioSource(fetch: origin.fetch, onFailure: { _ in })
        _ = try await source.start()
        defer { source.stop() }
        async let first = source.author(multivariant: origin.multivariant)
        async let second = source.author(multivariant: origin.multivariant)
        let results = await [first, second]
        #expect(results[0] != nil && results[0] == results[1])
        for path in ["audio.m3u8", "init.mp4", "seg-0.mp4"] { #expect(origin.fetchCount(pathSuffix: path) == 1) }
    }

    @Test func aDeclineIsRememberedAndReportedAsNotAccepted() async throws {
        let origin = FixtureOrigin(fixture: try await HLSAudioFixture.make(seconds: 4))
        let source = SurroundAudioSource(fetch: origin.fetch, onFailure: { _ in })
        _ = try await source.start()
        defer { source.stop() }
        #expect(await source.accepted == false) // no pre-flight yet
        origin.failRequests(pathSuffix: "audio.m3u8", true)
        #expect(await source.author(multivariant: origin.multivariant) == nil)
        origin.failRequests(pathSuffix: "audio.m3u8", false)
        #expect(await source.author(multivariant: origin.multivariant) == nil)
        #expect(await source.accepted == false)
        #expect(origin.fetchCount(pathSuffix: "audio.m3u8") == 1)
    }
}
