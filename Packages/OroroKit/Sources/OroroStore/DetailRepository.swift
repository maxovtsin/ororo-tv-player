import Foundation
import OroroCore

/// In-memory detail cache (TTL, default 10 min). Nothing is written to disk.
///
/// Identical concurrent reads share one unstructured network task, so a caller cancelling does not cancel the
/// others. Cached movie and episode values never carry `playback`; the `*Playback` calls always hit the network.
public actor DetailRepository: DetailProviding {
    private final class Slot<Value: Sendable> {
        var entries: [Int: (value: Value, storedAt: Date)] = [:]
        var inFlight: [Int: (token: UUID, task: Task<Value, any Error>)] = [:]

        func reset() {
            entries = [:]
            inFlight = [:]
        }
    }

    private let api: any OroroAPI
    private let credentials: any CredentialStoring
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date

    private let shows = Slot<ShowDetail>()
    private let movies = Slot<MovieDetail>()
    private let episodes = Slot<EpisodeDetail>()
    /// Bumped by `clear()` so results that were in flight at the time are not stored.
    private var generation = 0

    public init(api: any OroroAPI, credentials: any CredentialStoring, ttl: TimeInterval = 600,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.api = api
        self.credentials = credentials
        self.ttl = ttl
        self.now = now
    }

    public func show(id: Int) async throws -> ShowDetail {
        let api = api
        return try await cached(shows, id) { try await api.show(id: id, $0) }
    }

    public func movie(id: Int) async throws -> MovieDetail {
        let api = api
        return try await cached(movies, id) { Self.stripped(try await api.movie(id: id, $0)) }
    }

    public func episode(id: Int) async throws -> EpisodeDetail {
        let api = api
        return try await cached(episodes, id) { Self.stripped(try await api.episode(id: id, $0)) }
    }

    public func moviePlayback(id: Int) async throws -> MovieDetail {
        let credentials = try requireCredentials()
        let generation = generation
        let detail = try await api.movie(id: id, credentials)
        store(Self.stripped(detail), in: movies, id, generation)
        return detail
    }

    public func episodePlayback(id: Int) async throws -> EpisodeDetail {
        let credentials = try requireCredentials()
        let generation = generation
        let detail = try await api.episode(id: id, credentials)
        store(Self.stripped(detail), in: episodes, id, generation)
        return detail
    }

    public func clear() async {
        generation += 1
        shows.reset()
        movies.reset()
        episodes.reset()
    }

    // MARK: - Private

    private func cached<Value: Sendable>(
        _ slot: Slot<Value>, _ id: Int,
        fetch: @escaping @Sendable (Credentials) async throws -> Value
    ) async throws -> Value {
        if let entry = slot.entries[id], now().timeIntervalSince(entry.storedAt) < ttl { return entry.value }
        if let pending = slot.inFlight[id] { return try await pending.task.value }

        let credentials = try requireCredentials()
        let token = UUID()
        let generation = generation
        // Unstructured on purpose: cancelling one awaiting caller must not cancel the shared request.
        let task = Task { try await fetch(credentials) }
        slot.inFlight[id] = (token, task)
        do {
            let value = try await task.value
            finish(slot, id, token)
            store(value, in: slot, id, generation)
            return value
        } catch {
            finish(slot, id, token)
            throw error
        }
    }

    private func finish<Value: Sendable>(_ slot: Slot<Value>, _ id: Int, _ token: UUID) {
        if slot.inFlight[id]?.token == token { slot.inFlight[id] = nil }
    }

    private func store<Value: Sendable>(_ value: Value, in slot: Slot<Value>, _ id: Int, _ generation: Int) {
        guard generation == self.generation else { return }
        slot.entries[id] = (value, now())
    }

    private func requireCredentials() throws -> Credentials {
        guard let credentials = credentials.load() else { throw APIError.unauthorized }
        return credentials
    }

    private static func stripped(_ detail: MovieDetail) -> MovieDetail {
        var copy = detail
        copy.playback = nil
        return copy
    }

    private static func stripped(_ detail: EpisodeDetail) -> EpisodeDetail {
        var copy = detail
        copy.playback = nil
        return copy
    }
}
