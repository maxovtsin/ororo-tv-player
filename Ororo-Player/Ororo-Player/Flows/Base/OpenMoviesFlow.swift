//
//  OpenMoviesFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import OroroKit
import Transitions

final class OpenMoviesFlow: Flow {

    struct Injection {
        let items: [Searchable]
        let serviceProvider: ServiceProvider
    }

    // MARK: - Flow
    let coordinator: Coordinator
    unowned var serviceProvider: ServiceProvider!

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
    }

    func start(
        injection: Injection,
        transitionHandler: TransitionHandler
        ) {

        serviceProvider = injection.serviceProvider

        let movies = injection.items.sorted { $0.title < $1.title }
        let moviesController = SearchViewController(output: self)
        moviesController.title = "movies".localized()
        moviesController.configure(with: movies)
        let navigationController = UINavigationController(
            rootViewController: moviesController
        )

        transitionHandler.present(
            flow: self,
            transition: BaseTransition.inTabBar,
            params: (
                navigationController,
                UIImage(named: "movies.tabbar.icon")
            )
        )
    }
}

extension OpenMoviesFlow: SearchViewOutput {

    func didPressLong(model: Searchable) {
        guard let movie = model.model as? Movie else { return }
        coordinator.show(
            OpenMovieFlow.self,
            injection: OpenMovieFlow.Injection(
                movie: movie,
                serviceProvider: serviceProvider,
                isLongPressed: true
            )
        )
    }

    func didPress(model: Searchable) {
        guard let movie = model.model as? Movie else { return }
        coordinator.show(
            OpenMovieFlow.self,
            injection: OpenMovieFlow.Injection(
                movie: movie,
                serviceProvider: serviceProvider,
                isLongPressed: false
            )
        )
    }
}
