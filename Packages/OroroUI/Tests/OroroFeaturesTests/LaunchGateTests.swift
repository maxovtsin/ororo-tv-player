import OroroCore
@testable import OroroFeatures
import Testing

@Suite struct LaunchGateTests {
    @Test func waitsForIntroWhenReadyEarly() {
        #expect(LaunchGate.showsLoading(.ready, introFinished: false))
        #expect(!LaunchGate.showsLoading(.ready, introFinished: true))
    }
    @Test func signedOutAfterIntro() {
        #expect(LaunchGate.showsLoading(.signedOut, introFinished: false))
        #expect(!LaunchGate.showsLoading(.signedOut, introFinished: true))
    }
    @Test func failedAfterIntro() {
        #expect(LaunchGate.showsLoading(.failed(.offline), introFinished: false))
        #expect(!LaunchGate.showsLoading(.failed(.offline), introFinished: true))
    }
    @Test func loadingStatesAlwaysShowLoading() {
        #expect(LaunchGate.showsLoading(.launching, introFinished: true))
        #expect(LaunchGate.showsLoading(.loadingCatalog(0.4), introFinished: true))
        #expect(LaunchGate.progress(.loadingCatalog(0.4)) == 0.4)
        #expect(LaunchGate.progress(.launching) == nil)
    }
    @Test func skippedIntroCountsAsFinished() {
        // A press marks the intro finished; the gate then follows the session alone.
        #expect(!LaunchGate.showsLoading(.ready, introFinished: true))
    }
    @Test func introPlaysOnlyOnce() {
        #expect(LaunchGate.playsIntro(introFinished: false))
        #expect(!LaunchGate.playsIntro(introFinished: true))
    }
}
