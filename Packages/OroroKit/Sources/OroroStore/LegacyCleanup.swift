import Foundation

/// One-time removal of data left behind by the 2018 app: its Core Data store and offline downloads.
///
/// The old app used `NSPersistentContainer(name: "Ororo")` (so `Ororo.sqlite`, `-shm` and `-wal` in Application Support)
/// and kept downloads in `Documents/Downloads/<md5>/{video.mp4,subtitle.vtt}`.
public enum LegacyCleanup {
    static let flagKey = "legacyCleanup.v1"
    static let storeFileNames = ["Ororo.sqlite", "Ororo.sqlite-shm", "Ororo.sqlite-wal"]
    static let downloadsDirectoryName = "Downloads"

    /// Runs once per install. `roots` replaces the default Application Support and Documents directories (for tests).
    public static func run(fileManager: FileManager = .default, defaults: UserDefaults = .standard, roots: [URL]? = nil) {
        guard !defaults.bool(forKey: flagKey) else { return }
        let directories = roots ?? defaultRoots(fileManager)
        for directory in directories {
            for name in storeFileNames + [downloadsDirectoryName] {
                let url = directory.appendingPathComponent(name)
                if fileManager.fileExists(atPath: url.path) {
                    try? fileManager.removeItem(at: url)
                }
            }
        }
        defaults.set(true, forKey: flagKey)
    }

    private static func defaultRoots(_ fileManager: FileManager) -> [URL] {
        [FileManager.SearchPathDirectory.applicationSupportDirectory, .documentDirectory]
            .compactMap { fileManager.urls(for: $0, in: .userDomainMask).first }
    }
}
