import Foundation
import OroroDesign

/// One frame of the old-TV overlay drawn over the first screen after the power-on (the `crtOverlay` shader).
struct CRTOverlayFrame: Equatable {
    /// How much of the tube is left: curved-glass edges, scanlines, vignette, hum bar, reflection (0 is gone).
    var strength: Double
    /// Grain, 0…1.
    var noise: Double

    /// The picture on the old TV, as the power-on left it.
    static let oldTV = CRTOverlayFrame(strength: 1, noise: CRTFrame.rest.noise)
    /// No overlay at all.
    static let modern = CRTOverlayFrame(strength: 0, noise: 0)
}

/// The hand-off from the power-on to the first screen, as a pure function of time since it showed
/// (`Motion.crtHandoff…`): the picture holds on the old TV, then the glass flattens smoothly into the modern picture.
enum HandoffCurve {
    static func frame(at t: TimeInterval) -> CRTOverlayFrame {
        let flattenAt = seconds(Motion.crtHandoffFlattenAt), end = seconds(Motion.crtHandoffEnd)
        switch t {
        case ..<flattenAt:
            return .oldTV
        case ..<end:
            let p = (t - flattenAt) / (end - flattenAt)
            let strength = 1 - p * p * (3 - 2 * p)
            return CRTOverlayFrame(strength: strength, noise: CRTOverlayFrame.oldTV.noise * strength)
        default:
            return .modern
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
