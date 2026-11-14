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
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment) {
        self.environment = environment
        _session = State(initialValue: AppSession(environment: environment))
    }

    var body: some View {
        ZStack {
            switch session.state {
            case .launching:
                LoadingScreen(progress: nil)
                    .transition(.opacity)
            case .signedOut:
                SignInScreen(prefilledEmail: session.storedEmail)
                    .transition(.opacity)
            case .loadingCatalog(let progress):
                LoadingScreen(progress: progress)
                    .transition(.opacity)
            case .ready:
                TabRootView(tabs: tabs)
                    .transition(.opacity)
            case .failed(let error):
                CatalogFailureScreen(error: error) {
                    Task { await session.retry() }
                }
                .transition(.opacity)
            }
        }
        .motion(Motion.cinematic, value: Phase(session.state))
        .environment(session)
        .environment(launcher)
        .environment(\.appEnvironment, environment)
        .fullScreenCover(item: $launcher.active) { request in
            PlayerScreen(request: request)
                .environment(session)
                .environment(launcher)
                .environment(tabs.router(tabs.selected))
                .environment(\.appEnvironment, environment)
        }
        .sheet(isPresented: $session.needsReauth) {
            ReauthSheet(email: session.storedEmail)
                .environment(session)
                .environment(\.appEnvironment, environment)
        }
        .task {
            if session.state == .launching { await session.start() }
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

/// `AppSession.State` without the loading fraction, so progress ticks don't re-run the root crossfade.
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

#Preview {
    AppRootView()
}
