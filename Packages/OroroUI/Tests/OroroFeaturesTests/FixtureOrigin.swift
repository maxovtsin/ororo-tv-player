import Foundation
import OroroCore
@testable import OroroFeatures
import OroroTestSupport
import Synchronization

/// A fake CDN built from `HLSAudioFixture`: one multivariant playlist, one stereo audio rendition.
///
/// Every request must carry `wmsAuthSign=PLACEHOLDER`, otherwise it fails with HTTP 403. Segment URLs in the audio
/// playlist are relative; with `redirectAudioPlaylistTo`, the playlist fetch reports that host as its final URL and
/// the init and media segments are only served from that host.
final class FixtureOrigin: Sendable {
    static let multivariantURL = URL(string: "https://origin.invalid/main.m3u8?wmsAuthSign=PLACEHOLDER")!
    private static let originHost = "origin.invalid", token = "wmsAuthSign=PLACEHOLDER"

    private struct State {
        var initSegment: Data
        var counts: [String: Int] = [:]
        var failing: Set<String> = []
    }

    private let segments: [Data]
    private let durations: [Double]
    private let redirectHost: String?
    private let state: Mutex<State>

    init(fixture: HLSAudioFixture, redirectAudioPlaylistTo host: String? = nil) {
        segments = fixture.segments
        durations = fixture.segments.map { segment in
            let packets = (try? FragmentedMP4.parseAudioSegment(segment).packets.count) ?? 0
            return packets > 0 ? Double(packets * SurroundFormat.framesPerPacket) / SurroundFormat.sampleRate : 2
        }
        redirectHost = host
        state = Mutex(State(initSegment: fixture.initSegment))
    }

    var segmentCount: Int { segments.count }

    /// Already absolutised, as `SubtitlePlaylistBuilder.master` would leave it.
    var multivariant: String {
        """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="English",LANGUAGE="en",DEFAULT=YES,AUTOSELECT=YES,\
        CHANNELS="2",URI="https://\(Self.originHost)/a/audio.m3u8?\(Self.token)"
        #EXT-X-STREAM-INF:BANDWIDTH=2000000,AVERAGE-BANDWIDTH=1800000,CODECS="avc1.640028,mp4a.40.2",AUDIO="aud"
        https://\(Self.originHost)/v/video.m3u8?\(Self.token)

        """
    }

    var fetch: SubtitleResourceResponder.ResolvingFetch {
        { [self] url in try self.serve(url) }
    }

    func fetchCount(pathSuffix: String) -> Int {
        state.withLock { $0.counts.filter { $0.key.hasSuffix(pathSuffix) }.values.reduce(0, +) }
    }

    func failRequests(pathSuffix: String, _ failing: Bool) {
        state.withLock {
            if failing { $0.failing.insert(pathSuffix) } else { $0.failing.remove(pathSuffix) }
        }
    }

    func replaceInit(with data: Data) {
        state.withLock { $0.initSegment = data }
    }

    // MARK: - Serving

    private var audioPlaylist: String {
        var lines = ["#EXTM3U", "#EXT-X-VERSION:7", "#EXT-X-TARGETDURATION:3", "#EXT-X-PLAYLIST-TYPE:VOD",
                     "#EXT-X-MAP:URI=\"init.mp4?\(Self.token)\""]
        for (index, duration) in durations.enumerated() {
            lines.append("#EXTINF:\(String(format: "%.5f", duration)),")
            lines.append("seg-\(index).mp4?\(Self.token)")
        }
        lines.append("#EXT-X-ENDLIST")
        return lines.joined(separator: "\n") + "\n"
    }

    private func serve(_ url: URL) throws -> (data: Data, url: URL) {
        let path = url.path
        let (initSegment, failing) = state.withLock { state -> (Data, Bool) in
            state.counts[path, default: 0] += 1
            return (state.initSegment, state.failing.contains { path.hasSuffix($0) })
        }
        if failing { throw SubtitleResourceLoader.FetchError.transport(code: -1009) }
        guard url.query?.contains(Self.token) == true else { throw SubtitleResourceLoader.FetchError.http(status: 403) }

        let mediaHost = redirectHost ?? Self.originHost
        if path == "/a/audio.m3u8", url.host == Self.originHost {
            var final = URLComponents(url: url, resolvingAgainstBaseURL: false)
            final?.host = mediaHost
            return (Data(audioPlaylist.utf8), final?.url ?? url)
        }
        guard url.host == mediaHost else { throw SubtitleResourceLoader.FetchError.http(status: 404) }
        if path == "/a/init.mp4" { return (initSegment, url) }
        if path.hasPrefix("/a/seg-"), path.hasSuffix(".mp4"),
           let index = Int(path.dropFirst("/a/seg-".count).dropLast(".mp4".count)), segments.indices.contains(index) {
            return (segments[index], url)
        }
        throw SubtitleResourceLoader.FetchError.http(status: 404)
    }
}
