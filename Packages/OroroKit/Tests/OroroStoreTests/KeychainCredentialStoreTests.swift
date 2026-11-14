import Foundation
import OroroCore
import XCTest
@testable import OroroStore

final class KeychainCredentialStoreTests: XCTestCase {
    private var store: KeychainCredentialStore!

    override func setUp() {
        super.setUp()
        store = KeychainCredentialStore(service: "test.ororo.\(UUID().uuidString)")
    }

    override func tearDown() {
        try? store.clear()
        store = nil
        super.tearDown()
    }

    func testSaveThenLoad() throws {
        try store.save(Credentials(email: "a@example.com", password: "dummy-pass"))
        XCTAssertEqual(store.load(), Credentials(email: "a@example.com", password: "dummy-pass"))
    }

    func testSaveReplacesPrevious() throws {
        try store.save(Credentials(email: "a@example.com", password: "one"))
        try store.save(Credentials(email: "b@example.com", password: "two"))
        XCTAssertEqual(store.load(), Credentials(email: "b@example.com", password: "two"))
    }

    func testClearRemoves() throws {
        try store.save(Credentials(email: "a@example.com", password: "one"))
        try store.clear()
        XCTAssertNil(store.load())
    }

    func testLoadWithNothingStoredIsNil() {
        XCTAssertNil(store.load())
    }

    func testClearWhenEmptyDoesNotThrow() {
        XCTAssertNoThrow(try store.clear())
    }
}
