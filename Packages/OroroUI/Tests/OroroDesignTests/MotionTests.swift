import SwiftUI
import Testing
@testable import OroroDesign

@Suite struct MotionTests {
    @Test func staggerDelayCapsAtFive() {
        #expect(Motion.staggerDelay(index: 0) == 0)
        #expect(abs(Motion.staggerDelay(index: 3) - 0.12) < 1e-9)
        #expect(abs(Motion.staggerDelay(index: 50) - 0.2) < 1e-9)
        #expect(Motion.staggerDelay(index: -2) == 0)
    }

    @Test func reduceMotionResolvesToQuick() {
        #expect(Motion.resolved(Motion.cinematic, reduceMotion: true) == Motion.quick)
        #expect(Motion.resolved(Motion.standard, reduceMotion: true) == Motion.quick)
        #expect(Motion.resolved(Motion.standard, reduceMotion: false) == Motion.standard)
        #expect(Motion.resolved(Motion.cinematic, reduceMotion: false) == Motion.cinematic)
    }

    @Test func tokenValuesArePinned() {
        #expect(Motion.quick == .easeOut(duration: 0.2))
        #expect(Motion.standard == .spring(duration: 0.45, bounce: 0.15))
        #expect(Motion.cinematic == .easeInOut(duration: 0.6))
        #expect(Motion.drift == .linear(duration: 8))
        #expect(Motion.shimmer == .linear(duration: 1.4).repeatForever(autoreverses: false))
    }

    @Test func tokensAreDistinct() {
        #expect(Motion.quick != Motion.standard)
        #expect(Motion.standard != Motion.cinematic)
    }
}
