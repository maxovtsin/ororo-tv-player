import Foundation
import Observation
import OroroCore
import OroroDesign

/// State of the filter grid: the query, its results (computed off the main actor), and the footer strip text.
@MainActor @Observable final class BrowseGridViewModel {
    typealias Compute = @Sendable (BrowseQuery, Catalog) async -> [Title]

    /// Spec: footer text debounce.
    static let footerDebounce: Duration = .milliseconds(150)

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
    private(set) var focused: Title?
    /// Debounced by `footerDebounce` after focus moves.
    private(set) var footerText: String?
    let genres: [String]
    let decades: [Int]

    /// Called synchronously whenever the query changes (before results are recomputed).
    @ObservationIgnored var onQueryChange: ((BrowseQuery) -> Void)?

    @ObservationIgnored private let catalog: Catalog
    @ObservationIgnored private let compute: Compute
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var computeTask: Task<Void, Never>?
    @ObservationIgnored private var footerTask: Task<Void, Never>?
    @ObservationIgnored private var indexByTileID: [String: Int] = [:]

    init(query: BrowseQuery, catalog: Catalog, debounce: Duration = BrowseGridViewModel.footerDebounce,
         locale: Locale = .current, compute: @escaping Compute = BrowseGridViewModel.defaultCompute) {
        var query = query
        // A malformed route must not select options the kind does not offer.
        if query.kind == .movie {
            query.status = nil
            if query.sort == .popular { query.sort = .recentlyUpdated }
        }
        self.query = query
        self.catalog = catalog
        self.compute = compute
        self.debounce = debounce
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

    /// `id` is a tile id ("show-12"); nil when focus left the grid.
    func focusChanged(_ id: String?) {
        focused = id.flatMap { indexByTileID[$0] }.map { results[$0] }
        scheduleFooter()
    }

    /// Waits for the in-flight computation and footer update. For tests.
    func settle() async {
        await computeTask?.value
        await footerTask?.value
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
        let (current, query, catalog, compute) = (generation, query, catalog, compute)
        isFiltering = true
        computeTask = Task { [weak self] in
            let titles = await compute(query, catalog)
            guard !Task.isCancelled else { return }
            let output = await Self.build(titles)
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

    @concurrent static func build(_ titles: [Title]) async -> Output {
        var index: [String: Int] = [:]
        index.reserveCapacity(titles.count)
        var tiles: [TileModel] = []
        tiles.reserveCapacity(titles.count)
        for (offset, title) in titles.enumerated() {
            let tile = TileModel(title)
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
        if let focused, indexByTileID[TileModel.tileID(focused.id)] == nil {
            self.focused = nil
            scheduleFooter()
        }
    }

    private func scheduleFooter() {
        footerTask?.cancel()
        let (target, debounce) = (focused, debounce)
        footerTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            footerText = target.map { Self.footerText(for: $0, locale: locale) }
        }
    }

    /// "name · IMDb 8.3 · 2019 · Ongoing"; absent parts are omitted, status is for shows only.
    static func footerText(for title: Title, locale: Locale) -> String {
        var parts = [title.name]
        if let rating = title.imdbRating {
            let value = rating.formatted(.number.precision(.fractionLength(1)).locale(locale))
            parts.append(String(localized: "browse.grid.footer.imdb", defaultValue: "IMDb \(value)", bundle: .module, locale: locale))
        }
        if let year = title.year {
            parts.append(String(year))
        }
        if title.id.kind == .show, let ended = title.ended {
            parts.append(ended
                ? String(localized: "browse.status.ended", defaultValue: "Ended", bundle: .module, locale: locale)
                : String(localized: "browse.status.ongoing", defaultValue: "Ongoing", bundle: .module, locale: locale))
        }
        return parts.joined(separator: " · ")
    }

    /// Replaces the path entry holding this grid's original query so Back and tab switches keep the filters.
    /// Returns false when `index` no longer points at that entry (e.g. the screen was popped).
    @discardableResult
    static func writeBack(_ query: BrowseQuery, replacing original: BrowseQuery, into path: inout [Route], at index: Int?) -> Bool {
        guard let index, path.indices.contains(index), path[index] == .browse(original) else { return false }
        path[index] = .browse(query)
        return true
    }
}
