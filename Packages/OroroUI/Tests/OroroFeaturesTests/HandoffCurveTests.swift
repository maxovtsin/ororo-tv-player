import Foundation
import OroroDesign
@testable import OroroFeatures
import Testing

/// The hand-off from the power-on to the first screen: a hold on the old TV, then the glass flattening into the
/// modern picture.
@Suite struct HandoffCurveTests {
    private func frame(_ duration: Duration) -> CRTOverlayFrame {
        HandoffCurve.frame(at: Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
    }

    /// No static burst: the first screen appears straight on the old TV, as the power-on left it.
    @Test func startsOnTheOldTVWithoutStatic() {
        #expect(frame(.zero) == .oldTV)
        #expect(frame(Motion.crtHandoffFlattenAt / 2) == .oldTV)
        #expect(frame(Motion.crtHandoffFlattenAt) == .oldTV)
    }

    @Test func flattensSmoothlyToTheModernPicture() {
        var previous = frame(Motion.crtHandoffFlattenAt)
        var t = Motion.crtHandoffFlattenAt
        while t < Motion.crtHandoffEnd {
            t += .milliseconds(5)
            let next = frame(t)
            #expect(next.strength <= previous.strength)
            #expect(previous.strength - next.strength < 0.05, "jump at \(t)")
            previous = next
        }
        #expect(frame(Motion.crtHandoffEnd) == .modern)
        #expect(frame(.seconds(10)) == .modern)
    }

    @Test func overlayShowsOnlyOnceTheLoadingScreenHasGone() {
        #expect(LaunchGate.showsCRTHandoff(pending: true, state: .ready, introFinished: true))
        #expect(LaunchGate.showsCRTHandoff(pending: true, state: .signedOut, introFinished: true))
        // Still on the loading screen (catalog downloading after the intro): not yet.
        #expect(!LaunchGate.showsCRTHandoff(pending: true, state: .loadingCatalog(0.4), introFinished: true))
        #expect(!LaunchGate.showsCRTHandoff(pending: false, state: .ready, introFinished: true))
    }

    /// The power-on picture stays on top of the new screen until that screen draws steadily (the hand-off has
    /// started), so its first, empty frames never show.
    @Test func loadingScreenCoversTheNewScreenUntilTheHandoffStarts() {
        #expect(LaunchGate.showsLoadingScreen(.ready, introFinished: true, handoffPending: true, handoffStarted: false))
        #expect(!LaunchGate.showsLoadingScreen(.ready, introFinished: true, handoffPending: true, handoffStarted: true))
        // No hand-off (Reduce Motion, or a later catalog load): the usual rule.
        #expect(!LaunchGate.showsLoadingScreen(.ready, introFinished: true, handoffPending: false, handoffStarted: false))
        #expect(LaunchGate.showsLoadingScreen(.loadingCatalog(0.3), introFinished: true, handoffPending: false,
                                              handoffStarted: false))
    }
}
