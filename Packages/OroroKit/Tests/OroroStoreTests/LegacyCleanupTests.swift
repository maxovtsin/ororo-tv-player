import Foundation
import Testing
@testable import OroroStore

@Suite struct LegacyCleanupTests {
    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeDefaults() -> UserDefaults {
        let name = "legacy-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    @Test func removesLegacyStoreAndDownloads() throws {
        let support = try makeRoot()
        let documents = try makeRoot()
        for name in ["Ororo.sqlite", "Ororo.sqlite-shm", "Ororo.sqlite-wal"] {
            try touch(support.appendingPathComponent(name))
        }
        try touch(documents.appendingPathComponent("Downloads/abc/video.mp4"))
        try touch(documents.appendingPathComponent("Downloads/abc/subtitle.vtt"))

        LegacyCleanup.run(defaults: makeDefaults(), roots: [support, documents])

        for name in ["Ororo.sqlite", "Ororo.sqlite-shm", "Ororo.sqlite-wal"] {
            #expect(!exists(support.appendingPathComponent(name)))
        }
        #expect(!exists(documents.appendingPathComponent("Downloads")))
    }

    @Test func leavesOtherFilesAlone() throws {
        let root = try makeRoot()
        try touch(root.appendingPathComponent("Ororo.sqlite"))
        try touch(root.appendingPathComponent("notes.txt"))
        try touch(root.appendingPathComponent("Other/video.mp4"))

        LegacyCleanup.run(defaults: makeDefaults(), roots: [root])

        #expect(exists(root.appendingPathComponent("notes.txt")))
        #expect(exists(root.appendingPathComponent("Other/video.mp4")))
        #expect(!exists(root.appendingPathComponent("Ororo.sqlite")))
    }

    @Test func runsOnlyOnce() throws {
        let root = try makeRoot()
        let defaults = makeDefaults()
        LegacyCleanup.run(defaults: defaults, roots: [root])
        #expect(defaults.bool(forKey: "legacyCleanup.v1"))

        try touch(root.appendingPathComponent("Ororo.sqlite"))
        LegacyCleanup.run(defaults: defaults, roots: [root])
        #expect(exists(root.appendingPathComponent("Ororo.sqlite")))
    }

    @Test func missingDirectoriesAreFine() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)")
        let defaults = makeDefaults()
        LegacyCleanup.run(defaults: defaults, roots: [missing])
        #expect(defaults.bool(forKey: "legacyCleanup.v1"))
    }
}
