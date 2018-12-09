//
//  SearchCollectionViewCell.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Ororo_Kit

final class SearchCollectionViewCell: UICollectionViewCell {

    // MARK: - Properties
    let labelProgress = UILabel()
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

    override func prepareForReuse() {
        super.prepareForReuse()
        imageViewCover.stopLoading()
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
        labelName.textAlignment = .left
        labelName.numberOfLines = 3

        #if os(iOS)
        labelName.font = UIFont.systemFont(ofSize: 18,
                                           weight: .bold)
        #elseif os(tvOS)
        labelName.font = UIFont.systemFont(ofSize: 32,
                                           weight: .bold)
        #endif

        labelProgress.textColor = .white
        labelProgress.textAlignment = .right
        labelProgress.numberOfLines = 1

        #if os(iOS)
        labelProgress.font = UIFont.systemFont(ofSize: 18,
                                               weight: .bold)
        #elseif os(tvOS)
        labelProgress.font = UIFont.systemFont(ofSize: 32,
                                               weight: .bold)
        #endif

        contentView.addSubview(imageViewCover)
        contentView.addSubview(background)
        contentView.addSubview(labelName)
        contentView.addSubview(labelProgress)

        background.backgroundColor = .black
        background.alpha = 0.5

        imageViewCover.clipsToBounds = true
        imageViewCover.contentMode = .scaleAspectFill

        #if os(iOS)
        labelName.layout {
            $0.bottom <-> -10
            $0.leading <-> 10
            $0.trailing <-> -10
        }
        labelProgress.layout {
            $0.top <-> 10
            $0.leading <-> 10
            $0.trailing <-> -10
        }
        #elseif os(tvOS)
        labelName.layout {
            $0.bottom <-> -30
            $0.leading <-> 30
            $0.trailing <-> -30
        }
        labelProgress.layout {
            $0.top <-> 10
            $0.leading <-> 10
            $0.trailing <-> -10
        }
        #endif

        background.pinToParent()
        imageViewCover.pinToParent()
    }
}
