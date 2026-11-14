import Foundation
import Nuke
import Testing
@testable import OroroDesign

@Suite struct ImageCacheTests {
    @Test func requestResizesToPixelSize() throws {
        let url = try #require(URL(string: "https://example.com/poster.jpg"))
        let request = ImageCache.request(url, pointSize: CGSize(width: 300, height: 450), scale: 2)
        let resize = try #require(request.processors.compactMap { $0 as? ImageProcessors.Resize }.first)
        #expect(resize.description.contains("size: (600.0, 900.0) pixels"))
        #expect(request.url == url)
    }

    @Test func clearEmptiesDiskUsage() async throws {
        ImageCache.configure()
        let cache = try #require(ImageCache.dataCache)
        cache.storeData(Data(repeating: 7, count: 64 * 1024), for: "ororo-test-seed")
        cache.flush()
        #expect(await ImageCache.diskUsage() >= 64 * 1024)
        await ImageCache.clear()
        #expect(await ImageCache.diskUsage() == 0)
    }

    @Test func diskLimitIs500MB() {
        #expect(ImageCache.diskLimit == 524_288_000)
    }
}
