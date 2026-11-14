import SwiftUI

public extension View {
    /// The S7 seam: glass button/capsule style. tvOS 26 / iOS 26 system Liquid Glass.
    /// Apply to a `Button`; prominent is for the primary action (Play).
    @ViewBuilder
    func glassControl(prominent: Bool = false) -> some View {
        if prominent {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.glass)
        }
    }
}
