import Foundation
import OroroCore
@testable import OroroFeatures
import Testing

@Suite struct SubtitleResourceLoaderTests {
    private static let streamURL = URL(string: "https://example.invalid/hls/stream.m3u8?wmsAuthSign=PLACEHOLDER")!
    private static let englishVTT = URL(string: "https://example.invalid/subs/en.vtt")!
    private static let russianVTT = URL(string: "https://example.invalid/subs/ru.vtt")!

    private static let original = """
    #EXTM3U
    #EXT-X-VERSION:3
    #EXT-X-STREAM-INF:BANDWIDTH=1280000,RESOLUTION=1280x720
    chunklist_720.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=2560000,RESOLUTION=1920x1080
    https://cdn.example.invalid/chunklist_1080.m3u8?wmsAuthSign=PLACEHOLDER
    """

    private static let playback = Playback(
        streamURL: streamURL,
        subtitles: [Subtitle(lang: "en", url: englishVTT), Subtitle(lang: "ru", url: russianVTT)],
        fetchedAt: Date(timeIntervalSince1970: 1_761_955_200)
    )

    private struct FetchFailed: Error {}

    /// Serves `original` for the stream URL only; records nothing else.
    private static func responder(preferredLanguage: String? = "en") -> SubtitleResourceResponder {
        SubtitleResourceResponder(playback: playback, preferredLanguage: preferredLanguage) { url in
            guard url == streamURL else { throw FetchFailed() }
            return Data(original.utf8)
        }
    }

    // swiftlint:disable:next inclusive_language
    @Test func masterRequestReturnsRewrittenPlaylistWithSubtitleEntries() async throws {
        let result = try await Self.responder().response(for: SubtitlePlaylistBuilder.masterURL(), duration: 0)
        let text = try #require(String(bytes: result.data, encoding: .utf8))
        let expected = SubtitlePlaylistBuilder.master(
            original: Self.original, originalURL: Self.streamURL, subtitles: Self.playback.subtitles, defaultLanguage: "en"
        )
        #expect(text == expected)
        #expect(text.contains("https://example.invalid/hls/chunklist_720.m3u8"))
        #expect(text.contains(
            "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",NAME=\"English\",LANGUAGE=\"en\",AUTOSELECT=YES,DEFAULT=YES,"
                + "URI=\"ororo-subs://subtitles/en.m3u8\""
        ))
        #expect(text.contains(
            "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",NAME=\"Russian\",LANGUAGE=\"ru\",AUTOSELECT=YES,DEFAULT=NO,"
                + "URI=\"ororo-subs://subtitles/ru.m3u8\""
        ))
        #expect(text.contains("#EXT-X-STREAM-INF:BANDWIDTH=1280000,RESOLUTION=1280x720,SUBTITLES=\"subs\""))
    }

    @Test func playlistWithoutPreferredLanguageHasNoDefaultTrack() async throws {
        let result = try await Self.responder(preferredLanguage: nil)
            .response(for: SubtitlePlaylistBuilder.masterURL(), duration: 0)
        let text = try #require(String(bytes: result.data, encoding: .utf8))
        #expect(!text.contains("DEFAULT=YES"))
        #expect(text.contains("LANGUAGE=\"en\""))
    }

    @Test func subtitleRequestReturnsOneSegmentPlaylistForThatLanguage() async throws {
        let responder = Self.responder()
        let result = try await responder.response(for: SubtitlePlaylistBuilder.subtitleURL(lang: "ru"), duration: 2700.4)
        let text = try #require(String(bytes: result.data, encoding: .utf8))
        #expect(text == """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:2701
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXTINF:2700.4,
        https://example.invalid/subs/ru.vtt
        #EXT-X-ENDLIST

        """)
    }

    @Test func subtitleRequestWithUnusableDurationStillAnswers() async throws {
        let responder = Self.responder()
        for duration in [0, -1, .nan, .infinity] as [TimeInterval] {
            let result = try await responder.response(for: SubtitlePlaylistBuilder.subtitleURL(lang: "en"), duration: duration)
            let text = try #require(String(bytes: result.data, encoding: .utf8))
            #expect(text.contains("#EXTINF:\(SubtitleResourceResponder.fallbackDuration),"))
            #expect(text.contains("https://example.invalid/subs/en.vtt"))
        }
    }

    @Test func unknownURLThrows() async {
        let responder = Self.responder()
        let unknown = [
            SubtitlePlaylistBuilder.subtitleURL(lang: "de"),
            URL(string: "ororo-subs://elsewhere/en.m3u8")!,
            URL(string: "https://example.invalid/hls/stream.m3u8")!
        ]
        for url in unknown {
            await #expect(throws: SubtitleResourceResponder.Failure.unknownURL) {
                _ = try await responder.response(for: url, duration: 100)
            }
        }
    }

    // swiftlint:disable:next inclusive_language
    @Test func masterFetchFailurePropagates() async {
        let responder = SubtitleResourceResponder(playback: Self.playback, preferredLanguage: "en", fetch: { _ in
            throw FetchFailed()
        })
        await #expect(throws: FetchFailed.self) {
            _ = try await responder.response(for: SubtitlePlaylistBuilder.masterURL(), duration: 0)
        }
    }

    @Test func contentTypeIsMpegURL() async throws {
        let responder = Self.responder()
        let multivariant = try await responder.response(for: SubtitlePlaylistBuilder.masterURL(), duration: 0)
        let subtitles = try await responder.response(for: SubtitlePlaylistBuilder.subtitleURL(lang: "en"), duration: 60)
        #expect(multivariant.contentType == "application/x-mpegURL")
        #expect(subtitles.contentType == "application/x-mpegURL")
    }

    @Test func contentInformationUsesM3UPlaylistUTI() {
        #expect(SubtitleResourceLoader.uniformTypeIdentifier(forMIMEType: SubtitleResourceResponder.contentType)
            == "public.m3u-playlist")
        #expect(SubtitleResourceLoader.uniformTypeIdentifier(forMIMEType: "application/vnd.apple.mpegurl")
            == "public.m3u-playlist")
    }

    @Test func relativeURIsResolveAgainstRedirectedURL() async throws {
        let redirected = URL(string: "https://edge.example.invalid/live/abc/stream.m3u8?wmsAuthSign=PLACEHOLDER")!
        let responder = SubtitleResourceResponder(playback: Self.playback, preferredLanguage: nil) { url in
            guard url == Self.streamURL else { throw FetchFailed() }
            return (Data(Self.original.utf8), redirected)
        }
        let result = try await responder.response(for: SubtitlePlaylistBuilder.masterURL(), duration: 0)
        let text = try #require(String(bytes: result.data, encoding: .utf8))
        #expect(text.contains("https://edge.example.invalid/live/abc/chunklist_720.m3u8"))
        #expect(!text.contains("https://example.invalid/hls/chunklist_720.m3u8"))
    }

    @Test func fetchErrorsCarryNoURL() {
        let signed = Self.streamURL
        let urlError = URLError(.notConnectedToInternet, userInfo: [NSURLErrorFailingURLErrorKey: signed])
        let mapped = SubtitleResourceLoader.urlFree(urlError)
        #expect(mapped as? SubtitleResourceLoader.FetchError
            == .transport(code: URLError.Code.notConnectedToInternet.rawValue))
        let userInfo = (mapped as NSError).userInfo
        #expect(userInfo[NSURLErrorFailingURLErrorKey] == nil)
        #expect(!"\(mapped)".contains("wmsAuthSign"))
        #expect(SubtitleResourceLoader.urlFree(SubtitleResourceLoader.FetchError.http(status: 403)) as? SubtitleResourceLoader.FetchError
            == .http(status: 403))
        #expect(SubtitleResourceLoader.urlFree(URLError(.cancelled)) as? SubtitleResourceLoader.FetchError == .cancelled)
    }

    @Test func downloadSessionNeverCaches() {
        let configuration = SubtitleResourceLoader.session.configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func mediaDurationSumsSegmentsOfFirstVariant() {
        let multivariant = SubtitlePlaylistBuilder.master(
            original: Self.original, originalURL: Self.streamURL, subtitles: Self.playback.subtitles, defaultLanguage: nil
        )
        #expect(SubtitleResourceLoader.firstVariantURL(inMultivariant: multivariant)
            == URL(string: "https://example.invalid/hls/chunklist_720.m3u8"))
        let media = """
        #EXTM3U
        #EXT-X-TARGETDURATION:10
        #EXTINF:10.0,
        media_0.ts
        #EXTINF:9.5,title
        media_1.ts
        #EXTINF:4,
        media_2.ts
        #EXT-X-ENDLIST
        """
        #expect(SubtitleResourceLoader.mediaDuration(ofMediaPlaylist: media) == 23.5)
        #expect(SubtitleResourceLoader.mediaDuration(ofMediaPlaylist: "#EXTM3U\n") == 0)
    }

    @Test func appliesAudioAuthoringToTheMultivariantPlaylist() async throws {
        let responder = SubtitleResourceResponder(
            playback: Self.playback, preferredLanguage: "en", resolvingFetch: { _ in (Data(Self.original.utf8), Self.streamURL) },
            authorAudio: { $0 + "#AUTHORED\n" })
        let data = try await responder.response(for: SubtitlePlaylistBuilder.masterURL(), duration: 0).data
        let text = try #require(String(bytes: data, encoding: .utf8))
        #expect(text.hasSuffix("#AUTHORED\n") && text.contains(#"SUBTITLES="subs""#))
    }

    @Test func keepsThePlaylistWhenAudioAuthoringDeclines() async throws {
        let fetch: SubtitleResourceResponder.ResolvingFetch = { _ in (Data(Self.original.utf8), Self.streamURL) }
        let plain = SubtitleResourceResponder(playback: Self.playback, preferredLanguage: "en", resolvingFetch: fetch)
        let declined = SubtitleResourceResponder(playback: Self.playback, preferredLanguage: "en", resolvingFetch: fetch, authorAudio: { _ in nil })
        let url = SubtitlePlaylistBuilder.masterURL()
        #expect(try await declined.response(for: url, duration: 0).data == plain.response(for: url, duration: 0).data)
    }
}
