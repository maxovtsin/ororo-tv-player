import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// S6 seam: where the Trailer button sends the user, or nil to hide it.
///
/// tvOS opens the YouTube app (`youtube://watch/<id>`) and only when `canOpenURL` allows it, which needs `youtube` in
/// the app's `LSApplicationQueriesSchemes`. iOS falls back to `https://youtube.com/watch?v=<id>`.
enum TrailerAvailability {
    @MainActor static func url(for youTubeID: String) -> URL? {
        guard !youTubeID.isEmpty,
              let encoded = youTubeID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#&=")))
        else { return nil }
        #if os(tvOS)
        guard let url = URL(string: "youtube://watch/\(encoded)"), UIApplication.shared.canOpenURL(url) else { return nil }
        return url
        #else
        return URL(string: "https://youtube.com/watch?v=\(encoded)")
        #endif
    }
}
