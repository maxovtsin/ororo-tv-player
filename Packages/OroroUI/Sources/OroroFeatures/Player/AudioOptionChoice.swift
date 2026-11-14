/// Picks a title's own multichannel audio option (e.g. an HLS "English Surround 5.1" rendition next to the default
/// stereo one) for a surround output. Pure: the engine maps `AVMediaSelectionOption`s to `Candidate`s.
struct AudioOptionChoice {
    /// One audible option: its position in the group, its language, and its channel count (`nil` when unknown).
    struct Candidate: Equatable {
        var index: Int
        var language: String?
        var channels: Int?
    }

    /// The option with the most channels, if more than 2: from `current`'s language when that language has one, else
    /// from any language. Ties keep the first in order. `nil` when no option is known to have more than 2 channels.
    static func best(among options: [Candidate], current: Candidate?) -> Candidate? {
        let multichannel = options.filter { ($0.channels ?? 0) > 2 }
        let sameLanguage = multichannel.filter { $0.language == current?.language }
        let pool = current != nil && !sameLanguage.isEmpty ? sameLanguage : multichannel
        // `max(by:)` returns the last of equal maxima; reduce keeps the first.
        return pool.reduce(nil) { best, option in
            guard let best else { return option }
            return (option.channels ?? 0) > (best.channels ?? 0) ? option : best
        }
    }
}
