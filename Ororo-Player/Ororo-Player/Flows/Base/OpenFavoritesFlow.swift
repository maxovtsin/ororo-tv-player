//
//  OpenFavoritesFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import OroroKit
import CoreData
import Transitions

final class OpenFavoritesFlow: Flow {

    typealias ViewController = BaseViewController<
        SearchCollectionViewCellPresenter
    >

    // MARK: - Flow
    let coordinator: Coordinator

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
    }

    func start(
        injection: ServiceProvider,
        transitionHandler: TransitionHandler
        ) {

        let viewController = ViewController()

        viewController.title = "favorites".localized()
        viewController.tap = { (model) in
            self.didPress(
                model: model,
                serviceProvider: injection
            )
        }
        viewController.longTap = { (model) in
            self.didPressLong(
                model: model,
                viewController: viewController,
                serviceProvider: injection
            )
        }
        viewController.viewWillAppear = {
            self.viewWillAppear(
                viewController: viewController,
                serviceProvider: injection
            )
        }

        update(
            viewController: viewController,
            with: injection
        )

        let navigationController = UINavigationController(
            rootViewController: viewController
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

    // MARK: - Private functions
    private func obtainFavouriteMovies(
        storageService: StorageService
        ) -> [Searchable] {
        guard let movies = storageService
            .fetchAll(
                "isFavourite == YES",
                arguments: []
            ) as [CDMovie]? else { return [] }
        return movies
            .compactMap { Movie(movie: $0) }
            .map { Searchable(model: $0) }
    }

    private func obtainFavouriteShows(
        storageService: StorageService
        ) -> [Searchable] {
        guard let shows = storageService
            .fetchAll(
                "isFavourite == YES",
                arguments: []
            ) as [CDShow]? else { return [] }
        return shows
            .compactMap { Show(show: $0) }
            .map { Searchable(model: $0) }
    }

    private func obtainItemsInProgress(
        storageService: StorageService
        ) -> [Searchable] {
        let movies = storageService
            .fetchAll(
                "playbackProgress < 0.9 AND playbackProgress != 0",
                arguments: []
            ) as [CDMovie]?
        let episodes = storageService
            .fetchAll(
                "playbackProgress < 0.9 AND playbackProgress != 0",
                arguments: []
            ) as [CDEpisode]?

        let _movies = movies?
            .map { Movie(movie: $0) }
            .map { Searchable(model: $0) } ?? []
        let _episodes = episodes?
            .map { Episode(episode: $0) }
            .map { Searchable(model: $0) } ?? []

        return _movies + _episodes
    }

    private func didPress(
        model: Searchable,
        serviceProvider: ServiceProvider
        ) {

        if let show = model.model as? Show {
            coordinator.show(
                OpenShowFlow.self,
                injection: OpenShowFlow.Injection(
                    show: show,
                    serviceProvider: serviceProvider,
                    comletion: nil,
                    isLongPressed: false
                )
            )
        } else if let movie = model.model as? Movie {
            coordinator.show(
                OpenMovieFlow.self,
                injection: OpenMovieFlow.Injection(
                    movie: movie,
                    serviceProvider: serviceProvider,
                    isLongPressed: false
                )
            )
        } else if let episode = model.model as? Episode {
            coordinator.show(
                StartPlayingEpisodeFlow.self,
                injection: StartPlayingEpisodeFlow.Injection(
                    episode: episode,
                    serviceProvider: serviceProvider
                )
            )
        }
    }

    private func didPressLong(
        model: Searchable,
        viewController: ViewController,
        serviceProvider: ServiceProvider
        ) {
        if let show = model.model as? Show {
            coordinator.show(
                OpenShowFlow.self,
                injection: OpenShowFlow.Injection(
                    show: show,
                    serviceProvider: serviceProvider,
                    comletion: {
                        self.viewWillAppear(
                            viewController: viewController,
                            serviceProvider: serviceProvider
                        )
                },
                    isLongPressed: true
                )
            )
        } else if let movie = model.model as? Movie {
            coordinator.show(
                ShowMovieOptionsFlow.self,
                injection: ShowMovieOptionsFlow.Injection(
                    movie: movie,
                    serviceProvider: serviceProvider,
                    completion: {
                        self.viewWillAppear(
                            viewController: viewController,
                            serviceProvider: serviceProvider
                        )
                }
                )
            )
        } else if let episode = model.model as? Episode {
            coordinator.show(
                ShowEpisodeOptionsFlow.self,
                injection: ShowEpisodeOptionsFlow.Injection(
                    episode: episode,
                    serviceProvider: serviceProvider,
                    completion: {
                        self.viewWillAppear(
                            viewController: viewController,
                            serviceProvider: serviceProvider
                        )
                }
                )
            )
        }
    }

    private func update(
        viewController: ViewController,
        with serviceProvider: ServiceProvider
        ) {
        let movies = obtainFavouriteMovies(
            storageService: serviceProvider.storageService
        )
        let shows = obtainFavouriteShows(
            storageService: serviceProvider.storageService
        )
        let inProgress = obtainItemsInProgress(
            storageService: serviceProvider.storageService
        )
        var favourites: [Searchable] = inProgress + movies + shows
        favourites.sort(by: { $0.title > $1.title })
        viewController.configure(with: favourites)
    }

    private func viewWillAppear(
        viewController: ViewController,
        serviceProvider: ServiceProvider
        ) {
        update(
            viewController: viewController,
            with: serviceProvider
        )
    }
}
