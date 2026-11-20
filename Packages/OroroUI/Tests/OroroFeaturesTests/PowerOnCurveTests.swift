import Foundation
import OroroDesign
@testable import OroroFeatures
import Testing

/// The CRT power-on as a function of time: dot → line → raster opening overexposed → settling.
@Suite struct PowerOnCurveTests {
    private func frame(_ duration: Duration, reduceMotion: Bool = false) -> CRTFrame {
        PowerOnCurve.frame(at: Double(duration.components.attoseconds) / 1e18 + Double(duration.components.seconds),
                           reduceMotion: reduceMotion)
    }

    @Test func screenIsDarkAtTheStart() {
        #expect(frame(.zero).exposure == 0)
    }

    @Test func dotThenAHotHorizontalLine() {
        let dot = frame(Motion.powerOnDotAt + .milliseconds(10))
        #expect(dot.exposure > 3)
        #expect(dot.rasterWidth < 0.05)
        #expect(dot.rasterHeight < 0.01)

        let line = frame(Motion.powerOnLineEnd)
        #expect(line.rasterWidth > 0.99)
        #expect(line.rasterHeight < 0.01)
        #expect(line.exposure > 3)
        #expect(line.wash > 0.8)
    }

    @Test func rasterOpensOverexposedAndDimsAsItGrows() {
        let mid = Motion.powerOnLineEnd + (Motion.powerOnOpenEnd - Motion.powerOnLineEnd) / 2
        let opening = frame(mid)
        #expect(opening.rasterHeight > 0.05 && opening.rasterHeight < 1)
        #expect(opening.exposure > 1.2)
        #expect(opening.exposure < frame(Motion.powerOnLineEnd).exposure)

        let open = frame(Motion.powerOnOpenEnd)
        #expect(open.rasterHeight > 0.99)
        #expect(open.blur > 0)
        #expect(open.split > CRTFrame.rest.split)
    }

    /// A warm launch ends the intro at `powerOnEarlyEnd`, so the picture must already be at rest a little before.
    @Test func pictureHasSettledBeforeTheEarlyEnd() {
        #expect(frame(Motion.powerOnEarlyEnd) == .rest)
        let settled = frame(Motion.powerOnSettled)
        #expect(settled.rasterWidth == 1 && settled.rasterHeight == 1)
        #expect(abs(settled.exposure - 1) < 0.1)
        #expect(settled.wash < 0.05)
        #expect(settled.blur < 0.5)
    }

    @Test func endsAtRest() {
        #expect(frame(Motion.powerOnDuration(reduceMotion: false)) == .rest)
        #expect(frame(.seconds(30)) == .rest)
    }

    /// No jumps in the raster once the beam is on: it grows smoothly.
    @Test func rasterGrowsContinuously() {
        var previous = frame(Motion.powerOnDotAt)
        var t = Motion.powerOnDotAt
        while t < Motion.powerOnDuration(reduceMotion: false) {
            t += .milliseconds(1)
            let next = frame(t)
            #expect(abs(next.rasterWidth - previous.rasterWidth) < 0.05, "width jump at \(t)")
            #expect(abs(next.rasterHeight - previous.rasterHeight) < 0.05, "height jump at \(t)")
            #expect(next.rasterWidth >= previous.rasterWidth - 1e-9)
            previous = next
        }
    }

    @Test func reduceMotionIsTheSettledPictureThroughout() {
        for ms in stride(from: 0, through: 1200, by: 100) {
            #expect(frame(.milliseconds(ms), reduceMotion: true) == .rest)
        }
    }
}
