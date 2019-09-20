//
//  Endpoint.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit

public protocol Endpoint {
    var path: String { get }
}

public struct CustomEndpoint: Endpoint {

    public let path: String

    public init(path: String) {
        self.path = path
    }
}
