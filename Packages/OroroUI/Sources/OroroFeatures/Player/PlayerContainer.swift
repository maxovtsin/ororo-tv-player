import AVKit
import SwiftUI

/// Hosts `AVPlayerViewController` (native transport bar, scrubbing, subtitle menu, PiP, Siri).
/// On tvOS the Next Episode action is the controller's contextual action.
struct PlayerContainer: UIViewControllerRepresentable {
    let engine: AVPlayerEngine
    var showsNextEpisodeAction = false
    var onNextEpisode: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = engine.player
        controller.allowsPictureInPicturePlayback = true
        #if os(iOS)
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        #endif
        engine.subtitles.attach(to: controller, engine: engine)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.onNextEpisode = onNextEpisode
        #if os(tvOS)
        guard context.coordinator.showsNextEpisodeAction != showsNextEpisodeAction else { return }
        context.coordinator.showsNextEpisodeAction = showsNextEpisodeAction
        controller.contextualActions = showsNextEpisodeAction ? [context.coordinator.nextEpisodeAction()] : []
        #endif
    }

    @MainActor final class Coordinator {
        var showsNextEpisodeAction = false
        var onNextEpisode: () -> Void = {}

        func nextEpisodeAction() -> UIAction {
            UIAction(
                title: String(localized: "player.nextEpisode", defaultValue: "Next Episode", bundle: .module),
                image: UIImage(systemName: "forward.end.fill")
            ) { [weak self] _ in
                self?.onNextEpisode()
            }
        }
    }
}
