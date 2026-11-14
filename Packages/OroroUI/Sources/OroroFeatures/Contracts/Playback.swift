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
}

public enum PlayerEvent: Sendable, Equatable {
    case time(position: TimeInterval, duration: TimeInterval), paused, resumed, ended, failed
    case stalled(seconds: TimeInterval), subtitleChanged(String?), userInput
}
