//
//  DiffTests.swift
//  Ororo-KitTests
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import XCTest
@testable import Ororo_Kit

class DiffTests: XCTestCase {

    struct Item: Uniqueable {
        let id: String
    }

    func test_GivenTwoEmptyCollections_ThenAllChangesWillBeEmpty() {
        let changes = diff(old: [Item](), new: [Item]())

        XCTAssert(changes.isEmpty, "Changes array must be empty")
    }

    func test_GivenTwoEqualCollections_ThenChangesWillNotBeGenerated() {
        let new = [Item(id: "a"), Item(id: "b")]
        let old = [Item(id: "a"), Item(id: "b")]
        let changes = diff(old: old, new: new)

        XCTAssert(changes.isEmpty, "Changes array must be empty")
    }

    func test_GivenTwoDifferentCollections_ThenInsertionsWillBeGenerated() {
        let new = [Item(id: "a"), Item(id: "b")]
        let old = [Item]()
        let changes = diff(old: old, new: new)

        let insertions = changes.filter { (op) -> Bool in
            if case .insertion(_) = op { return true } else { return false }
        }
        let deletions = changes.filter { (op) -> Bool in
            if case .deletion(_) = op { return true } else { return false }
        }
        let moves = changes.filter { (op) -> Bool in
            if case .move(_) = op { return true } else { return false }
        }

        XCTAssert(deletions.isEmpty, "Deletions must be empty")
        XCTAssert(moves.isEmpty, "Moves must be empty")
        XCTAssert(insertions.count == 2, "Insertions must not be empty")

        let _insertions: [Diff.Operation] = [.insertion(0), .insertion(1)]

        XCTAssertEqual(insertions, _insertions, "The insertions must be equal")
    }

    func test_GivenTwoDifferentCollections_ThenDeletionsWillBeGenerated() {
        let new = [Item]()
        let old = [Item(id: "a"), Item(id: "b")]
        let changes = diff(old: old, new: new)

        let insertions = changes.filter { (op) -> Bool in
            if case .insertion(_) = op { return true } else { return false }
        }
        let deletions = changes.filter { (op) -> Bool in
            if case .deletion(_) = op { return true } else { return false }
        }
        let moves = changes.filter { (op) -> Bool in
            if case .move(_) = op { return true } else { return false }
        }

        XCTAssert(moves.isEmpty, "Moves must be empty")
        XCTAssert(insertions.isEmpty, "Insertions must be empty")

        XCTAssert(deletions.count == 2, "Deletions must not be empty")

        let _deletions: [Diff.Operation] = [.deletion(0), .deletion(1)]

        XCTAssertEqual(deletions, _deletions, "The deletions must be equal")
    }

    func test_GivenTwoDifferentCollections_ThenMovementsWillBeGenerated() {
        let new = [Item(id: "a"), Item(id: "c"), Item(id: "b")]
        let old = [Item(id: "a"), Item(id: "b"), Item(id: "c")]

        let changes = diff(old: old, new: new)

        let insertions = changes.filter { (op) -> Bool in
            if case .insertion(_) = op { return true } else { return false }
        }
        let deletions = changes.filter { (op) -> Bool in
            if case .deletion(_) = op { return true } else { return false }
        }
        let moves = changes.filter { (op) -> Bool in
            if case .move(_) = op { return true } else { return false }
        }

        XCTAssert(deletions.isEmpty, "Deletions must be empty")
        XCTAssert(insertions.isEmpty, "Insertions must be empty")

        XCTAssert(moves.count == 2, "Moves must not be empty")

        let _moves: [Diff.Operation] = [.move(2, 1), .move(1, 2)]

        XCTAssertEqual(moves, _moves, "The changes must be equal")
    }

    func test_GivenTwoDifferentCollections_ThenInsertionsDeletionsAndMovementsWillBeGenerated() {
        let new = [Item(id: "d"), Item(id: "c"), Item(id: "a")]
        let old = [Item(id: "a"), Item(id: "b"), Item(id: "c")]

        let changes = diff(old: old, new: new)

        let insertions = changes.filter { (op) -> Bool in
            if case .insertion(_) = op { return true } else { return false }
        }
        let deletions = changes.filter { (op) -> Bool in
            if case .deletion(_) = op { return true } else { return false }
        }
        let moves = changes.filter { (op) -> Bool in
            if case .move(_) = op { return true } else { return false }
        }

        let _deletions: [Diff.Operation] = [.deletion(1)]
        XCTAssertEqual(deletions, _deletions, "The deletions must be equal")

        let _insertions: [Diff.Operation] = [.insertion(0)]
        XCTAssertEqual(insertions, _insertions, "The insertions must be equal")

        let _moves: [Diff.Operation] = [.move(2, 1), .move(0, 2)]
        XCTAssertEqual(moves, _moves, "The moves must be equal")
    }
}
