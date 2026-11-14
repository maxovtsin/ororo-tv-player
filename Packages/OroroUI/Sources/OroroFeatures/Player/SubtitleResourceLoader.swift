import AVFoundation
import Foundation
import OroroCore
import Synchronization
import UniformTypeIdentifiers

/// The pure core of `SubtitleResourceLoader`: answers the custom-scheme URLs of an injected-subtitle asset.
/// Never logs or stores the stream URL.
struct SubtitleResourceResponder: Sendable {
    enum Failure: Error, Equatable { case unknownURL, unreadablePlaylist }

    /// A fetch that also reports the final URL after redirects (relative URIs resolve against it).
    typealias ResolvingFetch = @Sendable (URL) async throws -> (data: Data, url: URL)

    static let contentType = "application/x-mpegURL"
    /// Used for the subtitle playlist when the media duration is unknown (3 h covers any episode or movie).
    static let fallbackDuration: TimeInterval = 10_800

    private let playback: Playback
    private let preferredLanguage: String?
    private let fetch: ResolvingFetch

    init(playback: Playback, preferredLanguage: String?, fetch: @escaping @Sendable (URL) async throws -> Data) {
        self.init(playback: playback, preferredLanguage: preferredLanguage, resolvingFetch: { url in
            (try await fetch(url), url)
        })
    }

    init(playback: Playback, preferredLanguage: String?, resolvingFetch: @escaping ResolvingFetch) {
        self.playback = playback
        self.preferredLanguage = preferredLanguage
        self.fetch = resolvingFetch
    }

    func response(for url: URL, duration: TimeInterval) async throws -> (data: Data, contentType: String) {
        if url == SubtitlePlaylistBuilder.masterURL() {
            let fetched = try await fetch(playback.streamURL)
            guard let original = String(bytes: fetched.data, encoding: .utf8) else { throw Failure.unreadablePlaylist }
            let multivariant = SubtitlePlaylistBuilder.master(
                original: original, originalURL: fetched.url,
                subtitles: playback.subtitles, defaultLanguage: preferredLanguage
            )
            return (Data(multivariant.utf8), Self.contentType)
        }
        guard let lang = SubtitlePlaylistBuilder.language(from: url),
              let subtitle = playback.subtitles.first(where: { $0.lang == lang }) else {
            throw Failure.unknownURL
        }
        let usable = duration.isFinite && duration > 0 ? duration : Self.fallbackDuration
        let playlist = SubtitlePlaylistBuilder.subtitlePlaylist(vttURL: subtitle.url, duration: usable)
        return (Data(playlist.utf8), Self.contentType)
    }
}

/// Serves the synthetic multivariant ("master") and subtitle playlists to AVFoundation for the `ororo-subs` scheme.
/// AVFoundation holds its delegate weakly: the owner (`HLSInjectedSubtitles`) keeps it alive.
final class SubtitleResourceLoader: NSObject, AVAssetResourceLoaderDelegate, Sendable {
    /// A fetch failure that carries no URL (no `NSErrorFailingURLKey`), so the signed stream URL never reaches
    /// AVFoundation's error log or the player item's error.
    enum FetchError: Error, Equatable { case http(status: Int), transport(code: Int), cancelled }

    let queue = DispatchQueue(label: "ororo.subtitle-loader")
    private let responder: SubtitleResourceResponder
    private let duration: MediaDuration
    private let inFlight = Mutex<[ObjectIdentifier: Task<Void, Never>]>([:])

    init(playback: Playback, preferredLanguage: String?,
         fetch: @escaping SubtitleResourceResponder.ResolvingFetch = SubtitleResourceLoader.download) {
        let responder = SubtitleResourceResponder(playback: playback, preferredLanguage: preferredLanguage, resolvingFetch: fetch)
        self.responder = responder
        self.duration = MediaDuration(responder: responder, fetch: fetch)
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url, url.scheme == SubtitlePlaylistBuilder.scheme else { return false }
        let request = LoadingRequest(value: loadingRequest)
        let key = ObjectIdentifier(loadingRequest)
        let responder = responder, duration = duration
        let task = Task { [weak self] in
            defer { _ = self?.inFlight.withLock { $0.removeValue(forKey: key) } }
            do {
                let isMultivariant = url == SubtitlePlaylistBuilder.masterURL()
                let seconds = isMultivariant ? 0 : await duration.value()
                let result = try await responder.response(for: url, duration: seconds)
                if isMultivariant { await duration.remember(multivariant: result.data) }
                guard !Task.isCancelled else { return }
                request.finish(data: result.data, contentType: result.contentType)
            } catch {
                guard !Task.isCancelled else { return }
                request.finish(error: Self.urlFree(error))
            }
        }
        inFlight.withLock { $0[key] = task }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        let task = inFlight.withLock { $0.removeValue(forKey: ObjectIdentifier(loadingRequest)) }
        task?.cancel()
    }

    // MARK: - Content type

    /// `contentInformationRequest.contentType` takes a UTI; a MIME-derived `UTType` would be a dynamic `dyn.…` type.
    static func uniformTypeIdentifier(forMIMEType mime: String) -> String {
        switch mime.lowercased() {
        case "application/x-mpegurl", "application/vnd.apple.mpegurl", "audio/mpegurl", "audio/x-mpegurl":
            UTType.m3uPlaylist.identifier
        default:
            UTType(mimeType: mime)?.identifier ?? UTType.data.identifier
        }
    }

    // MARK: - Media duration (the subtitle playlist must span the whole title)

    /// The first variant URI of a multivariant playlist (absolute after `SubtitlePlaylistBuilder.master`).
    static func firstVariantURL(inMultivariant playlist: String) -> URL? {
        let lines = playlist.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { $0.hasPrefix("#EXT-X-STREAM-INF") }) else { return nil }
        return lines[(index + 1)...]
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
            .flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Sum of `#EXTINF` durations of a media playlist.
    static func mediaDuration(ofMediaPlaylist playlist: String) -> TimeInterval {
        playlist.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").reduce(0) { total, line in
            guard line.hasPrefix("#EXTINF:") else { return total }
            let value = line.dropFirst("#EXTINF:".count).prefix { $0 != "," }
            return total + (TimeInterval(value.trimmingCharacters(in: .whitespaces)) ?? 0)
        }
    }

    // MARK: - Fetching (no caching, no URLs in errors)

    /// Ephemeral and cache-free: a playback URL is never persisted, not even in `URLCache`.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// HTTPS GET; non-2xx is an error. Returns the final URL after redirects. Never logs the URL.
    @Sendable static func download(_ url: URL) async throws -> (data: Data, url: URL) {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw FetchError.http(status: http.statusCode)
            }
            return (data, response.url ?? url)
        } catch {
            throw urlFree(error)
        }
    }

    /// Keeps the loader's own errors; replaces anything else (URLError carries the failing URL) with `FetchError`.
    static func urlFree(_ error: any Error) -> any Error {
        switch error {
        case let error as FetchError: error
        case let error as SubtitleResourceResponder.Failure: error
        case is CancellationError: FetchError.cancelled
        case let error as URLError: error.code == .cancelled ? FetchError.cancelled : FetchError.transport(code: error.code.rawValue)
        default: FetchError.transport(code: URLError.Code.unknown.rawValue)
        }
    }
}

/// Resolves the title's duration once, from the first variant's media playlist.
private actor MediaDuration {
    private let responder: SubtitleResourceResponder
    private let fetch: SubtitleResourceResponder.ResolvingFetch
    private var multivariant: Data?
    private var resolved: Task<TimeInterval, Never>?

    init(responder: SubtitleResourceResponder, fetch: @escaping SubtitleResourceResponder.ResolvingFetch) {
        self.responder = responder
        self.fetch = fetch
    }

    func remember(multivariant data: Data) {
        multivariant = data
    }

    func value() async -> TimeInterval {
        if let resolved { return await resolved.value }
        let cached = multivariant, responder = responder, fetch = fetch
        let task = Task<TimeInterval, Never> {
            let playlistData: Data? = if let cached {
                cached
            } else {
                try? await responder.response(for: SubtitlePlaylistBuilder.masterURL(), duration: 0).data
            }
            guard let playlistData, let text = String(bytes: playlistData, encoding: .utf8),
                  let variant = SubtitleResourceLoader.firstVariantURL(inMultivariant: text),
                  let media = try? await fetch(variant).data,
                  let mediaText = String(bytes: media, encoding: .utf8) else { return 0 }
            return SubtitleResourceLoader.mediaDuration(ofMediaPlaylist: mediaText)
        }
        resolved = task
        return await task.value
    }
}

/// AVAssetResourceLoadingRequest is not Sendable; it is only touched to finish it, once.
private struct LoadingRequest: @unchecked Sendable {
    let value: AVAssetResourceLoadingRequest

    func finish(data: Data, contentType: String) {
        guard !value.isCancelled else { return }
        if let info = value.contentInformationRequest {
            info.contentType = SubtitleResourceLoader.uniformTypeIdentifier(forMIMEType: contentType)
            info.contentLength = Int64(data.count)
            info.isByteRangeAccessSupported = false
        }
        if let request = value.dataRequest {
            let start = Int(clamping: max(request.requestedOffset, 0))
            let end = request.requestsAllDataToEndOfResource ? data.count : min(data.count, start + request.requestedLength)
            if start < end { request.respond(with: data.subdata(in: start..<end)) }
        }
        value.finishLoading()
    }

    func finish(error: any Error) {
        guard !value.isCancelled else { return }
        value.finishLoading(with: error)
    }
}
