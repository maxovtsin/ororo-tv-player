import OroroCore
import OroroDesign
import SwiftUI

/// Full-screen player: AVPlayerViewController plus the session's prompts (resume, up-next countdown,
/// "Still watching?", failures). Presented and dismissed through black.
public struct PlayerScreen: View {
    private let request: PlayRequest

    @Environment(\.appEnvironment) private var environment
    @Environment(AppSession.self) private var appSession
    @Environment(PlaybackLauncher.self) private var launcher
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: PlayerModel?
    @State private var showsVideo = false
    /// The phase whose alert was answered; keeps it from re-presenting until the session moves on.
    @State private var answeredPhase: PlaybackSession.Phase?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(request: PlayRequest) {
        self.request = request
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                PlayerContainer(
                    engine: model.engine,
                    showsNextEpisodeAction: model.session.showsNextEpisodeAction,
                    onNextEpisode: { Task { await model.session.playNextNow() } }
                )
                .ignoresSafeArea()
                .opacity(showsVideo ? 1 : 0)
                overlays(for: model.session)
                    .motion(Motion.quick, value: model.session.phase)
            }
        }
        .motion(Motion.quick, value: showsVideo)
        #if os(iOS)
        .statusBarHidden()
        #endif
        .task { await start() }
        .onChange(of: model?.session.phase) { _, phase in
            answeredPhase = nil
            switch phase {
            case .playing: showsVideo = true
            case .finished: Task { await close(dismiss: true) }
            default: break
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let session = model?.session else { return }
            Task { await session.sceneBecameActive() }
        }
        .onDisappear {
            // Dismissed by the system (Menu / swipe) rather than by `close`.
            Task {
                await close(dismiss: false)
                model?.engine.stop() // idempotent; also covers a close interrupted mid-fade
            }
        }
        .alert(resumeTitle, isPresented: isPresented(\.isAskingResume)) { resumeButtons } message: { EmptyView() }
        .alert(stillWatchingTitle, isPresented: isPresented(\.isStillWatching)) { stillWatchingButtons } message: { EmptyView() }
        .alert(failureTitle, isPresented: isPresented(\.isFailed)) { failureButtons } message: { Text(failureMessage) }
    }

    // MARK: - Lifecycle

    private func start() async {
        guard model == nil else { return }
        let engine = AVPlayerEngine()
        let session = PlaybackSession(request: request, environment: environment, session: appSession, engine: engine)
        model = PlayerModel(engine: engine, session: session)
        await session.start()
    }

    /// Records progress, hands the played id to the launcher and tears the engine down — once.
    private func close(dismiss: Bool) async {
        guard let model, !model.isClosed else { return }
        model.isClosed = true
        // Silence and record first, so a cover torn down mid-fade never leaves audio playing or progress unsaved.
        model.engine.pause()
        launcher.lastPlayed = await model.session.willDismiss()
        if dismiss { await fadeToBlack() } else { showsVideo = false }
        model.engine.stop()
        if dismiss, launcher.active?.id == request.id {
            launcher.active = nil
        }
    }

    /// Lets the video fade out completely before the cover goes away (presented and dismissed through black).
    private func fadeToBlack() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            withAnimation(Motion.resolved(Motion.quick, reduceMotion: reduceMotion)) {
                showsVideo = false
            } completion: {
                done.resume()
            }
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private func overlays(for session: PlaybackSession) -> some View {
        if case let .countdown(next, secondsLeft) = session.phase {
            CountdownOverlay(
                next: next, secondsLeft: secondsLeft,
                onPlayNow: { Task { await session.playNextNow() } },
                onCancel: { session.cancelCountdown() }
            )
            .transition(.opacity)
        }
        #if os(iOS)
        if session.showsNextEpisodeAction, session.phase == .playing {
            NextEpisodeOverlayButton { Task { await session.playNextNow() } }
                .transition(.opacity)
        }
        #endif
    }

    // MARK: - Alerts

    private func isPresented(_ keyPath: KeyPath<PlaybackSession.Phase, Bool>) -> Binding<Bool> {
        Binding(
            get: {
                guard let phase = model?.session.phase, phase != answeredPhase else { return false }
                return phase[keyPath: keyPath]
            },
            set: { _ in }
        )
    }

    /// Marks the current alert answered, then runs its action.
    private func answer(_ action: @escaping @MainActor () async -> Void) {
        answeredPhase = model?.session.phase
        Task { await action() }
    }

    private var resumeTitle: Text {
        Text(String(localized: "player.resume.title", defaultValue: "Resume Playback?", bundle: .module))
    }

    @ViewBuilder private var resumeButtons: some View {
        if let session = model?.session, case let .askResume(position) = session.phase {
            let time = playerTimestamp(position)
            Button(String(localized: "player.resume.resume", defaultValue: "Resume from \(time)", bundle: .module)) {
                answer { await session.chooseResume(true) }
            }
            Button(String(localized: "player.resume.startOver", defaultValue: "Start Over", bundle: .module)) {
                answer { await session.chooseResume(false) }
            }
            Button(String(localized: "player.resume.cancel", defaultValue: "Cancel", bundle: .module), role: .cancel) {
                answer { await close(dismiss: true) }
            }
        }
    }

    private var stillWatchingTitle: Text {
        Text(String(localized: "player.stillWatching.title", defaultValue: "Still watching?", bundle: .module))
    }

    @ViewBuilder private var stillWatchingButtons: some View {
        if let session = model?.session {
            Button(String(localized: "player.stillWatching.continue", defaultValue: "Continue Watching", bundle: .module)) {
                answer { await session.confirmStillWatching(true) }
            }
            Button(String(localized: "player.stillWatching.stop", defaultValue: "Stop", bundle: .module), role: .cancel) {
                answer { await session.confirmStillWatching(false) }
            }
        }
    }

    private var failure: PlaybackSession.Failure? {
        if case let .failed(failure) = model?.session.phase { failure } else { nil }
    }

    private var failureTitle: Text {
        switch failure {
        case .notPlayable:
            Text(String(localized: "player.failure.notPlayable.title", defaultValue: "Can't play this title.", bundle: .module))
        case .fetch:
            Text(String(localized: "player.failure.fetch.title", defaultValue: "Couldn't load this title.", bundle: .module))
        case .stream, nil:
            Text(String(localized: "player.failure.stream.title", defaultValue: "Playback stopped.", bundle: .module))
        }
    }

    private var failureMessage: String {
        switch failure {
        case .notPlayable:
            String(localized: "player.failure.notPlayable.message", defaultValue: "Check your ororo.tv subscription.", bundle: .module)
        case .fetch:
            String(localized: "player.failure.fetch.message", defaultValue: "Check your connection and try again.", bundle: .module)
        case .stream, nil:
            String(localized: "player.failure.stream.message",
                   defaultValue: "The stream couldn't be loaded. Check your connection and try again.", bundle: .module)
        }
    }

    @ViewBuilder private var failureButtons: some View {
        if let session = model?.session {
            Button(String(localized: "player.failure.retry", defaultValue: "Retry", bundle: .module)) {
                answer { await session.retry() }
            }
            Button(String(localized: "player.failure.close", defaultValue: "Close", bundle: .module), role: .cancel) {
                answer { await close(dismiss: true) }
            }
        }
    }
}

/// The engine and session for one presentation; created when the screen first appears.
@MainActor private final class PlayerModel {
    let engine: AVPlayerEngine
    let session: PlaybackSession
    var isClosed = false

    init(engine: AVPlayerEngine, session: PlaybackSession) {
        self.engine = engine
        self.session = session
    }
}

private extension PlaybackSession.Phase {
    var isAskingResume: Bool {
        if case .askResume = self { true } else { false }
    }

    var isStillWatching: Bool {
        self == .stillWatching
    }

    var isFailed: Bool {
        if case .failed = self { true } else { false }
    }
}

#Preview {
    PlayerScreen(request: PlayRequest(target: .movie(1001)))
        .environment(AppSession(environment: .preview()))
        .environment(PlaybackLauncher())
}
