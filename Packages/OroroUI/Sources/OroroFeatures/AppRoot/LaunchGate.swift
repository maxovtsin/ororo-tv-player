/// Decides when the root shows the loading screen. The power-on intro overlaps the real startup:
/// the loading screen stays up until the intro has finished (or been skipped) and the session
/// has left `.launching` / `.loadingCatalog`, and the intro plays once per app run. On a warm
/// launch (already past startup when the open completes) the intro ends there, without the flicker.
enum LaunchGate {
    static func showsLoading(_ state: AppSession.State, introFinished: Bool) -> Bool {
        switch state {
        case .launching, .loadingCatalog: true
        case .signedOut, .ready, .failed: !introFinished
        }
    }

    static func playsIntro(introFinished: Bool) -> Bool {
        !introFinished
    }

    /// Whether the intro ends when its open completes (`Motion.powerOnEarlyEnd`) rather than
    /// playing the flicker: true once the session has left `.launching` / `.loadingCatalog`.
    static func endsIntroEarly(_ state: AppSession.State) -> Bool {
        switch state {
        case .launching, .loadingCatalog: false
        case .signedOut, .ready, .failed: true
        }
    }

    /// The catalog download's byte fraction, or nil while there's no download.
    static func progress(_ state: AppSession.State) -> Double? {
        if case .loadingCatalog(let progress) = state { progress } else { nil }
    }

    /// Whether the CRT hand-off overlay shows: one is pending (the power-on just ended) and the loading screen has
    /// given way to the next screen.
    static func showsCRTHandoff(pending: Bool, state: AppSession.State, introFinished: Bool) -> Bool {
        pending && !showsLoading(state, introFinished: introFinished)
    }
}
