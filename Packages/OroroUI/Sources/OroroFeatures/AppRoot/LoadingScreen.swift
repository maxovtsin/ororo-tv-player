import OroroCore
import OroroDesign
import SwiftUI

/// Branded first-load screen: a CRT powering on (`PowerOnCurve`, drawn by the `crt` shader) that overlaps the
/// real startup, then a glowing progress line during a catalog download, all on the tube's curved glass.
/// `progress` is the download's byte fraction; nil while launching. When `playsIntro` is false the picture is
/// shown at rest. `endsEarly` is true once startup is over; if it is when the picture has settled
/// (`Motion.powerOnEarlyEnd`), the intro ends there without the mains flicker (a warm launch). `onIntroFinished`
/// is called once, when the intro ends or is skipped (a remote press or Menu on tvOS, a tap on iOS).
struct LoadingScreen: View {
    let progress: Double?
    let playsIntro: Bool
    let endsEarly: Bool
    let onIntroFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The power-on is playing (false: no intro, finished or skipped; the picture is at rest).
    @State private var introRunning: Bool
    /// The power-on's time origin: the first frame actually drawn.
    @State private var introClock = FrameClock()
    /// Reduce Motion: the picture fades in instead of powering on.
    @State private var faded: Bool
    @State private var reported = false
    /// `endsEarly` as of now: the intro task reads it after its sleep, when its copy of `self` is stale.
    @State private var startupOver = false
    /// Clock for the shader's static and hum bar (kept small so `Float` stays precise).
    @State private var appeared = Date()

    init(progress: Double?, playsIntro: Bool, endsEarly: Bool, onIntroFinished: @escaping () -> Void) {
        self.progress = progress
        self.playsIntro = playsIntro
        self.endsEarly = endsEarly
        self.onIntroFinished = onIntroFinished
        _introRunning = State(initialValue: playsIntro)
        _faded = State(initialValue: !playsIntro)
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let elapsed = introRunning ? introClock.elapsed() : .infinity
            let frame = PowerOnCurve.frame(at: elapsed, reduceMotion: reduceMotion)
            let time = context.date.timeIntervalSince(appeared).truncatingRemainder(dividingBy: 1000)
            GeometryReader { proxy in
                picture(in: proxy.size)
                    .layerEffect(Self.crt(frame, size: proxy.size, time: time), maxSampleOffset: .zero)
            }
        }
        .ignoresSafeArea()
        .opacity(faded ? 1 : 0)
        .motion(Motion.quick, value: progress == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress == nil ? Self.launchingLabel : Self.catalogLabel)
        .accessibilityValue(progress.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "")
        .modifier(SkipIntro(enabled: playsIntro, skip: skip))
        .onChange(of: endsEarly, initial: true) { startupOver = endsEarly }
        .task(id: playsIntro) {
            // Once the intro has finished early (a warm launch), the picture keeps settling while Home fades in;
            // only a skip snaps it to rest (`skip`).
            if playsIntro { await runIntro() } else { faded = true }
        }
    }

    // MARK: Picture

    /// What the tube shows: the warm screen, the neon wordmark and, while downloading, the progress line.
    private func picture(in size: CGSize) -> some View {
        ZStack {
            // One Canvas pass for the screen and the wordmark: inside a layer effect, a separate Image layer
            // composited without the gradient beneath it (a black box around the word).
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                context.fill(Path(rect), with: .radialGradient(
                    Gradient(colors: [Palette.screenGlow, Palette.screenBlack]), center: CGPoint(x: rect.midX, y: rect.midY),
                    startRadius: 0, endRadius: max(size.width, size.height) * 0.6))
                let image = context.resolve(Image("Wordmark", bundle: .module))
                let width = min(Self.wordmarkWidth, size.width - 2 * Spacing.screenEdge)
                let height = width * image.size.height / max(image.size.width, 1)
                context.draw(image, in: CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height))
            }
            if let progress {
                progressLine(progress, in: size)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
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

    private static func crt(_ frame: CRTFrame, size: CGSize, time: TimeInterval) -> Shader {
        ShaderLibrary.bundle(.module).crt(
            .float2(size), .float(time),
            .float(frame.rasterWidth), .float(frame.rasterHeight), .float(frame.exposure), .float(frame.wash),
            .float(frame.blur), .float(frame.split), .float(frame.wobble), .float(frame.noise),
            .float(CRTFrame.scanPeriod), .float(1)
        )
    }

    // MARK: Intro

    private func runIntro() async {
        guard introRunning else { return }
        do {
            if reduceMotion {
                withAnimation(Motion.quick) { faded = true }
                try await Task.sleep(for: Motion.powerOnDuration(reduceMotion: true))
            } else {
                faded = true
                // The power-on's own (frame-paced) time, not the wall clock: see `FrameClock`.
                await introClock.reached(Motion.powerOnEarlyEnd)
                try Task.checkCancellation()
                if startupOver {
                    // Warm launch: the picture has settled; show Home now, no mains flicker.
                    finish()
                    return
                }
                await introClock.reached(Motion.powerOnDuration(reduceMotion: false))
                try Task.checkCancellation()
            }
            introRunning = false
            finish()
        } catch {
            // Cancelled: skipped (already reported) or the screen went away.
        }
    }

    /// The picture at rest, e.g. after a skip.
    private func settle() {
        introRunning = false
        faded = true
    }

    private func skip() {
        settle()
        finish()
    }

    private func finish() {
        guard !reported else { return }
        reported = true
        onIntroFinished()
    }

    // MARK: Constants

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
