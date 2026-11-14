import SwiftUI

// STUB (T3) — implemented by Task D3.
/// isLoading: label morphs to a spinner in place, button disabled.
public struct ActionButton: View {
    public enum Style: Sendable { case prominent, regular }

    private let title: String
    private let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, style: Style = .regular, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) { Text(verbatim: title) }
    }
}

/// Symbol replace + bounce.
public struct ToggleListButton: View {
    private let action: () -> Void

    public init(isInList: Bool, action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) { Text(verbatim: "ToggleListButton") }
    }
}
