import OroroCore
import OroroDesign
import SwiftUI

/// Decade / IMDb / Status / Sort menus plus the genre chip row (spec: Shows / Movies tabs).
struct FilterBar: View {
    let model: BrowseGridViewModel

    /// Min IMDb options: Any, 6+, 7+, 8+.
    static let ratingOptions: [Double?] = [nil, 6, 7, 8]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                decadeMenu
                ratingMenu
                if model.showsStatusFilter {
                    statusMenu
                }
                Spacer(minLength: Spacing.m)
                sortMenu
            }
            genreChips
        }
        .padding(.horizontal, Spacing.screenEdge)
    }

    // MARK: - Menus

    private var decadeMenu: some View {
        filterMenu(
            String(localized: "browse.filter.decade", defaultValue: "Decade", bundle: .module),
            value: model.query.decade.map(Self.decadeLabel) ?? Self.any
        ) {
            Picker(selection: Binding(get: { model.query.decade }, set: { model.setDecade($0) })) {
                Text(verbatim: Self.any).tag(Int?.none)
                ForEach(model.decades, id: \.self) { decade in
                    Text(verbatim: Self.decadeLabel(decade)).tag(Int?.some(decade))
                }
            } label: { EmptyView() }
        }
    }

    private var ratingMenu: some View {
        filterMenu(
            String(localized: "browse.filter.imdb", defaultValue: "IMDb", bundle: .module),
            value: Self.ratingLabel(model.query.minRating)
        ) {
            Picker(selection: Binding(get: { model.query.minRating }, set: { model.setMinRating($0) })) {
                ForEach(Self.ratingOptions, id: \.self) { rating in
                    Text(verbatim: Self.ratingLabel(rating)).tag(rating)
                }
            } label: { EmptyView() }
        }
    }

    private var statusMenu: some View {
        filterMenu(
            String(localized: "browse.filter.status", defaultValue: "Status", bundle: .module),
            value: Self.statusLabel(model.query.status)
        ) {
            Picker(selection: Binding(get: { model.query.status }, set: { model.setStatus($0) })) {
                ForEach([nil, BrowseQuery.Status.ongoing, .ended], id: \.self) { status in
                    Text(verbatim: Self.statusLabel(status)).tag(status)
                }
            } label: { EmptyView() }
        }
    }

    private var sortMenu: some View {
        filterMenu(
            String(localized: "browse.filter.sort", defaultValue: "Sort", bundle: .module),
            value: Self.sortLabel(model.query.sort)
        ) {
            Picker(selection: Binding(get: { model.query.sort }, set: { model.setSort($0) })) {
                ForEach(model.availableSorts, id: \.self) { sort in
                    Text(verbatim: Self.sortLabel(sort)).tag(sort)
                }
            } label: { EmptyView() }
        }
    }

    private func filterMenu(_ name: String, value: String, @ViewBuilder content: () -> some View) -> some View {
        Menu {
            content()
        } label: {
            Text(verbatim: "\(name): \(value)")
                .font(Typography.body)
                .lineLimit(1)
                .padding(.horizontal, Spacing.s)
        }
        .glassControl()
        .buttonBorderShape(.capsule)
        .accessibilityLabel(name)
        .accessibilityValue(value)
    }

    // MARK: - Genre chips

    private var genreChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.s) {
                Chip(String(localized: "browse.filter.allGenres", defaultValue: "All", bundle: .module),
                     isSelected: model.query.genre == nil) {
                    model.setGenre(nil)
                }
                ForEach(model.genres, id: \.self) { genre in
                    Chip(GenreName.localized(genre), isSelected: model.query.genre == genre) {
                        model.setGenre(genre)
                    }
                }
            }
            .padding(.vertical, Spacing.xs)
        }
        .scrollClipDisabled()
    }

    // MARK: - Labels

    static var any: String {
        String(localized: "browse.filter.any", defaultValue: "Any", bundle: .module)
    }

    static func decadeLabel(_ decade: Int) -> String {
        String(localized: "browse.filter.decadeValue", defaultValue: "\(String(decade))s", bundle: .module)
    }

    static func ratingLabel(_ rating: Double?) -> String {
        guard let rating else { return any }
        return String(localized: "browse.filter.ratingValue", defaultValue: "\(Int(rating))+", bundle: .module)
    }

    static func statusLabel(_ status: BrowseQuery.Status?) -> String {
        switch status {
        case nil: any
        case .ongoing: String(localized: "browse.status.ongoing", defaultValue: "Ongoing", bundle: .module)
        case .ended: String(localized: "browse.status.ended", defaultValue: "Ended", bundle: .module)
        }
    }

    static func sortLabel(_ sort: BrowseQuery.Sort) -> String {
        switch sort {
        case .popular: String(localized: "browse.sort.popular", defaultValue: "Popular", bundle: .module)
        case .rating: String(localized: "browse.sort.rating", defaultValue: "Rating", bundle: .module)
        case .year: String(localized: "browse.sort.year", defaultValue: "Year", bundle: .module)
        case .recentlyUpdated: String(localized: "browse.sort.recentlyUpdated", defaultValue: "Recently Updated", bundle: .module)
        case .alphabetical: String(localized: "browse.sort.alphabetical", defaultValue: "A–Z", bundle: .module)
        }
    }
}
