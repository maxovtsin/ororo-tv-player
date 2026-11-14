import SwiftUI

public enum MetadataItem: Hashable, Sendable { case badge(BadgeKind), text(String) }

/// One line, " · " between text items, one combined accessibility element.
public struct MetadataLine: View {
    private let items: [MetadataItem]

    public init(_ items: [MetadataItem]) {
        self.items = items
    }

    /// Spoken form: every item's label joined with ", ".
    public nonisolated static func accessibilityLabel(for items: [MetadataItem]) -> String {
        items.map { item in
            switch item {
            case .badge(let kind): kind.accessibilityLabel
            case .text(let string): string
            }
        }
        .joined(separator: ", ")
    }

    public var body: some View {
        HStack(spacing: Spacing.s) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0, showsSeparator(before: index) {
                    Text(verbatim: "·").foregroundStyle(Palette.textSecondary)
                }
                switch item {
                case .badge(let kind): Badge(kind)
                case .text(let string): Text(verbatim: string).foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .font(Typography.caption)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: items))
    }

    /// A dot sits only between two text items.
    private func showsSeparator(before index: Int) -> Bool {
        if case .text = items[index], case .text = items[index - 1] { return true }
        return false
    }
}

#Preview("MetadataLine") {
    MetadataLine([.badge(.imdb(8.3)), .text("2025"), .text("Drama"), .text("2h 10m"), .badge(.hd)])
        .padding()
}
