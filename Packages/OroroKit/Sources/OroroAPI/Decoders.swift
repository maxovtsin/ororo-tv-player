import Foundation
import OroroCore

/// Lenient decoding of ororo.tv API responses into the `OroroCore` models.
/// A wrong top-level shape throws `APIError.decoding`; malformed fields degrade to nil / empty.
public enum Decoders {
    /// Top-level key "shows".
    public static func shows(_ data: Data) throws -> [Title] {
        try wrapping {
            try JSONDecoder().decode(ShowListDTO.self, from: data).items.compactMap { $0.value?.title(kind: .show) }
        }
    }

    /// Top-level key "movies".
    public static func movies(_ data: Data) throws -> [Title] {
        try wrapping {
            try JSONDecoder().decode(MovieListDTO.self, from: data).items.compactMap { $0.value?.title(kind: .movie) }
        }
    }

    public static func show(_ data: Data) throws -> ShowDetail {
        try wrapping {
            let dto = try JSONDecoder().decode(ShowDTO.self, from: data)
            let showID = dto.title.id
            return ShowDetail(
                title: dto.title.title(kind: .show),
                seasonCount: dto.seasons,
                episodes: (dto.episodes ?? []).compactMap { $0.value?.episode(showID: showID) }
            )
        }
    }

    public static func movie(_ data: Data, now: Date) throws -> MovieDetail {
        try wrapping {
            let dto = try JSONDecoder().decode(MovieDTO.self, from: data)
            let subtitles = (dto.subtitles ?? []).subtitles
            return MovieDetail(
                title: dto.title.title(kind: .movie),
                trailerYouTubeID: dto.trailer.flatMap { $0.isEmpty ? nil : $0 },
                qualities: WireParsing.qualities(dto.versions),
                subtitleLanguages: WireParsing.unique(subtitles.map(\.lang)),
                playback: playback(url: dto.url, subtitles: subtitles, now: now)
            )
        }
    }

    /// The endpoint does not return the show id: `showID == nil` gives `episode.showID == 0`.
    public static func episode(_ data: Data, showID: Int?, now: Date) throws -> EpisodeDetail {
        try wrapping {
            let dto = try JSONDecoder().decode(EpisodeDTO.self, from: data)
            let subtitles = (dto.subtitles ?? []).subtitles
            return EpisodeDetail(
                episode: dto.episode(showID: showID ?? 0),
                showName: dto.showName,
                subtitleLanguages: WireParsing.unique(subtitles.map(\.lang)),
                playback: playback(url: dto.url, subtitles: subtitles, now: now)
            )
        }
    }

    private static func playback(url: String?, subtitles: [Subtitle], now: Date) -> Playback? {
        WireParsing.url(url).map { Playback(streamURL: $0, subtitles: subtitles, fetchedAt: now) }
    }

    private static func wrapping<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch {
            throw APIError.decoding
        }
    }
}
