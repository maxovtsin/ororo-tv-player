import Foundation
import Observation
import OroroCore
import OroroStore

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

    private let environment: AppEnvironment
    /// The background catalog work started by `start()` (cache decode and refresh); tests await it.
    @ObservationIgnored private(set) var backgroundWork: Task<Void, Never>?
    /// The refresh in flight, shared by overlapping callers.
    @ObservationIgnored private var refreshInFlight: Task<Void, Never>?

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// The email of the stored credentials, used to prefill sign-in sheets.
    var storedEmail: String? {
        environment.credentials.load()?.email
    }

    /// Credentials? → loadCached → ready; then refresh in background.
    public func start() async {
        guard let credentials = environment.credentials.load() else {
            state = .signedOut
            return
        }
        newEpisodeInfo = await environment.newEpisodes.cached()

        // Later launches: Home renders from its snapshot while the full lists decode.
        if await environment.catalog.homeSnapshot() != nil {
            state = .ready
            backgroundWork = Task { [weak self] in
                guard let self else { return }
                await self.loadCacheThenRefresh(credentials: credentials)
            }
            return
        }
        if let cached = await environment.catalog.loadCached() {
            install(cached)
            state = .ready
            backgroundWork = Task { [weak self] in
                guard let self else { return }
                await self.refresh(force: false)
            }
            return
        }
        await loadFromNetwork(credentials)
    }

    public func signIn(email: String, password: String) async throws {
        let credentials = Credentials(email: email, password: password)
        let loaded: Catalog
        do {
            loaded = try await environment.catalog.signIn(credentials, progress: nil)
        } catch is CancellationError {
            // A benign overlap (superseded load or a cancelled request): never shown to the user.
            return
        }
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
        try? environment.credentials.clear()
        await environment.details.clear()
        await environment.catalog.clear()
        catalog = nil
        newEpisodeInfo = [:]
        needsReauth = false
        state = .signedOut
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

    /// Refresh if stale.
    public func sceneBecameActive() async {
        guard state == .ready else { return }
        if let lastUpdated = await environment.catalog.lastUpdated(),
           Date().timeIntervalSince(lastUpdated) < CatalogRepository.staleness {
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
        state = .launching
        await start()
    }

    // MARK: - Private

    private func loadCacheThenRefresh(credentials: Credentials) async {
        guard let cached = await environment.catalog.loadCached() else {
            // The snapshot outlived the lists: load them again.
            await loadFromNetwork(credentials)
            return
        }
        guard !Task.isCancelled, state == .ready else { return }
        install(cached)
        await refresh(force: false)
    }

    /// Credentials but no cache: the branded loading screen with byte progress.
    private func loadFromNetwork(_ credentials: Credentials) async {
        state = .loadingCatalog(0)
        do {
            let loaded = try await environment.catalog.signIn(credentials) { [weak self] fraction in
                Task { @MainActor in self?.updateProgress(fraction) }
            }
            install(loaded)
            state = .ready
            await resolveNewEpisodes()
        } catch is CancellationError {
            // Superseded by a sign-out or another sign-in, which set the state themselves.
        } catch APIError.unauthorized {
            state = .signedOut
        } catch let error as APIError {
            state = .failed(error)
        } catch {
            state = .failed(.server(status: 0))
        }
    }

    private func updateProgress(_ fraction: Double) {
        guard case .loadingCatalog(let current) = state, fraction > current else { return }
        state = .loadingCatalog(min(1, fraction))
    }

    private func performRefresh(force: Bool) async {
        do {
            let changed = try await environment.catalog.refresh(force: force, now: Date())
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
        let shows = LibraryQueries.showsWithNewEpisodes(library, catalog: catalog)
        let resolved = await environment.newEpisodes.resolve(shows: shows, library: library)
        guard !Task.isCancelled, state == .ready else { return }
        newEpisodeInfo = resolved
    }
}
