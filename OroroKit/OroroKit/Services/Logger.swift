//
//  Logger.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Foundation

@inline(__always)
public func logDebug(_ message: @autoclosure () -> String) {
//    print(message())
}

@inline(__always)
public func logFatal(_ message: @autoclosure () -> String) -> Never {
    fatalError(message())
}
