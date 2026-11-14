import SwiftUI

// STUB (T3) — implemented by Task D4.

/// 2:3
public struct PosterTile: View {
    private let model: TileModel

    public init(_ model: TileModel, isFocused: Bool) {
        self.model = model
    }

    public var body: some View {
        Text(verbatim: model.title)
    }
}

/// 16:9; title + subtitle reveal below on focus (quick); progress bar; badge top-leading.
public struct LandscapeTile: View {
    private let model: TileModel

    public init(_ model: TileModel, isFocused: Bool) {
        self.model = model
    }

    public var body: some View {
        Text(verbatim: model.title)
    }
}

public struct SeeAllTile: View {
    public init(shape: TileShape) {}

    public var body: some View {
        EmptyView()
    }
}

/// Shimmer; static with Reduce Motion.
public struct SkeletonTile: View {
    public init(shape: TileShape) {}

    public var body: some View {
        EmptyView()
    }
}

/// Per platform.
public enum TileMetrics {
    public static func size(_ shape: TileShape) -> CGSize {
        .zero
    }
}
