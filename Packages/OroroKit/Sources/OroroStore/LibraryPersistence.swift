import Foundation

/// Where `LibraryStore` keeps its JSON.
public protocol LibraryPersistence: Sendable {
    /// The primary library data, or nil when there is none.
    func read() -> Data?
    /// Replaces the primary library data.
    func write(_ data: Data)
    /// Stores a copy of unreadable data. Never replaces an existing backup.
    func writeBackup(_ data: Data)
    /// Deletes both the primary data and the backup (used by "Erase library").
    func remove()
}

/// The durable option on tvOS. Backup key: key + ".unreadable".
public struct UserDefaultsLibraryPersistence: LibraryPersistence {
    // Apple's UserDefaults documentation states "The UserDefaults class is thread-safe", so sharing one instance
    // across isolation domains is sound even though the SDK does not mark it Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults
    private let key: String

    private var backupKey: String { key + ".unreadable" }

    public init(defaults: sending UserDefaults = .standard, key: String = "library.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func read() -> Data? {
        defaults.data(forKey: key)
    }

    public func write(_ data: Data) {
        defaults.set(data, forKey: key)
    }

    public func writeBackup(_ data: Data) {
        guard defaults.object(forKey: backupKey) == nil else { return }
        defaults.set(data, forKey: backupKey)
    }

    public func remove() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: backupKey)
    }
}

/// `library.json` in `directory`, written atomically. Backup: `library.unreadable.json`.
public struct FileLibraryPersistence: LibraryPersistence {
    private let directory: URL

    private var fileURL: URL { directory.appending(path: "library.json", directoryHint: .notDirectory) }
    private var backupURL: URL { directory.appending(path: "library.unreadable.json", directoryHint: .notDirectory) }

    public init(directory: URL) {
        self.directory = directory
    }

    public func read() -> Data? {
        try? Data(contentsOf: fileURL)
    }

    public func write(_ data: Data) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    public func writeBackup(_ data: Data) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // `.withoutOverwriting` fails if a backup already exists, which is what we want.
        try? data.write(to: backupURL, options: .withoutOverwriting)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: backupURL)
    }
}
