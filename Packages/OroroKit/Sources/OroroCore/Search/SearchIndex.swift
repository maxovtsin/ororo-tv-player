import Foundation

/// Prebuilt, case- and diacritic-folded index over a `Catalog`. Build once, query many times.
public struct SearchIndex: Sendable {
    private struct Entry: Sendable {
        let title: Title
        let name: [UInt8]
        let words: [[UInt8]]
        let genres: Set<String>
        let year: Int?
    }

    private let shows: [Entry]
    private let movies: [Entry]

    public init(catalog: Catalog) {
        // Within a tier shows rank by popularity, movies by rating. Pre-sorting makes the
        // per-query tier sort a cheap pass (index order breaks the remaining ties).
        let sortedShows = catalog.shows.sorted { $0.popularity > $1.popularity }
        let sortedMovies = catalog.movies.sorted { ($0.imdbRating ?? -1) > ($1.imdbRating ?? -1) }
        shows = sortedShows.map(Self.entry)
        movies = sortedMovies.map(Self.entry)
    }

    public func search(_ query: String, limit: Int = 50) -> SearchResults {
        let folded = Self.fold(query)
        let bytes = Array(folded.utf8)
        guard !folded.isEmpty, limit > 0 else { return SearchResults(shows: [], movies: []) }
        let yearQuery = folded.count == 4 ? Int(folded) : nil
        return SearchResults(
            shows: Self.rank(shows, folded, bytes, yearQuery, limit),
            movies: Self.rank(movies, folded, bytes, yearQuery, limit)
        )
    }

    // MARK: - Internals

    /// Lowercase, strip diacritics, collapse runs of whitespace to a single space.
    static func fold(_ string: String) -> String {
        let base = string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return base.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func entry(_ title: Title) -> Entry {
        let name = fold(title.name)
        return Entry(
            title: title,
            name: Array(name.utf8),
            words: name.split(separator: " ").map { Array($0.utf8) },
            genres: Set(title.genres.map(fold)),
            year: title.year
        )
    }

    private static func tier(of entry: Entry, _ query: String, _ bytes: [UInt8], _ yearQuery: Int?) -> Int? {
        if entry.name == bytes { return 0 }
        if entry.name.starts(with: bytes) { return 1 }
        if entry.words.contains(where: { $0.starts(with: bytes) }) { return 2 }
        if contains(entry.name, bytes) { return 3 }
        if entry.genres.contains(query) { return 4 }
        if let yearQuery, entry.year == yearQuery { return 5 }
        return nil
    }

    /// Byte-wise substring test; folded strings are plain UTF-8 so this is exact and fast.
    private static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        let last = haystack.count - needle.count
        var start = 0
        while start <= last {
            if haystack[start] == needle[0], haystack[start...].starts(with: needle) { return true }
            start += 1
        }
        return false
    }

    private static func rank(
        _ entries: [Entry], _ query: String, _ bytes: [UInt8], _ yearQuery: Int?, _ limit: Int
    ) -> [Title] {
        var matches: [(tier: Int, index: Int)] = []
        for (index, entry) in entries.enumerated() {
            if let tier = tier(of: entry, query, bytes, yearQuery) { matches.append((tier, index)) }
        }
        matches.sort { $0.tier != $1.tier ? $0.tier < $1.tier : $0.index < $1.index }
        return matches.prefix(limit).map { entries[$0.index].title }
    }
}
