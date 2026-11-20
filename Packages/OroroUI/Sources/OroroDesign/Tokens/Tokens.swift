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
    /// Poster grid captions: narrower than a landscape tile, so a step below `headline`.
    public static let tileTitle: Font = .callout.weight(.semibold)
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
    /// Tint of a selected chip / active filter: a lighter glass capsule (the label adapts for contrast).
    public static let selection: Color = .white.opacity(0.32)

    // Brand: the neon "ororo" on a warm tube screen (matches the app icon).
    /// #FFB547, the neon wordmark and progress line.
    public static let brandAmber = Color(red: 0xFF / 255, green: 0xB5 / 255, blue: 0x47 / 255)
    /// #FFF3D6, the power-on line's hot core.
    public static let tubeWhite = Color(red: 0xFF / 255, green: 0xF3 / 255, blue: 0xD6 / 255)
    /// #2B1606, the warm centre of the tube screen.
    public static let screenGlow = Color(red: 0x2B / 255, green: 0x16 / 255, blue: 0x06 / 255)
    /// #060303, the tube screen's edge; also the system launch screen's colour.
    public static let screenBlack = Color(red: 0x06 / 255, green: 0x03 / 255, blue: 0x03 / 255)
    /// rgba(255, 214, 160, 0.6), captions on the tube screen.
    public static let screenCaption = Color(red: 1, green: 0xD6 / 255, blue: 0xA0 / 255).opacity(0.6)
}
