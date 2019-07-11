//
//  SeasonCollectionViewCell.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import OroroKit

final class SeasonCollectionViewCell: UICollectionViewCell {

    // MARK: - Properties
    let labelName = UILabel()
    let imageViewCover = UIImageView()
    let background = UIView()

    // MARK: - Life cycle
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupUI()
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext,
                                 with coordinator: UIFocusAnimationCoordinator) {
        coordinator.addCoordinatedAnimations({
            if self.isFocused {
                self.labelName.textColor = .red
            } else {
                self.labelName.textColor = .white
            }
        }, completion: nil)
    }

    // MARK: - Private functions
    private func setupUI() {
        contentView.backgroundColor = .gray

        labelName.textColor = .white
        labelName.textAlignment = .center
        labelName.font = UIFont.systemFont(ofSize: 34,
                                           weight: .bold)

        contentView.addSubview(imageViewCover)
        contentView.addSubview(background)
        contentView.addSubview(labelName)

        background.backgroundColor = .black
        background.alpha = 0.5

        imageViewCover.clipsToBounds = true
        imageViewCover.contentMode = .scaleAspectFill

        labelName.pinToParent()
        background.pinToParent()
        imageViewCover.pinToParent()
    }
}
