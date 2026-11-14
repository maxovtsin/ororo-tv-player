import SwiftUI

public enum TileShape: Sendable { case poster, landscape }

public enum BadgeKind: Hashable, Sendable { case imdb(Double), hd, sd, cc, new, text(String) }

public struct TileModel: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var subtitle: String?
    public var posterURL: URL?
    public var backdropURL: URL?
    public var progress: Double?
    public var badge: BadgeKind?
    public var accessibilityLabel: String

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        progress: Double? = nil,
        badge: BadgeKind? = nil,
        accessibilityLabel: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.progress = progress
        self.badge = badge
        self.accessibilityLabel = accessibilityLabel
    }
}
