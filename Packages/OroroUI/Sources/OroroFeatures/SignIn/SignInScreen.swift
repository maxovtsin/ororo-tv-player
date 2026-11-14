import OroroCore
import OroroDesign
import SwiftUI

public struct SignInScreen: View {
    private let prefilledEmail: String?

    public init(prefilledEmail: String? = nil) {
        self.prefilledEmail = prefilledEmail
    }

    public var body: some View {
        SignInForm(prefilledEmail: prefilledEmail)
    }
}

private struct SignInForm: View {
    @Environment(AppSession.self) private var session
    @State private var model: SignInViewModel?
    let prefilledEmail: String?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .task {
            if model == nil {
                let session = session
                model = SignInViewModel(email: prefilledEmail ?? "") { email, password in
                    try await session.signIn(email: email, password: password)
                }
            }
        }
    }

    private func content(_ model: SignInViewModel) -> some View {
        @Bindable var model = model
        return VStack(spacing: Spacing.m) {
            Text("Sign in", bundle: .module).font(Typography.heroTitle)
            TextField(String(localized: "signin.email", defaultValue: "Email", bundle: .module), text: $model.email)
                .textContentType(.username)
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            SecureField(String(localized: "signin.password", defaultValue: "Password", bundle: .module), text: $model.password)
                .textContentType(.password)
            if let message = model.error {
                Text(Self.text(for: message))
                    .font(Typography.body)
                    .foregroundStyle(.red)
            }
            ActionButton(
                String(localized: "signin.submit", defaultValue: "Sign In", bundle: .module),
                style: .prominent,
                isLoading: model.isWorking
            ) {
                Task { await model.submit() }
            }
            .disabled(!model.canSubmit)
        }
        .frame(maxWidth: 800)
        .padding(Spacing.screenEdge)
    }

    private static func text(for message: SignInViewModel.Message) -> String {
        switch message {
        case .wrongCredentials:
            String(localized: "signin.error.wrongCredentials", defaultValue: "Wrong email or password.", bundle: .module)
        case .offline:
            String(localized: "signin.error.offline", defaultValue: "You appear to be offline. Check your connection and try again.", bundle: .module)
        case .server:
            String(localized: "signin.error.server", defaultValue: "Something went wrong. Please try again.", bundle: .module)
        }
    }
}

#Preview {
    SignInScreen(prefilledEmail: "me@example.com")
}
