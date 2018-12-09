//
//  DownloadEpisodeModel.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Ororo_Kit

struct DownloadEpisodeModel {
    let episode: Episode
    let progress: Float

    init(episode: Episode, progress: Float) {
        self.episode = episode
        self.progress = progress
    }
}

extension DownloadEpisodeModel: Uniqueable {
    var id: Int { return episode.id }
}
