import Foundation

// STUB (T3) — implemented by Task C7.
public enum Display {
    /// en: "2h 35m", "45m"
    public static func runtime(minutes: Int, locale: Locale) -> String {
        ""
    }

    /// Nil unless 2 ASCII letters.
    public static func flag(_ iso2: String) -> String? {
        nil
    }

    public static func countryName(_ iso2: String, locale: Locale) -> String? {
        nil
    }

    /// Falls back to uppercased code.
    public static func languageName(_ code: String, locale: Locale) -> String {
        ""
    }

    /// "S2 E5"
    public static func episodeLabel(season: Int, number: Int) -> String {
        ""
    }

    /// en: "30 Mar 2025"
    public static func airdate(_ date: Date, locale: Locale) -> String {
        ""
    }

    /// Nil when older than 14 days or in the future.
    public static func newEpisodeAgo(_ date: Date, now: Date, locale: Locale) -> String? {
        nil
    }

    /// "23:14", "1:02:03"
    public static func timecode(_ seconds: TimeInterval) -> String {
        ""
    }

    /// "1 Season", "2 Seasons"
    public static func seasonCount(_ n: Int, locale: Locale) -> String {
        ""
    }

    /// "240p–1080p"; same → "720p"
    public static func qualityRange(lowest: String, highest: String) -> String {
        ""
    }
}
