import OroroDesign
import SwiftUI

/// Shown over the current screen when a request answers 401 mid-session (password changed).
/// Signing in again clears `AppSession.needsReauth`, which dismisses the sheet; the library is untouched.
struct ReauthSheet: View {
    let email: String?

    var body: some View {
        VStack(spacing: Spacing.m) {
            Text(String(localized: "appRoot.reauth.message",
                        defaultValue: "Your session has expired. Sign in again to continue.", bundle: .module))
                .font(Typography.headline)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            SignInScreen(prefilledEmail: email)
        }
        .padding(Spacing.screenEdge)
    }
}

#Preview {
    ReauthSheet(email: "user@example.invalid")
}
