import SwiftUI

// STUB (T3) — implemented by Task D3.
public struct Chip: View {
    private let title: String
    private let action: () -> Void

    public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) { Text(verbatim: title) }
    }
}
