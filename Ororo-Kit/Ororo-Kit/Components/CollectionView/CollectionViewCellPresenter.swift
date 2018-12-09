//
//  CollectionViewCellPresenter.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit

public protocol CollectionViewCellPresenter: class {

    /// Type of a cell.
    associatedtype CellType: UICollectionViewCell
    /// Type of a model.
    associatedtype ModelType: Uniqueable

    static func registerCells(_ collection: UICollectionView)

    static func dequeueCell(_ collection: UICollectionView,
                            indexPath: IndexPath) -> CellType

    // Should configure a cell by a model.
    static func configure(cell: CellType, model: ModelType)

    /// Must return the size of a cell.
    static func sizeForCell(maximumWidth width: CGFloat) -> CGSize

    static func minimumLineSpacingForSection(maximumWidth width: CGFloat) -> CGFloat
}

public extension CollectionViewCellPresenter {

    static func registerCells(_ collection: UICollectionView) {
        collection.register(cellClass: CellType.self)
    }

    static func dequeueCell(_ collection: UICollectionView,
                            indexPath: IndexPath) -> CellType {
        return collection.dequeueReusableCell(withClass: CellType.self,
                                              forIndexPath: indexPath)
    }
}
