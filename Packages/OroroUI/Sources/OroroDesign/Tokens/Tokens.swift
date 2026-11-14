import SwiftUI

// STUB (T3) — implemented by Task D1. Placeholder values only.
public enum Spacing {
    public static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 16, l: CGFloat = 24, xl: CGFloat = 40
    public static let screenEdge: CGFloat = 80
    public static let shelfGap: CGFloat = 40
}

/// System text styles only.
public enum Typography {
    public static let heroTitle: Font = .largeTitle, title: Font = .title, headline: Font = .headline
    public static let body: Font = .body, caption: Font = .caption, badge: Font = .caption2
}

public enum Palette {
    /// #F5C518
    public static let imdb = Color(red: 0xF5 / 255, green: 0xC5 / 255, blue: 0x18 / 255)
    public static let scrim: Color = .black.opacity(0.6), textPrimary: Color = .primary, textSecondary: Color = .secondary
    public static let focusHighlight: Color = .white
}
