import Foundation
import Testing
@testable import OroroCore

@Suite struct SubtitlePlaylistBuilderTests {
    private let base = URL(string: "https://cdn.example.com/video/show/master.m3u8?token=abc")!
    private let en = Subtitle(lang: "en", url: URL(string: "https://subs.example.com/en.vtt")!)
    private let fr = Subtitle(lang: "fr", url: URL(string: "https://subs.example.com/fr.vtt")!)

    private func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    @Test func relativeVariantURIsBecomeAbsolute() {
        let input = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\n720/index.m3u8\n"
        let out = SubtitlePlaylistBuilder.master(original: input, originalURL: base, subtitles: [], defaultLanguage: nil)
        #expect(lines(out).contains("https://cdn.example.com/video/show/720/index.m3u8"))
        #expect(!out.contains("SUBTITLES"))
    }

    @Test func absoluteURIWithQueryIsUntouched() {
        let uri = "https://other.example.com/a/index.m3u8?wmsAuthSign=PLACEHOLDER&x=1"
        let input = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\n\(uri)\n"
        let out = SubtitlePlaylistBuilder.master(original: input, originalURL: base, subtitles: [], defaultLanguage: nil)
        #expect(lines(out).contains(uri))
    }

    @Test func uriAttributesInMediaTagsAreRewritten() {
        let input = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="English",URI="audio/en.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=1000,AUDIO="aud"
        v.m3u8
        """
        let out = SubtitlePlaylistBuilder.master(original: input, originalURL: base, subtitles: [], defaultLanguage: nil)
        #expect(out.contains("URI=\"https://cdn.example.com/video/show/audio/en.m3u8\""))
    }

    @Test func streamInfGetsSubtitlesGroup() {
        let input = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1000
        a.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2000,SUBTITLES="existing"
        b.m3u8
        """
        let out = SubtitlePlaylistBuilder.master(original: input, originalURL: base, subtitles: [en], defaultLanguage: nil)
        #expect(lines(out).contains("#EXT-X-STREAM-INF:BANDWIDTH=1000,SUBTITLES=\"subs\""))
        #expect(lines(out).contains("#EXT-X-STREAM-INF:BANDWIDTH=2000,SUBTITLES=\"existing\""))
    }

    @Test func oneMediaEntryPerLanguageWithDefaultFlag() {
        let input = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\na.m3u8\n"
        let out = lines(SubtitlePlaylistBuilder.master(original: input, originalURL: base, subtitles: [en, fr], defaultLanguage: "fr"))
        #expect(out[0] == "#EXTM3U")
        #expect(out[1] == "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",NAME=\"English\",LANGUAGE=\"en\","
            + "AUTOSELECT=YES,DEFAULT=NO,URI=\"ororo-subs://subtitles/en.m3u8\"")
        #expect(out[2] == "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",NAME=\"French\",LANGUAGE=\"fr\","
            + "AUTOSELECT=YES,DEFAULT=YES,URI=\"ororo-subs://subtitles/fr.m3u8\"")
    }

    @Test func noSubtitlesProducesNoMediaEntries() {
        let input = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\na.m3u8\n"
        let out = SubtitlePlaylistBuilder.master(original: input, originalURL: base, subtitles: [], defaultLanguage: "en")
        #expect(!out.contains("#EXT-X-MEDIA"))
        #expect(out == "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nhttps://cdn.example.com/video/show/a.m3u8\n")
    }

    @Test func mediaPlaylistIsWrappedInMaster() { // swiftlint:disable:this inclusive_language
        let input = "#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nseg0.ts\n#EXT-X-ENDLIST\n"
        let out = lines(SubtitlePlaylistBuilder.master(original: input, originalURL: base, subtitles: [en], defaultLanguage: "en"))
        #expect(out[0] == "#EXTM3U")
        #expect(out[1].hasPrefix("#EXT-X-MEDIA:TYPE=SUBTITLES"))
        #expect(out[1].contains("DEFAULT=YES"))
        #expect(out[2].hasPrefix("#EXT-X-STREAM-INF:"))
        #expect(out[2].hasSuffix("SUBTITLES=\"subs\""))
        #expect(out[3] == base.absoluteString)
        #expect(!out.contains("seg0.ts"))
    }

    @Test func subtitlePlaylistShape() {
        let vtt = URL(string: "https://subs.example.com/en.vtt")!
        let expected = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:2701
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXTINF:2700.4,
        https://subs.example.com/en.vtt
        #EXT-X-ENDLIST

        """
        #expect(SubtitlePlaylistBuilder.subtitlePlaylist(vttURL: vtt, duration: 2700.4) == expected)
    }

    @Test func duplicateLanguagesKeepFirst() {
        let dup = Subtitle(lang: "en", url: URL(string: "https://subs.example.com/en2.vtt")!)
        let input = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\na.m3u8\n"
        let out = SubtitlePlaylistBuilder.master(original: input, originalURL: base, subtitles: [en, dup], defaultLanguage: nil)
        #expect(out.components(separatedBy: "#EXT-X-MEDIA:").count == 2)
    }

    @Test func languageRoundTripsThroughURL() {
        let url = SubtitlePlaylistBuilder.subtitleURL(lang: "pt-BR")
        #expect(url.absoluteString == "ororo-subs://subtitles/pt-BR.m3u8")
        #expect(SubtitlePlaylistBuilder.language(from: url) == "pt-BR")
        #expect(SubtitlePlaylistBuilder.language(from: SubtitlePlaylistBuilder.masterURL()) == nil)
        #expect(SubtitlePlaylistBuilder.masterURL().absoluteString == "ororo-subs://master.m3u8")
        #expect(SubtitlePlaylistBuilder.language(from: URL(string: "https://x.com/subtitles/en.m3u8")!) == nil)
    }

    @Test func crlfInputIsHandled() {
        let input = "#EXTM3U\r\n#EXT-X-STREAM-INF:BANDWIDTH=1000\r\na.m3u8\r\n"
        let out = SubtitlePlaylistBuilder.master(original: input, originalURL: base, subtitles: [en], defaultLanguage: nil)
        #expect(!out.contains("\r"))
        #expect(lines(out).contains("#EXT-X-STREAM-INF:BANDWIDTH=1000,SUBTITLES=\"subs\""))
        #expect(lines(out).contains("https://cdn.example.com/video/show/a.m3u8"))
    }
}
