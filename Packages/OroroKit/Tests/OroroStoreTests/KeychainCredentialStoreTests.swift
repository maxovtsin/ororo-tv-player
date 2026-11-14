import Foundation
import OroroCore
import Testing
@testable import OroroStore

@Suite struct KeychainCredentialStoreTests {
    private let store = KeychainCredentialStore(service: "test.ororo.\(UUID().uuidString)")

    @Test func saveThenLoad() throws {
        defer { try? store.clear() }
        try store.save(Credentials(email: "a@example.com", password: "dummy-pass"))
        #expect(store.load() == Credentials(email: "a@example.com", password: "dummy-pass"))
    }

    @Test func saveReplacesPrevious() throws {
        defer { try? store.clear() }
        try store.save(Credentials(email: "a@example.com", password: "one"))
        try store.save(Credentials(email: "b@example.com", password: "two"))
        #expect(store.load() == Credentials(email: "b@example.com", password: "two"))
    }

    @Test func clearRemoves() throws {
        defer { try? store.clear() }
        try store.save(Credentials(email: "a@example.com", password: "one"))
        try store.clear()
        #expect(store.load() == nil)
    }

    @Test func loadWithNothingStoredIsNil() {
        defer { try? store.clear() }
        #expect(store.load() == nil)
    }

    @Test func clearWhenEmptyDoesNotThrow() throws {
        defer { try? store.clear() }
        try store.clear()
    }
}
