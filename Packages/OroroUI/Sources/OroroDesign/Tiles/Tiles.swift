import SwiftUI

/// Per-platform tile sizes (artwork only; the landscape caption overlays the space below).
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

/// 2:3
public struct PosterTile: View {
    private let model: TileModel
    private let isFocused: Bool

    public init(_ model: TileModel, isFocused: Bool) {
        self.model = model
        self.isFocused = isFocused
    }

    public var body: some View {
        let size = TileMetrics.size(.poster)
        ZStack(alignment: .topLeading) {
            RemoteImage(url: model.posterURL, pointSize: size)
            if let badge = model.badge {
                Badge(badge).padding(Spacing.s)
            }
        }
        .frame(width: size.width, height: size.height)
        .modifier(TileChrome(isFocused: isFocused))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
    }
}

/// 16:9; title + subtitle reveal below on focus (quick); progress bar; badge top-leading.
public struct LandscapeTile: View {
    private let model: TileModel
    private let isFocused: Bool

    public init(_ model: TileModel, isFocused: Bool) {
        self.model = model
        self.isFocused = isFocused
    }

    public var body: some View {
        let size = TileMetrics.size(.landscape)
        ZStack(alignment: .topLeading) {
            if let backdrop = model.backdropURL {
                RemoteImage(url: backdrop, pointSize: size)
            } else {
                PlaceholderArtwork(posterURL: model.posterURL, title: model.title)
            }
            if let badge = model.badge {
                Badge(badge).padding(Spacing.s)
            }
            if let progress = model.progress {
                ProgressBar(progress: progress)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(width: size.width, height: size.height)
        .modifier(TileChrome(isFocused: isFocused))
        .overlay(alignment: .bottomLeading) { caption(width: size.width) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
    }

    private func caption(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: model.title)
                .font(Typography.headline)
                .lineLimit(1)
            if let subtitle = model.subtitle {
                Text(verbatim: subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
        .offset(y: 64)
        .opacity(isFocused ? 1 : 0)
        .motion(Motion.quick, value: isFocused)
    }
}

public struct SeeAllTile: View {
    private let shape: TileShape

    public init(shape: TileShape) {
        self.shape = shape
    }

    public var body: some View {
        let size = TileMetrics.size(shape)
        VStack(spacing: Spacing.s) {
            Image(systemName: "chevron.right.circle")
                .font(.largeTitle)
            Text("See All", bundle: .module)
                .font(Typography.headline)
        }
        .foregroundStyle(Palette.textSecondary)
        .frame(width: size.width, height: size.height)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: TileMetrics.cornerRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("See all", bundle: .module))
    }
}

/// Shimmer; static with Reduce Motion.
public struct SkeletonTile: View {
    private let shape: TileShape
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    public init(shape: TileShape) {
        self.shape = shape
    }

    public var body: some View {
        let size = TileMetrics.size(shape)
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
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
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
