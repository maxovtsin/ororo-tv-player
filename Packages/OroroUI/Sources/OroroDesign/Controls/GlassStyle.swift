import SwiftUI

public extension View {
    /// The S7 seam: glass button/capsule style. tvOS 26 / iOS 26 system Liquid Glass.
    /// Apply to a `Button`; prominent is for the primary action (Play).
    /// Styles buttons only: it has no effect on non-button views. For non-button
    /// capsules use `.glassEffect(in: .capsule)` instead.
    @ViewBuilder
    func glassControl(prominent: Bool = false) -> some View {
        if prominent {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.glass)
        }
    }

    /// Glass capsule for a selectable chip or an active filter. Untinted prominent glass is indistinguishable
    /// from plain glass on tvOS, so the selected state carries `Palette.selection`.
    func glassSelectable(isSelected: Bool) -> some View {
        glassControl(prominent: isSelected)
            .tint(isSelected ? Palette.selection : nil)
    }
}
