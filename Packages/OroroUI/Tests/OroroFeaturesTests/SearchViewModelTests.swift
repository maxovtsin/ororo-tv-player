import Foundation
import OroroCore
import OroroTestSupport
import Testing
@testable import OroroFeatures

@Suite @MainActor struct SearchViewModelTests {
    private let catalog = Catalog(
        shows: [Samples.show(1, popularity: 9, name: "Breaking Point"), Samples.show(2, popularity: 5, name: "Other Show")],
        movies: [Samples.movie(10, name: "Point Break"), Samples.movie(11, name: "Unrelated")],
        fetchedAt: Samples.now
    )

    private func model(debounce: Duration = .milliseconds(30)) -> SearchViewModel {
        let model = SearchViewModel(debounce: debounce)
        model.setCatalog(catalog, version: 1)
        return model
    }

    @Test func emptyQueryShowsSuggestions() async {
        let model = model()
        model.query = "  "
        await model.queryChanged()
        #expect(model.results == nil)
        #expect(model.showsNoResults == false)
        #expect(model.suggestions.map(\.id) == ["popularShows", "topRatedMovies"])
        #expect(model.suggestions[0].items.first?.title.name == "Breaking Point")
    }

    @Test func queryProducesResultsAfterDebounce() async {
        let model = model()
        model.query = "point"
        await model.queryChanged()
        #expect(model.results?.shows.map(\.name) == ["Breaking Point"])
        #expect(model.results?.movies.map(\.name) == ["Point Break"])
        model.query = ""
        await model.queryChanged()
        #expect(model.results == nil)
    }

    @Test func rapidTypingRunsOneSearch() async {
        let model = model(debounce: .milliseconds(60))
        var tasks: [Task<Void, Never>] = []
        for text in ["b", "br", "bre", "brea", "break"] {
            tasks.append(Task { model.query = text; await model.queryChanged() })
            await Task.yield()
        }
        for task in tasks { await task.value }
        #expect(model.searchRunCount == 1)
        #expect(model.results?.shows.map(\.name) == ["Breaking Point"])
        #expect(model.results?.movies.map(\.name) == ["Point Break"])
    }

    @Test func staleResultIsDiscarded() async {
        let model = model(debounce: .milliseconds(40))
        model.query = "unrelated"
        let first = Task { await model.queryChanged() }
        await Task.yield()
        model.query = "other"
        let second = Task { await model.queryChanged() }
        await first.value
        await second.value
        #expect(model.results?.shows.map(\.name) == ["Other Show"])
        #expect(model.results?.movies.isEmpty == true)
    }

    @Test func noResultsFlag() async {
        let model = model()
        model.query = "zzzz"
        await model.queryChanged()
        #expect(model.results == SearchResults(shows: [], movies: []))
        #expect(model.showsNoResults)
        model.query = "point"
        await model.queryChanged()
        #expect(model.showsNoResults == false)
    }

    @Test func newCatalogVersionRebuildsIndex() async {
        let model = model()
        model.setCatalog(catalog, version: 1)
        #expect(model.indexBuildCount == 1)
        model.query = "fresh"
        await model.queryChanged()
        #expect(model.showsNoResults)
        let next = Catalog(shows: [Samples.show(3, name: "Fresh Prince")], movies: [], fetchedAt: Samples.now)
        model.setCatalog(next, version: 2)
        #expect(model.indexBuildCount == 2)
        await model.queryChanged()
        #expect(model.results?.shows.map(\.name) == ["Fresh Prince"])
        #expect(model.suggestions.first?.items.first?.title.name == "Fresh Prince")
    }

    @Test func nilCatalogIsSafe() async {
        let model = SearchViewModel(debounce: .zero)
        model.setCatalog(nil, version: 0)
        model.query = "anything"
        await model.queryChanged()
        #expect(model.results == nil)
        #expect(model.suggestions.isEmpty)
        #expect(model.showsNoResults == false)
        model.setCatalog(catalog, version: 1)
        model.setCatalog(nil, version: 2)
        #expect(model.suggestions.isEmpty)
    }
}
