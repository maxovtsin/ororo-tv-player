import Foundation
import Observation
import OroroCore

// STUB (T3) — implemented by Task F1.
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

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// Credentials? → loadCached → ready; then refresh in background.
    public func start() async {}

    public func signIn(email: String, password: String) async throws {
        throw APIError.decoding
    }

    /// Clears credentials, details, catalog cache; library untouched.
    public func signOut() async {}

    public func refresh(force: Bool) async {}

    /// Refresh if stale.
    public func sceneBecameActive() async {}

    /// `.unauthorized` → needsReauth = true.
    public func report(_ error: any Error) {}

    public func retry() async {}
}
