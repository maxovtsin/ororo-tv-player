import Foundation
import Nuke

// STUB (T3) — implemented by Task D2.
public enum ImageCache {
    public static let diskLimit = 500 * 1024 * 1024

    /// Builds the shared Nuke pipeline: disk cache "ororo.images", decompression off-main.
    public static func configure() {}

    /// Resize processor to pixel size.
    public static func request(_ url: URL, pointSize: CGSize, scale: CGFloat) -> ImageRequest {
        ImageRequest(url: url)
    }

    public static func prefetch(_ urls: [URL], pointSize: CGSize) {}

    /// Returns when cached or failed.
    public static func preload(_ url: URL, pointSize: CGSize) async {}

    public static func clear() async {}

    public static func diskUsage() async -> Int {
        0
    }
}
