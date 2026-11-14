import Foundation
import OroroCore

/// Hand-built, deterministic test data (no decoding, so it works before Task A1).
///
/// `catalog`: 48 shows (ids 101...148) and 48 movies (ids 1001...1048), `fetchedAt == now`.
/// Values are spread by formula over the index `i` in 1...48 — see the report of Task T3 for the table.
public enum Samples {
    /// 2025-11-01T00:00:00Z
    public static let now = Date(timeIntervalSince1970: 1_761_955_200)

    public static let day: TimeInterval = 86_400

    public static let genres = ["Drama", "Comedy", "Crime", "Thriller", "Sci-Fi", "Documentary", "Animation", "Romance"]

    public static let catalog = Catalog(
        shows: (1...48).map(sampleShow),
        movies: (1...48).map(sampleMovie),
        fetchedAt: now
    )

    // MARK: - Builders

    public static func show(
        _ id: Int,
        popularity: Int = 0,
        newestVideo: Date? = nil,
        name: String? = nil,
        imdbRating: Double? = 7.5,
        year: Int? = 2020,
        genres: [String] = ["Drama"],
        countries: [String] = ["US"],
        ended: Bool = false,
        updatedAt: Date? = nil,
        hasBackdrop: Bool = true,
        desc: String? = "A sample show."
    ) -> Title {
        Title(
            id: TitleID(kind: .show, id: id),
            name: name ?? "Show \(id)",
            desc: desc,
            posterURL: URL(string: "https://example.invalid/posters/show-\(id).jpg"),
            backdropURL: hasBackdrop ? URL(string: "https://example.invalid/backdrops/show-\(id).jpg") : nil,
            imdbRating: imdbRating,
            imdbID: "tt\(1_000_000 + id)",
            year: year,
            genres: genres,
            countries: countries,
            lengthMinutes: 45,
            resolution: nil,
            ended: ended,
            popularity: popularity,
            newestVideo: newestVideo,
            updatedAt: updatedAt ?? newestVideo
        )
    }

    public static func movie(
        _ id: Int,
        name: String? = nil,
        imdbRating: Double? = 7.0,
        year: Int? = 2020,
        genres: [String] = ["Drama"],
        countries: [String] = ["US"],
        lengthMinutes: Int? = 120,
        resolution: Resolution? = .hd,
        updatedAt: Date? = nil,
        hasBackdrop: Bool = true,
        desc: String? = "A sample movie."
    ) -> Title {
        Title(
            id: TitleID(kind: .movie, id: id),
            name: name ?? "Movie \(id)",
            desc: desc,
            posterURL: URL(string: "https://example.invalid/posters/movie-\(id).jpg"),
            backdropURL: hasBackdrop ? URL(string: "https://example.invalid/backdrops/movie-\(id).jpg") : nil,
            imdbRating: imdbRating,
            imdbID: "tt\(2_000_000 + id)",
            year: year,
            genres: genres,
            countries: countries,
            lengthMinutes: lengthMinutes,
            resolution: resolution,
            ended: nil,
            popularity: 0,
            newestVideo: nil,
            updatedAt: updatedAt
        )
    }

    /// Episodes for `seasons` (season number → episode count), ordered by season then number.
    /// Episode id = showID * 10_000 + season * 100 + number; numbers start at 1;
    /// airdate = 2023-11-14 + (season * 60 + number * 7) days; qualities ["240p", "480p", "720p"]; `.hd`.
    public static func episodes(showID: Int, seasons: [Int: Int]) -> [Episode] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return seasons.keys.sorted().flatMap { season in
            (0..<max(seasons[season] ?? 0, 0)).map { offset -> Episode in
                let number = offset + 1
                return Episode(
                    id: showID * 10_000 + season * 100 + number,
                    showID: showID,
                    name: "Episode \(number)",
                    plot: "Plot of season \(season) episode \(number).",
                    season: season,
                    number: number,
                    airdate: base.addingTimeInterval(Double(season * 60 + number * 7) * day),
                    resolution: .hd,
                    qualities: ["240p", "480p", "720p"]
                )
            }
        }
    }

    // MARK: - Catalog generation

    static let showNames = [
        "Night Harbor", "The Glass Coast", "Paper Kings", "Northern Line", "Quiet Hours", "The Long Field",
        "Copper Saints", "Midnight Bureau", "Salt and Iron", "The Ninth Floor", "Open Water", "Harbor Lights",
        "Second Signal", "The Orchard", "Blue District", "Lost Frequencies", "The Arbiter", "Small Mercies",
        "Station Eleven Road", "The Winter Court", "High Wire", "Old Money", "Red Meridian", "The Clearing",
        "Fault Lines", "Dead Reckoning", "Bright Young Things", "The Long Night", "Outpost", "Common Ground",
        "The Dispatch", "Iron Valley", "Lighthouse Keepers", "Silver Lining", "The Understudy", "Last Orders",
        "Deep Field", "The Crossing", "Tin Star", "Golden Hour", "Black Ice", "The Assembly",
        "Long Shadows", "Parallel Lines", "The Archivist", "Night Shift", "Wild Coast", "Zero Hour"
    ]

    static let movieNames = [
        "Amélie", "The Last Lantern", "Iron Sky Road", "Beneath the Pines", "A Quiet Storm", "Glass Houses",
        "The Cartographer", "Ember", "Moonlit Avenue", "The Long Goodbye Home", "Starfall", "Paper Moon Rising",
        "The Heist at Noon", "Cold Harbor", "Sundown", "The Kind Stranger", "Echoes", "Night Train to Lyon",
        "The Iron Garden", "Undertow", "Bright Lights", "The Silent Partner", "Wanderlust", "Northbound",
        "The Painted Veil Road", "Breakwater", "Firefly Summer", "The Lost City", "Hollow Point", "Velvet",
        "The Clockmaker", "Daybreak", "Riverside", "The Gambler's Son", "Afterglow", "Stone Circle",
        "The Envoy", "Low Tide", "Crimson Peak Road", "The Interpreter", "Saltwater", "Dust and Thunder",
        "The Visitor", "Overland", "Sparrow", "The Night Manager", "Blue Hour", "Zenith"
    ]

    /// Primary genre; 24-step cycle: Drama 7, Comedy 5, Crime 4, Thriller 3, Sci-Fi 2, Documentary/Animation/Romance 1.
    static func primaryGenre(_ i: Int) -> String {
        let cycle = ["Drama", "Comedy", "Drama", "Crime", "Comedy", "Thriller", "Drama", "Sci-Fi",
                     "Crime", "Documentary", "Drama", "Comedy", "Drama", "Thriller", "Crime", "Animation",
                     "Drama", "Comedy", "Drama", "Thriller", "Crime", "Romance", "Comedy", "Sci-Fi"]
        return cycle[(i - 1) % cycle.count]
    }

    static func sampleShow(_ i: Int) -> Title {
        let newest = now.addingTimeInterval(-Double((i * 11) % 120) * day - 3600)
        var genres = [primaryGenre(i)]
        if i % 6 == 3 && i != 45 { genres.append("Sci-Fi") }
        return show(
            100 + i,
            popularity: i % 12 == 0 ? 0 : ((i * 17) % 48 + 1) * 100,
            newestVideo: newest,
            name: showNames[i - 1],
            imdbRating: i % 15 == 0 ? nil : 5.0 + Double((i * 7) % 45) / 10,
            year: i % 16 == 0 ? nil : 2025 - (i * 5) % 30,
            genres: genres,
            countries: [["US", "GB", "FR", "RU", "DE", "ES"][i % 6]],
            ended: i % 5 == 0,
            updatedAt: newest,
            hasBackdrop: ![3, 20, 41].contains(i),
            desc: [7, 33].contains(i) ? nil : "Description of \(showNames[i - 1])."
        )
    }

    static func sampleMovie(_ i: Int) -> Title {
        var genres = [primaryGenre(i)]
        if i % 5 == 0 { genres.append("Romance") }
        return movie(
            1000 + i,
            name: movieNames[i - 1],
            imdbRating: i % 14 == 0 ? nil : 5.5 + Double((i * 13) % 40) / 10,
            year: i % 17 == 0 ? nil : 2025 - (i * 7) % 40,
            genres: genres,
            countries: [["FR", "US", "GB", "IT", "JP", "RU"][i % 6]],
            lengthMinutes: 85 + (i * 13) % 70,
            resolution: i % 4 == 0 ? .sd : .hd,
            updatedAt: now.addingTimeInterval(-Double((i * 7) % 90) * day - 7200),
            hasBackdrop: ![5, 27, 44].contains(i),
            desc: [9, 38].contains(i) ? nil : "Description of \(movieNames[i - 1])."
        )
    }
}
