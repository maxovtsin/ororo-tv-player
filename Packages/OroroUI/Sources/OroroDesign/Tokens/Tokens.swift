import SwiftUI

public enum Spacing {
    #if os(tvOS)
    public static let xs: CGFloat = 6, s: CGFloat = 12, m: CGFloat = 24, l: CGFloat = 40, xl: CGFloat = 64
    /// Horizontal inset matching the tvOS title-safe area (1920 × 1080 pt canvas).
    public static let screenEdge: CGFloat = 80
    public static let shelfGap: CGFloat = 48
    #else
    public static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 16, l: CGFloat = 24, xl: CGFloat = 32
    public static let screenEdge: CGFloat = 20
    public static let shelfGap: CGFloat = 24
    #endif
}

/// System text styles only, so Dynamic Type, Bold Text and contrast settings apply.
public enum Typography {
    public static let heroTitle: Font = .largeTitle.weight(.bold)
    public static let title: Font = .title2.weight(.semibold)
    public static let headline: Font = .headline
    public static let body: Font = .body
    public static let caption: Font = .caption
    public static let badge: Font = .caption2.weight(.bold)
}

public enum Palette {
    /// #F5C518
    public static let imdb = Color(red: 0xF5 / 255, green: 0xC5 / 255, blue: 0x18 / 255)
    /// Darkening layer behind text over artwork.
    public static let scrim: Color = .black.opacity(0.6)
    public static let textPrimary: Color = .primary
    public static let textSecondary: Color = .secondary
    public static let focusHighlight: Color = .white
}
