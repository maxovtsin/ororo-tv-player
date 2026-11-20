import OroroCore
import OroroDesign
import SwiftUI

/// Sort, Decade / IMDb / Status menus and Reset, then the genre chip row (spec: Shows / Movies tabs).
/// A menu with a value set is drawn prominent, so the active filters read at a glance.
struct FilterBar: View {
    let model: BrowseGridViewModel
    /// Reset tapped (the screen moves focus to the first tile once the new results land).
    let onReset: () -> Void

    /// Min IMDb options: Any, 6+, 7+, 8+.
    static let ratingOptions: [Double?] = [nil, 6, 7, 8]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.s) {
                    sortMenu
                    decadeMenu
                    ratingMenu
                    if model.showsStatusFilter {
                        statusMenu
                    }
                    if !model.isDefault {
                        resetButton
                            .transition(.opacity)
                    }
                }
                .motion(Motion.quick, value: model.isDefault)
                .padding(.vertical, Spacing.xs)
            }
            .scrollClipDisabled()
            .contentMargins(.horizontal, Spacing.screenEdge, for: .scrollContent)
            .filterFocusSection()
            genreChips
        }
    }

    // MARK: - Menus

    private var sortMenu: some View {
        filterMenu(
            String(localized: "browse.filter.sort", defaultValue: "Sort", bundle: .module),
            value: Self.sortLabel(model.query.sort), isActive: false, systemImage: "arrow.up.arrow.down"
        ) {
            Picker(selection: Binding(get: { model.query.sort }, set: { model.setSort($0) })) {
                ForEach(model.availableSorts, id: \.self) { sort in
                    Text(verbatim: Self.sortLabel(sort)).tag(sort)
                }
            } label: { EmptyView() }
        }
    }

    private var decadeMenu: some View {
        filterMenu(
            String(localized: "browse.filter.decade", defaultValue: "Decade", bundle: .module),
            value: model.query.decade.map(Self.decadeLabel), isActive: model.query.decade != nil
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
            value: model.query.minRating.map { rating in
                String(localized: "browse.filter.imdbValue", defaultValue: "IMDb \(Self.ratingLabel(rating))", bundle: .module)
            }, isActive: model.query.minRating != nil
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
            value: model.query.status.map(Self.statusLabel), isActive: model.query.status != nil
        ) {
            Picker(selection: Binding(get: { model.query.status }, set: { model.setStatus($0) })) {
                ForEach([nil, BrowseQuery.Status.ongoing, .ended], id: \.self) { status in
                    Text(verbatim: Self.statusLabel(status)).tag(status)
                }
            } label: { EmptyView() }
        }
    }

    private var resetButton: some View {
        Button(action: onReset) {
            Label(String(localized: "browse.grid.reset", defaultValue: "Reset Filters", bundle: .module),
                  systemImage: "xmark")
                .font(Typography.body)
                .lineLimit(1)
                .padding(.horizontal, Spacing.s)
        }
        .glassControl()
        .buttonBorderShape(.capsule)
    }

    /// The label shows the value when one is set ("2010s"), else the filter's name; both end in a chevron.
    private func filterMenu(_ name: String, value: String?, isActive: Bool, systemImage: String? = nil,
                            @ViewBuilder content: () -> some View) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: Spacing.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(verbatim: value ?? name)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
            }
            .font(Typography.body)
            .padding(.horizontal, Spacing.s)
        }
        .glassSelectable(isSelected: isActive)
        .buttonBorderShape(.capsule)
        .accessibilityLabel(name)
        .accessibilityValue(value ?? Self.any)
    }

    // MARK: - Genre chips

    private var genreChips: some View {
        ScrollViewReader { proxy in
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
                        .id(genre)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
            .scrollClipDisabled()
            .contentMargins(.horizontal, Spacing.screenEdge, for: .scrollContent)
            .filterFocusSection()
            .onAppear {
                // "See All" from a genre row far down the list: show its selected chip.
                if let genre = model.query.genre { proxy.scrollTo(genre, anchor: .center) }
            }
        }
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
        case .topPicks: String(localized: "browse.sort.topPicks", defaultValue: "Top Picks", bundle: .module)
        case .popular: String(localized: "browse.sort.popular", defaultValue: "Popular", bundle: .module)
        case .rating: String(localized: "browse.sort.rating", defaultValue: "Rating", bundle: .module)
        case .year: String(localized: "browse.sort.year", defaultValue: "Year", bundle: .module)
        case .recentlyUpdated: String(localized: "browse.sort.recentlyUpdated", defaultValue: "Recently Updated", bundle: .module)
        case .alphabetical: String(localized: "browse.sort.alphabetical", defaultValue: "A–Z", bundle: .module)
        }
    }
}

private extension View {
    /// `.focusSection()` on tvOS, so moving up from the grid lands on the nearest control (unavailable on iOS).
    @ViewBuilder func filterFocusSection() -> some View {
        #if os(tvOS)
        focusSection()
        #else
        self
        #endif
    }
}
