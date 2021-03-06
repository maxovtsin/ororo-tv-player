//
//  EpisodeModel.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Foundation
import OroroKit

class EpisodeModel {

    let episode: Episode
    let show: Show

    init(episode: Episode, show: Show) {
        self.episode = episode
        self.show = show
    }
}

extension EpisodeModel: Uniqueable {
    var id: Int { return episode.id }

    public static func == (lhs: EpisodeModel, rhs: EpisodeModel) -> Bool {
        return lhs.id == rhs.id
    }
}
