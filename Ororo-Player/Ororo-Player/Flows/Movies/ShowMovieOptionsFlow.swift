//
//  ShowMovieOptionsFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Ororo_Kit

final class ShowMovieOptionsFlow {

    // MARK: - Properties
    private let transitionHandler: TransitionHandler
    private let serviceProvider: ServiceProvider

    lazy var openPlayerFlow: OpenPlayerFlow = {
        return OpenPlayerFlow(transitionHandler: transitionHandler,
                              serviceProvider: serviceProvider)
    }()

    // MARK: - Life cycle
    init(transitionHandler: TransitionHandler,
         serviceProvider: ServiceProvider) {
        self.transitionHandler = transitionHandler
        self.serviceProvider = serviceProvider
    }

    // MARK: - Flow interface
    public func start(movie: Movie, completion: (() -> Void)?) {
        let alertController = UIAlertController(title: nil,
                                                message: nil,
                                                preferredStyle: .actionSheet)

        if let isFavourite = movie.isFavourite, isFavourite {
            let favouriteAction = UIAlertAction(title: "remove_from_favorites".localized(),
                                                style: .default) { (_) in
                                                    self.updateFavourites(movie: movie,
                                                                          isFavourite: false,
                                                                          completion: completion)
            }
            alertController.addAction(favouriteAction)
        } else {
            let favouriteAction = UIAlertAction(title: "add_to_favorites".localized(),
                                                style: .default) { (_) in
                                                    self.updateFavourites(movie: movie,
                                                                          isFavourite: true,
                                                                          completion: completion)
            }
            alertController.addAction(favouriteAction)
        }

        let cancelAction = UIAlertAction(title: "cancel".localized(),
                                         style: .cancel) { (_) in }

        alertController.addAction(cancelAction)

        transitionHandler.present(viewController: alertController, modally: true)
    }

    // MARK: - Private functions
    private func updateFavourites(movie: Movie, isFavourite: Bool, completion: (() -> Void)?) {
        serviceProvider.storageService
            .performAsync(transaction: { (context) in
                let movie = context.fetchOne("id == %@",
                                             arguments: [movie.id]) as CDMovie?
                movie?.isFavourite = NSNumber(value: isFavourite)
            }, completion: completion)
    }
}
