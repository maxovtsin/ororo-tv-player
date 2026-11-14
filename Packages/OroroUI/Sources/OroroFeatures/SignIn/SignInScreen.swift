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
    private enum Field { case email, password }

    @Environment(AppSession.self) private var session
    @State private var model: SignInViewModel
    @FocusState private var focus: Field?
    private let prefilled: Bool

    init(prefilledEmail: String?) {
        // Placeholder closure; replaced in `onAppear` once the environment's session is readable.
        _model = State(initialValue: SignInViewModel(email: prefilledEmail ?? "") { _, _ in })
        prefilled = !(prefilledEmail ?? "").isEmpty
    }

    var body: some View {
        content
            .onAppear {
                model.rebind { [session] email, password in
                    try await session.signIn(email: email, password: password)
                }
                focus = prefilled ? .password : .email
            }
    }

    private var content: some View {
        @Bindable var model = model
        return VStack(spacing: Spacing.m) {
            Text(String(localized: "signin.title", defaultValue: "Sign in", bundle: .module))
                .font(Typography.heroTitle)
            TextField(String(localized: "signin.email", defaultValue: "Email", bundle: .module), text: $model.email)
                .textContentType(.username)
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
            SecureField(String(localized: "signin.password", defaultValue: "Password", bundle: .module), text: $model.password)
                .textContentType(.password)
                .focused($focus, equals: .password)
            if let message = model.error {
                // No error token in `Palette`; system red is kept deliberately.
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
        .onChange(of: model.error) { _, message in
            guard let message else { return }
            focus = .password
            AccessibilityNotification.Announcement(Self.text(for: message)).post()
        }
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
        .environment(AppSession(environment: .preview()))
}
