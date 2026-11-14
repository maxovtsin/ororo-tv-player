import Foundation
import OroroCore

// STUB (T3) — implemented by Task ST1.
public final class KeychainCredentialStore: CredentialStoring {
    private let service: String

    public init(service: String = "com.dissimirall.Ororo-Player") {
        self.service = service
    }

    public func load() -> Credentials? {
        nil
    }

    public func save(_ c: Credentials) throws {}

    public func clear() throws {}
}
