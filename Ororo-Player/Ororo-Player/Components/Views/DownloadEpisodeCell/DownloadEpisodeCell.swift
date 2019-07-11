//
//  DownloadEpisodeCell.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import OroroKit

final class DownloadEpisodeCell: UICollectionViewCell {

    // MARK: - Properties
    let labelName = UILabel()
    let labelProgress = UILabel()
    let labelSeasonEpisode = UILabel()
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
                self.labelSeasonEpisode.textColor = .red
            } else {
                self.labelName.textColor = .white
                self.labelSeasonEpisode.textColor = .white
            }
        }, completion: nil)
    }

    // MARK: - Private functions
    private func setupUI() {
        contentView.backgroundColor = .gray

        labelName.textColor = .white
        labelName.numberOfLines = 0
        labelName.textAlignment = .left
        labelName.font = UIFont.systemFont(ofSize: 18,
                                           weight: .bold)

        labelProgress.textColor = .white
        labelProgress.textAlignment = .right
        labelProgress.font = UIFont.systemFont(ofSize: 18,
                                               weight: .bold)

        labelSeasonEpisode.textColor = .white
        labelSeasonEpisode.textAlignment = .left
        labelSeasonEpisode.font = UIFont.systemFont(ofSize: 18,
                                                    weight: .bold)

        contentView.addSubview(imageViewCover)
        contentView.addSubview(background)
        contentView.addSubview(labelName)
        contentView.addSubview(labelSeasonEpisode)
        contentView.addSubview(labelProgress)

        background.backgroundColor = .black
        background.alpha = 0.5

        imageViewCover.clipsToBounds = true
        imageViewCover.contentMode = .scaleAspectFill

        labelProgress.layout {
            $0.top <-> 5
            $0.leading <-> 10
            $0.trailing <-> -10
            $0.height <-> 30
        }

        labelSeasonEpisode.layout {
            $0.bottom <-> -10
            $0.leading <-> 10
            $0.trailing <-> -10
            $0.height <-> 30
        }

        labelName.layout {
            $0.bottom <-> (labelSeasonEpisode.top + 0)
            $0.leading <-> 10
            $0.trailing <-> -10
        }

        background.pinToParent()
        imageViewCover.pinToParent()
    }
}
