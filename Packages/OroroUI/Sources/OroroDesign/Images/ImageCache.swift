import Nuke
import Synchronization
import SwiftUI

/// Wrapper around the shared Nuke pipeline: a 500 MB disk cache named "ororo.images"
/// and decompression on Nuke's background queue (never the main thread).
public enum ImageCache {
    public static let diskLimit = 500 * 1024 * 1024

    private static let cacheName = "ororo.images"
    private static let state = Mutex<DataCache?>(nil)
    private static let configured = Mutex(false)
    private static let retained = Mutex<[ImagePrefetcher]>([])

    /// The shared disk cache; `nil` until `configure()` has run (or if the disk is unavailable).
    static var dataCache: DataCache? {
        state.withLock { $0 }
    }

    /// Builds the shared Nuke pipeline: disk cache "ororo.images", decompression off-main.
    /// Safe to call more than once; only the first call builds the pipeline.
    public static func configure() {
        let shouldBuild = configured.withLock { done -> Bool in
            defer { done = true }
            return !done
        }
        guard shouldBuild else { return }

        var configuration = ImagePipeline.Configuration.withDataCache(name: cacheName, sizeLimit: diskLimit)
        configuration.isDecompressionEnabled = true
        configuration.dataCachePolicy = .automatic
        state.withLock { $0 = configuration.dataCache as? DataCache }
        ImagePipeline.shared = ImagePipeline(configuration: configuration)
    }

    /// Resize processor to pixel size.
    public static func request(_ url: URL, pointSize: CGSize, scale: CGFloat) -> ImageRequest {
        let pixels = CGSize(width: pointSize.width * scale, height: pointSize.height * scale)
        return ImageRequest(url: url, processors: [ImageProcessors.Resize(size: pixels, unit: .pixels)])
    }

    /// Warms the disk cache for `urls`. Uses Nuke's point-to-pixel conversion, which matches
    /// the `displayScale` that `RemoteImage` passes to `request(_:pointSize:scale:)`.
    public static func prefetch(_ urls: [URL], pointSize: CGSize) {
        guard !urls.isEmpty else { return }
        configure()
        let prefetcher = ImagePrefetcher(destination: .diskCache)
        prefetcher.startPrefetching(with: urls.map { prefetchRequest($0, pointSize: pointSize) })
        retained.withLock { $0.append(prefetcher) }
    }

    /// Returns when cached or failed.
    public static func preload(_ url: URL, pointSize: CGSize) async {
        configure()
        _ = try? await ImagePipeline.shared.image(for: prefetchRequest(url, pointSize: pointSize))
    }

    public static func clear() async {
        configure()
        ImagePipeline.shared.cache.removeAll()
        guard let cache = dataCache else { return }
        await Task.detached {
            cache.removeAll()
            cache.flush()
        }.value
    }

    public static func diskUsage() async -> Int {
        guard let cache = dataCache else { return 0 }
        return await Task.detached {
            cache.flush()
            return cache.totalSize
        }.value
    }

    private static func prefetchRequest(_ url: URL, pointSize: CGSize) -> ImageRequest {
        ImageRequest(url: url, processors: [ImageProcessors.Resize(size: pointSize, unit: .points)])
    }
}
