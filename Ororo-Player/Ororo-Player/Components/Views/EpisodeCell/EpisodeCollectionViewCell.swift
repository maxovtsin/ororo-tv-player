//
//  EpisodeCollectionViewCell.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Ororo_Kit

final class EpisodeCollectionViewCell: UICollectionViewCell {

    // MARK: - Properties
    let labelName = UILabel()
    let labelProgress = UILabel()
    let labelDescription = UILabel()
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
                self.labelProgress.textColor = .red
                self.labelDescription.alpha = 1.0
            } else {
                self.labelName.textColor = .white
                self.labelProgress.textColor = .white
                self.labelDescription.alpha = 0.0
            }
        }, completion: nil)
    }

    // MARK: - Private functions
    private func setupUI() {
        contentView.backgroundColor = .gray

        labelName.textColor = .white
        labelName.textAlignment = .left
        labelName.font = UIFont.systemFont(ofSize: DeviceVisualTheme.titleFontSize,
                                           weight: .bold)

        labelProgress.textColor = .white
        labelProgress.textAlignment = .right
        labelProgress.font = UIFont.systemFont(ofSize: DeviceVisualTheme.titleFontSize,
                                           weight: .bold)

        labelDescription.numberOfLines = 0
        labelDescription.textColor = .white
        labelDescription.textAlignment = .left
        labelDescription.font = UIFont.systemFont(ofSize: DeviceVisualTheme.descriptionFontSize,
                                                  weight: .regular)

        #if os(iOS)
        labelDescription.alpha = 1.0
        #elseif os(tvOS)
        labelDescription.alpha = 0.0
        #endif

        contentView.addSubview(imageViewCover)
        contentView.addSubview(background)
        contentView.addSubview(labelName)
        contentView.addSubview(labelDescription)

        background.backgroundColor = .black
        background.alpha = 0.6

        imageViewCover.clipsToBounds = true
        imageViewCover.contentMode = .scaleAspectFill

        #if os(iOS)

        labelName.layout {
            $0.top <-> 10
            $0.leading <-> 20
            $0.trailing <-> -20
            $0.height <-> 30
        }

        labelDescription.layout {
            $0.top <-> labelName.bottom
            $0.bottom <-> -10
            $0.leading <-> 20
            $0.trailing <-> -20
        }

        #elseif os(tvOS)

        contentView.addSubview(labelProgress)

        labelName.layout {
            $0.top <-> 30
            $0.leading <-> 30
            $0.height <-> 30
        }

        labelDescription.layout {
            $0.top <-> labelName.bottom
            $0.bottom <-> -10
            $0.leading <-> 20
            $0.trailing <-> -20
        }

        labelProgress.layout {
            $0.top <-> 30
            $0.leading <-> (labelName.trailing + 10)
            $0.trailing <-> -30
            $0.height <-> 30
            $0.width <-> 90
        }

        #endif

        background.pinToParent()
        imageViewCover.pinToParent()
    }
}
