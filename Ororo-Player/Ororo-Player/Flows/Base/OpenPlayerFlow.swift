//
//  OpenPlayerFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Ororo_Kit

class OpenPlayerFlow {

    struct Playable {
        let url: URL
        let subtitles: [Subtitle]?
        let subtitle: Data?
        let lang: String
        let progress: Double
    }

    // MARK: - Properties
    private let transitionHandler: TransitionHandler
    private let serviceProvider: ServiceProvider

    // MARK: - Life cycle
    init(transitionHandler: TransitionHandler,
         serviceProvider: ServiceProvider) {
        self.transitionHandler = transitionHandler
        self.serviceProvider = serviceProvider
    }

    // MARK: - Public interface
    func start(playable: Playable,
               progressObserver: @escaping (Float64) -> Void) {
        if playable.progress == 0 {
            startPlayback(playable: playable,
                          progressObserver: progressObserver)
        } else {
            showOptions(playable: playable,
                        progressObserver: progressObserver)
        }
    }

    // MARK: - Private functions
    private func showOptions(playable: Playable,
                             progressObserver: @escaping (Float64) -> Void) {

        let alertController = UIAlertController(title: nil,
                                                message: nil,
                                                preferredStyle: .actionSheet)

        let continueAction = UIAlertAction(title: "continue".localized(),
                                           style: .default) { (_) in
                                            self.startPlayback(playable: playable,
                                                               progressObserver: progressObserver)
        }
        alertController.addAction(continueAction)

        let fromTheBeginingAction = UIAlertAction(title: "start_from_the_beginning".localized(),
                                                  style: .default) { (_) in
                                                    let p = Playable(url: playable.url,
                                                                     subtitles: playable.subtitles,
                                                                     subtitle: playable.subtitle,
                                                                     lang: playable.lang,
                                                                     progress: 0.0)
                                                    self.startPlayback(playable: p,
                                                                       progressObserver: progressObserver)
        }
        alertController.addAction(fromTheBeginingAction)

        let cancelAction = UIAlertAction(title: "cancel".localized(),
                                         style: .cancel) { (_) in }

        alertController.addAction(cancelAction)

        transitionHandler.present(viewController: alertController, modally: true)
    }

    private func startPlayback(playable: Playable,
                               progressObserver: @escaping (Float64) -> Void) {

        let subtitleManager = SubtitleManager()
        let videoPlayerManager = VideoPlayerManager(url: playable.url,
                                                    progress: playable.progress)

        videoPlayerManager.addTimeObserver(period: 2) { (time, duration) in
            progressObserver(time / duration)
        }

        let playerViewController = VideoPlayerViewController(subtitleManager: subtitleManager,
                                                             videoPlayerManager: videoPlayerManager)

        if let subData = playable.subtitle {
            subtitleManager.configure(subtitlePayload: subData)
        } else if let subtitles = playable.subtitles {
            load(subtitles: subtitles,
                 for: playable.lang,
                 completion: { (subtitles) in
                    subtitleManager.configure(subtitlePayload: subtitles)
            })
        }

        transitionHandler.present(viewController: playerViewController, modally: true)
    }

    private func load(subtitles: [Subtitle],
                      for lang: String,
                      completion: @escaping (Data) -> Void) {

        let subtitleForLang = subtitles.first { $0.lang == lang }
        guard let _subtitleForLang = subtitleForLang  else { return }
        guard let subtitleUrl = _subtitleForLang.url else { return }

        let endpoint = CustomEndpoint(path: subtitleUrl)
        serviceProvider.network
            .request(with: endpoint) { (response) in
                switch response {
                case .success(let data):
                    completion(data)
                case .error:
                    logDebug("Loading subtitle failed")
                }
        }
    }
}
