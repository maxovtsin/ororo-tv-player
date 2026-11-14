import OroroCore
import OroroDesign
import SwiftUI

/// Up-next countdown shown over the ended episode: plays the next one at zero unless cancelled.
struct CountdownOverlay: View {
    let next: EpisodeRef
    let secondsLeft: Int
    let onPlayNow: () -> Void
    let onCancel: () -> Void

    @FocusState private var focusesPlayNow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(String(localized: "player.countdown.title", defaultValue: "Next Episode", bundle: .module))
                .font(Typography.headline)
                .foregroundStyle(.secondary)
            Text(String(
                localized: "player.countdown.episode",
                defaultValue: "Season \(next.season), Episode \(next.number)",
                bundle: .module
            ))
            .font(Typography.title)
            Text(String(
                localized: "player.countdown.startsIn",
                defaultValue: "Starts in \(secondsLeft) s",
                bundle: .module
            ))
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: true))
            .motion(Motion.quick, value: secondsLeft)
            .accessibilityLabel(String(
                localized: "player.countdown.startsIn.accessibility",
                defaultValue: "Starts in \(secondsLeft) seconds",
                bundle: .module
            ))
            HStack(spacing: Spacing.m) {
                ActionButton(
                    String(localized: "player.countdown.playNow", defaultValue: "Play Now", bundle: .module),
                    systemImage: "play.fill", style: .prominent, action: onPlayNow
                )
                .focused($focusesPlayNow)
                ActionButton(String(localized: "player.countdown.cancel", defaultValue: "Cancel", bundle: .module), action: onCancel)
            }
        }
        .padding(Spacing.l)
        .glassEffect(in: .rect(cornerRadius: Spacing.m))
        .tvFocusSection()
        .padding(Spacing.screenEdge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .onAppear { focusesPlayNow = true }
    }
}

private extension View {
    /// Lets the tvOS focus engine leave AVPlayerViewController for the overlay; no-op on iOS.
    @ViewBuilder
    func tvFocusSection() -> some View {
        #if os(tvOS)
        focusSection()
        #else
        self
        #endif
    }
}

/// iOS stand-in for the tvOS contextual action (AVPlayerViewController has no `contextualActions` on iOS).
struct NextEpisodeOverlayButton: View {
    let action: () -> Void

    var body: some View {
        ActionButton(
            String(localized: "player.nextEpisode", defaultValue: "Next Episode", bundle: .module),
            systemImage: "forward.end.fill", action: action
        )
        // Clears the transport bar.
        .padding(.bottom, Spacing.xl * 2)
        .padding(.trailing, Spacing.screenEdge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}

/// "mm:ss", or "h:mm:ss" from one hour, as in "Resume from 23:14".
func playerTimestamp(_ seconds: TimeInterval) -> String {
    let total = seconds.isFinite ? max(Int(seconds), 0) : 0
    let hours = total / 3600, minutes = total / 60 % 60, secs = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, secs)
        : String(format: "%02d:%02d", minutes, secs)
}

#Preview("Countdown") {
    ZStack {
        Color.black.ignoresSafeArea()
        CountdownOverlay(next: EpisodeRef(episodeID: 1, season: 2, number: 4), secondsLeft: 3, onPlayNow: {}, onCancel: {})
    }
}

#Preview("Next Episode (iOS)") {
    ZStack {
        Color.black.ignoresSafeArea()
        NextEpisodeOverlayButton {}
    }
}
