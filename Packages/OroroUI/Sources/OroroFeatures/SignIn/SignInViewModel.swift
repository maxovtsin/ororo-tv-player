import Foundation
import Observation
import OroroCore

@MainActor @Observable
public final class SignInViewModel {
    public enum Message: Equatable { case wrongCredentials, offline, server }

    public var email: String
    public var password: String = ""
    public private(set) var isWorking = false
    public private(set) var error: Message?

    private let signIn: (String, String) async throws -> Void

    public init(email: String = "", signIn: @escaping (String, String) async throws -> Void) {
        self.email = email
        self.signIn = signIn
    }

    public var canSubmit: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.contains("@") && !password.isEmpty
    }

    public func submit() async {
        guard canSubmit, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await signIn(email.trimmingCharacters(in: .whitespacesAndNewlines), password)
            error = nil
        } catch is CancellationError {
            // Benign overlap; stay idle, show nothing.
        } catch let apiError as APIError {
            switch apiError {
            case .unauthorized: error = .wrongCredentials
            case .offline: error = .offline
            default: error = .server
            }
        } catch {
            self.error = .server
        }
    }
}
