import Foundation

// STUB (T3) — implemented by Task C6. `scheme`/`groupID` are final values.
public enum SubtitlePlaylistBuilder {
    public static let scheme = "ororo-subs", groupID = "subs"

    /// ororo-subs://master.m3u8 ("master playlist" is the HLS spec term.)
    public static func masterURL() -> URL { // swiftlint:disable:this inclusive_language
        URL(filePath: "/")
    }

    /// ororo-subs://subtitles/<lang>.m3u8
    public static func subtitleURL(lang: String) -> URL {
        URL(filePath: "/")
    }

    public static func language(from url: URL) -> String? {
        nil
    }

    // swiftlint:disable:next inclusive_language
    public static func master(original: String, originalURL: URL, subtitles: [Subtitle], defaultLanguage: String?) -> String {
        ""
    }

    public static func subtitlePlaylist(vttURL: URL, duration: TimeInterval) -> String {
        ""
    }
}
