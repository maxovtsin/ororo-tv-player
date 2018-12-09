//
//  Searchable.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit

public protocol DecoratedSearchable {
    var id: Int { get }
    var title: String { get }
    var desc: String { get }
    var posterThumb: String { get }
    var playbackProgress: Double? { get }
}

public extension DecoratedSearchable {
    var desc: String { return "" }
    var playbackProgress: Double? { return 0.0 }
}

public struct Searchable: DecoratedSearchable {

    public let model: DecoratedSearchable

    public init(model: DecoratedSearchable) {
        self.model = model
    }
}

extension Searchable: Uniqueable {
    public var id: Int {
        return model.id ^ title.hashValue
    }

    public var title: String {
        return model.title
    }

    public var posterThumb: String {
        return model.posterThumb
    }
}
