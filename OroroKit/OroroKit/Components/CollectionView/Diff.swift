//
//  Diff.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Foundation

public protocol Uniqueable: Equatable {
    associatedtype IdType: Hashable
    var id: IdType { get }
}

public struct Diff {

    public enum Operation: Hashable, Equatable {
        case deleted(Int)
        case inserted(Int)
        case moved(Int, Int)
        case updated(Int)

        public static func == (lhs: Operation, rhs: Operation) -> Bool {
            switch (lhs, rhs) {
            case let (.deleted(a), .deleted(b)):
                return a == b
            case let (.inserted(a), .inserted(b)):
                return a == b
            case let (.moved(a, b), .moved(c, d)):
                return a == c && b == d
            case let (.updated(a), .updated(b)):
                return a == b
            default:
                return false
            }
        }
    }

    public static func diff<T>(old: [T],
                               new: [T]) -> [Diff.Operation] where T: Uniqueable {

        let oldIds = old.map { $0.id }
        let newIds = new.map { $0.id }

        let oldIndexesById = Dictionary(uniqueKeysWithValues: zip(oldIds, 0...))
        let newIndexesById = Dictionary(uniqueKeysWithValues: zip(newIds, 0...))

        var operations = [Diff.Operation]()

        // Deletetions
        for oldId in oldIds where newIndexesById[oldId] == nil {
            guard let deleted = oldIndexesById[oldId] else { continue }
            operations.append(.deleted(deleted))
        }

        // Insertions and movements
        for newId in newIds {
            let newIndex = newIndexesById[newId]!
            if let oldIndex = oldIndexesById[newId] {
                if oldIndex != newIndex {
                    operations.append(.moved(oldIndex, newIndex))
                } else if old[oldIndex] != new[newIndex] {
                    operations.append(.updated(newIndex))
                }
            } else {
                operations.append(.inserted(newIndex))
            }
        }

        return operations
    }
}
