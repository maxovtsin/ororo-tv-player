import Foundation
import OroroCore
import OroroDesign

extension TileModel {
    /// A plain title tile: subtitle is the year; no progress, no badge.
    public init(_ title: Title, locale: Locale = .current) {
        self.init(
            id: Self.tileID(title.id),
            title: title.name,
            subtitle: title.year.map { String($0) },
            posterURL: title.posterURL,
            backdropURL: title.backdropURL,
            progress: nil,
            badge: nil,
            accessibilityLabel: Self.accessibilityLabel(title, progress: nil, locale: locale)
        )
    }

    /// A shelf item tile: subtitle is "S2 E5" when the item has an episode, else the year;
    /// `.new` / `.newCount` / `.newSince` all map to the `.new` badge.
    public init(_ item: ShelfItem, locale: Locale = .current) {
        let subtitle: String? = if let episode = item.episode {
            "S\(episode.season) E\(episode.number)"
        } else {
            item.title.year.map { String($0) }
        }
        self.init(
            id: item.id,
            title: item.title.name,
            subtitle: subtitle,
            posterURL: item.title.posterURL,
            backdropURL: item.title.backdropURL,
            progress: item.progress,
            badge: item.badge == nil ? nil : .new,
            accessibilityLabel: Self.accessibilityLabel(item.title, progress: item.progress, locale: locale)
        )
    }

    /// Same scheme as `ShelfItem.id`: "<kind>-<id>".
    static func tileID(_ id: TitleID) -> String {
        "\(id.kind.rawValue)-\(id.id)"
    }

    /// "name, year, IMDb rating x, n percent watched" with absent parts omitted.
    static func accessibilityLabel(_ title: Title, progress: Double?, locale: Locale) -> String {
        var parts = [title.name]
        if let year = title.year {
            parts.append(String(year))
        }
        if let rating = title.imdbRating {
            let value = rating.formatted(.number.precision(.fractionLength(1)).locale(locale))
            parts.append(String(localized: "tile.accessibility.imdb", defaultValue: "IMDb rating \(value)", bundle: .module, locale: locale))
        }
        if let progress, progress.isFinite {
            let percent = Int((min(max(progress, 0), 1) * 100).rounded())
            parts.append(String(localized: "tile.accessibility.watched", defaultValue: "\(percent) percent watched", bundle: .module, locale: locale))
        }
        return parts.joined(separator: ", ")
    }
}
