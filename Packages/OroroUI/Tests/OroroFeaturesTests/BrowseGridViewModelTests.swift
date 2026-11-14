import Foundation
import OroroCore
@testable import OroroFeatures
import OroroTestSupport
import Testing

@Suite @MainActor struct BrowseGridViewModelTests {
    private let locale = Locale(identifier: "en_US")

    private let catalog = Catalog(
        shows: [
            Samples.show(1, popularity: 50, name: "Alpha", imdbRating: 8.3, year: 2019, genres: ["Drama", "Crime"], ended: false),
            Samples.show(2, popularity: 90, name: "Bravo", imdbRating: 6.1, year: 2011, genres: ["Comedy"], ended: true),
            Samples.show(3, popularity: 70, name: "Charlie", imdbRating: 7.4, year: 2021, genres: ["Drama"], ended: false)
        ],
        movies: [
            Samples.movie(10, name: "Delta", imdbRating: 7.2, year: 2015, genres: ["Drama"], updatedAt: Date(timeIntervalSince1970: 100)),
            Samples.movie(11, name: "Echo", imdbRating: 8.8, year: 2018, genres: ["Comedy"], updatedAt: Date(timeIntervalSince1970: 300)),
            Samples.movie(12, name: "Foxtrot", imdbRating: nil, year: nil, genres: ["Drama"], updatedAt: Date(timeIntervalSince1970: 200))
        ],
        fetchedAt: Samples.now
    )

    private func model(_ query: BrowseQuery, compute: BrowseGridViewModel.Compute? = nil) -> BrowseGridViewModel {
        BrowseGridViewModel(query: query, catalog: catalog, debounce: .zero, locale: locale,
                            compute: compute ?? { BrowseEngine.apply($0, to: $1) })
    }

    private func ids(_ model: BrowseGridViewModel) -> [Int] {
        model.results.map(\.id.id)
    }

    @Test func initialResultsMatchQuery() async {
        let query = BrowseQuery(kind: .show, genre: "Drama", sort: .rating)
        let model = model(query)
        #expect(model.isFiltering)
        await model.settle()
        #expect(!model.isFiltering)
        #expect(ids(model) == [1, 3])
        #expect(model.results == BrowseEngine.apply(query, to: catalog))
        #expect(model.genres == BrowseEngine.genres(for: .show, in: catalog))
        #expect(model.decades == [2020, 2010])
    }

    @Test func settersUpdateResults() async {
        let model = model(.default(.show))
        await model.settle()
        #expect(ids(model) == [2, 3, 1]) // popularity 90, 70, 50

        model.setGenre("Drama")
        #expect(model.query.genre == "Drama")
        await model.settle()
        #expect(ids(model) == [3, 1])

        model.setDecade(2010)
        await model.settle()
        #expect(ids(model) == [1])

        model.setDecade(nil)
        model.setMinRating(7.0)
        model.setStatus(.ongoing)
        await model.settle()
        #expect(ids(model) == [3, 1])

        model.setSort(.alphabetical)
        await model.settle()
        #expect(ids(model) == [1, 3])
        #expect(model.query == BrowseQuery(kind: .show, genre: "Drama", minRating: 7.0, status: .ongoing, sort: .alphabetical))
    }

    @Test func movieQueryHidesPopularSortAndStatus() async {
        let movies = model(.default(.movie))
        #expect(movies.availableSorts == [.rating, .year, .recentlyUpdated, .alphabetical])
        #expect(!movies.showsStatusFilter)
        movies.setStatus(.ended)
        movies.setSort(.popular)
        #expect(movies.query == .default(.movie))

        let shows = model(.default(.show))
        #expect(shows.availableSorts == [.popular, .rating, .year, .recentlyUpdated, .alphabetical])
        #expect(shows.showsStatusFilter)

        // A malformed route is normalised.
        let odd = model(BrowseQuery(kind: .movie, status: .ongoing, sort: .popular))
        #expect(odd.query == .default(.movie))
        await movies.settle()
        await odd.settle()
    }

    @Test func resetRestoresDefault() async {
        var notified: [BrowseQuery] = []
        let model = model(BrowseQuery(kind: .show, genre: "Drama", decade: 2010, minRating: 8, status: .ended, sort: .year))
        model.onQueryChange = { notified.append($0) }
        await model.settle()
        #expect(!model.isDefault)
        model.reset()
        #expect(model.query == .default(.show))
        #expect(model.isDefault)
        #expect(notified == [.default(.show)])
        await model.settle()
        #expect(ids(model) == [2, 3, 1])
    }

    @Test func rapidChangesKeepOnlyLastResult() async {
        let gate = Gate()
        let stale = Samples.show(999, name: "Stale")
        let model = model(.default(.show)) { query, catalog in
            if query.sort == .rating {
                await gate.wait()
                return [stale]
            }
            return BrowseEngine.apply(query, to: catalog)
        }
        await model.settle()

        model.setSort(.rating) // blocked in compute
        model.setSort(.alphabetical)
        model.setGenre("Drama")
        await model.settle()
        #expect(ids(model) == [1, 3])

        await gate.open()
        for _ in 0..<50 { await Task.yield() }
        #expect(ids(model) == [1, 3])
        #expect(!model.isFiltering)
        #expect(model.query == BrowseQuery(kind: .show, genre: "Drama", sort: .alphabetical))
    }

    @Test func footerTextForShowAndMovie() async {
        let shows = model(.default(.show))
        await shows.settle()
        shows.focusChanged("show-1")
        await shows.settle()
        #expect(shows.focused?.id.id == 1)
        #expect(shows.footerText == "Alpha · IMDb 8.3 · 2019 · Ongoing")
        shows.focusChanged("show-2")
        await shows.settle()
        #expect(shows.footerText == "Bravo · IMDb 6.1 · 2011 · Ended")
        shows.focusChanged(nil)
        await shows.settle()
        #expect(shows.focused == nil)
        #expect(shows.footerText == nil)

        let movies = model(.default(.movie))
        await movies.settle()
        movies.focusChanged("movie-11")
        await movies.settle()
        #expect(movies.footerText == "Echo · IMDb 8.8 · 2018")
        movies.focusChanged("movie-12")
        await movies.settle()
        #expect(movies.footerText == "Foxtrot")
    }

    @Test func footerIsDebounced() async {
        let model = BrowseGridViewModel(query: .default(.show), catalog: catalog, debounce: .seconds(3600), locale: locale)
        await model.settle()
        model.focusChanged("show-1")
        await Task.yield()
        #expect(model.focused?.id.id == 1)
        #expect(model.footerText == nil) // still waiting out the debounce
        model.focusChanged(nil) // cancels the pending update
    }

    @Test func emptyResultIsReported() async {
        let model = model(BrowseQuery(kind: .show, genre: "Crime", minRating: 9, sort: .rating))
        await model.settle()
        #expect(model.results.isEmpty)
        #expect(!model.isFiltering)
        #expect(!model.isDefault)
        model.reset()
        await model.settle()
        #expect(ids(model) == [2, 3, 1])
    }

    @Test func queryIsWrittenBackToTheOriginalPathEntry() {
        let original = BrowseQuery.default(.show)
        let changed = BrowseQuery(kind: .show, genre: "Drama", sort: .year)
        var path: [Route] = [.show(5), .browse(original)]
        #expect(BrowseGridViewModel.writeBack(changed, replacing: original, into: &path, at: 1))
        #expect(path == [.show(5), .browse(changed)])
        // The entry no longer holds the original query, or the index is unusable.
        #expect(!BrowseGridViewModel.writeBack(changed, replacing: original, into: &path, at: 1))
        #expect(!BrowseGridViewModel.writeBack(changed, replacing: original, into: &path, at: nil))
        #expect(!BrowseGridViewModel.writeBack(changed, replacing: original, into: &path, at: 5))
        #expect(path == [.show(5), .browse(changed)])
    }

    @Test func noWriteBackWhileADetailIsPushedOrAfterPop() {
        let original = BrowseQuery.default(.show)
        let changed = BrowseQuery(kind: .show, genre: "Drama", sort: .year)
        var pushed: [Route] = [.browse(original), .show(1)]
        #expect(!BrowseGridViewModel.writeBack(changed, replacing: original, into: &pushed, at: 0))
        #expect(pushed == [.browse(original), .show(1)])
        var popped: [Route] = []
        #expect(!BrowseGridViewModel.writeBack(changed, replacing: original, into: &popped, at: 0))
        #expect(popped.isEmpty)
    }

    @Test func tilesAndLookupMatchResults() async {
        let model = model(.default(.show))
        await model.settle()
        #expect(model.tiles.map(\.id) == ["show-2", "show-3", "show-1"])
        #expect(model.title(forTileID: "show-3")?.id.id == 3)
        #expect(model.title(forTileID: "movie-10") == nil)
    }
}

/// A one-shot gate: `wait()` suspends until `open()`.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
