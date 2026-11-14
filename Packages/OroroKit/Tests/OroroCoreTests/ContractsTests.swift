import Foundation
import OroroCore
import OroroTestSupport
import Testing

@Test func libraryRoundTripsThroughJSON() throws {
    var lib = Library()
    lib.upNext[7] = UpNextEntry(ref: EpisodeRef(episodeID: 1, season: 1, number: 2), setAt: Date(timeIntervalSince1970: 50))
    lib.followed[7] = FollowState(seenNewestVideo: Date(timeIntervalSince1970: 100), started: true)
    let back = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(lib))
    #expect(back == lib)
}

@Test func catalogLooksUpByID() {
    #expect(Samples.catalog.title(Samples.catalog.shows[0].id) == Samples.catalog.shows[0])
    #expect(Samples.catalog.title(TitleID(kind: .movie, id: -1)) == nil)
}

@Test func defaultQuerySortDependsOnKind() {
    #expect(BrowseQuery.default(.show).sort == .popular)
    #expect(BrowseQuery.default(.movie).sort == .recentlyUpdated)
}

@Test func fixturesLoad() { #expect(Fixtures.data("shows").count > 1000) }
