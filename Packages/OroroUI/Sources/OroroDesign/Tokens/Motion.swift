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
    // unfolds (0.35–0.65 s), two flicker dips (0.65–1.05 s), done at 1.1 s.

    /// The bright line growing to full width.
    public static let powerOnLine: Animation = .easeOut(duration: 0.35)
    /// The line opening vertically and fading while the wordmark unfolds and unblurs.
    public static let powerOnOpen: Animation = .easeOut(duration: 0.3)
    /// One half of a flicker dip (down or back up).
    public static let powerOnFlicker: Animation = .easeInOut(duration: 0.1)
    /// When the open starts, from the intro's start.
    public static let powerOnOpenAt: Duration = .milliseconds(350)
    /// When the first flicker dip starts, from the intro's start.
    public static let powerOnFlickerAt: Duration = .milliseconds(650)
    /// Length of one half dip; matches `powerOnFlicker`.
    public static let powerOnFlickerStep: Duration = .milliseconds(100)
    /// Number of flicker dips, and the wordmark's opacity at the bottom of each.
    public static let powerOnFlickerDips = 2, powerOnFlickerOpacity = 0.55

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
