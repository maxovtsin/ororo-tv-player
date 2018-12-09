//
//  Season.swift
//  Ororo-Player-iOS
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Foundation

public struct Season {

    public let number: Int
    public let posterThumb: String?
    public let episodes: [Episode]

    public init(number: Int,
                posterThumb: String?,
                episodes: [Episode]) {
        self.number = number
        self.posterThumb = posterThumb
        self.episodes = episodes
    }
}

extension Season: Uniqueable {
    public var id: Int {
        return number
    }
}
