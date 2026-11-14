import Foundation
import OroroCore
@testable import OroroStore
import Synchronization
import Testing

@Suite struct LibraryStoreTests {
    private let item = MyListItem(title: TitleID(kind: .show, id: 42), addedAt: Date(timeIntervalSince1970: 1_761_955_200))

    // MARK: - Basics

    @Test func startsEmptyWithNoData() async {
        let p = InMemoryPersistence()
        let store = LibraryStore(persistence: p)
        #expect(await store.snapshot() == Library())
        #expect(p.writes.isEmpty)
        #expect(p.backup == nil)
    }

    @Test func updateIsVisibleImmediatelyInSnapshot() async {
        let p = InMemoryPersistence()
        let store = LibraryStore(persistence: p, clock: ManualClock())
        let item = item
        await store.update { $0.myList.append(item) }
        #expect(await store.snapshot().myList == [item])
        #expect(p.writes.isEmpty)       // disk write is deferred
    }

    @Test func flushPersistsAndNewStoreReadsItBack() async throws {
        let p = InMemoryPersistence()
        let store = LibraryStore(persistence: p, clock: ManualClock())
        let item = item
        await store.update {
            $0.myList.append(item)
            $0.preferences.subtitleLanguage = nil
        }
        await store.flush()
        #expect(p.writes.count == 1)

        let json = try #require(p.data.flatMap { String(data: $0, encoding: .utf8) })
        #expect(json.contains(#""addedAt":1761955200"#))      // seconds since 1970
        #expect(json.hasPrefix(#"{"followed""#))                 // sorted keys

        let reopened = LibraryStore(persistence: p)
        #expect(await reopened.snapshot() == store.snapshot())
        #expect(await reopened.snapshot().myList == [item])
        #expect(await reopened.snapshot().preferences.subtitleLanguage == nil)
    }

    @Test func flushWithoutChangesDoesNotWrite() async {
        let p = InMemoryPersistence()
        let store = LibraryStore(persistence: p, clock: ManualClock())
        await store.flush()
        #expect(p.writes.isEmpty)
    }

    // MARK: - Throttling

    @Test func writesAreThrottledToFlushInterval() async throws {
        let clock = ManualClock()
        let p = InMemoryPersistence()
        let store = LibraryStore(persistence: p, flushInterval: .seconds(10), clock: clock)
        let item = item

        await store.update { $0.myList.append(item) }
        await store.update { $0.preferences.autoplayNext = false }
        try await clock.waitForSleepers(1)
        #expect(clock.sleeperCount == 1)                // one scheduled flush for both updates
        #expect(p.writes.isEmpty)

        clock.advance(by: .seconds(9))
        #expect(clock.sleeperCount == 1)                // not due yet
        #expect(p.writes.isEmpty)

        clock.advance(by: .seconds(1))
        try await eventually { p.writes.count == 1 }
        let written = try LibraryStore.decoder.decode(Library.self, from: try #require(p.data))
        #expect(written.myList == [item])
        #expect(written.preferences.autoplayNext == false)

        // A later change schedules a new flush one interval later.
        await store.update { $0.preferences.autoplayNext = true }
        try await clock.waitForSleepers(1)
        #expect(p.writes.count == 1)
        clock.advance(by: .seconds(10))
        try await eventually { p.writes.count == 2 }
    }

    @Test func explicitFlushCancelsScheduledFlush() async throws {
        let clock = ManualClock()
        let p = InMemoryPersistence()
        let store = LibraryStore(persistence: p, flushInterval: .seconds(10), clock: clock)
        await store.update { $0.preferences.autoplayNext = false }
        try await clock.waitForSleepers(1)
        await store.flush()
        #expect(p.writes.count == 1)
        try await eventually { clock.sleeperCount == 0 }
        clock.advance(by: .seconds(10))
        await store.flush()                             // nothing new to write
        #expect(p.writes.count == 1)
    }

    // MARK: - Stream

    @Test func updatesStreamEmitsEachChange() async throws {
        let store = LibraryStore(persistence: InMemoryPersistence(), clock: ManualClock())
        await store.update { $0.preferences.autoplayNext = false }   // before subscribing: not replayed
        let stream = await store.updates()
        let received = Mutex<[Library]>([])
        let consumer = Task {
            for await library in stream { received.withLock { $0.append(library) } }
        }
        defer { consumer.cancel() }
        let item = item

        // The stream keeps only the newest unread value, so wait for each emission before the next change.
        await store.update { $0.myList.append(item) }
        try await eventually { received.withLock { $0.count } == 1 }
        await store.update { $0.preferences.subtitleLanguage = "fr" }
        try await eventually { received.withLock { $0.count } == 2 }
        await store.update { $0.preferences.subtitleLanguage = "fr" }   // no change: not published
        await store.erase()
        try await eventually { received.withLock { $0.count } == 3 }

        let libraries = received.withLock { $0 }
        try #require(libraries.count == 3)
        #expect(libraries[0].myList == [item])
        #expect(libraries[0].preferences.autoplayNext == false)
        #expect(libraries[0].preferences.subtitleLanguage == "en")
        #expect(libraries[1].preferences.subtitleLanguage == "fr")
        #expect(libraries[2] == Library())
    }

    @Test func updateThatChangesNothingDoesNotDirtyOrSchedule() async throws {
        let clock = ManualClock()
        let p = InMemoryPersistence()
        let store = LibraryStore(persistence: p, flushInterval: .seconds(10), clock: clock)
        await store.update { $0.preferences.autoplayNext = true }      // already true
        await store.flush()
        #expect(p.writes.isEmpty)
        #expect(clock.sleeperCount == 0)
    }

    // MARK: - Erase

    @Test func eraseClearsMemoryAndDisk() async throws {
        let p = InMemoryPersistence(data: Data("not json".utf8))
        let store = LibraryStore(persistence: p, clock: ManualClock())
        #expect(p.backup == Data("not json".utf8))
        let item = item
        await store.update {
            $0.myList.append(item)
            $0.watchedEpisodes = [1, 2, 3]
            $0.preferences.autoplayNext = false
        }
        await store.flush()
        #expect(p.data != nil)

        await store.erase()
        #expect(await store.snapshot() == Library())
        #expect(p.data == nil)
        #expect(p.backup == nil)                         // erase also deletes the unreadable-data backup
        await store.flush()                              // nothing left to write
        #expect(p.data == nil)
        #expect(await LibraryStore(persistence: p).snapshot() == Library())
        #expect(p.backup == nil)
    }

    // MARK: - Size and caps

    @Test func libraryAtAllCapsFitsBudget() throws {
        // Worst case: every cap full, large ids, and dates with fractional seconds (longest JSON numbers).
        let base = Date(timeIntervalSince1970: 1_761_955_200.123_456)
        func date(_ i: Int) -> Date { base + Double(i) + 0.987_654_321 }
        var library = Library()
        library.myList = (0..<Library.maxMyList).map {
            MyListItem(title: TitleID(kind: $0.isMultiple(of: 2) ? .show : .movie, id: 100_000 + $0), addedAt: date($0))
        }
        library.progress = (0..<Library.maxProgress).map {
            ProgressEntry(
                playable: PlayableID(kind: .episode, id: 1_000_000 + $0),
                showID: 100_000 + $0,
                season: 12,
                number: 24,
                episodeName: "A Fairly Long Episode Name, Part \($0)",
                position: 1_234.567_891,
                duration: 2_640.123_456,
                updatedAt: date($0)
            )
        }
        library.watchedEpisodes = (0..<Library.maxWatched).map { 1_000_000 + $0 }
        library.watchedMovies = (0..<Library.maxWatched).map { 1_000_000 + $0 }
        library.followed = Dictionary(uniqueKeysWithValues: (0..<Library.maxMyList).map {
            (100_000 + $0, FollowState(seenNewestVideo: date($0), started: true))
        })
        library.upNext = Dictionary(uniqueKeysWithValues: (0..<Library.maxMyList).map {
            (100_000 + $0, UpNextEntry(ref: EpisodeRef(episodeID: 2_000_000 + $0, season: 12, number: 24), setAt: date($0)))
        })
        let data = try LibraryStore.encoder.encode(library)
        #expect(data.count < 300_000)
        #expect(data.count < LibraryStore.sizeBudget)
    }

    @Test func updatePrunesBeyondCaps() async {
        let store = LibraryStore(persistence: InMemoryPersistence(), clock: ManualClock())
        let base = Date(timeIntervalSince1970: 1_761_955_200)
        await store.update { library in
            library.myList = (0..<(Library.maxMyList + 3)).map {
                MyListItem(title: TitleID(kind: .movie, id: $0), addedAt: base + Double($0))
            }
            library.watchedEpisodes = Array(0..<(Library.maxWatched + 2))
        }
        let library = await store.snapshot()
        #expect(library.myList.count == Library.maxMyList)
        #expect(library.myList.contains { $0.title.id == 0 } == false)          // oldest dropped
        #expect(library.myList.contains { $0.title.id == Library.maxMyList + 2 }) // newest kept
        #expect(library.watchedEpisodes.count == Library.maxWatched)
        #expect(library.watchedEpisodes.first == 2)
    }

    // MARK: - Unreadable data (Review Focus 2)

    @Test func corruptDataStartsEmptyAndIsBackedUp() async {
        let p = InMemoryPersistence(data: Data("not json".utf8))
        let store = LibraryStore(persistence: p)
        #expect(await store.snapshot() == Library())
        #expect(p.backup == Data("not json".utf8))
    }

    @Test func newerSchemaIsNotOverwritten() async throws {
        let original = Data(#"{"schemaVersion":99,"futureField":true}"#.utf8)
        let p = InMemoryPersistence(data: original)
        let store = LibraryStore(persistence: p)
        #expect(await store.snapshot() == Library())
        await store.update { $0.preferences.autoplayNext = false }; await store.flush()
        #expect(p.backup != nil)                         // the v99 blob survives under the backup key
        #expect(p.backup == original)
        let written = try LibraryStore.decoder.decode(Library.self, from: try #require(p.data))
        #expect(written.preferences.autoplayNext == false)
    }

    @Test func newerSchemaThatDecodesIsStillBackedUp() async throws {
        var future = Library(schemaVersion: 2)
        future.watchedMovies = [7]
        let original = try LibraryStore.encoder.encode(future)
        let p = InMemoryPersistence(data: original)
        let store = LibraryStore(persistence: p)
        #expect(await store.snapshot() == Library())
        #expect(p.backup == original)
    }

    @Test func unreadableDataIsNotOverwrittenUntilTheUserChangesSomething() async {
        let original = Data("not json".utf8)
        let p = InMemoryPersistence(data: original)
        let store = LibraryStore(persistence: p, clock: ManualClock())
        await store.flush()
        #expect(p.writes.isEmpty)
        #expect(p.data == original)
        #expect(p.backupWrites == 1)

        _ = LibraryStore(persistence: p)                 // reopening backs up again, but never replaces the first backup
        #expect(p.backup == original)
    }

    @Test func readableDataIsNotBackedUp() async throws {
        var library = Library()
        library.watchedMovies = [7, 8]
        let p = InMemoryPersistence(data: try LibraryStore.encoder.encode(library))
        let store = LibraryStore(persistence: p)
        #expect(await store.snapshot() == library)
        #expect(p.backupWrites == 0)
    }

    // MARK: - Real persistences

    @Test func userDefaultsPersistenceRoundTripsAndKeepsFirstBackup() throws {
        let suite = "LibraryStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let p = UserDefaultsLibraryPersistence(defaults: defaults, key: "lib")

        #expect(p.read() == nil)
        p.write(Data("one".utf8))
        #expect(p.read() == Data("one".utf8))

        p.writeBackup(Data("old".utf8))
        p.writeBackup(Data("newer".utf8))
        let check = try #require(UserDefaults(suiteName: suite))
        #expect(check.data(forKey: "lib.unreadable") == Data("old".utf8))

        p.remove()
        #expect(p.read() == nil)
        #expect(check.data(forKey: "lib.unreadable") == nil)          // remove() clears the backup too
    }

    @Test func filePersistenceRoundTripsAndKeepsFirstBackup() throws {
        let dir = URL.temporaryDirectory.appending(path: "LibraryStoreTests-\(UUID().uuidString)/library", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let p = FileLibraryPersistence(directory: dir)

        #expect(p.read() == nil)
        p.write(Data("one".utf8))                                 // creates the directory
        p.write(Data("two".utf8))
        #expect(p.read() == Data("two".utf8))
        #expect(try Data(contentsOf: dir.appending(path: "library.json")) == Data("two".utf8))

        p.writeBackup(Data("old".utf8))
        p.writeBackup(Data("newer".utf8))
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path()).filter { $0 != "library.json" }
        #expect(backups.count == 1)
        let backup = try Data(contentsOf: dir.appending(path: try #require(backups.first)))
        #expect(backup == Data("old".utf8))

        p.remove()
        #expect(p.read() == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path()).isEmpty)   // backup removed too
    }

    @Test func storeOverFilePersistenceSurvivesReopen() async throws {
        let dir = URL.temporaryDirectory.appending(path: "LibraryStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LibraryStore(persistence: FileLibraryPersistence(directory: dir), clock: ManualClock())
        await store.update { $0.watchedMovies = [5, 6] }
        await store.flush()
        let reopened = LibraryStore(persistence: FileLibraryPersistence(directory: dir))
        #expect(await reopened.snapshot().watchedMovies == [5, 6])
    }
}

// MARK: - Helpers

/// Test-local persistence. Like the real ones, `writeBackup` never replaces an existing backup and `remove()` deletes both.
final class InMemoryPersistence: LibraryPersistence, Sendable {
    private struct State {
        var data: Data?
        var backup: Data?
        var writes: [Data] = []
        var backupWrites = 0
    }

    private let state: Mutex<State>

    init(data: Data? = nil) {
        state = Mutex(State(data: data))
    }

    var data: Data? { state.withLock { $0.data } }
    var backup: Data? { state.withLock { $0.backup } }
    var writes: [Data] { state.withLock { $0.writes } }
    var backupWrites: Int { state.withLock { $0.backupWrites } }

    func read() -> Data? { state.withLock { $0.data } }

    func write(_ data: Data) {
        state.withLock {
            $0.data = data
            $0.writes.append(data)
        }
    }

    func writeBackup(_ data: Data) {
        state.withLock {
            $0.backupWrites += 1
            if $0.backup == nil { $0.backup = data }
        }
    }

    func remove() {
        state.withLock {
            $0.data = nil
            $0.backup = nil
        }
    }
}

/// A clock that only moves when the test calls `advance(by:)`.
final class ManualClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [UUID: Sleeper] = [:]
    }

    private let state = Mutex(State())

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }
    var sleeperCount: Int { state.withLock { $0.sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let resumeNow: Bool = state.withLock {
                    if Task.isCancelled || deadline <= $0.now { return true }
                    $0.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return false
                }
                if resumeNow {
                    if Task.isCancelled { continuation.resume(throwing: CancellationError()) } else { continuation.resume() }
                }
            }
        } onCancel: {
            let sleeper = state.withLock { $0.sleepers.removeValue(forKey: id) }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        let due: [Sleeper] = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let now = state.now
            let ids = state.sleepers.filter { $0.value.deadline <= now }.map(\.key)
            return ids.compactMap { state.sleepers.removeValue(forKey: $0) }
        }
        for sleeper in due { sleeper.continuation.resume() }
    }

    func waitForSleepers(_ count: Int) async throws {
        try await eventually { self.sleeperCount >= count }
    }
}

private struct TimedOut: Error {}

/// Polls `condition` on the real clock for up to two seconds.
private func eventually(_ condition: @Sendable () -> Bool) async throws {
    for _ in 0..<400 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    if !condition() { throw TimedOut() }
}
