import Foundation
import OroroDesign

/// One frame of the old-TV overlay drawn over the first screen after the power-on (the `crtOverlay` shader).
struct CRTOverlayFrame: Equatable {
    /// How much of the tube is left: curved-glass edges, scanlines, vignette, hum bar, reflection (0 is gone).
    var strength: Double
    /// Static, 0…1.
    var noise: Double
    /// Picture brightness: below 1 while the channel tunes in.
    var exposure: Double

    /// The picture on the old TV, as the power-on left it.
    static let oldTV = CRTOverlayFrame(strength: 1, noise: CRTFrame.rest.noise, exposure: 1)
    /// No overlay at all.
    static let modern = CRTOverlayFrame(strength: 0, noise: 0, exposure: 1)
}

/// The hand-off from the power-on to the first screen, as a pure function of time since it showed
/// (`Motion.crtHandoff…`): the channel tunes in through a burst of static (which also hides the new screen's first
/// render), the picture holds on the old TV, then the glass flattens smoothly into the modern picture.
enum HandoffCurve {
    static let tuneNoise = 0.9, tuneExposure = 0.6

    static func frame(at t: TimeInterval) -> CRTOverlayFrame {
        let tuned = seconds(Motion.crtHandoffTuned), flattenAt = seconds(Motion.crtHandoffFlattenAt)
        let end = seconds(Motion.crtHandoffEnd)
        switch t {
        case ..<tuned:
            let p = max(t, 0) / tuned
            return CRTOverlayFrame(strength: 1, noise: tuneNoise + (CRTOverlayFrame.oldTV.noise - tuneNoise) * p,
                                   exposure: tuneExposure + (1 - tuneExposure) * p)
        case ..<flattenAt:
            return .oldTV
        case ..<end:
            let p = (t - flattenAt) / (end - flattenAt)
            let strength = 1 - p * p * (3 - 2 * p)
            return CRTOverlayFrame(strength: strength, noise: CRTOverlayFrame.oldTV.noise * strength, exposure: 1)
        default:
            return .modern
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
