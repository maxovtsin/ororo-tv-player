import Foundation

/// Where `LibraryStore` keeps its JSON. `writeBackup` stores a copy of unreadable data and never replaces an existing backup.
public protocol LibraryPersistence: Sendable {
    func read() -> Data?
    func write(_ data: Data)
    func writeBackup(_ data: Data)
    func remove()
}

/// The durable option on tvOS. Backup key: key + ".unreadable".
public struct UserDefaultsLibraryPersistence: LibraryPersistence {
    // UserDefaults is documented as thread-safe; the init takes it `sending` so no one else holds it non-Sendably.
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
    }
}
