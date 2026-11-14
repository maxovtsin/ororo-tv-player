import Foundation

// STUB (T3) — implemented by Task C2.
public enum BrowseEngine {
    public static func apply(_ query: BrowseQuery, to catalog: Catalog) -> [Title] {
        []
    }

    /// By title count desc.
    public static func genres(for kind: TitleKind, in catalog: Catalog) -> [String] {
        []
    }

    /// e.g. [2020, 2010, …]
    public static func decades(for kind: TitleKind, in catalog: Catalog) -> [Int] {
        []
    }
}
