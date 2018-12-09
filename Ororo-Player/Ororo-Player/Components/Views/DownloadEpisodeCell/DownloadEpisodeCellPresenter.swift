//
//  DownloadEpisodeCellPresenter.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Ororo_Kit

final class DownloadEpisodeCellPresenter: CollectionViewCellPresenter {

    typealias CellType = DownloadEpisodeCell
    typealias ModelType = DownloadEpisodeModel

    static func configure(cell: CellType,
                          model: ModelType) {
        let number = model.episode.number ?? ""
        let season = model.episode.season
        let name = model.episode.showName ?? ""

        let progress = Int(model.progress * 100)

        cell.labelName.text = name
        cell.labelProgress.text = "\(progress)%"
        cell.labelSeasonEpisode.text = "S:\(season) - E:\(number)"
    }

    static func sizeForCell(maximumWidth width: CGFloat) -> CGSize {
        return DeviceVisualTheme.sizeForSearchCell(maxWidth: width)
    }
}
