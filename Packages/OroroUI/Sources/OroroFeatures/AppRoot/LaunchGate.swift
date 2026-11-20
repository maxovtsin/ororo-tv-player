/// Decides when the root shows the loading screen. The power-on intro overlaps the real startup:
/// the loading screen stays up until the intro has finished (or been skipped) and the session
/// has left `.launching` / `.loadingCatalog`, and the intro plays once per app run.
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

    /// The catalog download's byte fraction, or nil while there's no download.
    static func progress(_ state: AppSession.State) -> Double? {
        if case .loadingCatalog(let progress) = state { progress } else { nil }
    }
}
