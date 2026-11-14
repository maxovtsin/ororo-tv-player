import Foundation

/// Builds the HLS text that injects external WebVTT subtitles into an ororo.tv stream.
public enum SubtitlePlaylistBuilder {
    public static let scheme = "ororo-subs", groupID = "subs"

    private static let streamInf = "#EXT-X-STREAM-INF"
    private static let subtitlesAttribute = "SUBTITLES=\"\(groupID)\""

    /// ororo-subs://master.m3u8 ("master playlist" is the HLS spec term.)
    public static func masterURL() -> URL { // swiftlint:disable:this inclusive_language
        URL(string: "\(scheme)://master.m3u8")!
    }

    /// ororo-subs://subtitles/<lang>.m3u8
    public static func subtitleURL(lang: String) -> URL {
        URL(string: "\(scheme)://subtitles/\(lang).m3u8")
            ?? URL(string: "\(scheme)://subtitles/und.m3u8")!
    }

    public static func language(from url: URL) -> String? {
        guard url.scheme == scheme, url.host() == "subtitles", url.pathExtension == "m3u8" else { return nil }
        let lang = url.deletingPathExtension().lastPathComponent
        return lang.isEmpty || lang == "/" ? nil : lang
    }

    // swiftlint:disable:next inclusive_language
    public static func master(original: String, originalURL: URL, subtitles: [Subtitle], defaultLanguage: String?) -> String {
        let originalLines = original
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        let isVariantPlaylist = originalLines.contains { $0.hasPrefix(streamInf) }
        let entries = mediaEntries(for: subtitles, defaultLanguage: defaultLanguage)

        if !isVariantPlaylist && !entries.isEmpty {
            var out = ["#EXTM3U"]
            out += entries
            out.append("\(streamInf):BANDWIDTH=2000000,\(subtitlesAttribute)")
            out.append(originalURL.absoluteString)
            return out.joined(separator: "\n") + "\n"
        }

        var out: [String] = []
        var inserted = false
        for line in originalLines {
            out.append(rewrite(line: line, base: originalURL, addSubtitles: !entries.isEmpty))
            if !inserted, line.hasPrefix("#EXTM3U") {
                out += entries
                inserted = true
            }
        }
        if !inserted, !entries.isEmpty {
            out.insert(contentsOf: entries, at: 0)
        }
        return out.joined(separator: "\n")
    }

    /// Used when the video's duration is unknown (non-finite or not positive): longer than any title.
    public static let fallbackDuration: TimeInterval = 6 * 3600
    /// Upper bound, so the target duration always fits an `Int`.
    public static let maximumDuration: TimeInterval = 7 * 24 * 3600

    public static func subtitlePlaylist(vttURL: URL, duration rawDuration: TimeInterval) -> String {
        let duration = rawDuration.isFinite && rawDuration > 0 ? min(rawDuration, maximumDuration) : fallbackDuration
        let target = Int(duration.rounded(.up))
        return """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:\(target)
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXTINF:\(duration),
        \(vttURL.absoluteString)
        #EXT-X-ENDLIST

        """
    }

    // MARK: - Helpers

    private static func mediaEntries(for subtitles: [Subtitle], defaultLanguage: String?) -> [String] {
        var seen = Set<String>()
        let english = Locale(identifier: "en")
        return subtitles.compactMap { subtitle in
            guard seen.insert(subtitle.lang).inserted else { return nil }
            let name = english.localizedString(forLanguageCode: subtitle.lang) ?? subtitle.lang.uppercased()
            let isDefault = subtitle.lang == defaultLanguage ? "YES" : "NO"
            return "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"\(groupID)\",NAME=\"\(name)\","
                + "LANGUAGE=\"\(subtitle.lang)\",AUTOSELECT=YES,DEFAULT=\(isDefault),"
                + "URI=\"\(subtitleURL(lang: subtitle.lang).absoluteString)\""
        }
    }

    private static func rewrite(line: String, base: URL, addSubtitles: Bool) -> String {
        if line.isEmpty { return line }
        guard line.hasPrefix("#") else {
            return absolute(line, base: base)
        }
        var result = line
        if let range = result.range(of: "URI=\"[^\"]*\"", options: .regularExpression) {
            let value = String(result[range].dropFirst(5).dropLast())
            result.replaceSubrange(range, with: "URI=\"\(absolute(value, base: base))\"")
        }
        if addSubtitles, result.hasPrefix(streamInf), !result.contains("SUBTITLES=") {
            result += ",\(subtitlesAttribute)"
        }
        return result
    }

    private static func absolute(_ uri: String, base: URL) -> String {
        guard !uri.isEmpty, let resolved = URL(string: uri, relativeTo: base) else { return uri }
        return resolved.absoluteString
    }
}
