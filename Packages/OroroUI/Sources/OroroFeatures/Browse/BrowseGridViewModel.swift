import Foundation
import Observation
import OroroCore
import OroroDesign

/// State of the filter grid: the query and its results and tiles (computed off the main actor).
@MainActor @Observable final class BrowseGridViewModel {
    typealias Compute = @Sendable (BrowseQuery, Catalog) async -> [Title]

    /// Runs on the global executor, never on the main actor.
    @concurrent static func defaultCompute(_ query: BrowseQuery, _ catalog: Catalog) async -> [Title] {
        BrowseEngine.apply(query, to: catalog)
    }

    var query: BrowseQuery
    private(set) var results: [Title] = []
    /// `results` as grid tiles, built once per results change.
    private(set) var tiles: [TileModel] = []
    /// True from creation / a query change until its results have landed.
    private(set) var isFiltering = true
    /// Bumps each time `results` is replaced; the screen keys its crossfade on it.
    private(set) var resultsVersion = 0
    let genres: [String]
    let decades: [Int]

    /// Called synchronously whenever the query changes (before results are recomputed).
    @ObservationIgnored var onQueryChange: ((BrowseQuery) -> Void)?

    @ObservationIgnored private let catalog: Catalog
    @ObservationIgnored private let compute: Compute
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var computeTask: Task<Void, Never>?
    @ObservationIgnored private var indexByTileID: [String: Int] = [:]

    init(query: BrowseQuery, catalog: Catalog, locale: Locale = .current, compute: @escaping Compute = BrowseGridViewModel.defaultCompute) {
        var query = query
        // A malformed route must not select options the kind does not offer.
        if query.kind == .movie {
            query.status = nil
            if query.sort == .popular { query.sort = .recentlyUpdated }
        }
        self.query = query
        self.catalog = catalog
        self.compute = compute
        self.locale = locale
        genres = BrowseEngine.genres(for: query.kind, in: catalog)
        decades = BrowseEngine.decades(for: query.kind, in: catalog)
        recompute()
    }

    var availableSorts: [BrowseQuery.Sort] {
        BrowseQuery.Sort.allCases.filter { query.kind == .show || $0 != .popular }
    }

    var showsStatusFilter: Bool {
        query.kind == .show
    }

    var isDefault: Bool {
        query == .default(query.kind)
    }

    func setGenre(_ genre: String?) {
        update { $0.genre = genre }
    }

    func setDecade(_ decade: Int?) {
        update { $0.decade = decade }
    }

    func setMinRating(_ rating: Double?) {
        update { $0.minRating = rating }
    }

    func setStatus(_ status: BrowseQuery.Status?) {
        guard showsStatusFilter else { return }
        update { $0.status = status }
    }

    func setSort(_ sort: BrowseQuery.Sort) {
        guard availableSorts.contains(sort) else { return }
        update { $0.sort = sort }
    }

    func reset() {
        update { $0 = .default($0.kind) }
    }

    /// Waits for the in-flight computation. For tests.
    func settle() async {
        await computeTask?.value
    }

    // MARK: - Private

    private func update(_ change: (inout BrowseQuery) -> Void) {
        var next = query
        change(&next)
        guard next != query else { return }
        query = next
        onQueryChange?(next)
        recompute()
    }

    private func recompute() {
        computeTask?.cancel()
        generation += 1
        let (current, query, catalog, compute, locale) = (generation, query, catalog, compute, locale)
        isFiltering = true
        computeTask = Task { [weak self] in
            let titles = await compute(query, catalog)
            guard !Task.isCancelled else { return }
            let output = await Self.build(titles, locale: locale)
            guard !Task.isCancelled else { return }
            self?.apply(output, generation: current)
        }
    }

    /// Everything derived from the results, built off the main actor so it only assigns.
    struct Output: Sendable {
        let titles: [Title]
        let tiles: [TileModel]
        let indexByTileID: [String: Int]
    }

    @concurrent static func build(_ titles: [Title], locale: Locale) async -> Output {
        var index: [String: Int] = [:]
        index.reserveCapacity(titles.count)
        var tiles: [TileModel] = []
        tiles.reserveCapacity(titles.count)
        for (offset, title) in titles.enumerated() {
            var tile = TileModel(title, locale: locale)
            tile.subtitle = caption(for: title, locale: locale)
            tiles.append(tile)
            if index[tile.id] == nil { index[tile.id] = offset }
        }
        return Output(titles: titles, tiles: tiles, indexByTileID: index)
    }

    /// The title behind a grid tile id.
    func title(forTileID id: String) -> Title? {
        indexByTileID[id].map { results[$0] }
    }

    private func apply(_ output: Output, generation current: Int) {
        guard current == generation else { return }
        results = output.titles
        tiles = output.tiles
        indexByTileID = output.indexByTileID
        resultsVersion += 1
        isFiltering = false
    }

    /// The caption line under a grid tile: "2019 · ★ 8.3"; absent parts are omitted, nil when both are.
    nonisolated static func caption(for title: Title, locale: Locale) -> String? {
        var parts: [String] = []
        if let year = title.year {
            parts.append(String(year))
        }
        if let rating = title.imdbRating {
            parts.append("★ " + rating.formatted(.number.precision(.fractionLength(1)).locale(locale)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Replaces the path entry holding this grid's original query so Back and tab switches keep the filters.
    /// Only writes while the grid is the top entry: a push on top (detail) or a pop must not touch the stack.
    /// Returns false when `index` no longer points at that entry.
    @discardableResult
    static func writeBack(_ query: BrowseQuery, replacing original: BrowseQuery, into path: inout [Route], at index: Int?) -> Bool {
        guard let index, path.count == index + 1, path[index] == .browse(original) else { return false }
        path[index] = .browse(query)
        return true
    }
}
