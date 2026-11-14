import SwiftUI

// STUB (T3) — implemented by Task D1. Token values are the plan's; helpers are no-ops.
public enum Motion {
    public static let quick: Animation = .easeOut(duration: 0.2)
    public static let standard: Animation = .spring(duration: 0.45, bounce: 0.15)
    public static let cinematic: Animation = .easeInOut(duration: 0.6)
    public static let staggerStep: Double = 0.04, staggerMax = 5

    /// min(index, 5) * 0.04
    public static func staggerDelay(index: Int) -> Double {
        0
    }

    /// reduceMotion → quick
    public static func resolved(_ token: Animation, reduceMotion: Bool) -> Animation {
        token
    }
}

public extension View {
    /// Reads accessibilityReduceMotion.
    func motion<V: Equatable>(_ token: Animation, value: V) -> some View {
        self
    }

    /// Fade + 24 pt rise; fade only with Reduce Motion.
    func staggeredAppearance(index: Int) -> some View {
        self
    }
}
