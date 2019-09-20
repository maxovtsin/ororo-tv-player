//
//  UICollectionView+Extensions.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit

extension UICollectionViewCell {

    /// Returns default identifier for a cell.
    class func defaultIdentifier() -> String {
        return NSStringFromClass(self)
    }
}

extension UICollectionView {

    /// Registers collection view cell by particular type.
    final func register<T: UICollectionViewCell>(cellClass class: T.Type) {
        self.register(`class`,
                      forCellWithReuseIdentifier: `class`.defaultIdentifier())
    }

    /// Registers collection view cell by particular nib.
    final func registerNib<T: UICollectionViewCell>(cellClass class: T.Type) {
        self.register(UINib(nibName: String(describing: `class`), bundle: nil),
                      forCellWithReuseIdentifier: `class`.defaultIdentifier())
    }

    /// Obtains collection view cell by particular type.
    final func dequeueReusableCell<T: UICollectionViewCell>(withClass class: T.Type,
                                                            forIndexPath indexPath: IndexPath) -> T {
        guard let cell = self
            .dequeueReusableCell(withReuseIdentifier: `class`.defaultIdentifier(),
                                 for: indexPath) as? T else {
                                    logFatal("""
                                        [UI] Cell with identifier: \(`class`.defaultIdentifier())
                                        for index path: \(indexPath) is not \(T.self)
                                        """)
        }
        return cell
    }
}
