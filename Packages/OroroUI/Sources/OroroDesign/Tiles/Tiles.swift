import SwiftUI

/// Per-platform tile sizes.
///
/// `size(_:)` is the artwork size. A landscape tile additionally reserves `captionHeight(_:)`
/// directly below its artwork for the title and subtitle, so its total layout
/// height is `size.height + captionHeight`. `ShelfRow` and `PosterGrid` must allow that total.
public enum TileMetrics {
    public static func size(_ shape: TileShape) -> CGSize {
        #if os(tvOS)
        switch shape {
        case .poster: CGSize(width: 260, height: 390)
        case .landscape: CGSize(width: 400, height: 225)
        }
        #else
        switch shape {
        case .poster: CGSize(width: 120, height: 180)
        case .landscape: CGSize(width: 240, height: 135)
        }
        #endif
    }

    /// Space reserved below the artwork for the caption (zero for posters).
    public static func captionHeight(_ shape: TileShape) -> CGFloat {
        switch shape {
        case .poster: 0
        case .landscape:
            #if os(tvOS)
            80
            #else
            44
            #endif
        }
    }

    /// A poster `width` points wide (2:3); nil is the standard poster size.
    static func posterSize(width: CGFloat?) -> CGSize {
        let standard = size(.poster)
        guard let width else { return standard }
        return CGSize(width: width, height: (width * standard.height / standard.width).rounded())
    }

    static let cornerRadius: CGFloat = 12
    static let focusScale: CGFloat = 1.08
}

private struct TileChrome: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: TileMetrics.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: TileMetrics.cornerRadius)
                    .strokeBorder(Palette.focusHighlight, lineWidth: isFocused ? 3 : 0)
            }
            .scaleEffect(isFocused ? TileMetrics.focusScale : 1)
            .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: isFocused ? 16 : 0, y: isFocused ? 8 : 0)
            .motion(Motion.quick, value: isFocused)
    }
}

private struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.35))
                Capsule().fill(.white)
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 4)
        .padding(.horizontal, Spacing.m)
        .padding(.bottom, Spacing.m)
    }
}

/// 2:3. In a grid, `width` sizes the tile to its column and `showsCaption` adds title + subtitle below the artwork.
public struct PosterTile: View {
    private let model: TileModel
    private let isFocused: Bool
    private let width: CGFloat?
    private let showsCaption: Bool

    public init(_ model: TileModel, isFocused: Bool, width: CGFloat? = nil, showsCaption: Bool = false) {
        self.model = model
        self.isFocused = isFocused
        self.width = width
        self.showsCaption = showsCaption
    }

    public var body: some View {
        let size = TileMetrics.posterSize(width: width)
        VStack(alignment: .leading, spacing: 0) {
            artwork(size: size)
                .modifier(TileChrome(isFocused: isFocused))
            if showsCaption {
                TileCaption(model: model, isFocused: isFocused, compact: true)
                    // Clears the artwork's focus scale so the caption never sits under it.
                    .padding(.top, size.height * (TileMetrics.focusScale - 1) / 2 + Spacing.xs)
                    .frame(width: size.width, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
    }

    private func artwork(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if model.posterURL != nil {
                RemoteImage(url: model.posterURL, pointSize: size)
            } else {
                PlaceholderArtwork(posterURL: nil, title: model.title)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay(alignment: .topLeading) { badgeView }
    }

    @ViewBuilder private var badgeView: some View {
        if let badge = model.badge { Badge(badge).padding(Spacing.s) }
    }
}

/// Title and subtitle below a tile's artwork, brightened on focus.
private struct TileCaption: View {
    let model: TileModel
    let isFocused: Bool
    /// Poster grids: a smaller title, so narrow columns fit more of it.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: model.title)
                .font(compact ? Typography.tileTitle : Typography.headline)
                .lineLimit(1)
            if let subtitle = model.subtitle {
                Text(verbatim: subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(isFocused ? Palette.textPrimary : Palette.textSecondary)
        .motion(Motion.quick, value: isFocused)
    }
}

/// 16:9; title + subtitle always shown below (brightened on focus); progress bar; badge top-leading.
public struct LandscapeTile: View {
    private let model: TileModel
    private let isFocused: Bool

    public init(_ model: TileModel, isFocused: Bool) {
        self.model = model
        self.isFocused = isFocused
    }

    public var body: some View {
        let size = TileMetrics.size(.landscape)
        VStack(alignment: .leading, spacing: 0) {
            artwork(size: size)
                .modifier(TileChrome(isFocused: isFocused))
            caption
                .frame(width: size.width, height: TileMetrics.captionHeight(.landscape), alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
    }

    private func artwork(size: CGSize) -> some View {
        ZStack(alignment: .bottom) {
            if let backdrop = model.backdropURL {
                RemoteImage(url: backdrop, pointSize: size)
            } else {
                PlaceholderArtwork(posterURL: model.posterURL, title: model.title)
            }
            if let progress = model.progress {
                ProgressBar(progress: progress)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay(alignment: .topLeading) {
            if let badge = model.badge { Badge(badge).padding(Spacing.s) }
        }
    }

    private var caption: some View {
        TileCaption(model: model, isFocused: isFocused)
            .padding(.top, Spacing.m)
    }
}

public struct SeeAllTile: View {
    private let shape: TileShape
    @Environment(\.isFocused) private var isFocused

    public init(shape: TileShape) {
        self.shape = shape
    }

    public var body: some View {
        let size = TileMetrics.size(shape)
        VStack(spacing: Spacing.s) {
            Image(systemName: "chevron.right.circle")
                .font(Typography.title)
            Text(label)
                .font(Typography.headline)
        }
        .foregroundStyle(isFocused ? Palette.textPrimary : Palette.textSecondary)
        .frame(width: size.width, height: size.height)
        .background(.white.opacity(isFocused ? 0.16 : 0.08))
        .modifier(TileChrome(isFocused: isFocused))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        String(localized: "tile.seeAll", defaultValue: "See All", bundle: .module)
    }
}

/// Shimmer; static with Reduce Motion.
public struct SkeletonTile: View {
    private let shape: TileShape
    private let width: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    /// `width` sizes a poster skeleton to a grid column; nil is the standard size.
    public init(shape: TileShape, width: CGFloat? = nil) {
        self.shape = shape
        self.width = width
    }

    public var body: some View {
        let size = shape == .poster ? TileMetrics.posterSize(width: width) : TileMetrics.size(shape)
        RoundedRectangle(cornerRadius: TileMetrics.cornerRadius)
            .fill(.white.opacity(0.08))
            .overlay {
                if !reduceMotion {
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.12), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .offset(x: phase * size.width)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: TileMetrics.cornerRadius))
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Motion.shimmer) { phase = 1 }
            }
    }
}

#Preview("Poster focused / unfocused") {
    HStack(spacing: 40) {
        PosterTile(TileModel(id: "1", title: "Severance", badge: .imdb(8.7), accessibilityLabel: "Severance"), isFocused: true)
        PosterTile(TileModel(id: "2", title: "Dark", badge: .hd, accessibilityLabel: "Dark"), isFocused: false)
        SeeAllTile(shape: .poster)
        SkeletonTile(shape: .poster)
    }
    .padding(60)
}

#Preview("Landscape variants") {
    HStack(spacing: 40) {
        LandscapeTile(
            TileModel(id: "1", title: "Andor", subtitle: "S1 E4", backdropURL: nil, progress: 0.62,
                      badge: .new, accessibilityLabel: "Andor"),
            isFocused: true
        )
        LandscapeTile(
            TileModel(id: "2", title: "Alien", subtitle: "1979", backdropURL: URL(string: "https://example.com/a.jpg"),
                      accessibilityLabel: "Alien"),
            isFocused: false
        )
        SeeAllTile(shape: .landscape)
        SkeletonTile(shape: .landscape)
    }
    .padding(60)
}
