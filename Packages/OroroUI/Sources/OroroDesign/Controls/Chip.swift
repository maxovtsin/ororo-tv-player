import SwiftUI

/// Season pill / filter chip: a glass capsule, prominent when selected.
public struct Chip: View {
    private let title: String
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(Typography.body)
                .lineLimit(1)
                .padding(.horizontal, Spacing.s)
        }
        .glassSelectable(isSelected: isSelected)
        .buttonBorderShape(.capsule)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Chips") {
    HStack {
        Chip("Season 1", isSelected: true) {}
        Chip("Season 2", isSelected: false) {}
    }
    .padding()
}
