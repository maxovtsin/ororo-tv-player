import Foundation
import OroroCore

/// The player behind `PlaybackSession` (AVPlayer in F10, a fake in tests).
@MainActor public protocol PlayerEngine: AnyObject {
    var events: AsyncStream<PlayerEvent> { get }
    func load(_ playback: Playback, startAt: TimeInterval, subtitleLanguage: String?) async throws
    func play()
    func pause()
    func seek(to: TimeInterval) async
    var position: TimeInterval { get }
    var duration: TimeInterval { get }
    /// Shown above the progress line; applied to every item a later `load` creates.
    var nowPlaying: NowPlaying? { get set }
    /// Plays original audio from the next load on (for this engine's life).
    func disableSurround()
    /// The app returned to the foreground: re-checks anything that may not have survived sleep.
    func sceneBecameActive() async
}

public extension PlayerEngine {
    func disableSurround() {}
    func sceneBecameActive() async {}
}

/// What the player shows above its progress line: a movie's name, or a show's name over "S2 E5 · Episode name".
public struct NowPlaying: Equatable, Sendable {
    public let title: String
    public let subtitle: String?

    public init(title: String, subtitle: String?) {
        self.title = title
        self.subtitle = subtitle
    }

    /// An episode wins over a movie name; without a show name the episode line becomes the title.
    static func make(movieName: String?, showName: String?, episode: Episode?) -> NowPlaying? {
        guard let episode else { return movieName.map { NowPlaying(title: $0, subtitle: nil) } }
        let label = episode.number.map { Display.episodeLabel(season: episode.season, number: $0) } ?? "S\(episode.season)"
        let name = episode.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let line = name.isEmpty ? label : "\(label) · \(name)"
        guard let showName else { return NowPlaying(title: line, subtitle: nil) }
        return NowPlaying(title: showName, subtitle: line)
    }
}

public enum PlayerEvent: Sendable, Equatable {
    case time(position: TimeInterval, duration: TimeInterval), paused, resumed, ended, failed
    case stalled(seconds: TimeInterval), subtitleChanged(String?), userInput
    /// Simulated surround gave up; the session reloads the title with original audio.
    case surroundFailed
}
