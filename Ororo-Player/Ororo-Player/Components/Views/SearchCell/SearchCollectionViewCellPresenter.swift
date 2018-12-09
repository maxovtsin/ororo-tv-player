//
//  SearchCollectionViewCellPresenter.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Ororo_Kit

final class SearchCollectionViewCellPresenter: CollectionViewCellPresenter {

    typealias CellType = SearchCollectionViewCell
    typealias ModelType = Searchable

    static func configure(cell: CellType,
                          model: ModelType) {
        cell.labelName.text = model.title
        if let progress = model.playbackProgress, progress != 0 {
            cell.labelProgress.text = "\(Int(progress * 100))%"
        } else {
            cell.labelProgress.text = ""
        }
        if let url = URL(string: model.posterThumb) {
            cell.imageViewCover.set(url: url)
        }
    }

    static func sizeForCell(maximumWidth width: CGFloat) -> CGSize {
        return DeviceVisualTheme.sizeForSearchCell(maxWidth: width)
    }
}
