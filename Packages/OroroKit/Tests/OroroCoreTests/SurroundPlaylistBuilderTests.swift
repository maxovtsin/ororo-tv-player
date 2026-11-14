import Foundation
import Testing
@testable import OroroCore

@Suite struct SurroundPlaylistBuilderTests {
    private static let base = URL(string: "http://127.0.0.1:5000/token/")!
    private static let episode = """
    #EXTM3U
    #EXT-X-VERSION:6
    #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",LANGUAGE="en",AUTOSELECT=YES,DEFAULT=YES,URI="ororo-subs://subtitles/en.m3u8"
    #EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=853x480,AUDIO="aud1",SUBTITLES="subs"
    https://cdn.example.invalid/v/480.m3u8?wmsAuthSign=PLACEHOLDER
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud1",LANGUAGE="eng",NAME="English",URI="https://cdn.example.invalid/a/1.m3u8?wmsAuthSign=PLACEHOLDER"
    #EXT-X-STREAM-INF:BANDWIDTH=400000,AVERAGE-BANDWIDTH=350000,RESOLUTION=426x240,AUDIO="aud2",SUBTITLES="subs"
    https://cdn.example.invalid/v/240.m3u8?wmsAuthSign=PLACEHOLDER
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud2",LANGUAGE="eng",NAME="English",CHANNELS="2",URI="https://cdn.example.invalid/a/2.m3u8?wmsAuthSign=PLACEHOLDER"
    """
    private static let localURI = #"URI="http://127.0.0.1:5000/token/audio/0.m3u8""#

    @Test func pointsEveryAudioGroupAtOneRenditionFromTheBestVariant() throws {
        let result = try #require(SurroundPlaylistBuilder.multivariant(absolutised: Self.episode, localBase: Self.base))
        let lines = result.text.components(separatedBy: "\n")
        #expect(result.sources.count == 1)
        #expect(result.sources[0].path == "/a/1.m3u8" && result.sources[0].query == "wmsAuthSign=PLACEHOLDER")
        let audio = lines.filter { $0.contains("TYPE=AUDIO") }
        #expect(audio.count == 2)
        #expect(audio.allSatisfy { $0.contains(#"CHANNELS="6""#) && !$0.contains(#"CHANNELS="2""#) && $0.contains(Self.localURI) })
        #expect(lines.contains { $0.hasPrefix("#EXT-X-STREAM-INF:BANDWIDTH=1884000,") })
        #expect(lines.contains { $0.hasPrefix("#EXT-X-STREAM-INF:BANDWIDTH=784000,AVERAGE-BANDWIDTH=734000,") })
        #expect(lines.contains("https://cdn.example.invalid/v/480.m3u8?wmsAuthSign=PLACEHOLDER"))
        #expect(lines.contains { $0.contains("TYPE=SUBTITLES") && $0.contains("ororo-subs://subtitles/en.m3u8") })
        #expect(!result.text.contains("/a/1.m3u8") && !result.text.contains("/a/2.m3u8"))
    }

    @Test func keepsDifferentLanguagesAsSeparateRenditions() throws {
        let twoLanguages = Self.episode.replacingOccurrences(
            of: #"GROUP-ID="aud2",LANGUAGE="eng",NAME="English""#, with: #"GROUP-ID="aud1",LANGUAGE="rus",NAME="Russian""#)
        let result = try #require(SurroundPlaylistBuilder.multivariant(absolutised: twoLanguages, localBase: Self.base))
        #expect(result.sources.map(\.path) == ["/a/1.m3u8", "/a/2.m3u8"])
        #expect(result.text.contains("audio/0.m3u8") && result.text.contains("audio/1.m3u8"))
    }

    @Test func declinesWhenAudioIsNotASeparateStereoRendition() {
        let muxed = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nhttps://cdn.example.invalid/v.m3u8\n"
        #expect(SurroundPlaylistBuilder.multivariant(absolutised: muxed, localBase: Self.base) == nil)
        let noURI = "#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"a\",NAME=\"x\"\n"
            + "#EXT-X-STREAM-INF:BANDWIDTH=1000,AUDIO=\"a\"\nhttps://x.invalid/v.m3u8\n"
        #expect(SurroundPlaylistBuilder.multivariant(absolutised: noURI, localBase: Self.base) == nil)
        let surround = Self.episode.replacingOccurrences(of: #"CHANNELS="2""#, with: #"CHANNELS="6""#)
        #expect(SurroundPlaylistBuilder.multivariant(absolutised: surround, localBase: Self.base) == nil)
    }

    private static let media = """
    #EXTM3U
    #EXT-X-VERSION:7
    #EXT-X-TARGETDURATION:5
    #EXT-X-PLAYLIST-TYPE:VOD
    #EXT-X-MAP:URI="init.fmp4?wmsAuthSign=PLACEHOLDER"
    #EXTINF:4.01,
    seg-1.fmp4?wmsAuthSign=PLACEHOLDER
    #EXTINF:3.541,
    seg-2.fmp4?wmsAuthSign=PLACEHOLDER
    #EXT-X-ENDLIST
    """
    private static let mediaURL = URL(string: "https://edge7.example.invalid/a/1.m3u8?wmsAuthSign=PLACEHOLDER")!

    @Test func rewritesTheMediaPlaylistToLocalURLsAndKeepsTheSignedQuery() throws {
        let result = try #require(SurroundPlaylistBuilder.mediaPlaylist(
            original: Self.media, originalURL: Self.mediaURL, localBase: Self.base, rendition: 1))
        #expect(result.initURL.absoluteString == "https://edge7.example.invalid/a/init.fmp4?wmsAuthSign=PLACEHOLDER")
        #expect(result.segments.map(\.absoluteString) == [
            "https://edge7.example.invalid/a/seg-1.fmp4?wmsAuthSign=PLACEHOLDER",
            "https://edge7.example.invalid/a/seg-2.fmp4?wmsAuthSign=PLACEHOLDER"
        ])
        let lines = result.text.components(separatedBy: "\n")
        #expect(lines.contains(#"#EXT-X-MAP:URI="http://127.0.0.1:5000/token/audio/1/init.mp4""#))
        #expect(lines.contains("http://127.0.0.1:5000/token/audio/1/0.m4s"))
        #expect(lines.contains("http://127.0.0.1:5000/token/audio/1/1.m4s"))
        #expect(lines.contains("#EXTINF:3.541,") && lines.contains("#EXT-X-ENDLIST"))
        #expect(!result.text.contains("wmsAuthSign") && !result.text.contains("example.invalid"))
    }

    @Test(arguments: [
        ("#EXT-X-KEY:METHOD=AES-128,URI=\"https://x.invalid/key\"", "#EXTINF:4.01,"),
        ("#EXT-X-BYTERANGE:1000@0", "#EXTINF:4.01,"),
        ("#EXT-X-DISCONTINUITY", "#EXTINF:4.01,"),
        ("#EXT-X-MAP:URI=\"other.mp4\"", "#EXTINF:4.01,"),
        ("#EXT-X-MAP:URI=\"init.fmp4\",BYTERANGE=\"700@0\"", "#EXT-X-MAP:URI=\"init.fmp4?wmsAuthSign=PLACEHOLDER\"")
    ])
    func declinesMediaPlaylistsItCannotServe(tag: String, replacing: String) {
        let range = Self.media.range(of: replacing)!
        let text = replacing.hasPrefix("#EXTINF") ? Self.media.replacingCharacters(in: range, with: tag + "\n" + replacing)
            : Self.media.replacingCharacters(in: range, with: tag)
        #expect(SurroundPlaylistBuilder.mediaPlaylist(original: text, originalURL: Self.mediaURL, localBase: Self.base, rendition: 0) == nil)
    }

    @Test func declinesLivePlaylistsAndPlaylistsWithoutAnInitSegment() {
        let live = Self.media.replacingOccurrences(of: "#EXT-X-ENDLIST", with: "")
        #expect(SurroundPlaylistBuilder.mediaPlaylist(original: live, originalURL: Self.mediaURL, localBase: Self.base, rendition: 0) == nil)
        let transportStream = "#EXTM3U\n#EXTINF:4,\nseg.ts\n#EXT-X-ENDLIST\n"
        #expect(SurroundPlaylistBuilder.mediaPlaylist(
            original: transportStream, originalURL: Self.mediaURL, localBase: Self.base, rendition: 0) == nil)
    }

    @Test func acceptsAnExplicitNoEncryptionKey() {
        let text = Self.media.replacingOccurrences(of: "#EXT-X-PLAYLIST-TYPE:VOD", with: "#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-KEY:METHOD=NONE")
        #expect(SurroundPlaylistBuilder.mediaPlaylist(original: text, originalURL: Self.mediaURL, localBase: Self.base, rendition: 0) != nil)
    }

    @Test func mapsLocalPathsBackToResources() {
        #expect(SurroundPlaylistBuilder.resource(forPath: "audio/2.m3u8") == .playlist(rendition: 2))
        #expect(SurroundPlaylistBuilder.resource(forPath: "audio/2/init.mp4") == .initSegment(rendition: 2))
        #expect(SurroundPlaylistBuilder.resource(forPath: "audio/2/17.m4s") == .segment(rendition: 2, index: 17))
        #expect(SurroundPlaylistBuilder.resource(forPath: "audio/x.m3u8") == nil)
        #expect(SurroundPlaylistBuilder.resource(forPath: "audio/2/-1.m4s") == nil)
        #expect(SurroundPlaylistBuilder.resource(forPath: "../secret") == nil)
    }
}
