import SwiftUI

/// isLoading: label morphs to a spinner in place, button disabled.
public struct ActionButton: View {
    public enum Style: Sendable { case prominent, regular }

    private let title: String
    private let systemImage: String?
    private let style: Style
    private let isLoading: Bool
    private let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, style: Style = .regular, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                // The label stays in layout (invisible while loading) so the button keeps its size.
                label.opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().transition(.opacity)
                }
            }
            .motion(Motion.quick, value: isLoading)
        }
        .glassControl(prominent: style == .prominent)
        .disabled(isLoading)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isLoading ? .updatesFrequently : [])
    }

    private var label: some View {
        HStack(spacing: Spacing.s) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(verbatim: title)
        }
    }
}

/// Symbol replace + bounce.
public struct ToggleListButton: View {
    private let isInList: Bool
    private let action: () -> Void

    public init(isInList: Bool, action: @escaping () -> Void) {
        self.isInList = isInList
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: isInList ? "checkmark" : "plus")
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: isInList)
        }
        .glassControl()
        .accessibilityLabel(isInList
            ? String(localized: "list.remove.accessibility", defaultValue: "Remove from My List", bundle: .module)
            : String(localized: "list.add.accessibility", defaultValue: "Add to My List", bundle: .module))
    }
}

#Preview("Buttons") {
    HStack {
        ActionButton("Play", systemImage: "play.fill", style: .prominent) {}
        ActionButton("Play", systemImage: "play.fill", style: .prominent, isLoading: true) {}
        ActionButton("Trailer", systemImage: "film") {}
        ToggleListButton(isInList: false) {}
        ToggleListButton(isInList: true) {}
    }
    .padding()
}
