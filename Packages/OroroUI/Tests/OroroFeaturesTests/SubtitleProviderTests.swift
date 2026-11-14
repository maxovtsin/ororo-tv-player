import Foundation
import OroroCore
@testable import OroroFeatures
import Testing

@Suite @MainActor struct SubtitleProviderTests {
    private static let stream = URL(string: "https://example.invalid/hls/stream.m3u8?wmsAuthSign=PLACEHOLDER")!
    private static let bare = Playback(streamURL: stream, subtitles: [], fetchedAt: .now)

    @Test func titleWithoutSubtitlesPlaysTheStreamDirectlyWithoutSurround() {
        #expect(HLSInjectedSubtitles().makeAsset(for: Self.bare, preferredLanguage: nil, surround: nil).url == Self.stream)
    }

    @Test func titleWithoutSubtitlesUsesTheSyntheticPlaylistWithSurround() {
        let asset = HLSInjectedSubtitles().makeAsset(for: Self.bare, preferredLanguage: nil, surround: FakeSurroundSource())
        #expect(asset.url == SubtitlePlaylistBuilder.masterURL())
    }
}
