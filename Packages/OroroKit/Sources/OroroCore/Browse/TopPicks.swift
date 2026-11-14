import Foundation

/// "Top Picks": highest IMDb rating first, but only among titles worth trusting the rating for.
///
/// ororo gives no vote counts, so a raw rating sort is led by obscure titles and old classics. Instead:
/// - Shows people watch on ororo (`popularity > 0`) come first, by rating (ties: more popular first).
/// - Movies (no popularity data) from the last `recentYears` years come first, by rating (ties: newer first).
/// - Every other rated title follows, by rating; unrated titles go last.
public enum TopPicks {
    public static let recentYears = 15

    public static func ordered(_ titles: [Title], now: Date) -> [Title] {
        let currentYear = year(of: now)
        return titles.sorted { precedes($0, $1, currentYear: currentYear) }
    }

    static func precedes(_ lhs: Title, _ rhs: Title, currentYear: Int) -> Bool {
        let (left, right) = (tier(lhs, currentYear: currentYear), tier(rhs, currentYear: currentYear))
        if left != right { return left < right }
        let (leftRating, rightRating) = (lhs.imdbRating ?? 0, rhs.imdbRating ?? 0)
        if leftRating != rightRating { return leftRating > rightRating }
        if lhs.popularity != rhs.popularity { return lhs.popularity > rhs.popularity }
        let (leftYear, rightYear) = (lhs.year ?? 0, rhs.year ?? 0)
        if leftYear != rightYear { return leftYear > rightYear }
        return lhs.id.id < rhs.id.id
    }

    static func year(of date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.component(.year, from: date)
    }

    /// 0 = trusted and rated, 1 = rated, 2 = unrated.
    private static func tier(_ title: Title, currentYear: Int) -> Int {
        guard title.imdbRating != nil else { return 2 }
        let trusted = switch title.id.kind {
        case .show: title.popularity > 0
        case .movie: (title.year ?? 0) > currentYear - recentYears
        }
        return trusted ? 0 : 1
    }
}
