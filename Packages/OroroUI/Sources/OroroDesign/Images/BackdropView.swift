import SwiftUI

// STUB (T3) — implemented by Task D2.
public enum BackdropDim: Sendable { case hero, detail, detailLight }

/// Crossfades on url change (cinematic); drift = 1.00→1.06 over 8 s, off with Reduce Motion.
public struct BackdropView: View {
    public init(url: URL?, dim: BackdropDim, drift: Bool = false) {}

    public var body: some View {
        Color.black
    }
}

/// Blurred poster fill + title text.
public struct PlaceholderArtwork: View {
    private let title: String

    public init(posterURL: URL?, title: String) {
        self.title = title
    }

    public var body: some View {
        Text(verbatim: title)
    }
}
