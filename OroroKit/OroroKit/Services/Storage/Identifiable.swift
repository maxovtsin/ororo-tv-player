//
//  Identifiable.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Foundation

public protocol Identifiable {
    static var primaryId: String { get }
}
