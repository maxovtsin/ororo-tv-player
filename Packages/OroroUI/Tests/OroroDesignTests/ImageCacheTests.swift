import Foundation
import Nuke
import Testing
@testable import OroroDesign

@Suite struct ImageCacheTests {
    @Test func requestResizesToPixelSize() throws {
        let url = try #require(URL(string: "https://example.com/poster.jpg"))
        let request = ImageCache.request(url, pointSize: CGSize(width: 300, height: 450), scale: 2)
        let resize = try #require(request.processors.compactMap { $0 as? ImageProcessors.Resize }.first)
        let expected = ImageProcessors.Resize(size: CGSize(width: 600, height: 900), unit: .pixels)
        #expect(resize.identifier == expected.identifier)
        #expect(resize.identifier != ImageProcessors.Resize(size: CGSize(width: 300, height: 450), unit: .pixels).identifier)
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

    @Test func prefetchReusesOneSharedPrefetcher() throws {
        let url = try #require(URL(string: "https://127.0.0.1:1/never.jpg"))
        let size = CGSize(width: 100, height: 100)
        ImageCache.prefetch([url], pointSize: size)
        let first = try #require(ImageCache.sharedPrefetcher)
        ImageCache.prefetch([url], pointSize: size)
        ImageCache.stopPrefetching([url], pointSize: size)
        #expect(ImageCache.sharedPrefetcher === first)
    }

    @Test func diskLimitIs500MB() {
        #expect(ImageCache.diskLimit == 524_288_000)
    }
}
