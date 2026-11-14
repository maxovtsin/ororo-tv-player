import AVFoundation
import Foundation
import OroroCore
import UniformTypeIdentifiers

/// The pure core of `SubtitleResourceLoader`: answers the custom-scheme URLs of an injected-subtitle asset.
/// Never logs or stores the stream URL.
struct SubtitleResourceResponder: Sendable {
    enum Failure: Error, Equatable { case unknownURL, unreadablePlaylist }

    static let contentType = "application/x-mpegURL"
    /// Used for the subtitle playlist when the media duration is unknown (3 h covers any episode or movie).
    static let fallbackDuration: TimeInterval = 10_800

    private let playback: Playback
    private let preferredLanguage: String?
    private let fetch: @Sendable (URL) async throws -> Data

    init(playback: Playback, preferredLanguage: String?, fetch: @escaping @Sendable (URL) async throws -> Data) {
        self.playback = playback
        self.preferredLanguage = preferredLanguage
        self.fetch = fetch
    }

    func response(for url: URL, duration: TimeInterval) async throws -> (data: Data, contentType: String) {
        if url == SubtitlePlaylistBuilder.masterURL() {
            let data = try await fetch(playback.streamURL)
            guard let original = String(bytes: data, encoding: .utf8) else { throw Failure.unreadablePlaylist }
            let multivariant = SubtitlePlaylistBuilder.master(
                original: original, originalURL: playback.streamURL,
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
    let queue = DispatchQueue(label: "ororo.subtitle-loader")
    private let responder: SubtitleResourceResponder
    private let duration: MediaDuration

    init(playback: Playback, preferredLanguage: String?,
         fetch: @escaping @Sendable (URL) async throws -> Data = SubtitleResourceLoader.download) {
        let responder = SubtitleResourceResponder(playback: playback, preferredLanguage: preferredLanguage, fetch: fetch)
        self.responder = responder
        self.duration = MediaDuration(responder: responder, fetch: fetch)
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url, url.scheme == SubtitlePlaylistBuilder.scheme else { return false }
        let request = LoadingRequest(value: loadingRequest)
        let responder = responder, duration = duration
        Task {
            do {
                let isMultivariant = url == SubtitlePlaylistBuilder.masterURL()
                let seconds = isMultivariant ? 0 : await duration.value()
                let result = try await responder.response(for: url, duration: seconds)
                if isMultivariant { await duration.remember(multivariant: result.data) }
                request.finish(data: result.data, contentType: result.contentType)
            } catch {
                request.finish(error: error)
            }
        }
        return true
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

    /// Plain HTTPS GET; non-2xx is an error. Never logs the URL.
    @Sendable static func download(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

/// Resolves the title's duration once, from the first variant's media playlist.
private actor MediaDuration {
    private let responder: SubtitleResourceResponder
    private let fetch: @Sendable (URL) async throws -> Data
    private var multivariant: Data?
    private var resolved: Task<TimeInterval, Never>?

    init(responder: SubtitleResourceResponder, fetch: @escaping @Sendable (URL) async throws -> Data) {
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
                  let media = try? await fetch(variant),
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
        if let info = value.contentInformationRequest {
            info.contentType = UTType(mimeType: contentType)?.identifier ?? contentType
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
        value.finishLoading(with: error)
    }
}
