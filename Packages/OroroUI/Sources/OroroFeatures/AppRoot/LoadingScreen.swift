import OroroCore
import OroroDesign
import SwiftUI

/// Branded first-load screen: a CRT "power-on" (line → open → neon wordmark with a flicker) that
/// overlaps the real startup, then a glowing progress line during a catalog download.
/// `progress` is the download's byte fraction; nil while launching. When `playsIntro` is false the
/// wordmark is shown at rest. `endsEarly` is true once startup is over; if it is when the open
/// completes, the intro ends there without the flicker (a warm launch). `onIntroFinished` is called
/// once, when the intro ends or is skipped (a remote press or Menu on tvOS, a tap on iOS).
struct LoadingScreen: View {
    let progress: Double?
    let playsIntro: Bool
    let endsEarly: Bool
    let onIntroFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage: Stage
    @State private var dimmed = false
    @State private var reported = false
    /// `endsEarly` as of now: the intro task reads it after its sleeps, when its copy of `self` is stale.
    @State private var startupOver = false

    init(progress: Double?, playsIntro: Bool, endsEarly: Bool, onIntroFinished: @escaping () -> Void) {
        self.progress = progress
        self.playsIntro = playsIntro
        self.endsEarly = endsEarly
        self.onIntroFinished = onIntroFinished
        _stage = State(initialValue: playsIntro ? .dark : .settled)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                TubeScreen(glows: stage != .dark)
                powerOnLine(in: proxy.size)
                wordmark
                if let progress {
                    progressLine(progress, in: proxy.size)
                        .transition(.opacity)
                }
                // Over everything, so the lines run through the wordmark like a tube screen.
                Scanlines()
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .motion(Motion.quick, value: progress == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress == nil ? Self.launchingLabel : Self.catalogLabel)
        .accessibilityValue(progress.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "")
        .modifier(SkipIntro(enabled: playsIntro, skip: finish))
        .onChange(of: endsEarly, initial: true) { startupOver = endsEarly }
        .task(id: playsIntro) {
            if playsIntro { await runIntro() } else { settle() }
        }
    }

    // MARK: Layers

    /// The hot 2 pt line: grows to full width, then opens vertically and fades.
    private func powerOnLine(in size: CGSize) -> some View {
        Rectangle()
            .fill(Palette.tubeWhite)
            .frame(width: stage == .dark ? size.width * Self.lineSeed : size.width,
                   height: stage >= .open ? size.height * Self.lineOpenHeight : Self.lineThickness)
            .shadow(color: Palette.brandAmber, radius: Self.lineCore)
            .shadow(color: Palette.brandAmber, radius: Self.lineGlow)
            .opacity(stage == .line ? 1 : 0)
            .accessibilityHidden(true)
    }

    /// The neon wordmark: unfolds from 5% height and unblurs as the line opens, then flickers.
    /// With Reduce Motion it only fades in.
    private var wordmark: some View {
        Image("Wordmark", bundle: .module)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: Self.wordmarkWidth)
            .scaleEffect(x: 1, y: stage >= .open || reduceMotion ? 1 : Self.wordmarkSeed)
            .blur(radius: stage >= .open || reduceMotion ? 0 : Self.wordmarkBlur)
            .opacity(stage >= .open ? (dimmed ? Motion.powerOnFlickerOpacity : 1) : 0)
            .padding(.horizontal, Spacing.screenEdge)
            .accessibilityHidden(true)
    }

    /// Amber progress line (34% wide, 4 pt, glowing) at 68% height with the caption below.
    private func progressLine(_ progress: Double, in size: CGSize) -> some View {
        let width = size.width * Self.barWidth
        return VStack(spacing: Spacing.m) {
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.brandAmber.opacity(Self.barTrackOpacity))
                Capsule()
                    .fill(Palette.brandAmber)
                    .frame(width: width * min(max(progress, 0), 1))
                    .shadow(color: Palette.brandAmber, radius: Self.barGlow)
                    .motion(Motion.quick, value: progress)
            }
            .frame(width: width, height: Self.barThickness)
            Text(Self.catalogLabel)
                .font(Typography.caption)
                .foregroundStyle(Palette.screenCaption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, size.height * Self.barTop - Self.barThickness / 2)
    }

    // MARK: Intro

    private func runIntro() async {
        guard stage != .settled else { return }
        let clock = ContinuousClock()
        let start = clock.now
        do {
            if reduceMotion {
                withAnimation(Motion.quick) { stage = .settled }
            } else {
                withAnimation(Motion.powerOnLine) { stage = .line }
                try await clock.sleep(until: start + Motion.powerOnOpenAt)
                withAnimation(Motion.powerOnOpen) { stage = .open }
                try await clock.sleep(until: start + Motion.powerOnEarlyEnd)
                if startupOver {
                    // Warm launch: the wordmark is already up; show Home now, no flicker.
                    stage = .settled
                    finish()
                    return
                }
                for dip in 0..<Motion.powerOnFlickerDips {
                    let dipStart = start + Motion.powerOnFlickerAt + Motion.powerOnFlickerStep * (2 * dip)
                    try await clock.sleep(until: dipStart)
                    withAnimation(Motion.powerOnFlicker) { dimmed = true }
                    try await clock.sleep(until: dipStart + Motion.powerOnFlickerStep)
                    withAnimation(Motion.powerOnFlicker) { dimmed = false }
                }
            }
            try await clock.sleep(until: start + Motion.powerOnDuration(reduceMotion: reduceMotion))
            stage = .settled
            finish()
        } catch {
            // Cancelled: skipped (already reported) or the screen went away.
        }
    }

    /// The wordmark at rest, e.g. after a skip.
    private func settle() {
        guard stage != .settled || dimmed else { return }
        withAnimation(Motion.quick) {
            stage = .settled
            dimmed = false
        }
    }

    private func finish() {
        guard !reported else { return }
        reported = true
        onIntroFinished()
    }

    // MARK: Constants

    private enum Stage: Int, Comparable {
        /// The system launch screen's flat black; the line is a seed at the centre.
        case dark
        /// The line at full width.
        case line
        /// The line opened and faded; the wordmark unfolded.
        case open
        /// The wordmark at rest.
        case settled

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private static let lineThickness: CGFloat = 2, lineSeed: CGFloat = 0.02, lineOpenHeight: CGFloat = 0.4
    private static let lineCore: CGFloat = 4, lineGlow: CGFloat = 18
    private static let wordmarkSeed: CGFloat = 0.05, wordmarkBlur: CGFloat = 8
    #if os(tvOS)
    private static let wordmarkWidth: CGFloat = 960
    #else
    private static let wordmarkWidth: CGFloat = 420
    #endif
    private static let barWidth: CGFloat = 0.34, barThickness: CGFloat = 4, barTop: CGFloat = 0.68
    private static let barGlow: CGFloat = 6, barTrackOpacity = 0.18

    private static var catalogLabel: String {
        String(localized: "appRoot.loading.catalog", defaultValue: "Loading the catalog…", bundle: .module)
    }

    private static var launchingLabel: String {
        String(localized: "appRoot.loading.launching", defaultValue: "Loading", bundle: .module)
    }
}

/// The warm tube screen: radial #2B1606 → #060303 (scanlines are drawn over everything by `Scanlines`). `glows` false is
/// the flat #060303 of the system launch screen; the warm centre fades in with the power-on line.
private struct TubeScreen: View {
    let glows: Bool

    var body: some View {
        ZStack {
            Palette.screenBlack
            EllipticalGradient(colors: [Palette.screenGlow, Palette.screenBlack],
                               center: .center, startRadiusFraction: 0, endRadiusFraction: 0.75)
                .opacity(glows ? 1 : 0)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Horizontal scanlines: a dark band every `period` points, half as tall. Matches the approved mockup,
/// which drew 4 px lines on a stage half the TV's width.
private struct Scanlines: View {
    #if os(tvOS)
    private static let period: CGFloat = 8
    #else
    private static let period: CGFloat = 4
    #endif

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: Self.period / 2)),
                             with: .color(.black.opacity(0.3)))
                y += Self.period
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Lets a press skip the intro: select or Menu on tvOS, a tap on iOS. Inert once the intro is over,
/// so Menu goes back to the Home screen as usual while the catalog loads.
private struct SkipIntro: ViewModifier {
    let enabled: Bool
    let skip: () -> Void

    func body(content: Content) -> some View {
        #if os(tvOS)
        content
            .focusable(enabled)
            .onTapGesture { if enabled { skip() } }
            .onExitCommand(perform: enabled ? skip : nil)
        #else
        content
            .contentShape(Rectangle())
            .onTapGesture { if enabled { skip() } }
        #endif
    }
}

/// Full-screen catalog error with Retry: shown only when there is no cache to fall back on.
struct CatalogFailureScreen: View {
    let error: APIError
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: error == .offline ? "wifi.slash" : "exclamationmark.triangle")
                .font(Typography.heroTitle)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            Text(message)
                .font(Typography.title)
                .multilineTextAlignment(.center)
            ActionButton(String(localized: "appRoot.error.retry", defaultValue: "Retry", bundle: .module),
                         systemImage: "arrow.clockwise", style: .prominent, action: retry)
        }
        .padding(Spacing.screenEdge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var message: String {
        switch error {
        case .offline:
            String(localized: "appRoot.error.offline",
                   defaultValue: "You're offline. Check your connection and try again.", bundle: .module)
        default:
            // `.unauthorized` never reaches this screen: it returns to sign-in.
            String(localized: "appRoot.error.server",
                   defaultValue: "Couldn't load the catalog from ororo.tv. Try again in a moment.", bundle: .module)
        }
    }
}

#Preview("Power-on") {
    LoadingScreen(progress: nil, playsIntro: true, endsEarly: false) {}
}

#Preview("Loading") {
    LoadingScreen(progress: 0.4, playsIntro: false, endsEarly: false) {}
}

#Preview("Offline") {
    CatalogFailureScreen(error: .offline) {}
}
