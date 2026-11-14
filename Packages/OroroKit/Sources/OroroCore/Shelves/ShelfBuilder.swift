import Foundation

public enum ShelfBuilder {
    public static let shelfCap = 30

    private static let heroWindow: TimeInterval = 30 * 86_400
    private static let heroPerKind = 3
    private static let homeGenreRows = 4
    private static let topRatedYears = 20

    /// 6: 3 shows + 3 movies, interleaved show first.
    public static func hero(catalog: Catalog, now: Date) -> [Title] {
        let cutoff = now.addingTimeInterval(-heroWindow)
        let shows = heroPicks(catalog.shows, cutoff: cutoff, date: \.newestVideo) { Double($0.popularity) }
        let movies = heroPicks(catalog.movies, cutoff: cutoff, date: \.updatedAt) { $0.imdbRating ?? -1 }
        var result: [Title] = []
        for index in 0..<heroPerKind {
            if index < shows.count { result.append(shows[index]) }
            if index < movies.count { result.append(movies[index]) }
        }
        return result
    }

    public static func home(catalog: Catalog, hero: [HeroItem], continueWatching: [ShelfItem],
                            newEpisodes: [ShelfItem], myList: [Title], now: Date) -> HomeContent {
        let minYear = year(of: now) - topRatedYears
        var shelves: [Shelf] = []
        func add(_ shelf: Shelf) {
            if !shelf.items.isEmpty { shelves.append(shelf) }
        }

        add(personal("continueWatching", .continueWatching, continueWatching))
        add(personal("newEpisodes", .newEpisodes, newEpisodes))
        add(shelf("popularShows", .popularShows, popular(catalog.shows), .init(kind: .show, sort: .popular)))
        add(shelf("latestReleases", .latestReleases, latest(catalog.shows), .init(kind: .show, sort: .recentlyUpdated)))
        add(shelf("topRatedMovies", .topRatedMovies, topRated(catalog.movies, minYear: minYear, requirePopularity: false),
                  .init(kind: .movie, sort: .rating)))
        add(shelf("recentlyUpdatedMovies", .recentlyUpdatedMovies, recentlyUpdated(catalog.movies),
                  .init(kind: .movie, sort: .recentlyUpdated)))
        add(personal("myList", .myList, myList.map { ShelfItem(title: $0) }))

        for entry in genresByCount(catalog.shows + catalog.movies).prefix(homeGenreRows) {
            let showsInGenre = catalog.shows.filter { $0.genres.contains(entry.genre) }
            let moviesInGenre = catalog.movies.filter { $0.genres.contains(entry.genre) }
            // A BrowseQuery is single-kind, so the row follows the kind with more titles in the genre.
            let kind: TitleKind = showsInGenre.count >= moviesInGenre.count ? .show : .movie
            add(genreShelf(entry.genre, kind: kind, titles: kind == .show ? showsInGenre : moviesInGenre, now: now))
        }
        return HomeContent(hero: hero, shelves: shelves)
    }

    public static func browseTab(kind: TitleKind, catalog: Catalog) -> [Shelf] {
        let titles = catalog.titles(kind)
        let minYear = year(of: catalog.fetchedAt) - topRatedYears
        var shelves: [Shelf] = []
        func add(_ shelf: Shelf) {
            if !shelf.items.isEmpty { shelves.append(shelf) }
        }

        switch kind {
        case .show:
            add(shelf("popularNow", .popularNow, popular(titles), .init(kind: .show, sort: .popular)))
            add(shelf("latestReleases", .latestReleases, latest(titles), .init(kind: .show, sort: .recentlyUpdated)))
            add(shelf("topRated", .topRated, topRated(titles, minYear: minYear, requirePopularity: true),
                      .init(kind: .show, sort: .rating)))
        case .movie:
            add(shelf("recentlyUpdated", .recentlyUpdated, recentlyUpdated(titles), .init(kind: .movie, sort: .recentlyUpdated)))
            add(shelf("topRated", .topRated, topRated(titles, minYear: minYear, requirePopularity: false),
                      .init(kind: .movie, sort: .rating)))
        }
        for entry in genresByCount(titles) {
            add(genreShelf(entry.genre, kind: kind, titles: titles.filter { $0.genres.contains(entry.genre) },
                           now: catalog.fetchedAt))
        }
        return shelves
    }

    /// Count desc, then name ascending.
    public static func genresByCount(_ titles: [Title]) -> [(genre: String, count: Int)] {
        var counts: [String: Int] = [:]
        for title in titles {
            for genre in Set(title.genres) { counts[genre, default: 0] += 1 }
        }
        return counts
            .map { (genre: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.genre < $1.genre }
    }

    // MARK: - Hero

    private static func heroPicks(
        _ titles: [Title],
        cutoff: Date,
        date: KeyPath<Title, Date?>,
        score: (Title) -> Double
    ) -> [Title] {
        let eligible = titles.filter { title in
            title.backdropURL != nil
                && !(title.desc ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let recent = eligible.filter { ($0[keyPath: date] ?? .distantPast) >= cutoff }
        let pool = recent.count >= heroPerKind ? recent : eligible
        let sorted = pool.sorted { lhs, rhs in
            let (left, right) = (score(lhs), score(rhs))
            return left != right ? left > right : lhs.id.id < rhs.id.id
        }
        return Array(sorted.prefix(heroPerKind))
    }

    // MARK: - Orderings

    private static func popular(_ titles: [Title]) -> [Title] {
        titles.sorted {
            if $0.popularity != $1.popularity { return $0.popularity > $1.popularity }
            let (left, right) = ($0.imdbRating ?? -1, $1.imdbRating ?? -1)
            return left != right ? left > right : $0.id.id < $1.id.id
        }
    }

    private static func latest(_ titles: [Title]) -> [Title] {
        newestFirst(titles.filter { $0.newestVideo != nil }, \.newestVideo)
    }

    private static func recentlyUpdated(_ titles: [Title]) -> [Title] {
        newestFirst(titles.filter { $0.updatedAt != nil }, \.updatedAt)
    }

    private static func newestFirst(_ titles: [Title], _ date: KeyPath<Title, Date?>) -> [Title] {
        titles.sorted {
            let (left, right) = ($0[keyPath: date] ?? .distantPast, $1[keyPath: date] ?? .distantPast)
            return left != right ? left > right : $0.id.id < $1.id.id
        }
    }

    private static func topRated(_ titles: [Title], minYear: Int, requirePopularity: Bool) -> [Title] {
        titles
            .filter { title in
                guard let year = title.year, year >= minYear, title.imdbRating != nil else { return false }
                return !requirePopularity || title.popularity > 0
            }
            .sorted {
                let (left, right) = ($0.imdbRating ?? 0, $1.imdbRating ?? 0)
                return left != right ? left > right : $0.id.id < $1.id.id
            }
    }

    // MARK: - Shelves

    private static func personal(_ id: String, _ kind: ShelfKind, _ items: [ShelfItem]) -> Shelf {
        Shelf(id: id, kind: kind, items: Array(items.prefix(shelfCap)), totalCount: items.count)
    }

    private static func shelf(_ id: String, _ kind: ShelfKind, _ titles: [Title], _ seeAll: BrowseQuery) -> Shelf {
        Shelf(id: id, kind: kind, items: titles.prefix(shelfCap).map { ShelfItem(title: $0) },
              totalCount: titles.count, seeAll: seeAll)
    }

    /// Top Picks order; "See All" opens the grid with the same sort.
    private static func genreShelf(_ genre: String, kind: TitleKind, titles: [Title], now: Date) -> Shelf {
        var query = BrowseQuery.default(kind)
        query.genre = genre
        query.sort = .topPicks
        return shelf("genre-\(genre)", .genre(genre), TopPicks.ordered(titles, now: now), query)
    }

    private static func year(of date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.component(.year, from: date)
    }
}
