import Foundation
import OroroDesign

/// One frame of the CRT picture, as the `crt` shader draws it.
struct CRTFrame: Equatable {
    /// Lit raster as a fraction of the screen (the picture is squeezed into it, as deflection builds up).
    var rasterWidth: Double
    var rasterHeight: Double
    /// Brightness multiplier: 0 off, 1 at rest, well above 1 while the beam's energy is squeezed into a line.
    var exposure: Double
    /// White-hot overexposure, 0…1.
    var wash: Double
    /// Soft focus, in points.
    var blur: Double
    /// Red/blue misconvergence, in points.
    var split: Double
    /// Horizontal deflection wobble, in points (signed; oscillates while the picture settles).
    var wobble: Double
    /// Static, 0…1.
    var noise: Double

    /// Scanline period in points: matches the approved mockup (4 px lines on a stage half the TV's width).
    #if os(tvOS)
    static let scanPeriod: Double = 8
    #else
    static let scanPeriod: Double = 4
    #endif

    /// The settled picture: a hint of misconvergence and grain, as on a real set.
    static let rest = CRTFrame(rasterWidth: 1, rasterHeight: 1, exposure: 1, wash: 0, blur: 0, split: 1.0,
                               wobble: 0, noise: 0.05)
}

/// The power-on of a CRT, as a pure function of time since the intro started (`Motion.powerOn…` key times):
/// dark → a centre dot → a hot full-width line → the line opens into a washed-out, soft, colour-fringed
/// picture that dims as it grows → the tube warms and the picture settles (with a wobble) → two mains flicker
/// dips → rest. With Reduce Motion it is the settled picture throughout.
enum PowerOnCurve {
    /// The line's height: a few points on a 1080 pt screen.
    static let lineHeight = 0.004
    /// The dot's width before horizontal deflection kicks in.
    static let dotWidth = 0.004
    static let lineExposure = 6.0, openExposure = 1.6
    /// White wash left when the raster has fully opened.
    static let openWash = 0.35
    static let openBlur = 6.0, openSplit = 6.0, settleBlur = 3.0, settleSplit = 3.0, settleNoise = 0.3
    static let settleWobble = 3.0, wobbleHertz = 22.0
    /// A mains flicker dip after the early end: a triangle in exposure centred on `at` (seconds).
    struct Dip {
        let at: Double, halfWidth: Double, depth: Double
    }

    static let flicker = [Dip(at: 0.80, halfWidth: 0.05, depth: 0.12), Dip(at: 0.93, halfWidth: 0.05, depth: 0.08)]

    static func frame(at t: TimeInterval, reduceMotion: Bool) -> CRTFrame {
        guard !reduceMotion else { return .rest }
        let dot = seconds(Motion.powerOnDotAt), line = seconds(Motion.powerOnLineEnd)
        let open = seconds(Motion.powerOnOpenEnd), settled = seconds(Motion.powerOnSettled)
        let end = seconds(Motion.powerOnDuration(reduceMotion: false))

        switch t {
        case ..<dot:
            return CRTFrame(rasterWidth: dotWidth, rasterHeight: lineHeight, exposure: 0, wash: 1, blur: 0, split: 0,
                            wobble: 0, noise: 0)
        case ..<line:
            // The beam snaps out: slow at first (the dot is visible), then fast.
            let p = progress(t, from: dot, to: line)
            return CRTFrame(rasterWidth: dotWidth + (1 - dotWidth) * p * p, rasterHeight: lineHeight,
                            exposure: lineExposure, wash: 1, blur: 0, split: 0, wobble: 0, noise: 0)
        case ..<open:
            // The same energy spreads over more glass, so the picture dims as it opens.
            let p = easeOut(progress(t, from: line, to: open))
            return CRTFrame(rasterWidth: 1, rasterHeight: lineHeight + (1 - lineHeight) * p,
                            exposure: openExposure + (lineExposure - openExposure) * (1 - p), wash: 1 - (1 - openWash) * p,
                            blur: openBlur - (openBlur - settleBlur) * p, split: openSplit - (openSplit - settleSplit) * p,
                            wobble: 0, noise: settleNoise * p)
        case ..<settled:
            // The tube warms: brightness, focus and convergence settle exponentially; the geometry wobbles.
            let s = decay(progress(t, from: open, to: settled))
            let rest = CRTFrame.rest
            return CRTFrame(rasterWidth: 1, rasterHeight: 1, exposure: 1 + (openExposure - 1) * s, wash: openWash * s,
                            blur: settleBlur * s, split: rest.split + (settleSplit - rest.split) * s,
                            wobble: settleWobble * s * sin(2 * .pi * wobbleHertz * (t - open)),
                            noise: rest.noise + (settleNoise - rest.noise) * s)
        case ..<end:
            var frame = CRTFrame.rest
            for dip in flicker {
                frame.exposure -= dip.depth * max(0, 1 - abs(t - dip.at) / dip.halfWidth)
            }
            return frame
        default:
            return .rest
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private static func progress(_ t: Double, from start: Double, to end: Double) -> Double {
        min(max((t - start) / (end - start), 0), 1)
    }

    private static func easeOut(_ p: Double) -> Double {
        1 - pow(1 - p, 3)
    }

    /// 1 → 0, exponential, exactly 0 at p = 1. Gentle enough that a frame-paced step never pops the brightness.
    private static func decay(_ p: Double) -> Double {
        (exp(-2.5 * p) - exp(-2.5)) / (1 - exp(-2.5))
    }
}
