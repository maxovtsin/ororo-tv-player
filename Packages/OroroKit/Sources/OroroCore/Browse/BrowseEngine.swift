import Foundation

public enum BrowseEngine {
    public static func apply(_ query: BrowseQuery, to catalog: Catalog) -> [Title] {
        let source = query.kind == .show ? catalog.shows : catalog.movies
        let filtered = source.filter { matches($0, query) }
        return filtered.sorted { precedes($0, $1, by: query.sort) }
    }

    /// By title count desc.
    public static func genres(for kind: TitleKind, in catalog: Catalog) -> [String] {
        var counts: [String: Int] = [:]
        for title in titles(of: kind, in: catalog) {
            for genre in Set(title.genres) { counts[genre, default: 0] += 1 }
        }
        return counts.keys.sorted { lhs, rhs in
            let (left, right) = (counts[lhs, default: 0], counts[rhs, default: 0])
            if left != right { return left > right }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    /// e.g. [2020, 2010, …]
    public static func decades(for kind: TitleKind, in catalog: Catalog) -> [Int] {
        let decades = Set(titles(of: kind, in: catalog).compactMap { $0.year.map { $0 / 10 * 10 } })
        return decades.sorted(by: >)
    }

    // MARK: - Private

    private static func titles(of kind: TitleKind, in catalog: Catalog) -> [Title] {
        kind == .show ? catalog.shows : catalog.movies
    }

    private static func matches(_ title: Title, _ query: BrowseQuery) -> Bool {
        if let genre = query.genre, !title.genres.contains(genre) { return false }
        if let decade = query.decade {
            guard let year = title.year, year / 10 * 10 == decade else { return false }
        }
        if let minRating = query.minRating {
            guard let rating = title.imdbRating, rating >= minRating else { return false }
        }
        if query.kind == .show, let status = query.status {
            switch status {
            case .ongoing: if title.ended != false { return false }
            case .ended: if title.ended != true { return false }
            }
        }
        return true
    }

    private static func precedes(_ lhs: Title, _ rhs: Title, by sort: BrowseQuery.Sort) -> Bool {
        let order: ComparisonResult
        switch sort {
        case .popular:
            if (lhs.popularity == 0) != (rhs.popularity == 0) { return rhs.popularity == 0 }
            if lhs.popularity == 0 {
                order = descending(lhs.imdbRating, rhs.imdbRating)
            } else {
                order = descending(lhs.popularity, rhs.popularity)
            }
        case .rating:
            order = descending(lhs.imdbRating, rhs.imdbRating)
        case .year:
            let byYear = descending(lhs.year, rhs.year)
            order = byYear != .orderedSame ? byYear : descending(lhs.updatedAt, rhs.updatedAt)
        case .recentlyUpdated:
            order = descending(lhs.updatedAt, rhs.updatedAt)
        case .alphabetical:
            order = lhs.name.localizedStandardCompare(rhs.name)
        }
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.id.id < rhs.id.id
    }

    /// Larger values first; `nil` after every value.
    private static func descending<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (left?, right?):
            if left == right { return .orderedSame }
            return left > right ? .orderedAscending : .orderedDescending
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        }
    }
}
