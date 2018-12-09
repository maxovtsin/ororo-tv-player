//
//  Diff.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Foundation

public protocol Uniqueable {
    associatedtype IdType: Hashable
    var id: IdType { get }
}

public struct Diff {

    public enum Operation: Hashable, Equatable {
        case deletion(Int)
        case insertion(Int)
        case move(Int, Int)

        public static func == (lhs: Operation, rhs: Operation) -> Bool {
            switch (lhs, rhs) {
            case let (.deletion(a), .deletion(b)):
                return a == b
            case let (.insertion(a), .insertion(b)):
                return a == b
            case let (.move(a, b), .move(c, d)):
                return a == c && b == d
            default:
                return false
            }
        }
    }
}

public func diff<T>(old: [T],
                    new: [T]) -> [Diff.Operation] where T: Uniqueable {

    let oldIds = old.map { $0.id }
    let newIds = new.map { $0.id }

    let oldIndexesById = Dictionary(uniqueKeysWithValues: zip(oldIds, 0...))
    let newIndexesById = Dictionary(uniqueKeysWithValues: zip(newIds, 0...))

    var operations = [Diff.Operation]()

    // Deletetions
    for oldId in oldIds where newIndexesById[oldId] == nil {
        guard let deleted = oldIndexesById[oldId] else { continue }
        operations.append(.deletion(deleted))
    }

    // Insertions and movements
    for newId in newIds {
        let newIndex = newIndexesById[newId]!
        if let oldIndex = oldIndexesById[newId] {
            if oldIndex != newIndex {
                operations.append(.move(oldIndex, newIndex))
            }
        } else {
            operations.append(.insertion(newIndex))
        }
    }

    return operations
}
