import Foundation
import OroroDesign
@testable import OroroFeatures
import Testing

/// The hand-off from the power-on to the first screen: static as the channel tunes in, a hold on the old TV,
/// then the glass flattening into the modern picture.
@Suite struct HandoffCurveTests {
    private func frame(_ duration: Duration) -> CRTOverlayFrame {
        HandoffCurve.frame(at: Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
    }

    @Test func tunesInThroughStatic() {
        let start = frame(.zero)
        #expect(start.strength == 1)
        #expect(start.noise > 0.5)
        #expect(start.exposure < 1)
        let tuned = frame(Motion.crtHandoffTuned)
        #expect(tuned.noise <= CRTOverlayFrame.oldTV.noise + 1e-9)
        #expect(tuned.exposure == 1)
    }

    @Test func holdsOnTheOldTV() {
        #expect(frame(Motion.crtHandoffTuned + .milliseconds(10)) == .oldTV)
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
}
