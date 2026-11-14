import Foundation

// STUB (T3) — implemented by Task C3.
public struct SearchIndex: Sendable {
    public init(catalog: Catalog) {}

    public func search(_ query: String, limit: Int = 50) -> SearchResults {
        SearchResults(shows: [], movies: [])
    }
}
