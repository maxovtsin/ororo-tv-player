import AVFoundation
import AVKit
import OroroCore

/// How subtitles reach the player (the S4 seam). The primary implementation injects the `.vtt` files as native
/// HLS subtitle tracks; an overlay fallback would draw them in `contentOverlayView` instead.
@MainActor protocol SubtitleProvider {
    /// With a `surround` source the multivariant playlist is authored with its 5.1 audio.
    func makeAsset(for playback: Playback, preferredLanguage: String?, surround: (any SurroundSource)?) -> AVURLAsset
    func attach(to controller: AVPlayerViewController, engine: AVPlayerEngine)
}

/// Serves a synthetic master playlist under `ororo-subs://` through `SubtitleResourceLoader`, giving the native
/// subtitle menu, system caption styling and PiP. With a surround source the same playlist also carries the 5.1
/// audio. Titles without subtitles and without surround play the stream URL directly.
@MainActor final class HLSInjectedSubtitles: SubtitleProvider {
    /// AVFoundation keeps resource-loader delegates weakly; this keeps the current one alive.
    private var loader: SubtitleResourceLoader?

    init() {}

    func makeAsset(for playback: Playback, preferredLanguage: String?, surround: (any SurroundSource)?) -> AVURLAsset {
        guard !playback.subtitles.isEmpty || surround != nil else {
            loader = nil
            return AVURLAsset(url: playback.streamURL)
        }
        var authorAudio: SubtitleResourceResponder.AuthorAudio?
        if let surround {
            authorAudio = { multivariant in await surround.author(multivariant: multivariant) }
        }
        let loader = SubtitleResourceLoader(playback: playback, preferredLanguage: preferredLanguage, authorAudio: authorAudio)
        let asset = AVURLAsset(url: SubtitlePlaylistBuilder.masterURL())
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        self.loader = loader
        return asset
    }

    /// Native tracks need nothing on the controller; the system subtitle menu lists them.
    func attach(to controller: AVPlayerViewController, engine: AVPlayerEngine) {}
}
