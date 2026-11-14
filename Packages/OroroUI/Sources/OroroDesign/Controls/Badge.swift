import SwiftUI

// STUB (T3) — implemented by Task D3.
public struct Badge: View {
    public init(_ kind: BadgeKind) {}

    public var body: some View {
        EmptyView()
    }
}

public extension BadgeKind {
    /// "IMDb rating 8.3", "High definition", "Standard definition", "Subtitles available", "New"
    var accessibilityLabel: String {
        ""
    }
}
