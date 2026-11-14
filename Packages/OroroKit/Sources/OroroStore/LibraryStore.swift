import Foundation
import OroroCore

/// The user's library (My List, progress, watched flags, up-next, preferences): the only durable user data.
///
/// Memory is updated immediately; disk writes are throttled to one per `flushInterval` unless `flush()` is called.
/// `erase()` removes everything from disk, including the unreadable-data backup.
/// Unreadable stored data (corrupt, or written by a newer schema) is copied once to the persistence's backup slot,
/// and the primary slot is not overwritten until the user actually changes something.
public actor LibraryStore: LibraryStoring {
    public static let sizeBudget = 300_000
    static let currentSchemaVersion = 1

    private let persistence: any LibraryPersistence
    private let flushInterval: Duration
    private let clock: any Clock<Duration>

    private var library: Library
    /// True when memory holds changes that are not on disk yet.
    private var dirty = false
    private var scheduledFlush: Task<Void, Never>?
    private var flushGeneration = 0
    private var continuations: [UUID: AsyncStream<Library>.Continuation] = [:]

    public init(persistence: any LibraryPersistence, flushInterval: Duration = .seconds(10), clock: any Clock<Duration> = ContinuousClock()) {
        self.persistence = persistence
        self.flushInterval = flushInterval
        self.clock = clock
        self.library = Self.load(from: persistence)
    }

    /// UserDefaults on tvOS, Application Support file elsewhere.
    public static func platformDefault() -> LibraryStore {
        #if os(tvOS)
        LibraryStore(persistence: UserDefaultsLibraryPersistence())
        #else
        let support = URL.applicationSupportDirectory.appending(path: "library", directoryHint: .isDirectory)
        return LibraryStore(persistence: FileLibraryPersistence(directory: support))
        #endif
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    public func snapshot() async -> Library {
        library
    }

    public func update(_ mutate: @Sendable (inout Library) -> Void) async {
        var changed = library
        mutate(&changed)
        changed.prune()
        guard changed != library else { return }
        library = changed
        dirty = true
        publish()
        scheduleFlush()
    }

    public func flush() async {
        cancelScheduledFlush()
        guard dirty else { return }
        write()
    }

    public func erase() async {
        cancelScheduledFlush()
        library = Library()
        dirty = false
        persistence.remove()
        publish()
    }

    /// Emits the library after every changing `update` and every `erase`; does not replay the current value on subscription.
    /// Keeps only the newest unread value, so a slow subscriber sees the latest library rather than a backlog.
    public func updates() async -> AsyncStream<Library> {
        let (stream, continuation) = AsyncStream<Library>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return stream
    }

    // MARK: - Private

    private static func load(from persistence: any LibraryPersistence) -> Library {
        guard let data = persistence.read() else { return Library() }
        let decoder = decoder
        if let header = try? decoder.decode(SchemaHeader.self, from: data),
           let version = header.schemaVersion, version <= currentSchemaVersion,
           let library = try? decoder.decode(Library.self, from: data) {
            return library
        }
        // Corrupt or newer schema: keep the original bytes, start empty, leave the primary slot alone until a change.
        persistence.writeBackup(data)
        return Library()
    }

    private func scheduleFlush() {
        guard scheduledFlush == nil else { return }
        flushGeneration += 1
        let generation = flushGeneration
        let clock = clock
        let interval = flushInterval
        scheduledFlush = Task { [weak self] in
            do {
                try await clock.sleep(for: interval)
            } catch {
                return
            }
            await self?.scheduledFlushFired(generation)
        }
    }

    private func scheduledFlushFired(_ generation: Int) {
        guard generation == flushGeneration, scheduledFlush != nil else { return }
        scheduledFlush = nil
        guard dirty else { return }
        write()
    }

    private func cancelScheduledFlush() {
        scheduledFlush?.cancel()
        scheduledFlush = nil
        flushGeneration += 1
    }

    private func write() {
        guard let data = try? Self.encoder.encode(library) else { return }
        persistence.write(data)
        dirty = false
    }

    private func publish() {
        for continuation in continuations.values { continuation.yield(library) }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }
}

/// Reads only the version, so a newer schema is recognised even when it would decode as the current one.
private struct SchemaHeader: Decodable {
    let schemaVersion: Int?
}
