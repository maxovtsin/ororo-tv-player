import SwiftUI

/// How strongly the backdrop is darkened for the text that sits on it.
public enum BackdropDim: Sendable { case hero, detail, detailLight }

/// Crossfades on url change (cinematic); drift = 1.00→1.06 over 8 s, off with Reduce Motion.
public struct BackdropView: View {
    private let url: URL?
    private let dim: BackdropDim
    private let drift: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1

    private static let driftScale: CGFloat = 1.06
    private static let driftDuration: Double = 8
    private static let size = CGSize(width: 1920, height: 1080)

    public init(url: URL?, dim: BackdropDim, drift: Bool = false) {
        self.url = url
        self.dim = dim
        self.drift = drift
    }

    public var body: some View {
        ZStack {
            Color.black
            RemoteImage(url: url, pointSize: Self.size)
                .id(url)
                .transition(.opacity)
                .scaleEffect(scale)
                .task(id: url) { runDrift() }
        }
        .animation(Motion.resolved(Motion.cinematic, reduceMotion: reduceMotion), value: url)
        .overlay { gradient }
        .clipped()
        .accessibilityHidden(true)
    }

    private var gradient: some View {
        switch dim {
        case .hero:
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.15), location: 0),
                    .init(color: .black.opacity(0.35), location: 0.5),
                    .init(color: .black.opacity(0.85), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .detail:
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.9), location: 0),
                    .init(color: .black.opacity(0.6), location: 0.5),
                    .init(color: .black.opacity(0.35), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .detailLight:
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.7), location: 0),
                    .init(color: .black.opacity(0.2), location: 0.6),
                    .init(color: .black.opacity(0.1), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    /// Restarts the slow zoom whenever the image changes.
    private func runDrift() {
        var reset = Transaction(animation: nil)
        reset.disablesAnimations = true
        withTransaction(reset) { scale = 1 }
        guard drift, !reduceMotion else { return }
        withAnimation(.linear(duration: Self.driftDuration)) { scale = Self.driftScale }
    }
}

/// Blurred poster fill + title text.
public struct PlaceholderArtwork: View {
    private let posterURL: URL?
    private let title: String

    public init(posterURL: URL?, title: String) {
        self.posterURL = posterURL
        self.title = title
    }

    public var body: some View {
        ZStack {
            Color.gray.opacity(0.2)
            RemoteImage(url: posterURL, pointSize: CGSize(width: 300, height: 450))
                .blur(radius: 30)
            Color.black.opacity(0.35)
            Text(verbatim: title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(16)
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
    }
}

#Preview("Backdrop hero") {
    BackdropView(url: nil, dim: .hero, drift: true)
        .frame(width: 960, height: 540)
}

#Preview("Backdrop detail light") {
    BackdropView(url: nil, dim: .detailLight)
        .frame(width: 960, height: 540)
}

#Preview("PlaceholderArtwork") {
    PlaceholderArtwork(posterURL: nil, title: "The Long Dark Night")
        .frame(width: 480, height: 270)
}
