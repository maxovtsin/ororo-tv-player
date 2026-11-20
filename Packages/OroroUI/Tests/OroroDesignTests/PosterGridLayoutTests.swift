import CoreGraphics
import Testing
@testable import OroroDesign

@Suite struct PosterGridLayoutTests {
    /// Tiles plus gaps must fit inside the screen edges at every width, so no tile overlaps its neighbour.
    @Test func tilesFitTheWidth() {
        for width in stride(from: CGFloat(120), through: 2600, by: 7) {
            let layout = PosterGridLayout(width: width)
            let used = CGFloat(layout.columns) * layout.tileWidth + CGFloat(layout.columns - 1) * layout.spacing
            #expect(layout.columns >= 1)
            #expect(layout.tileWidth > 0)
            #expect(used <= max(width - 2 * Spacing.screenEdge, 1) + 0.5, "width \(width)")
        }
    }

    @Test func tilesNeverShrinkBelowTheMinimumWhenOneFits() {
        let narrowest = PosterGridLayout.minTileWidth + 2 * Spacing.screenEdge
        for width in stride(from: narrowest, through: 2600, by: 11) {
            #expect(PosterGridLayout(width: width).tileWidth >= PosterGridLayout.minTileWidth - 0.5, "width \(width)")
        }
    }

    #if os(tvOS)
    @Test func tvCanvasShowsSixFullSizePosters() {
        let layout = PosterGridLayout(width: 1920)
        #expect(layout.columns == 6)
        #expect(abs(layout.tileWidth - TileMetrics.size(.poster).width) < 0.5)
    }
    #else
    @Test func phoneShowsThreeColumns() {
        #expect(PosterGridLayout(width: 393).columns == 3)
    }
    #endif
}
