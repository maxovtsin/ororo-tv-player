import OroroCore
import OroroDesign
import SwiftUI

/// Left column: title, metadata, genres · flags, description, buttons, footer (subtitle languages · quality range).
struct DetailInfoColumn: View {
    let model: DetailViewModel
    var focus: FocusState<DetailFocus?>.Binding
    let onPlay: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(verbatim: model.title?.name ?? "")
                .font(Typography.heroTitle)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
                .staggeredAppearance(index: 0)
            VStack(alignment: .leading, spacing: Spacing.s) {
                MetadataLine(model.metadata)
                    .motion(Motion.quick, value: model.metadata)
                genresLine
            }
            .staggeredAppearance(index: 1)
            if let desc = model.title?.desc, !desc.isEmpty {
                Text(verbatim: desc)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .staggeredAppearance(index: 2)
            }
            buttons
                .padding(.top, Spacing.s)
            footer
        }
    }

    // MARK: - Pieces

    @ViewBuilder private var genresLine: some View {
        if let title = model.title, !title.genres.isEmpty || !title.countries.isEmpty {
            let flags = title.countries.compactMap(Display.flag).joined(separator: " ")
            let genres = title.genres.map { GenreName.localized($0, locale: locale) }
            let parts = [genres.joined(separator: " · "), flags].filter { !$0.isEmpty }
            let countryNames = title.countries.compactMap { Display.countryName($0, locale: locale) }
            Text(verbatim: parts.joined(separator: " · "))
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .accessibilityLabel(Text(verbatim: (genres + countryNames).joined(separator: ", ")))
        }
    }

    private var buttons: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ActionButton(model.primaryButtonTitle, systemImage: "play.fill", style: .prominent, action: onPlay)
                .focused(focus, equals: .primary)
            if model.id.kind == .movie, let trailerID = model.trailerID, let url = TrailerAvailability.url(for: trailerID) {
                ActionButton(String(localized: "detail.trailer", defaultValue: "Trailer", bundle: .module), systemImage: "play.rectangle") {
                    openURL(url)
                }
                .focused(focus, equals: .trailer)
            }
            myListButton
                .focused(focus, equals: .myList)
            SubtitleLanguagePicker(selection: model.preferredSubtitle, available: model.subtitleLanguages) { lang in
                Task { await model.setPreferredSubtitle(lang) }
            }
            .focused(focus, equals: .subtitles)
        }
    }

    /// "+ My List" with the symbol-replace bounce (choreography: + My List).
    private var myListButton: some View {
        Button {
            Task { await model.toggleList() }
        } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: model.isInList ? "checkmark" : "plus")
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: model.isInList)
                Text(String(localized: "detail.myList", defaultValue: "My List", bundle: .module))
            }
        }
        .glassControl()
        .accessibilityLabel(model.isInList
            ? String(localized: "detail.myList.remove", defaultValue: "Remove from My List", bundle: .module)
            : String(localized: "detail.myList.add", defaultValue: "Add to My List", bundle: .module))
    }

    /// Fades in (`quick`) when the detail response brings languages and qualities.
    private var footer: some View {
        let languages = model.subtitleLanguages ?? []
        let visibleParts = [
            languages.isEmpty ? nil : String(
                localized: "detail.footer.subtitles",
                defaultValue: "Subtitles: \(languages.map { $0.uppercased() }.joined(separator: " "))",
                bundle: .module
            ),
            model.qualityText
        ].compactMap { $0 }
        let spokenLanguages = languages.map { Display.languageName($0, locale: locale) }.joined(separator: ", ")
        let spokenParts = [
            languages.isEmpty ? nil : String(localized: "detail.footer.subtitles.accessibility",
                                             defaultValue: "Subtitles: \(spokenLanguages)", bundle: .module),
            model.qualityText.map { String(localized: "detail.footer.quality.accessibility", defaultValue: "Quality \($0)", bundle: .module) }
        ].compactMap { $0 }
        return Text(verbatim: visibleParts.joined(separator: " · "))
            .font(Typography.caption)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(2)
            .opacity(visibleParts.isEmpty ? 0 : 1)
            .motion(Motion.quick, value: visibleParts)
            .accessibilityLabel(Text(verbatim: spokenParts.joined(separator: ", ")))
            .accessibilityHidden(visibleParts.isEmpty)
            .padding(.top, Spacing.s)
    }
}
