//
//  ShowShowOptionsFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import OroroKit
import Transitions

final class ShowShowOptionsFlow: Flow {

    struct Injection {
        let show: Show
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

        let alertController = UIAlertController(title: nil,
                                                message: nil,
                                                preferredStyle: .actionSheet)

        if let isFavourite = injection.show.isFavourite, isFavourite {
            let favouriteAction = UIAlertAction(title: "remove_from_favorites".localized(),
                                                style: .default) { (_) in
                                                    self.updateFavourites(injection: injection,
                                                                          isFavourite: false)
            }
            alertController.addAction(favouriteAction)
        } else {
            let favouriteAction = UIAlertAction(title: "add_to_favorites".localized(),
                                                style: .default) { (_) in
                                                    self.updateFavourites(injection: injection,
                                                                          isFavourite: true)
            }
            alertController.addAction(favouriteAction)
        }

        let cancelAction = UIAlertAction(title: "cancel".localized(),
                                         style: .cancel) { (_) in }

        alertController.addAction(cancelAction)

        transitionHandler.present(
            flow: self,
            transition: BaseTransition.modal,
            params: alertController)
    }

    // MARK: - Private functions

    private func updateFavourites(injection: Injection, isFavourite: Bool) {
        injection.serviceProvider.storageService
            .performAsync(transaction: { (context) in
                let movie = context.fetchOne("id == %@",
                                             arguments: [injection.show.id]) as CDShow?
                movie?.isFavourite = NSNumber(value: isFavourite)
            }, completion: injection.completion)
    }
}
