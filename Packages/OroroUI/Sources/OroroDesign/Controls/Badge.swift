import SwiftUI

/// Solid-fill badge (IMDb yellow with black text; the others outlined). Never glass.
public struct Badge: View {
    private let kind: BadgeKind

    public init(_ kind: BadgeKind) {
        self.kind = kind
    }

    public var body: some View {
        label
            .font(Typography.badge.weight(.bold))
            .lineLimit(1)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .modifier(BadgeChrome(isFilled: isFilled))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(kind.accessibilityLabel)
    }

    private var isFilled: Bool {
        if case .imdb = kind { return true }
        return false
    }

    private var label: Text {
        switch kind {
        case .imdb(let rating): Text(verbatim: "IMDb \(Self.formatted(rating))")
        case .hd: Text(verbatim: "HD")
        case .sd: Text(verbatim: "SD")
        case .cc: Text(verbatim: "CC")
        case .new: Text(verbatim: Self.newTitle)
        case .text(let string): Text(verbatim: string)
        }
    }

    /// Shared by the visible "New" badge and its accessibility label.
    nonisolated static var newTitle: String {
        String(localized: "badge.new", defaultValue: "New", bundle: .module)
    }

    nonisolated static func formatted(_ rating: Double) -> String {
        rating.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US_POSIX")))
    }
}

private struct BadgeChrome: ViewModifier {
    let isFilled: Bool

    func body(content: Content) -> some View {
        if isFilled {
            content
                .foregroundStyle(Color.black)
                .background(Palette.imdb, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            content
                .foregroundStyle(Palette.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Palette.textPrimary.opacity(0.7), lineWidth: 1.5)
                )
        }
    }
}

public extension BadgeKind {
    /// "IMDb rating 8.3", "High definition", "Standard definition", "Subtitles available", "New"
    var accessibilityLabel: String {
        switch self {
        case .imdb(let rating):
            let text = Badge.formatted(rating)
            return String(localized: "badge.imdb.accessibility", defaultValue: "IMDb rating \(text)", bundle: .module)
        case .hd:
            return String(localized: "badge.hd.accessibility", defaultValue: "High definition", bundle: .module)
        case .sd:
            return String(localized: "badge.sd.accessibility", defaultValue: "Standard definition", bundle: .module)
        case .cc:
            return String(localized: "badge.cc.accessibility", defaultValue: "Subtitles available", bundle: .module)
        case .new:
            return Badge.newTitle
        case .text(let string):
            return string
        }
    }
}

#Preview("Badges") {
    HStack {
        Badge(.imdb(8.3))
        Badge(.hd)
        Badge(.sd)
        Badge(.cc)
        Badge(.new)
        Badge(.text("Ongoing"))
    }
    .padding()
}
