import Foundation

/// Locale-aware display formatting for the UI. Pure logic; no string catalog.
public enum Display {
    /// en: "2h 35m", "45m"
    public static func runtime(minutes: Int, locale: Locale) -> String {
        Duration.seconds(max(minutes, 0) * 60).formatted(
            .units(
                allowed: [.hours, .minutes],
                width: .narrow,
                zeroValueUnits: .hide
            )
            .locale(locale)
        )
    }

    /// Nil unless 2 ASCII letters.
    public static func flag(_ iso2: String) -> String? {
        let scalars = Array(iso2.unicodeScalars)
        guard scalars.count == 2,
              scalars.allSatisfy({ $0.isASCII && $0.properties.isAlphabetic })
        else { return nil }
        var result = ""
        for scalar in String(iso2).uppercased().unicodeScalars {
            guard let indicator = Unicode.Scalar(0x1F1E6 + scalar.value - 0x41) else { return nil }
            result.unicodeScalars.append(indicator)
        }
        return result
    }

    public static func countryName(_ iso2: String, locale: Locale) -> String? {
        guard iso2.count == 2 else { return nil }
        return locale.localizedString(forRegionCode: iso2.uppercased())
    }

    /// Falls back to uppercased code.
    public static func languageName(_ code: String, locale: Locale) -> String {
        locale.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    /// "S2 E5"
    public static func episodeLabel(season: Int, number: Int) -> String {
        "S\(season) E\(number)"
    }

    /// en: "30 Mar 2025"
    public static func airdate(_ date: Date, locale: Locale) -> String {
        date.formatted(
            // Airdates are UTC-midnight calendar dates; never depend on TimeZone.current.
            Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: .gmt)
        )
    }

    /// Nil when older than 14 days or in the future.
    public static func newEpisodeAgo(_ date: Date, now: Date, locale: Locale) -> String? {
        let age = now.timeIntervalSince(date)
        guard age >= 0, age <= 14 * 86_400 else { return nil }
        // Date.RelativeFormatStyle can only be relative to Date.now; the formatter takes an explicit reference.
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// "23:14", "1:02:03"
    public static func timecode(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(min(seconds, 359_999 * 3600)) // clamp so huge values cannot trap
        let (hours, minutes, secs) = (total / 3600, total % 3600 / 60, total % 60)
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// "240p–1080p"; same → "720p"
    public static func qualityRange(lowest: String, highest: String) -> String {
        lowest == highest ? lowest : "\(lowest)–\(highest)"
    }
}
