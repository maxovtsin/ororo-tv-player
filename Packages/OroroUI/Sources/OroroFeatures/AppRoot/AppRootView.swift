import OroroCore
import OroroDesign
import SwiftUI
import UIKit

/// The app's root: sign-in, catalog loading, the tabs, and the full-screen player.
public struct AppRootView: View {
    @Environment(\.appEnvironment) private var environment

    public init() {}

    public var body: some View {
        AppRootContent(environment: environment)
    }
}

/// The selected tab and one router per tab; outlives tab switches.
@MainActor @Observable final class TabsModel {
    var selected: AppTab = .home
    let routers: [AppTab: TabRouter] = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, TabRouter()) })

    func router(_ tab: AppTab) -> TabRouter {
        // Every case is created above.
        routers[tab] ?? TabRouter()
    }
}

private struct AppRootContent: View {
    let environment: AppEnvironment

    @State private var session: AppSession
    @State private var launcher = PlaybackLauncher()
    @State private var tabs = TabsModel()
    /// The power-on intro has ended or been skipped; it plays once per app run. See `LaunchGate`.
    @State private var introFinished = false
    /// The first screen after the power-on appears on the old TV, then the glass flattens away
    /// (`CRTHandoffOverlay`). Set at launch, so the loading screen already carries the instant transition when
    /// it is removed (a removed view uses the transition from its last body); cleared when the hand-off ends.
    /// Off with Reduce Motion (a plain crossfade).
    @State private var crtHandoffPending = false
    /// The screen beneath the loading screen draws steadily: the loading screen can go (`LaunchGate`).
    @State private var crtHandoffStarted = false
    /// Drives the sign-in sheet; see `ReauthGate`.
    @State private var presentsReauth = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(environment: AppEnvironment) {
        self.environment = environment
        _session = State(initialValue: AppSession(environment: environment))
    }

    var body: some View {
        ZStack {
            if !LaunchGate.showsLoading(session.state, introFinished: introFinished) {
                switch session.state {
                case .signedOut:
                    SignInScreen(prefilledEmail: session.storedEmail)
                        .transition(screenTransition)
                case .ready:
                    TabRootView(tabs: tabs)
                        .transition(screenTransition)
                case .failed(let error):
                    CatalogFailureScreen(error: error) {
                        Task { await session.retry() }
                    }
                    .transition(screenTransition)
                case .launching, .loadingCatalog:
                    // Always on the loading screen.
                    EmptyView()
                }
            }
            if LaunchGate.showsCRTHandoff(pending: crtHandoffPending, state: session.state, introFinished: introFinished) {
                CRTHandoffOverlay(onStarted: { crtHandoffStarted = true }, onFinished: { crtHandoffPending = false })
                    .transition(.identity)
            }
            // On top: during a CRT hand-off it covers the new screen until that screen draws steadily.
            if LaunchGate.showsLoadingScreen(session.state, introFinished: introFinished,
                                             handoffPending: crtHandoffPending, handoffStarted: crtHandoffStarted) {
                // One identity across launching → loading, so the intro keeps running.
                LoadingScreen(progress: LaunchGate.progress(session.state),
                              playsIntro: LaunchGate.playsIntro(introFinished: introFinished),
                              endsEarly: LaunchGate.endsIntroEarly(session.state),
                              onIntroFinished: { introFinished = true })
                    .transition(screenTransition)
            }
        }
        // Not during the CRT hand-off: its screen swap must commit at once rather than keep the loading screen
        // around for the crossfade's duration.
        .motion(Motion.cinematic, value: crtHandoffPending ? nil : Screen(session.state, introFinished: introFinished))
        .environment(session)
        .environment(launcher)
        .environment(\.appEnvironment, environment)
        .fullScreenCover(item: $launcher.active, onDismiss: updateReauth) { request in
            PlayerScreen(request: request)
                .environment(session)
                .environment(launcher)
                .environment(tabs.router(tabs.selected))
                .environment(\.appEnvironment, environment)
                .environment(\.selectTab, SelectTabAction { [tabs] tab in tabs.selected = tab })
        }
        .sheet(isPresented: $presentsReauth, onDismiss: { session.needsReauth = false }, content: {
            ReauthSheet(email: session.storedEmail)
                .environment(session)
                .environment(\.appEnvironment, environment)
        })
        .onChange(of: session.needsReauth, initial: true) { updateReauth() }
        .onAppear { crtHandoffPending = !reduceMotion }
        .task {
            if session.state == .launching { await session.start() }
        }
        .onChange(of: Phase(session.state)) { _, phase in
            // A new account starts on Home with empty stacks and no focus memory.
            if phase == .signedOut { tabs = TabsModel() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                Task { await environment.library.flush() }
                // The next launch starts on the launch screen (the power-on's dark first frame), not a blurred
                // snapshot of where the user left off.
                UIApplication.shared.ignoreSnapshotOnNextApplicationLaunch()
            case .active:
                Task { await session.sceneBecameActive() }
            default:
                break
            }
        }
    }
}

extension AppRootContent {
    /// The CRT hand-off swaps screens instantly (the old TV just changes picture); otherwise they crossfade.
    private var screenTransition: AnyTransition {
        crtHandoffPending ? .identity : .opacity
    }

    private func updateReauth() {
        presentsReauth = ReauthGate.presents(needsReauth: session.needsReauth, playerActive: launcher.active != nil)
    }
}

/// The sign-in sheet can't present over the player cover, so it waits until the player is gone
/// (re-evaluated when `needsReauth` changes and after the cover finishes dismissing).
enum ReauthGate {
    static func presents(needsReauth: Bool, playerActive: Bool) -> Bool {
        needsReauth && !playerActive
    }
}

/// `AppSession.State` without the loading fraction.
private enum Phase: Equatable {
    case launching, signedOut, loading, ready, failed

    init(_ state: AppSession.State) {
        switch state {
        case .launching: self = .launching
        case .signedOut: self = .signedOut
        case .loadingCatalog: self = .loading
        case .ready: self = .ready
        case .failed: self = .failed
        }
    }
}

/// What the root shows, without the loading fraction, so progress ticks don't re-run the crossfade.
private enum Screen: Equatable {
    case loading, signedOut, ready, failed

    init(_ state: AppSession.State, introFinished: Bool) {
        if LaunchGate.showsLoading(state, introFinished: introFinished) {
            self = .loading
            return
        }
        switch state {
        case .launching, .loadingCatalog: self = .loading
        case .signedOut: self = .signedOut
        case .ready: self = .ready
        case .failed: self = .failed
        }
    }
}

#Preview {
    AppRootView()
}
