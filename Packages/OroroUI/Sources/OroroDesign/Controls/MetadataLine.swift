import SwiftUI

// STUB (T3) — implemented by Task D3.
public enum MetadataItem: Hashable, Sendable { case badge(BadgeKind), text(String) }

/// One line, " · " between text items, one combined accessibility element.
public struct MetadataLine: View {
    public init(_ items: [MetadataItem]) {}

    public static func accessibilityLabel(for items: [MetadataItem]) -> String {
        ""
    }

    public var body: some View {
        EmptyView()
    }
}
