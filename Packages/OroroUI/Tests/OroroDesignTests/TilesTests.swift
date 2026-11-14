import Testing
import CoreGraphics
@testable import OroroDesign

@Suite struct TilesTests {
    @Test func metricsKeepAspectRatios() {
        let poster = TileMetrics.size(.poster)
        let landscape = TileMetrics.size(.landscape)
        #expect(abs(poster.width / poster.height - 2.0 / 3.0) < 0.01)
        #expect(abs(landscape.width / landscape.height - 16.0 / 9.0) < 0.01)
    }

    @Test func onlyLandscapeReservesCaptionSpace() {
        #expect(TileMetrics.captionHeight(.poster) == 0)
        #expect(TileMetrics.captionHeight(.landscape) > 0)
    }
}
