import Foundation
import OroroAPI
import OroroCore
import OroroStore
import SwiftUI

/// Every service a feature needs. Tests build one from the `OroroTestSupport` fakes via `init`.
public struct AppEnvironment: Sendable {
    public let api: any OroroAPI
    public let catalog: any CatalogProviding
    public let library: any LibraryStoring
    public let details: any DetailProviding
    public let credentials: any CredentialStoring
    public let newEpisodes: any NewEpisodeResolving

    public init(api: any OroroAPI, catalog: any CatalogProviding, library: any LibraryStoring,
                details: any DetailProviding, credentials: any CredentialStoring, newEpisodes: any NewEpisodeResolving) {
        self.api = api
        self.catalog = catalog
        self.library = library
        self.details = details
        self.credentials = credentials
        self.newEpisodes = newEpisodes
    }

    /// Builds the real OroroStore types. Call once per process and keep the result.
    public static func live() -> AppEnvironment {
        let credentials = KeychainCredentialStore()
        let api = LiveOroroAPI(transport: Transport())
        let details = DetailRepository(api: api, credentials: credentials)
        return AppEnvironment(
            api: api,
            catalog: CatalogRepository(api: api, credentials: credentials, directory: CatalogRepository.cachesDirectory()),
            library: LibraryStore.platformDefault(),
            details: details,
            credentials: credentials,
            newEpisodes: NewEpisodeResolver(details: details)
        )
    }

    /// Inert services for previews and the environment default: nothing signed in, empty library,
    /// every network call fails with `.offline`. Available in release builds (it backs `\.appEnvironment`'s default).
    public static func preview() -> AppEnvironment {
        AppEnvironment(
            api: PreviewAPI(),
            catalog: PreviewCatalog(),
            library: PreviewLibrary(),
            details: PreviewDetails(),
            credentials: PreviewCredentials(),
            newEpisodes: PreviewNewEpisodes()
        )
    }
}

extension EnvironmentValues {
    @Entry public var appEnvironment: AppEnvironment = .preview()
}

// MARK: - Minimal no-op services behind `preview()`

private struct PreviewAPI: OroroAPI {
    func shows(_ c: Credentials, ifNoneMatch: String?, progress: (@Sendable (Double) -> Void)?) async throws -> Conditional<ListResponse> {
        throw APIError.offline
    }

    func movies(_ c: Credentials, ifNoneMatch: String?, progress: (@Sendable (Double) -> Void)?) async throws -> Conditional<ListResponse> {
        throw APIError.offline
    }

    func show(id: Int, _ c: Credentials) async throws -> ShowDetail { throw APIError.offline }
    func movie(id: Int, _ c: Credentials) async throws -> MovieDetail { throw APIError.offline }
    func episode(id: Int, _ c: Credentials) async throws -> EpisodeDetail { throw APIError.offline }
}

private struct PreviewCatalog: CatalogProviding {
    func current() async -> Catalog? { nil }
    func lastUpdated() async -> Date? { nil }
    func signIn(_ c: Credentials, progress: (@Sendable (Double) -> Void)?) async throws -> Catalog { throw APIError.offline }
    func loadCached() async -> Catalog? { nil }
    func refresh(force: Bool, now: Date) async throws -> Bool { false }
    func homeSnapshot() async -> HomeContent? { nil }
    func saveHomeSnapshot(_ content: HomeContent) async {}
    func clear() async {}
}

private actor PreviewLibrary: LibraryStoring {
    private var library = Library()

    func snapshot() async -> Library { library }
    func update(_ mutate: @Sendable (inout Library) -> Void) async { mutate(&library) }
    func flush() async {}
    func erase() async { library = Library() }
    func updates() async -> AsyncStream<Library> { AsyncStream { $0.finish() } }
}

private struct PreviewDetails: DetailProviding {
    func show(id: Int) async throws -> ShowDetail { throw APIError.offline }
    func movie(id: Int) async throws -> MovieDetail { throw APIError.offline }
    func episode(id: Int) async throws -> EpisodeDetail { throw APIError.offline }
    func moviePlayback(id: Int) async throws -> MovieDetail { throw APIError.offline }
    func episodePlayback(id: Int) async throws -> EpisodeDetail { throw APIError.offline }
    func clear() async {}
}

private struct PreviewCredentials: CredentialStoring {
    func load() -> Credentials? { nil }
    func save(_ c: Credentials) throws {}
    func clear() throws {}
}

private struct PreviewNewEpisodes: NewEpisodeResolving {
    func cached() async -> [Int: NewEpisodeInfo] { [:] }
    func resolve(shows: [Title], library: Library) async -> [Int: NewEpisodeInfo] { [:] }
}
