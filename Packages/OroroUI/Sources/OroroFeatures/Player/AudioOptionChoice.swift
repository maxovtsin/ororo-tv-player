/// Picks a title's own multichannel audio option (e.g. an HLS "English Surround 5.1" rendition next to the default
/// stereo one) for a surround output. Pure: the engine maps `AVMediaSelectionOption`s to `Candidate`s.
struct AudioOptionChoice {
    /// One audible option: its position in the group, its language, and its channel count (`nil` when unknown).
    struct Candidate: Equatable {
        var index: Int
        var language: String?
        var channels: Int?
    }

    /// The option with the most channels, if more than 2, never in another language than `current`'s (a `nil` language
    /// matches only `nil`); any language when there is no current option. On a tie in channel count `current` stays
    /// when it is among the best, else the first in order wins. `nil` when no allowed option is known to have more
    /// than 2 channels.
    static func best(among options: [Candidate], current: Candidate?) -> Candidate? {
        let pool = options.filter { ($0.channels ?? 0) > 2 && (current == nil || $0.language == current?.language) }
        guard let most = pool.compactMap(\.channels).max() else { return nil }
        if let current, current.channels == most, pool.contains(current) { return current }
        return pool.first { $0.channels == most }
    }
}
