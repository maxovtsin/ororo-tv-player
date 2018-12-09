//
//  VideoPlayerViewController.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import AVKit
import Ororo_Kit

final class VideoPlayerViewController: AVPlayerViewController {

    // MARK: - Properties
    private let subtitleManager: SubtitleManager
    private let videoPlayerManager: VideoPlayerManager

    private let labelSubtitle = UILabel()

    // MARK: - Life cycle
    public init(subtitleManager: SubtitleManager,
                videoPlayerManager: VideoPlayerManager) {
        self.subtitleManager = subtitleManager
        self.videoPlayerManager = videoPlayerManager
        super.init(nibName: nil, bundle: nil)
        player = videoPlayerManager.player
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("Initializer is not implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureSubtitleLabel()
        configureObserver()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        videoPlayerManager.startPlaying()
    }

    // MARK: - Private functions
    private func configureObserver() {
        videoPlayerManager.addTimeObserver(period: 1) { [weak self] (progress, _) in
            guard let self = self else { return }
            self.subtitleManager.configure(label: self.labelSubtitle, time: progress)
        }
    }

    private func configureSubtitleLabel() {
        labelSubtitle.backgroundColor = UIColor.clear
        labelSubtitle.textAlignment = .center
        labelSubtitle.font = DeviceVisualTheme.subtitleFont
        labelSubtitle.textColor = UIColor.white
        labelSubtitle.numberOfLines = 0
        labelSubtitle.layer.shadowColor = UIColor.black.cgColor
        labelSubtitle.layer.shadowOffset = CGSize(width: 1.0, height: 1.0)
        labelSubtitle.layer.shadowOpacity = 0.9
        labelSubtitle.layer.shadowRadius = 1.0
        labelSubtitle.layer.shouldRasterize = true
        labelSubtitle.layer.rasterizationScale = UIScreen.main.scale
        labelSubtitle.lineBreakMode = .byWordWrapping
        contentOverlayView?.addSubview(labelSubtitle)

        labelSubtitle.layout(builder: {

            #if os(tvOS)
            $0.bottom <-> -50
            #elseif os(iOS)
            $0.bottom <-> -20
            #endif

            $0.centerX <-> self.contentOverlayView!.centerX
            $0.leading <-> (self.contentOverlayView!.leading + 30)
            $0.trailing <-> (self.contentOverlayView!.trailing + (-30))
        })
    }
}
