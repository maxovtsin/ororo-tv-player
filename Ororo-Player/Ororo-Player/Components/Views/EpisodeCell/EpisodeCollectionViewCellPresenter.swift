//
//  EpisodeCollectionViewCellPresenter.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import OroroKit

final class EpisodeCollectionViewCellPresenter: CollectionViewCellPresenter {

    typealias CellType = EpisodeCollectionViewCell
    typealias ModelType = EpisodeModel

    static func configure(cell: CellType,
                          model: ModelType) {

        let number = model.episode.number ?? ""
        let name = model.episode.name ?? ""
        cell.labelName.text = "\(number) - \(name)"
        cell.labelDescription.text = model.episode.plot

        if let progress = model.episode.playbackProgress, progress != 0 {
            cell.labelProgress.text = "\(Int(progress * 100))%"
        } else {
            cell.labelProgress.text = ""
        }

        if let urlString = model.show.posterThumb,
            let url = URL(string: urlString) {
            cell.imageViewCover.set(url: url)
        }
    }

    static func sizeForCell(maximumWidth width: CGFloat) -> CGSize {
        return DeviceVisualTheme.sizeForSearchCell(maxWidth: width)
    }
}
