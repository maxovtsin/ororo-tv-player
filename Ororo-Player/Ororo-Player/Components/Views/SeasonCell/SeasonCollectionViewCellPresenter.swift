//
//  SeasonCollectionViewCellPresenter.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Ororo_Kit

final class SeasonCollectionViewCellPresenter: CollectionViewCellPresenter {

    typealias CellType = SeasonCollectionViewCell
    typealias ModelType = Season

    static func configure(cell: CellType,
                          model: ModelType) {
        cell.labelName.text = "\(model.number) Season"

        if let url = URL(string: model.posterThumb!) {
            cell.imageViewCover.set(url: url)
        }
    }

    static func sizeForCell(maximumWidth width: CGFloat) -> CGSize {
        return DeviceVisualTheme.sizeForSearchCell(maxWidth: width)
    }
}
