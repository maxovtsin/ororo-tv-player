//
//  OpenPlayerFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import OroroKit
import Transitions

final class OpenPlayerFlow: Flow {

    struct Playable {
        let url: URL
        let subtitles: [Subtitle]?
        let subtitle: Data?
        let lang: String
        let progress: Double
    }

    struct Injection {
        let playable: Playable
        let serviceProvider: ServiceProvider
        let progressUpdate: (Float64) -> Void
    }

    // MARK: - Flow
    let coordinator: Coordinator

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
    }

    func start(
        injection: Injection,
        transitionHandler: TransitionHandler
        ) {

        if injection.playable.progress == 0 {
            startPlayback(
                injection: injection,
                coordinator: coordinator,
                transitionHandler: transitionHandler
            )
        } else {
            showOptions(
                injection: injection,
                coordinator: coordinator,
                transitionHandler: transitionHandler
            )
        }
    }

    // MARK: - Private functions
    private func showOptions(
        injection: Injection,
        coordinator: Coordinator,
        transitionHandler: TransitionHandler
        ) {

        let alertController = UIAlertController(
            title: nil,
            message: nil,
            preferredStyle: .actionSheet)

        let continueAction = UIAlertAction(
            title: "continue".localized(),
            style: .default) { (_) in
                self.startPlayback(
                    injection: injection,
                    coordinator: coordinator,
                    transitionHandler: transitionHandler)
        }
        alertController.addAction(continueAction)

        let fromTheBeginingAction = UIAlertAction(
            title: "start_from_the_beginning".localized(),
            style: .default) { (_) in
                let p = Playable(
                    url: injection.playable.url,
                    subtitles: injection.playable.subtitles,
                    subtitle: injection.playable.subtitle,
                    lang: injection.playable.lang,
                    progress: 0.0
                )
                let inj = Injection(
                    playable: p,
                    serviceProvider: injection.serviceProvider,
                    progressUpdate: injection.progressUpdate
                )
                self.startPlayback(
                    injection: inj,
                    coordinator: coordinator,
                    transitionHandler: transitionHandler)
        }
        alertController.addAction(fromTheBeginingAction)

        let cancelAction = UIAlertAction(
            title: "cancel".localized(),
            style: .cancel
        ) { (_) in }

        alertController.addAction(cancelAction)

        transitionHandler.present(
            flow: self,
            transition: BaseTransition.modal,
            params: alertController
        )
    }

    private func startPlayback(
        injection: Injection,
        coordinator: Coordinator,
        transitionHandler: TransitionHandler
        ) {

        let subtitleManager = SubtitleManager()
        let videoPlayerManager = VideoPlayerManager(
            url: injection.playable.url,
            progress: injection.playable.progress
        )

        videoPlayerManager.addTimeObserver(period: 2) { (time, duration) in
            injection.progressUpdate(time / duration)
        }

        let playerViewController = VideoPlayerViewController(
            subtitleManager: subtitleManager,
            videoPlayerManager: videoPlayerManager
        )

        if let subData = injection.playable.subtitle {
            subtitleManager.configure(subtitlePayload: subData)
        } else if let subtitles = injection.playable.subtitles {
            load(subtitles: subtitles,
                 for: injection.playable.lang,
                 serviceProvider: injection.serviceProvider,
                 completion: { (subtitles) in
                    subtitleManager.configure(subtitlePayload: subtitles)
            })
        }

        transitionHandler.present(
            flow: self,
            transition: BaseTransition.modal,
            params: playerViewController
        )
    }
    
    private func load(
        subtitles: [Subtitle],
        for lang: String,
        serviceProvider: ServiceProvider,
        completion: @escaping (Data) -> Void
        ) {

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
