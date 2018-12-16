//
//  ShowShowOptionsFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Ororo_Kit

final class ShowShowOptionsFlow {

    // MARK: - Properties
    private let transitionHandler: TransitionHandler
    private let serviceProvider: ServiceProvider

    // MARK: - Life cycle
    init(transitionHandler: TransitionHandler,
         serviceProvider: ServiceProvider) {
        self.transitionHandler = transitionHandler
        self.serviceProvider = serviceProvider
    }

    // MARK: - Flow interface
    public func start(episode: Episode, completion: (() -> Void)? = nil) {

        #if os(iOS)

        let alertController = UIAlertController(title: nil,
                                                message: nil,
                                                preferredStyle: .actionSheet)

        let downloadAction = UIAlertAction(title: "download".localized(),
                                           style: .default) { (_) in
                                            self.startDownload(episode: episode)
        }

        let cancelAction = UIAlertAction(title: "cancel".localized(),
                                         style: .cancel) { (_) in }

        alertController.addAction(downloadAction)
        alertController.addAction(cancelAction)

        transitionHandler.present(viewController: alertController, modally: true)

        #elseif os(tvOS)

        let alertController = UIAlertController(title: nil,
                                                message: nil,
                                                preferredStyle: .actionSheet)

        let downloadAction = UIAlertAction(title: "remove_from_favorites".localized(),
                                           style: .default) { (_) in
                                            self.removeFromFavourites(episode: episode,
                                                                      comletion: completion)
        }

        let cancelAction = UIAlertAction(title: "cancel".localized(),
                                         style: .cancel) { (_) in }

        alertController.addAction(downloadAction)
        alertController.addAction(cancelAction)

        transitionHandler.present(viewController: alertController, modally: true)

        #endif
    }

    public func start(show: Show, completion: (() -> Void)?) {
        let alertController = UIAlertController(title: nil,
                                                message: nil,
                                                preferredStyle: .actionSheet)

        if let isFavourite = show.isFavourite, isFavourite {
            let favouriteAction = UIAlertAction(title: "remove_from_favorites".localized(),
                                                style: .default) { (_) in
                                                    self.updateFavourites(show: show,
                                                                          isFavourite: false,
                                                                          comletion: completion)
            }
            alertController.addAction(favouriteAction)
        } else {
            let favouriteAction = UIAlertAction(title: "add_to_favorites".localized(),
                                                style: .default) { (_) in
                                                    self.updateFavourites(show: show,
                                                                          isFavourite: true,
                                                                          comletion: completion)
            }
            alertController.addAction(favouriteAction)
        }

        let cancelAction = UIAlertAction(title: "cancel".localized(),
                                         style: .cancel) { (_) in }

        alertController.addAction(cancelAction)

        transitionHandler.present(viewController: alertController, modally: true)
    }

    // MARK: - Private functions

    private func updateFavourites(show: Show, isFavourite: Bool, comletion: (() -> Void)?) {
        serviceProvider.storageService
            .performAsync(transaction: { (context) in
                let movie = context.fetchOne("id == %@",
                                             arguments: [show.id]) as CDShow?
                movie?.isFavourite = NSNumber(value: isFavourite)
            }, completion: comletion)
    }

    private func removeFromFavourites(episode: Episode, comletion: (() -> Void)?) {
        serviceProvider.storageService
            .performAsync(transaction: { (context) in
                let episode = context.fetchOne("id == %@",
                                               arguments: [episode.id]) as CDEpisode?
                episode?.playbackProgress = 0.0
            }, completion: comletion)
    }

    private func startDownload(episode: Episode) {
        serviceProvider.showsDataProvider
            .loadEpisod(episodId: episode.id,
                        onSuccess: { (episode) in
                            if episode!.downloadUrl != nil {
                                DownloadFlow(serviceProvider: self.serviceProvider)
                                    .start(episode: episode!)
                            }
            }, onError: { (_) in })
    }
}
