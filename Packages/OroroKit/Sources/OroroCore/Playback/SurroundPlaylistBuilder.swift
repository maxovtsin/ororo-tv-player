import Foundation

/// Authors the HLS text that serves simulated 5.1 surround from the app's loopback server.
///
/// The multivariant playlist keeps its video variants and re-points every audio group at local, six-channel renditions.
/// Each rendition's media playlist is rewritten to local URLs; the original (signed) URLs are returned, never written to text.
public enum SurroundPlaylistBuilder {
    public struct Multivariant: Equatable, Sendable {
        public var text: String
        /// `sources[r]` is the original media playlist URL chosen for rendition `r`.
        public var sources: [URL]
    }

    public struct MediaPlaylist: Equatable, Sendable {
        public var text: String
        public var initURL: URL
        public var segments: [URL]
    }

    public enum Resource: Equatable, Sendable {
        case playlist(rendition: Int)
        case initSegment(rendition: Int)
        case segment(rendition: Int, index: Int)
    }

    private static let mediaTag = "#EXT-X-MEDIA:", streamInfTag = "#EXT-X-STREAM-INF:", mapTag = "#EXT-X-MAP:"

    // MARK: - Multivariant

    /// - Parameter absolutised: the output of `SubtitlePlaylistBuilder.master`, with every URI absolute.
    /// - Returns: `nil` when the audio is not made of separate stereo or mono renditions.
    public static func multivariant(absolutised: String, localBase: URL) -> Multivariant? {
        let lines = absolutised.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let audio = lines.compactMap(audioEntry)
        guard !audio.isEmpty, audio.allSatisfy({ ["1", "2", nil].contains($0.attributes["CHANNELS"]) }) else { return nil }
        let candidates = audio.filter { $0.attributes["URI"] != nil }
        guard !candidates.isEmpty else { return nil }

        let bestGroup = lines.compactMap(variant).max { $0.bandwidth < $1.bandwidth }?.audioGroup
        var keys: [String] = [], sources: [URL] = []
        for entry in candidates where !keys.contains(entry.key) {
            let preferred = candidates.first { $0.key == entry.key && $0.attributes["GROUP-ID"] == bestGroup } ?? entry
            guard let uri = preferred.attributes["URI"], let url = URL(string: uri) else { return nil }
            keys.append(entry.key)
            sources.append(url)
        }

        let out = lines.map { line -> String in
            if let entry = audioEntry(line), entry.attributes["URI"] != nil, let index = keys.firstIndex(of: entry.key) {
                return rewriteAudio(entry, uri: localBase.absoluteString + "audio/\(index).m3u8")
            }
            return line.hasPrefix(streamInfTag) ? addingBandwidth(to: line) : line
        }
        return Multivariant(text: out.joined(separator: "\n"), sources: sources)
    }

    // MARK: - Media playlist

    /// - Parameter originalURL: the playlist's URL after redirects, which relative URIs resolve against.
    /// - Returns: `nil` unless it is a complete, unencrypted fMP4 playlist with one whole-file init segment.
    public static func mediaPlaylist(original: String, originalURL: URL, localBase: URL, rendition: Int) -> MediaPlaylist? {
        let prefix = localBase.absoluteString + "audio/\(rendition)/"
        var out: [String] = [], segments: [URL] = [], initURL: URL?, ended = false
        for line in original.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if line.hasPrefix(mapTag) {
                let attributes = parseAttributes(String(line.dropFirst(mapTag.count)))
                guard initURL == nil, attributes["BYTERANGE"] == nil, let uri = attributes["URI"],
                      let url = URL(string: uri, relativeTo: originalURL)?.absoluteURL else { return nil }
                initURL = url
                out.append("\(mapTag)URI=\"\(prefix)init.mp4\"")
            } else if line.hasPrefix("#") {
                if line.hasPrefix("#EXT-X-KEY:"), parseAttributes(String(line.dropFirst(11)))["METHOD"] != "NONE" { return nil }
                if line.hasPrefix("#EXT-X-BYTERANGE") || line == "#EXT-X-DISCONTINUITY" { return nil }
                ended = ended || line == "#EXT-X-ENDLIST"
                out.append(line)
            } else if line.isEmpty {
                out.append(line)
            } else {
                guard let url = URL(string: line, relativeTo: originalURL)?.absoluteURL else { return nil }
                out.append("\(prefix)\(segments.count).m4s")
                segments.append(url)
            }
        }
        guard let initURL, ended, !segments.isEmpty else { return nil }
        return MediaPlaylist(text: out.joined(separator: "\n"), initURL: initURL, segments: segments)
    }

    // MARK: - Local paths

    /// Maps a path relative to `localBase` back to what it names.
    public static func resource(forPath path: String) -> Resource? {
        let parts = path.components(separatedBy: "/")
        guard parts.first == "audio" else { return nil }
        if parts.count == 2, parts[1].hasSuffix(".m3u8"), let rendition = number(String(parts[1].dropLast(5))) {
            return .playlist(rendition: rendition)
        }
        guard parts.count == 3, let rendition = number(parts[1]) else { return nil }
        if parts[2] == "init.mp4" { return .initSegment(rendition: rendition) }
        if parts[2].hasSuffix(".m4s"), let index = number(String(parts[2].dropLast(4))) {
            return .segment(rendition: rendition, index: index)
        }
        return nil
    }

    private static func number(_ text: String) -> Int? {
        text.isEmpty || !text.allSatisfy(\.isASCII) || !text.allSatisfy(\.isNumber) ? nil : Int(text)
    }

    // MARK: - Helpers

    private struct AudioEntry {
        var attributes: [String: String]
        var ordered: [(key: String, value: String)]
        /// One rendition per distinct language and name.
        var key: String { (attributes["LANGUAGE"] ?? "") + "\n" + (attributes["NAME"] ?? "") }
    }

    private static func audioEntry(_ line: String) -> AudioEntry? {
        guard line.hasPrefix(mediaTag) else { return nil }
        let ordered = splitAttributes(String(line.dropFirst(mediaTag.count)))
        let entry = AudioEntry(attributes: dictionary(ordered), ordered: ordered)
        return entry.attributes["TYPE"] == "AUDIO" ? entry : nil
    }

    private static func variant(_ line: String) -> (bandwidth: Int, audioGroup: String?)? {
        guard line.hasPrefix(streamInfTag) else { return nil }
        let attributes = parseAttributes(String(line.dropFirst(streamInfTag.count)))
        return (Int(attributes["BANDWIDTH"] ?? "") ?? 0, attributes["AUDIO"])
    }

    private static func rewriteAudio(_ entry: AudioEntry, uri: String) -> String {
        let kept = entry.ordered.filter { $0.key != "CHANNELS" && $0.key != "URI" }.map { "\($0.key)=\($0.value)" }
        return mediaTag + (kept + ["CHANNELS=\"\(SurroundFormat.channelCount)\"", "URI=\"\(uri)\""]).joined(separator: ",")
    }

    private static func addingBandwidth(to line: String) -> String {
        let rebuilt = splitAttributes(String(line.dropFirst(streamInfTag.count))).map { attribute -> String in
            guard attribute.key == "BANDWIDTH" || attribute.key == "AVERAGE-BANDWIDTH", let value = Int(attribute.value) else {
                return "\(attribute.key)=\(attribute.value)"
            }
            return "\(attribute.key)=\(value + SurroundFormat.addedBitsPerSecond)"
        }
        return streamInfTag + rebuilt.joined(separator: ",")
    }

    private static func parseAttributes(_ list: String) -> [String: String] { dictionary(splitAttributes(list)) }

    private static func dictionary(_ ordered: [(key: String, value: String)]) -> [String: String] {
        Dictionary(ordered.map { ($0.key, unquoted($0.value)) }, uniquingKeysWith: { first, _ in first })
    }

    private static func unquoted(_ value: String) -> String {
        value.count >= 2 && value.hasPrefix("\"") && value.hasSuffix("\"") ? String(value.dropFirst().dropLast()) : value
    }

    /// Splits `KEY=value,KEY="quoted, value"` at the commas outside quotes, keeping values as written.
    private static func splitAttributes(_ list: String) -> [(key: String, value: String)] {
        var pieces: [String] = [], current = "", quoted = false
        for character in list {
            if character == "\"" { quoted.toggle() }
            if character == ",", !quoted {
                pieces.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        pieces.append(current)
        return pieces.compactMap { piece in
            guard let equals = piece.firstIndex(of: "=") else { return nil }
            return (String(piece[..<equals]), String(piece[piece.index(after: equals)...]))
        }
    }
}
