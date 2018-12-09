//
//  DeviceVisualTheme.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Ororo_Kit

class DeviceVisualTheme {

    static var titleFontSize: CGFloat {
        #if os(iOS)
        return 14
        #elseif os(tvOS)
        return 28
        #endif
    }

    static var descriptionFontSize: CGFloat {
        #if os(iOS)
        return 14
        #elseif os(tvOS)
        return 24
        #endif
    }

    static var backgroundColor: UIColor {
        #if os(iOS)
        return .init(rgb: 0xdfe6e9)
        #elseif os(tvOS)
        return .init(rgb: 0x636e72)
        #endif
    }

    static var subtitleFont: UIFont {
        #if os(iOS)
        return UIFont.boldSystemFont(ofSize: 12.0)
        #elseif os(tvOS)
        return UIFont.boldSystemFont(ofSize: 40.0)
        #endif
    }

    static var titleFont: UIFont {
        #if os(iOS)
        return UIFont.boldSystemFont(ofSize: 20.0)
        #elseif os(tvOS)
        return UIFont.boldSystemFont(ofSize: 56.0)
        #endif
    }

    static func configureCollectionViewFlow(flow: UICollectionViewFlowLayout) {

        #if os(iOS)
        flow.scrollDirection = .vertical
        flow.minimumInteritemSpacing = 15.0
        flow.sectionInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        #elseif os(tvOS)
        flow.scrollDirection = .vertical
        flow.minimumInteritemSpacing = 40.0
        flow.minimumLineSpacing = 40.0
        flow.sectionInset = UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
        #endif
    }

    static func sizeForSearchCell(maxWidth: CGFloat) -> CGSize {
        #if os(iOS)

        let width = (maxWidth - 30) / 2
        let height = width * 1.5
        return CGSize(width: width, height: height)

        #elseif os(tvOS)

        let width = (maxWidth - 150) / 3
        let height = width / 16 * 9
        return CGSize(width: width, height: height)

        #endif
    }

    static func minimumLineSpacingForSection(maxWidth: CGFloat) -> CGFloat {
        #if os(iOS)
        return 10
        #elseif os(tvOS)
        return 150 / 3 - 15
        #endif
    }

    static func loaderSpinnerStyle() -> UIActivityIndicatorView.Style {
        #if os(iOS)
        return .gray
        #elseif os(tvOS)
        return .whiteLarge
        #endif
    }
}
