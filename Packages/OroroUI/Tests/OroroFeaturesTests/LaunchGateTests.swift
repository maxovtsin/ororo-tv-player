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
    @Test func warmLaunchEndsIntroAfterOpen() {
        // Past launching/loading when the open completes: the intro ends there, no flicker.
        #expect(LaunchGate.endsIntroEarly(.ready))
        #expect(LaunchGate.endsIntroEarly(.signedOut))
        #expect(LaunchGate.endsIntroEarly(.failed(.offline)))
        // Still starting up: the full intro plays.
        #expect(!LaunchGate.endsIntroEarly(.launching))
        #expect(!LaunchGate.endsIntroEarly(.loadingCatalog(0.4)))
    }
    @Test func introPlaysOnlyOnce() {
        #expect(LaunchGate.playsIntro(introFinished: false))
        #expect(!LaunchGate.playsIntro(introFinished: true))
    }
}
