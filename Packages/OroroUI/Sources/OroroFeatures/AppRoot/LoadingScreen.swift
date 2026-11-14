import OroroCore
import OroroDesign
import SwiftUI

/// Branded first-load screen. `progress` is the catalog download's byte fraction; nil while launching.
struct LoadingScreen: View {
    let progress: Double?

    var body: some View {
        VStack(spacing: Spacing.l) {
            Text(verbatim: "Ororo")
                .font(Typography.heroTitle)
                .foregroundStyle(Palette.textPrimary)
            if let progress {
                VStack(spacing: Spacing.s) {
                    ProgressView(value: progress)
                        .frame(maxWidth: 480)
                        .motion(Motion.quick, value: progress)
                    Text(String(localized: "appRoot.loading.catalog", defaultValue: "Loading the catalog…", bundle: .module))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "appRoot.loading.catalog", defaultValue: "Loading the catalog…", bundle: .module))
                .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
            } else {
                ProgressView()
                    .accessibilityLabel(String(localized: "appRoot.loading.launching", defaultValue: "Loading", bundle: .module))
            }
        }
        .padding(Spacing.screenEdge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Full-screen catalog error with Retry: shown only when there is no cache to fall back on.
struct CatalogFailureScreen: View {
    let error: APIError
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: error == .offline ? "wifi.slash" : "exclamationmark.triangle")
                .font(Typography.heroTitle)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            Text(message)
                .font(Typography.title)
                .multilineTextAlignment(.center)
            ActionButton(String(localized: "appRoot.error.retry", defaultValue: "Retry", bundle: .module),
                         systemImage: "arrow.clockwise", style: .prominent, action: retry)
        }
        .padding(Spacing.screenEdge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var message: String {
        switch error {
        case .offline:
            String(localized: "appRoot.error.offline",
                   defaultValue: "You're offline. Check your connection and try again.", bundle: .module)
        default:
            // `.unauthorized` never reaches this screen: it returns to sign-in.
            String(localized: "appRoot.error.server",
                   defaultValue: "Couldn't load the catalog from ororo.tv. Try again in a moment.", bundle: .module)
        }
    }
}

#Preview("Loading") {
    LoadingScreen(progress: 0.4)
}

#Preview("Launching") {
    LoadingScreen(progress: nil)
}

#Preview("Offline") {
    CatalogFailureScreen(error: .offline) {}
}
