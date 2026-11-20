import OroroDesign
import SwiftUI

/// The old TV drawn over the first screen after the power-on (`HandoffCurve`, the `crtOverlay` shader): a hold,
/// then the glass flattening into the modern picture. The screen beneath stays live:
/// the overlay takes no touches or focus. Calls `onStarted` once the screen beneath draws steadily (its first
/// render is done) and `onFinished` once the glass has gone.
struct CRTHandoffOverlay: View {
    let onStarted: () -> Void
    let onFinished: () -> Void

    @State private var clock = FrameClock()
    /// Clock for the static and hum bar (kept small so `Float` stays precise).
    @State private var appeared = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let frame = HandoffCurve.frame(at: clock.elapsed())
            let time = context.date.timeIntervalSince(appeared).truncatingRemainder(dividingBy: 1000)
            GeometryReader { proxy in
                Rectangle()
                    .colorEffect(ShaderLibrary.bundle(.module).crtOverlay(
                        .float2(proxy.size), .float(time), .float(frame.strength), .float(frame.noise),
                        .float(CRTFrame.scanPeriod)
                    ))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            await clock.reached(.zero)
            guard !Task.isCancelled else { return }
            onStarted()
            await clock.reached(Motion.crtHandoffEnd)
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }
}
