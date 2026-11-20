import OroroCore
import OroroDesign
import SwiftUI

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
    /// Drives the sign-in sheet; see `ReauthGate`.
    @State private var presentsReauth = false
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment) {
        self.environment = environment
        _session = State(initialValue: AppSession(environment: environment))
    }

    var body: some View {
        ZStack {
            if LaunchGate.showsLoading(session.state, introFinished: introFinished) {
                // One identity across launching → loading, so the intro keeps running.
                LoadingScreen(progress: LaunchGate.progress(session.state),
                              playsIntro: LaunchGate.playsIntro(introFinished: introFinished),
                              endsEarly: LaunchGate.endsIntroEarly(session.state),
                              onIntroFinished: { introFinished = true })
                    .transition(.opacity)
            } else {
                switch session.state {
                case .signedOut:
                    SignInScreen(prefilledEmail: session.storedEmail)
                        .transition(.opacity)
                case .ready:
                    TabRootView(tabs: tabs)
                        .transition(.opacity)
                case .failed(let error):
                    CatalogFailureScreen(error: error) {
                        Task { await session.retry() }
                    }
                    .transition(.opacity)
                case .launching, .loadingCatalog:
                    // Always on the loading screen above.
                    EmptyView()
                }
            }
        }
        .motion(Motion.cinematic, value: Screen(session.state, introFinished: introFinished))
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
            case .active:
                Task { await session.sceneBecameActive() }
            default:
                break
            }
        }
    }
}

extension AppRootContent {
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
