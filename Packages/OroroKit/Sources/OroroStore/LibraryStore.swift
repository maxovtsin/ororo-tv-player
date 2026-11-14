import Foundation
import OroroCore

// STUB (T3) — implemented by Task ST2.
//
// NOTE for ST2: `LibraryPersistence`, `UserDefaultsLibraryPersistence` and `FileLibraryPersistence`
// are declared at the bottom of this file only because `LibraryStore.init` and `platformDefault()`
// need them to compile. ST2 moves them (unchanged signatures) into `LibraryPersistence.swift`.

public actor LibraryStore: LibraryStoring {
    public static let sizeBudget = 300_000

    private let persistence: any LibraryPersistence
    private let flushInterval: Duration
    private let clock: any Clock<Duration>

    public init(persistence: any LibraryPersistence, flushInterval: Duration = .seconds(10), clock: any Clock<Duration> = ContinuousClock()) {
        self.persistence = persistence
        self.flushInterval = flushInterval
        self.clock = clock
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

    public func snapshot() async -> Library {
        Library()
    }

    public func update(_ mutate: @Sendable (inout Library) -> Void) async {}

    public func flush() async {}

    public func erase() async {}

    public func updates() async -> AsyncStream<Library> {
        AsyncStream { $0.finish() }
    }
}

// MARK: - Persistence (ST2 moves these to LibraryPersistence.swift)

public protocol LibraryPersistence: Sendable {
    func read() -> Data?
    func write(_ data: Data)
    func writeBackup(_ data: Data)
    func remove()
}

/// Backup key: key + ".unreadable".
public struct UserDefaultsLibraryPersistence: LibraryPersistence {
    public init(defaults: sending UserDefaults = .standard, key: String = "library.v1") {}

    public func read() -> Data? {
        nil
    }

    public func write(_ data: Data) {}

    public func writeBackup(_ data: Data) {}

    public func remove() {}
}

/// library.json, atomic write.
public struct FileLibraryPersistence: LibraryPersistence {
    public init(directory: URL) {}

    public func read() -> Data? {
        nil
    }

    public func write(_ data: Data) {}

    public func writeBackup(_ data: Data) {}

    public func remove() {}
}
