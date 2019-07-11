//
//  ShowMovieOptionsFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import OroroKit
import Transitions

final class ShowMovieOptionsFlow: Flow {

    struct Injection {
        let movie: Movie
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
        let alertController = UIAlertController(
            title: nil,
            message: nil,
            preferredStyle: .actionSheet
        )

        if let isFavourite = injection.movie.isFavourite,
            isFavourite {
            let favouriteAction = UIAlertAction(
                title: "remove_from_favorites".localized(),
                style: .default) { (_) in
                    self.updateFavourites(
                        movie: injection.movie,
                        isFavourite: false,
                        serviceProvider: injection.serviceProvider,
                        completion: injection.completion
                    )
            }
            alertController.addAction(favouriteAction)
        } else {
            let favouriteAction = UIAlertAction(
                title: "add_to_favorites".localized(),
                style: .default) { (_) in
                    self.updateFavourites(
                        movie: injection.movie,
                        isFavourite: true,
                        serviceProvider: injection.serviceProvider,
                        completion: injection.completion
                    )
            }
            alertController.addAction(favouriteAction)
        }

        let cancelAction = UIAlertAction(title: "cancel".localized(),
                                         style: .cancel) { (_) in }

        alertController.addAction(cancelAction)

        transitionHandler.present(
            flow: self,
            transition: BaseTransition.modal,
            params: alertController
        )
    }

    // MARK: - Private functions
    private func updateFavourites(
        movie: Movie,
        isFavourite: Bool,
        serviceProvider: ServiceProvider,
        completion: (() -> Void)?
        ) {
        serviceProvider.storageService
            .performAsync(transaction: { (context) in
                let movie = context.fetchOne("id == %@",
                                             arguments: [movie.id]) as CDMovie?
                movie?.isFavourite = NSNumber(value: isFavourite)
            }, completion: completion)
    }
}
