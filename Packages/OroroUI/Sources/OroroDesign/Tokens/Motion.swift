import SwiftUI

/// Motion tokens. Every animation in the app uses one of these; nothing is written
/// with an ad-hoc duration. Reduce Motion collapses every token to `quick`.
public enum Motion {
    public static let quick: Animation = .easeOut(duration: 0.2)
    public static let standard: Animation = .spring(duration: 0.45, bounce: 0.15)
    public static let cinematic: Animation = .easeInOut(duration: 0.6)
    /// Backdrop slow zoom over the hero dwell. Used with Reduce Motion off only.
    public static let drift: Animation = .linear(duration: 8)
    /// Skeleton loop. Static under Reduce Motion.
    public static let shimmer: Animation = .linear(duration: 1.4).repeatForever(autoreverses: false)
    public static let staggerStep: Double = 0.04, staggerMax = 5

    // MARK: Power-on intro (loading screen)
    // Timeline from the intro's start: the line grows (0–0.35 s), opens while the wordmark
    // unfolds (0.35–0.65 s), two flicker dips (0.65–1.05 s), done at 1.1 s. A warm launch ends
    // at 0.65 s, when the open completes.

    /// CRT power-on key times, from the intro's start (`PowerOnCurve` reads them).
    /// The undeflected beam lights a dot at the centre.
    public static let powerOnDotAt: Duration = .milliseconds(40)
    /// Horizontal deflection has snapped the dot out into a full-width, overexposed line.
    public static let powerOnLineEnd: Duration = .milliseconds(200)
    /// Vertical deflection has opened the line into the full picture (washed out, soft, colour-fringed).
    public static let powerOnOpenEnd: Duration = .milliseconds(420)
    /// The tube has warmed and the picture has settled.
    public static let powerOnSettled: Duration = .milliseconds(560)
    /// A warm launch, already past startup by then, ends the intro here and skips the mains flicker that follows.
    /// Kept a little after `powerOnSettled`: building Home can stall the display for a few frames, and those
    /// should show the settled picture, not cut the settle short.
    public static let powerOnEarlyEnd: Duration = .milliseconds(650)

    /// The hand-off from the power-on to the first screen, from the moment it shows: static as the channel tunes
    /// in, a hold on the old TV, then the glass flattening into the modern picture (`HandoffCurve`).
    public static let crtHandoffTuned: Duration = .milliseconds(140)
    public static let crtHandoffFlattenAt: Duration = .milliseconds(700)
    public static let crtHandoffEnd: Duration = .milliseconds(1400)

    /// The whole intro: 1.1 s, or the 0.2 s wordmark fade (`quick`) with Reduce Motion.
    public static func powerOnDuration(reduceMotion: Bool) -> Duration {
        reduceMotion ? .milliseconds(200) : .milliseconds(1100)
    }

    /// Vertical rise, in points, of a staggered appearance.
    static let staggerRise: CGFloat = 24

    /// min(index, 5) * 0.04
    public static func staggerDelay(index: Int) -> Double {
        Double(min(max(index, 0), staggerMax)) * staggerStep
    }

    /// reduceMotion → quick
    public static func resolved(_ token: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? quick : token
    }
}

public extension View {
    /// Animates changes of `value` with `token`, or with `quick` under Reduce Motion.
    func motion<V: Equatable>(_ token: Animation, value: V) -> some View {
        modifier(MotionModifier(token: token, value: value))
    }

    /// Fade + 24 pt rise, delayed by the stagger step; fade only with Reduce Motion.
    func staggeredAppearance(index: Int) -> some View {
        modifier(StaggeredAppearanceModifier(index: index))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let token: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(Motion.resolved(token, reduceMotion: reduceMotion), value: value)
    }
}

private struct StaggeredAppearanceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : Motion.staggerRise)
            .onAppear {
                let animation = Motion.resolved(Motion.standard, reduceMotion: reduceMotion)
                withAnimation(animation.delay(Motion.staggerDelay(index: index))) {
                    appeared = true
                }
            }
    }
}
