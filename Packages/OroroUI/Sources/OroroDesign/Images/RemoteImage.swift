import NukeUI
import SwiftUI

/// Fades in with Motion.quick; neutral placeholder.
public struct RemoteImage: View {
    private let url: URL?
    private let pointSize: CGSize
    private let contentMode: ContentMode

    @Environment(\.displayScale) private var displayScale

    public init(url: URL?, pointSize: CGSize, contentMode: ContentMode = .fill) {
        self.url = url
        self.pointSize = pointSize
        self.contentMode = contentMode
    }

    public var body: some View {
        if let url {
            LazyImage(
                request: ImageCache.request(url, pointSize: pointSize, scale: displayScale),
                transaction: Transaction(animation: Motion.quick)
            ) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Color.gray.opacity(0.2)
    }
}

#Preview("RemoteImage placeholder") {
    RemoteImage(url: nil, pointSize: CGSize(width: 300, height: 450))
        .frame(width: 300, height: 450)
}
