import Foundation
import Observation
import OroroCore

@MainActor @Observable public final class SearchViewModel {
    public var query = ""
    public private(set) var results: SearchResults?
    public private(set) var suggestions: [Shelf] = []
    /// The trimmed query that produced `results` (for the "No results" message).
    public private(set) var resultsQuery = ""

    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var indexTask: Task<SearchIndex, Never>?
    @ObservationIgnored private var indexVersion: Int?
    @ObservationIgnored private var generation = 0

    /// Test seams.
    @ObservationIgnored private(set) var searchRunCount = 0
    @ObservationIgnored private(set) var indexBuildCount = 0

    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void

    public convenience init(debounce: Duration = .milliseconds(150)) {
        self.init(debounce: debounce, sleep: { try await Task.sleep(for: $0) })
    }

    /// Tests inject `sleep` to control when the debounce fires.
    init(debounce: Duration, sleep: @escaping @MainActor (Duration) async throws -> Void) {
        self.debounce = debounce
        self.sleep = sleep
    }

    public var showsNoResults: Bool {
        guard let results else { return false }
        return results.shows.isEmpty && results.movies.isEmpty
    }

    /// Builds the index (off the main actor) once per catalog version and refreshes the suggestion shelves.
    public func setCatalog(_ catalog: Catalog?, version: Int) {
        guard let catalog else {
            indexTask?.cancel()
            indexTask = nil
            indexVersion = nil
            suggestions = []
            results = nil
            return
        }
        guard indexVersion != version || indexTask == nil else { return }
        indexTask?.cancel()
        indexVersion = version
        indexBuildCount += 1
        indexTask = Task.detached(priority: .userInitiated) { SearchIndex(catalog: catalog) }
        let home = ShelfBuilder.home(catalog: catalog, hero: [], continueWatching: [], newEpisodes: [], myList: [], now: catalog.fetchedAt)
        suggestions = home.shelves.filter { $0.kind == .popularShows || $0.kind == .topRatedMovies }
    }

    /// Call whenever `query` changes (the screen uses `.task(id: query)`). Debounced; a newer call or cancellation discards this one.
    public func queryChanged() async {
        generation += 1
        let current = generation
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            results = nil
            return
        }
        do { try await sleep(debounce) } catch { return }
        guard current == generation, let indexTask else { return }
        searchRunCount += 1
        let index = await indexTask.value
        let found = await Task.detached(priority: .userInitiated) { index.search(text) }.value
        guard current == generation, !Task.isCancelled else { return }
        results = found
        resultsQuery = text
    }
}
