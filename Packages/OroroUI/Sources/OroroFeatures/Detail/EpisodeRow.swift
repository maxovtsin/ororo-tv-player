import OroroCore
import OroroDesign
import SwiftUI

/// One episode: number, name, airdate, HD/SD, plot (two lines; the focused row expands to six and turns white),
/// progress bar or watched checkmark.
struct EpisodeRow: View {
    let episode: Episode
    let isFocused: Bool
    let fraction: Double?
    let isWatched: Bool

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Text(verbatim: episode.number.map(String.init) ?? "–")
                .font(Typography.title.monospacedDigit())
                .opacity(0.8)
                .frame(minWidth: Self.numberWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                header
                if let plot = episode.plot, !plot.isEmpty {
                    Text(verbatim: plot)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(plotLines)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !isWatched, let fraction, fraction > 0 {
                    ProgressBar(fraction: fraction)
                        .padding(.top, Spacing.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.m)
        .foregroundStyle(isFocused ? Color.black : Palette.textPrimary)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isFocused ? Palette.focusHighlight : Color.white.opacity(0.0001))
        )
        .motion(Motion.standard, value: isFocused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(verbatim: DetailViewModel.episodeTitle(episode))
                .font(Typography.headline)
                .lineLimit(1)
            if let airdate = episode.airdate {
                Text(verbatim: "· \(Display.airdate(airdate, locale: locale))")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let resolution = episode.resolution {
                Badge(resolution == .hd ? .hd : .sd)
            }
            Spacer(minLength: 0)
            if isWatched {
                Image(systemName: "checkmark.circle.fill")
                    .font(Typography.headline)
            }
        }
    }

    private var plotLines: Int {
        #if os(tvOS)
        isFocused ? 6 : 2
        #else
        4
        #endif
    }

    private static var numberWidth: CGFloat {
        #if os(tvOS)
        56
        #else
        28
        #endif
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let number = episode.number {
            parts.append(String(localized: "detail.episode.accessibility.number", defaultValue: "Episode \(number)", bundle: .module))
        }
        parts.append(DetailViewModel.episodeTitle(episode))
        if let airdate = episode.airdate { parts.append(Display.airdate(airdate, locale: locale)) }
        if let resolution = episode.resolution { parts.append((resolution == .hd ? BadgeKind.hd : BadgeKind.sd).accessibilityLabel) }
        if isWatched {
            parts.append(String(localized: "detail.episode.accessibility.watched", defaultValue: "Watched", bundle: .module))
        } else if let fraction, fraction > 0 {
            let percent = Int((min(max(fraction, 0), 1) * 100).rounded())
            parts.append(String(localized: "tile.accessibility.watched", defaultValue: "\(percent) percent watched", bundle: .module))
        }
        if let plot = episode.plot, !plot.isEmpty { parts.append(plot) }
        return parts.joined(separator: ", ")
    }
}

/// Thin progress bar that follows the row's foreground colour.
private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.tertiary)
                Capsule().fill(.primary)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(maxWidth: 240)
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// No system lift: the row draws its own white highlight when focused.
struct EpisodeRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .motion(Motion.quick, value: configuration.isPressed)
    }
}

#Preview("Episode rows") {
    let episode = Episode(id: 1, showID: 1, name: "Plan B",
                          plot: "Richie makes his move, putting the Harrigans on high alert. Conrad and Maeve lock horns over Eddie.",
                          season: 1, number: 3, airdate: Date(timeIntervalSince1970: 1_744_502_400), resolution: .hd)
    VStack(spacing: 8) {
        EpisodeRow(episode: episode, isFocused: false, fraction: nil, isWatched: true)
        EpisodeRow(episode: episode, isFocused: true, fraction: 0.4, isWatched: false)
        EpisodeRow(episode: Episode(id: 2, showID: 1, season: 1, number: 4, resolution: .sd), isFocused: false, fraction: 0.6, isWatched: false)
    }
    .padding()
    .background(Color.black)
}
