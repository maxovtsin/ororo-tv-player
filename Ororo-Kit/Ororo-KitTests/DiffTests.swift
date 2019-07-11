//
//  DiffTests.swift
//  Ororo-KitTests
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import XCTest
@testable import OroroKit

class DiffTests: XCTestCase {

    struct Item: Uniqueable {
        let id: String
    }

    struct Item2: Uniqueable {
        let id: String
        let name: String
    }

    func test_GivenTwoEmptyCollections_ThenAllChangesWillBeEmpty() {
        let changes = Diff.diff(old: [Item](), new: [Item]())

        XCTAssert(changes.isEmpty, "Changes array must be empty")
    }

    func test_GivenTwoEqualCollections_ThenChangesWillNotBeGenerated() {
        let new = [Item(id: "a"), Item(id: "b")]
        let old = [Item(id: "a"), Item(id: "b")]
        let changes = Diff.diff(old: old, new: new)

        XCTAssert(changes.isEmpty, "Changes array must be empty")
    }

    func test_GivenTwoDifferentCollections_ThenInsertionsWillBeGenerated() {
        let new = [Item(id: "a"), Item(id: "b")]
        let old = [Item]()
        let changes = Diff.diff(old: old, new: new)

        let insertions = changes.filter { (op) -> Bool in
            if case .inserted(_) = op { return true } else { return false }
        }
        let deletions = changes.filter { (op) -> Bool in
            if case .deleted(_) = op { return true } else { return false }
        }
        let moves = changes.filter { (op) -> Bool in
            if case .moved(_) = op { return true } else { return false }
        }
        let updates = changes.filter { (op) -> Bool in
            if case .updated(_) = op { return true } else { return false }
        }

        XCTAssert(updates.isEmpty, "Updates must be empty")
        XCTAssert(deletions.isEmpty, "Deletions must be empty")
        XCTAssert(moves.isEmpty, "Moves must be empty")
        XCTAssert(insertions.count == 2, "Insertions must not be empty")

        let _insertions: [Diff.Operation] = [.inserted(0), .inserted(1)]

        XCTAssertEqual(insertions, _insertions, "The insertions must be equal")
    }

    func test_GivenTwoDifferentCollections_ThenDeletionsWillBeGenerated() {
        let new = [Item]()
        let old = [Item(id: "a"), Item(id: "b")]
        let changes = Diff.diff(old: old, new: new)

        let insertions = changes.filter { (op) -> Bool in
            if case .inserted(_) = op { return true } else { return false }
        }
        let deletions = changes.filter { (op) -> Bool in
            if case .deleted(_) = op { return true } else { return false }
        }
        let moves = changes.filter { (op) -> Bool in
            if case .moved(_) = op { return true } else { return false }
        }
        let updates = changes.filter { (op) -> Bool in
            if case .updated(_) = op { return true } else { return false }
        }

        XCTAssert(updates.isEmpty, "Updates must be empty")
        XCTAssert(moves.isEmpty, "Moves must be empty")
        XCTAssert(insertions.isEmpty, "Insertions must be empty")

        XCTAssert(deletions.count == 2, "Deletions must not be empty")

        let _deletions: [Diff.Operation] = [.deleted(0), .deleted(1)]

        XCTAssertEqual(deletions, _deletions, "The deletions must be equal")
    }

    func test_GivenTwoDifferentCollections_ThenMovementsWillBeGenerated() {
        let new = [Item(id: "a"), Item(id: "c"), Item(id: "b")]
        let old = [Item(id: "a"), Item(id: "b"), Item(id: "c")]

        let changes = Diff.diff(old: old, new: new)

        let insertions = changes.filter { (op) -> Bool in
            if case .inserted(_) = op { return true } else { return false }
        }
        let deletions = changes.filter { (op) -> Bool in
            if case .deleted(_) = op { return true } else { return false }
        }
        let moves = changes.filter { (op) -> Bool in
            if case .moved(_) = op { return true } else { return false }
        }
        let updates = changes.filter { (op) -> Bool in
            if case .updated(_) = op { return true } else { return false }
        }

        XCTAssert(updates.isEmpty, "Updates must be empty")
        XCTAssert(deletions.isEmpty, "Deletions must be empty")
        XCTAssert(insertions.isEmpty, "Insertions must be empty")

        XCTAssert(moves.count == 2, "Moves must not be empty")

        let _moves: [Diff.Operation] = [.moved(2, 1), .moved(1, 2)]

        XCTAssertEqual(moves, _moves, "The changes must be equal")
    }

    func test_GivenTwoDifferentCollections_ThenInsertionsDeletionsAndMovementsWillBeGenerated() {
        let new = [Item(id: "d"), Item(id: "c"), Item(id: "a")]
        let old = [Item(id: "a"), Item(id: "b"), Item(id: "c")]

        let changes = Diff.diff(old: old, new: new)

        let insertions = changes.filter { (op) -> Bool in
            if case .inserted(_) = op { return true } else { return false }
        }
        let deletions = changes.filter { (op) -> Bool in
            if case .deleted(_) = op { return true } else { return false }
        }
        let moves = changes.filter { (op) -> Bool in
            if case .moved(_) = op { return true } else { return false }
        }
        let updates = changes.filter { (op) -> Bool in
            if case .updated(_) = op { return true } else { return false }
        }
        XCTAssert(updates.isEmpty)

        let _deletions: [Diff.Operation] = [.deleted(1)]
        XCTAssertEqual(deletions, _deletions, "The deletions must be equal")

        let _insertions: [Diff.Operation] = [.inserted(0)]
        XCTAssertEqual(insertions, _insertions, "The insertions must be equal")

        let _moves: [Diff.Operation] = [.moved(2, 1), .moved(0, 2)]
        XCTAssertEqual(moves, _moves, "The moves must be equal")
    }

    func test_GivenTwoCollectionsWithUpdatedAndMovedItems_ThenMoveMustBeGenerated() {
        let new = [Item2(id: "a", name: "aa"), Item2(id: "b", name: "bb")]
        let old = [Item2(id: "b", name: "bb"), Item2(id: "a", name: "aa")]

        let changes = Diff.diff(old: old, new: new)

        let insertions = changes.filter { (op) -> Bool in
            if case .inserted(_) = op { return true } else { return false }
        }
        let deletions = changes.filter { (op) -> Bool in
            if case .deleted(_) = op { return true } else { return false }
        }
        let moves = changes.filter { (op) -> Bool in
            if case .moved(_) = op { return true } else { return false }
        }
        let updates = changes.filter { (op) -> Bool in
            if case .updated(_) = op { return true } else { return false }
        }
        XCTAssert(updates.isEmpty)
        XCTAssert(insertions.isEmpty)
        XCTAssert(deletions.isEmpty)

        let _moves: [Diff.Operation] = [.moved(1, 0), .moved(0, 1)]
        XCTAssertEqual(moves, _moves, "The moves must be equal")
    }

    func test_GivenTwoCollectionsWithUpdatedItems_ThenUpdateMustBeGenerated() {
        let new = [Item2(id: "a", name: "aa"), Item2(id: "b", name: "bb")]
        let old = [Item2(id: "a", name: "aa"), Item2(id: "b", name: "bbb")]

        let changes = Diff.diff(old: old, new: new)

        let insertions = changes.filter { (op) -> Bool in
            if case .inserted(_) = op { return true } else { return false }
        }
        let deletions = changes.filter { (op) -> Bool in
            if case .deleted(_) = op { return true } else { return false }
        }
        let moves = changes.filter { (op) -> Bool in
            if case .moved(_) = op { return true } else { return false }
        }
        let updates = changes.filter { (op) -> Bool in
            if case .updated(_) = op { return true } else { return false }
        }

        XCTAssert(insertions.isEmpty)
        XCTAssert(deletions.isEmpty)
        XCTAssert(moves.isEmpty)

        let _updates: [Diff.Operation] = [.updated(1)]
        XCTAssertEqual(updates, _updates, "The updates must be equal")
    }
}
