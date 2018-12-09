//
//  NSManagedObjectContext+Extensions.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import CoreData

extension NSManagedObject: Sortable {

    public static var sortDescriptor: String {
        return "id"
    }
}

extension NSManagedObject: Identifiable {

    public static var primaryId: String {
        return "id"
    }
}

public extension NSManagedObject {

    /// Returns a name of the property without module prefix.
    static var entityName: String {
        return NSStringFromClass(self).components(separatedBy: ".").last!
    }

    /// Creates a new item in the database removing all duplicates.
    static func forceCreate<T>(with id: String,
                               into context: NSManagedObjectContext) -> T where T: NSManagedObject {

        let duplicates = context.fetchAll("\(T.primaryId) == %@", arguments: [id]) as [T]?
        // Removing duplicates
        if let duplicate = duplicates?.first {
            return duplicate
        }

        let description = NSEntityDescription.entity(forEntityName: self.entityName,
                                                     in: context)
        return T.init(entity: description!, insertInto: context)
    }
}

public extension NSManagedObjectContext {

    /// Deletes existing object from the database.
    func deleteExisting(_ object: NSManagedObject) {
        self.performAndWait {
            self.delete(object)
        }
    }
}

extension NSManagedObjectContext: Fetchable {

    /// Fetches all items matching particular type.
    public func fetchAll<I>() -> [I]? where I: NSManagedObject {
        return fetchAll("", arguments: [])
    }

    /// Fetches all items matching particular type and fetchClause.
    public func fetchAll<I, O>(_ fetchQuery: String,
                               arguments: [O]) -> [I]? where I: NSManagedObject {

        let fetchRequest = NSFetchRequest<I>(entityName: I.entityName)
        fetchRequest.resultType = .managedObjectResultType

        fetchRequest.sortDescriptors = [NSSortDescriptor(key: I.sortDescriptor,
                                                         ascending: true)]

        // In case of absent a fetch query will create a predicate.
        if !fetchQuery.isEmpty {
            let predicate = NSPredicate(format: fetchQuery,
                                        argumentArray: arguments)
            fetchRequest.predicate = predicate
        }

        var fetchResults: [I]?
        var fetchError: Error?
        self.performAndWait {
            do {
                fetchResults = try self.fetch(fetchRequest)
            } catch {
                fetchError = error
            }
        }
        if fetchResults == nil {
            logDebug("[Storage Service] Execution failed with error \(String(describing: fetchError))")
            return nil
        }
        return fetchResults
    }

    public func fetchOne<I, O>(_ fetchClause: String,
                               arguments: [O]) -> I? where I: NSManagedObject {
        return fetchAll(fetchClause, arguments: arguments)?.first
    }
}
