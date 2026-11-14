import Foundation

// STUB (T3) — implemented by Task C1.
public enum ShelfBuilder {
    public static let shelfCap = 30

    /// 6: 3 shows + 3 movies, interleaved show first.
    public static func hero(catalog: Catalog, now: Date) -> [Title] {
        []
    }

    public static func home(catalog: Catalog, hero: [HeroItem], continueWatching: [ShelfItem],
                            newEpisodes: [ShelfItem], myList: [Title], now: Date) -> HomeContent {
        HomeContent(hero: hero, shelves: [])
    }

    public static func browseTab(kind: TitleKind, catalog: Catalog) -> [Shelf] {
        []
    }

    public static func genresByCount(_ titles: [Title]) -> [(genre: String, count: Int)] {
        []
    }
}
