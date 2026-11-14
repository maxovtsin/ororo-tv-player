import AVFoundation
import AVKit
import OroroCore

/// How subtitles reach the player (the S4 seam). The primary implementation injects the `.vtt` files as native
/// HLS subtitle tracks; an overlay fallback would draw them in `contentOverlayView` instead.
@MainActor protocol SubtitleProvider {
    func makeAsset(for playback: Playback, preferredLanguage: String?) -> AVURLAsset
    func attach(to controller: AVPlayerViewController, engine: AVPlayerEngine)
}

/// Serves a synthetic master playlist under `ororo-subs://` through `SubtitleResourceLoader`, giving the native
/// subtitle menu, system caption styling and PiP. Titles without subtitles play the stream URL directly.
@MainActor final class HLSInjectedSubtitles: SubtitleProvider {
    /// AVFoundation keeps resource-loader delegates weakly; this keeps the current one alive.
    private var loader: SubtitleResourceLoader?

    init() {}

    func makeAsset(for playback: Playback, preferredLanguage: String?) -> AVURLAsset {
        guard !playback.subtitles.isEmpty else {
            loader = nil
            return AVURLAsset(url: playback.streamURL)
        }
        let loader = SubtitleResourceLoader(playback: playback, preferredLanguage: preferredLanguage)
        let asset = AVURLAsset(url: SubtitlePlaylistBuilder.masterURL())
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        self.loader = loader
        return asset
    }

    /// Native tracks need nothing on the controller; the system subtitle menu lists them.
    func attach(to controller: AVPlayerViewController, engine: AVPlayerEngine) {}
}
