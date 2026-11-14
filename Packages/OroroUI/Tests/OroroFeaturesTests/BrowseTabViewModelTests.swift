import OroroCore
import OroroTestSupport
import Testing
@testable import OroroFeatures

@Suite @MainActor struct BrowseTabViewModelTests {
    @Test func nilCatalogGivesSkeleton() {
        let model = BrowseTabViewModel(kind: .show)
        model.appear(catalog: nil, version: 0)
        #expect(model.shelves == nil)
    }

    @Test func buildsShelvesForKind() throws {
        let shows = BrowseTabViewModel(kind: .show)
        shows.appear(catalog: Samples.catalog, version: 1)
        let showShelves = try #require(shows.shelves)
        #expect(showShelves.prefix(3).map(\.id) == ["popularNow", "latestReleases", "topRated"])
        #expect(showShelves.allSatisfy { $0.items.allSatisfy { $0.title.id.kind == .show } })

        let movies = BrowseTabViewModel(kind: .movie)
        movies.appear(catalog: Samples.catalog, version: 1)
        let movieShelves = try #require(movies.shelves)
        #expect(movieShelves.prefix(2).map(\.id) == ["recentlyUpdated", "topRated"])
        #expect(movieShelves.allSatisfy { $0.items.allSatisfy { $0.title.id.kind == .movie } })
        #expect(movieShelves.allSatisfy { $0.items.count <= 30 })
    }

    @Test func doesNotRebuildForSameVersion() throws {
        let model = BrowseTabViewModel(kind: .show)
        model.appear(catalog: Samples.catalog, version: 1)
        let first = try #require(model.shelves)
        let other = Catalog(shows: Array(Samples.catalog.shows.prefix(3)), movies: [], fetchedAt: Samples.now)
        model.appear(catalog: other, version: 1)
        #expect(model.shelves == first)
    }

    @Test func rebuildsForNewVersionOnAppear() throws {
        let model = BrowseTabViewModel(kind: .show)
        model.appear(catalog: Samples.catalog, version: 1)
        let first = try #require(model.shelves)
        let other = Catalog(shows: Array(Samples.catalog.shows.prefix(3)), movies: [], fetchedAt: Samples.now)
        model.appear(catalog: other, version: 2)
        let second = try #require(model.shelves)
        #expect(second != first)
        #expect(second.first?.totalCount == 3)
    }

    @Test func seeAllPushesPresetQuery() throws {
        let model = BrowseTabViewModel(kind: .movie)
        model.appear(catalog: Samples.catalog, version: 1)
        let shelf = try #require(model.shelves?.first { $0.id == "topRated" })
        let router = TabRouter()
        model.seeAll(shelf, router: router)
        #expect(router.path == [.browse(BrowseQuery(kind: .movie, sort: .rating))])
    }

    @Test func browseAllPushesDefaultQuery() {
        let router = TabRouter()
        BrowseTabViewModel(kind: .show).browseAll(router: router)
        BrowseTabViewModel(kind: .movie).browseAll(router: router)
        #expect(router.path == [.browse(BrowseQuery(kind: .show, sort: .popular)),
                                .browse(BrowseQuery(kind: .movie, sort: .recentlyUpdated))])
    }

    @Test func selectOpensDetail() throws {
        let model = BrowseTabViewModel(kind: .show)
        model.appear(catalog: Samples.catalog, version: 1)
        let shelf = try #require(model.shelves?.first)
        let item = try #require(shelf.items.first)
        let router = TabRouter()
        model.select(item, router: router)
        #expect(router.path == [.show(item.title.id.id)])
        #expect(router.zoomSourceID == nil)
        model.select(item, in: shelf, router: router)
        #expect(router.zoomSourceID == "\(shelf.id)/\(item.id)")
    }
}
