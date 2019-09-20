//
//  Codable+Helpers.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Foundation

extension Encodable {
    func encoded() throws -> Data {
        return try JSONEncoder().encode(self)
    }
}

extension Data {
    func decoded<T>() throws -> T where T: Decodable {
        return try JSONDecoder().decode(T.self, from: self)
    }
}
