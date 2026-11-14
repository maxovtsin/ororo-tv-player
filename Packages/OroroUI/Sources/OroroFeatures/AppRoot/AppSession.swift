import Foundation
import Observation
import os
import OroroCore
import OroroStore
import Synchronization

/// App-wide session: sign-in state, the current catalog and the new-episode info derived from it.
@MainActor @Observable public final class AppSession {
    public enum State: Equatable { case launching, signedOut, loadingCatalog(Double), ready, failed(APIError) }

    public private(set) var state: State = .launching
    /// Nil while only the Home snapshot is available.
    public private(set) var catalog: Catalog?
    /// Bumps when a new catalog is swapped in.
    public private(set) var catalogVersion = 0
    public private(set) var newEpisodeInfo: [Int: NewEpisodeInfo] = [:]
    public var needsReauth = false
    /// The email of the stored credentials, read once; prefills the sign-in screens.
    private(set) var storedEmail: String?

    private let environment: AppEnvironment
    private let now: @MainActor () -> Date
    /// The background catalog work started by `start()` (cache decode and refresh).
    @ObservationIgnored private var backgroundWork: Task<Void, Never>?
    /// The refresh in flight, shared by overlapping callers.
    @ObservationIgnored private var refreshInFlight: Task<Void, Never>?
    /// True from `start()` until its catalog work (decode + first refresh) has finished.
    @ObservationIgnored private(set) var isLaunching = false
    /// Tokens of the `signIn` calls still downloading; each call's progress hand-off is gated by its own token.
    @ObservationIgnored private var activeSignIns: Set<Int> = []
    @ObservationIgnored private var nextSignInToken = 0
    /// Credentials of a sign-in that failed after `/shows` succeeded; they are not stored yet, so Retry uses them.
    @ObservationIgnored private var pendingCredentials: Credentials?

    private static let log = Logger(subsystem: "com.dissimirall.Ororo-Player", category: "AppSession")

    public convenience init(environment: AppEnvironment) {
        self.init(environment: environment, now: { Date() })
    }

    init(environment: AppEnvironment, now: @escaping @MainActor () -> Date) {
        self.environment = environment
        self.now = now
    }

    /// Credentials? → loadCached → ready; then refresh in background.
    public func start() async {
        guard let credentials = environment.credentials.load() else {
            storedEmail = nil
            state = .signedOut
            return
        }
        storedEmail = credentials.email
        isLaunching = true
        newEpisodeInfo = await environment.newEpisodes.cached()

        // Later launches: Home renders from its snapshot while the full lists decode.
        if await environment.catalog.homeSnapshot() != nil {
            state = .ready
            backgroundWork = Task { [weak self] in
                guard let self else { return }
                await self.loadCacheThenRefresh(credentials: credentials)
                self.isLaunching = false
            }
            return
        }
        if let cached = await environment.catalog.loadCached() {
            install(cached)
            state = .ready
            backgroundWork = Task { [weak self] in
                guard let self else { return }
                await self.refresh(force: false)
                self.isLaunching = false
            }
            return
        }
        await loadFromNetwork(credentials)
        isLaunching = false
    }

    /// Stays `.signedOut` while `/shows` downloads (a 401 or offline error shows on the form). Once progress
    /// passes 0.5 — `/shows` succeeded and `/movies` is downloading — the state becomes `.loadingCatalog(progress)`; a later failure is
    /// `.failed(error)` with Retry.
    public func signIn(email: String, password: String) async throws {
        let credentials = Credentials(email: email, password: password)
        let catalogProvider = environment.catalog
        nextSignInToken += 1
        let token = nextSignInToken
        activeSignIns.insert(token)
        defer { activeSignIns.remove(token) }
        // Recorded synchronously, so a failure right after `/shows` is classified even before the progress hop lands.
        let showsSucceeded = Mutex(false)
        // Unstructured so the download survives the sign-in form disappearing when the loading screen takes over.
        let download = Task { [weak self] in
            try await catalogProvider.signIn(credentials) { [weak self] fraction in
                if fraction > 0.5 { showsSucceeded.withLock { $0 = true } }
                Task { @MainActor in self?.signInProgress(fraction, token: token) }
            }
        }
        let loaded: Catalog
        do {
            loaded = try await download.value
        } catch is CancellationError {
            // A benign overlap (superseded load or a cancelled request): never shown to the user.
            if case .loadingCatalog = state { state = .signedOut }
            return
        } catch {
            if showsSucceeded.withLock({ $0 }), state == .signedOut || state.isLoadingCatalog {
                pendingCredentials = credentials
                state = .failed(error as? APIError ?? .server(status: 0))
            }
            throw error
        }
        storedEmail = credentials.email
        pendingCredentials = nil
        install(loaded)
        needsReauth = false
        state = .ready
        await resolveNewEpisodes()
    }

    /// Clears credentials, details, catalog cache; library untouched.
    public func signOut() async {
        backgroundWork?.cancel()
        backgroundWork = nil
        refreshInFlight?.cancel()
        refreshInFlight = nil
        isLaunching = false
        pendingCredentials = nil
        // Everything in memory goes before the first await, so loads cancelled by `clear()` below see
        // `.signedOut` and never restore an earlier state.
        catalog = nil
        storedEmail = nil
        newEpisodeInfo = [:]
        needsReauth = false
        state = .signedOut
        do {
            try environment.credentials.clear()
        } catch {
            // Sign-out still completes locally; the Keychain failure is logged rather than shown.
            Self.log.error("Clearing credentials failed: \(String(describing: error), privacy: .public)")
        }
        await environment.details.clear()
        await environment.catalog.clear()
    }

    /// Overlapping calls share the refresh in flight; a forced one runs again after it.
    public func refresh(force: Bool) async {
        while let inFlight = refreshInFlight {
            await inFlight.value
            if refreshInFlight == inFlight { refreshInFlight = nil }
            guard force else { return }
        }
        let work = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(force: force)
        }
        refreshInFlight = work
        await work.value
        if refreshInFlight == work { refreshInFlight = nil }
    }

    /// Refresh if stale. Skipped during the launch window, which already decodes and refreshes.
    public func sceneBecameActive() async {
        guard state == .ready, !isLaunching else { return }
        if let lastUpdated = await environment.catalog.lastUpdated(),
           now().timeIntervalSince(lastUpdated) < CatalogRepository.staleness {
            return
        }
        await refresh(force: false)
    }

    /// `.unauthorized` → needsReauth = true. `CancellationError` is ignored.
    public func report(_ error: any Error) {
        guard !(error is CancellationError) else { return }
        if let apiError = error as? APIError, apiError == .unauthorized, state == .ready {
            needsReauth = true
        }
    }

    public func retry() async {
        guard case .failed = state else { return }
        // Kept until success, a 401 or sign-out, so repeated failures can be retried without retyping.
        if let pending = pendingCredentials {
            await loadFromNetwork(pending)
            return
        }
        state = .launching
        await start()
    }

    // MARK: - Private

    private func loadCacheThenRefresh(credentials: Credentials) async {
        let cached = await environment.catalog.loadCached()
        // Signed out (or otherwise moved on) while decoding.
        guard !Task.isCancelled, state == .ready else { return }
        guard let cached else {
            // The snapshot outlived the lists: load them again.
            await loadFromNetwork(credentials)
            return
        }
        install(cached)
        await refresh(force: false)
    }

    /// Credentials but no usable cache: the branded loading screen with byte progress.
    private func loadFromNetwork(_ credentials: Credentials) async {
        let previous = state
        state = .loadingCatalog(0)
        do {
            let loaded = try await environment.catalog.signIn(credentials) { [weak self] fraction in
                Task { @MainActor in self?.updateProgress(fraction) }
            }
            // A sign-out while downloading already moved the state on.
            guard case .loadingCatalog = state else { return }
            pendingCredentials = nil
            storedEmail = credentials.email
            install(loaded)
            state = .ready
            await resolveNewEpisodes()
        } catch is CancellationError {
            // Superseded by a sign-out or another sign-in; never stay on the loading screen.
            if case .loadingCatalog = state { state = previous }
        } catch {
            guard case .loadingCatalog = state else { return }
            if let apiError = error as? APIError, apiError == .unauthorized {
                pendingCredentials = nil
                state = .signedOut
            } else {
                state = .failed(error as? APIError ?? .server(status: 0))
            }
        }
    }

    private func updateProgress(_ fraction: Double) {
        guard case .loadingCatalog(let current) = state, fraction > current else { return }
        state = .loadingCatalog(min(1, fraction))
    }

    /// `/shows` is the first half of the progress, and only it can answer 401. Exactly 0.5 can still precede a 401
    /// (the transport reports the body before checking the status), so only `/movies` progress (> 0.5) counts.
    private func signInProgress(_ fraction: Double, token: Int) {
        guard activeSignIns.contains(token), fraction > 0.5 else { return }
        switch state {
        case .signedOut: state = .loadingCatalog(min(1, fraction))
        case .loadingCatalog: updateProgress(fraction)
        default: break
        }
    }

    private func performRefresh(force: Bool) async {
        do {
            let changed = try await environment.catalog.refresh(force: force, now: now())
            guard !Task.isCancelled else { return }
            if changed, let current = await environment.catalog.current() {
                install(current)
            }
            await resolveNewEpisodes()
        } catch {
            // With a cache, failures stay silent; retried on the next trigger. A 401 asks for sign-in again.
            report(error)
        }
    }

    private func install(_ newCatalog: Catalog) {
        catalog = newCatalog
        catalogVersion += 1
    }

    private func resolveNewEpisodes() async {
        guard let catalog else { return }
        let library = await environment.library.snapshot()
        // Only the shows the New Episodes row shows (Continue Watching ones are excluded there).
        let shows = LibraryQueries.newEpisodes(library, catalog: catalog, resolved: [:]).map(\.title)
        let resolved = await environment.newEpisodes.resolve(shows: shows, library: library)
        guard !Task.isCancelled, state == .ready else { return }
        newEpisodeInfo = resolved
    }
}

private extension AppSession.State {
    var isLoadingCatalog: Bool {
        if case .loadingCatalog = self { return true }
        return false
    }
}
