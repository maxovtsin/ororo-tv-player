//
//  ShowEpisodeOptionsFlow.swift
//  Ororo-Player-iOS
//
//  Created by Max Ovtsin on 28/4/19.
//  Copyright © 2019 Max Ovtsin. All rights reserved.
//

import UIKit
import OroroKit
import Transitions

final class ShowEpisodeOptionsFlow: Flow {

    struct Injection {
        let episode: Episode
        let serviceProvider: ServiceProvider
        let completion: (() -> Void)?
    }

    // MARK: - Flow interface
    let coordinator: Coordinator

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
    }

    func start(
        injection: Injection,
        transitionHandler: TransitionHandler
        ) {

        let alertController = getController(
            injection: injection,
            coordinator: coordinator
        )

        transitionHandler.present(
            flow: self,
            transition: BaseTransition.modal,
            params: alertController
        )
    }

    // MARK: - Private functions

    #if os(iOS)
    private func getController(
        injection: Injection,
        coordinator: Coordinator
        ) -> UIAlertController {
        let alertController = UIAlertController(title: nil,
                                                message: nil,
                                                preferredStyle: .actionSheet)

        let downloadAction = UIAlertAction(title: "download".localized(),
                                           style: .default) { (_) in
                                            self.startDownload(
                                                episode: injection.episode,
                                                serviceProvider: injection.serviceProvider
                                            )
        }

        let cancelAction = UIAlertAction(title: "cancel".localized(),
                                         style: .cancel) { (_) in }

        alertController.addAction(downloadAction)
        alertController.addAction(cancelAction)

        return alertController
    }
    #endif

    #if os(tvOS)
    private func getController(
        injection: Injection,
        coordinator: Coordinator
        ) -> UIAlertController {
        let alertController = UIAlertController(title: nil,
                                                message: nil,
                                                preferredStyle: .actionSheet)

        let downloadAction = UIAlertAction(title: "remove_from_favorites".localized(),
                                           style: .default) { (_) in

                                            //                                            self.removeFromFavourites(episode: episode,
                                            //                                                                      comletion: completion)
        }

        let cancelAction = UIAlertAction(title: "cancel".localized(),
                                         style: .cancel) { (_) in }

        alertController.addAction(downloadAction)
        alertController.addAction(cancelAction)

        return alertController
    }
    #endif

    private func removeFromFavourites(
        episode: Episode,
        serviceProvider: ServiceProvider,
        comletion: (() -> Void)?
        ) {
        serviceProvider.storageService
            .performAsync(transaction: { (context) in
                let episode = context.fetchOne(
                    "id == %@",
                    arguments: [episode.id]
                    ) as CDEpisode?
                episode?.playbackProgress = 0.0
            }, completion: comletion)
    }

    private func startDownload(
        episode: Episode,
        serviceProvider: ServiceProvider
        ) {
        serviceProvider.downloadManager.startDownload(
            episode: episode
        )
    }
}
