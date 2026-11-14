import Foundation

// STUB (T3) — implemented by Task C5.
public enum LibraryQueries {
    public static func continueWatching(_ library: Library, catalog: Catalog) -> [ShelfItem] {
        []
    }

    /// Includes those in Continue Watching.
    public static func showsWithNewEpisodes(_ library: Library, catalog: Catalog) -> [Title] {
        []
    }

    public static func newEpisodes(_ library: Library, catalog: Catalog, resolved: [Int: NewEpisodeInfo]) -> [ShelfItem] {
        []
    }

    /// Newest first.
    public static func myList(_ library: Library, catalog: Catalog) -> [Title] {
        []
    }

    public static func heroAction(for title: Title, library: Library) -> HeroAction {
        title.id.kind == .movie ? .playMovie : .playFirstEpisode
    }

    /// In-progress, else upNext.
    public static func resumeTarget(showID: Int, library: Library) -> EpisodeRef? {
        nil
    }
}
