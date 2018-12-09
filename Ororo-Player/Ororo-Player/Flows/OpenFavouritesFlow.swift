//
//  OpenFavouritesFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Ororo_Kit
import CoreData

final class OpenFavouritesFlow {

    // MARK: - Properties
    private let transitionHandler: TransitionHandler
    private let viewController = BaseViewController<SearchCollectionViewCellPresenter>()
    private let serviceProvider: ServiceProvider

    lazy var showMovieOptionsFlow: ShowMovieOptionsFlow = {
        return ShowMovieOptionsFlow(transitionHandler: transitionHandler,
                                    serviceProvider: serviceProvider)
    }()
    lazy var showShowOptionsFlow: ShowShowOptionsFlow = {
        return ShowShowOptionsFlow(transitionHandler: transitionHandler,
                                   serviceProvider: serviceProvider)
    }()
    lazy var openMovieFlow: OpenMovieFlow = {
        return OpenMovieFlow(transitionHandler: transitionHandler,
                             serviceProvider: serviceProvider)
    }()
    lazy var openShowFlow: OpenShowFlow = {
        return OpenShowFlow(transitionHandler: transitionHandler,
                            serviceProvider: serviceProvider)
    }()
    lazy var startPlayingEpisodeFlow: StartPlayingEpisodeFlow = {
        return StartPlayingEpisodeFlow(transitionHandler: transitionHandler,
                                       serviceProvider: serviceProvider)
    }()

    // MARK: - Life cycle
    init(transitionHandler: TransitionHandler,
         serviceProvider: ServiceProvider) {
        self.transitionHandler = transitionHandler
        self.serviceProvider = serviceProvider
    }

    // MARK: - Flow
    func start() -> UINavigationController {
        viewController.title = "Favourites"
        viewController.tap = { (model) in
            self.didPress(model: model)
        }
        viewController.longTap = { (model) in
            self.didPressLong(model: model)
        }
        viewController.viewWillAppear = {
            self.viewWillAppear()
        }

        updateViewController()

        return UINavigationController(rootViewController: viewController)
    }

    // MARK: - Private functions
    private func obtainFavouriteMovies() -> [Searchable] {
        guard let movies = serviceProvider.storageService
            .fetchAll("isFavourite == YES", arguments: []) as [CDMovie]? else { return [] }
        return movies
            .compactMap { Movie(movie: $0) }
            .map { Searchable(model: $0) }
    }

    private func obtainFavouriteShows() -> [Searchable] {
        guard let shows = serviceProvider.storageService
            .fetchAll("isFavourite == YES", arguments: []) as [CDShow]? else { return [] }
        return shows
            .compactMap { Show(show: $0) }
            .map { Searchable(model: $0) }
    }

    private func obtainItemsInProgress() -> [Searchable] {
        let movies = serviceProvider.storageService
            .fetchAll("playbackProgress < 0.9 AND playbackProgress != 0",
                      arguments: []) as [CDMovie]?
        let episodes = serviceProvider.storageService
            .fetchAll("playbackProgress < 0.9 AND playbackProgress != 0",
                      arguments: []) as [CDEpisode]?

        let _movies = movies?
            .map { Movie(movie: $0) }
            .map { Searchable(model: $0) } ?? []
        let _episodes = episodes?
            .map { Episode(episode: $0) }
            .map { Searchable(model: $0) } ?? []

        return _movies + _episodes
    }

    private func didPress(model: Searchable) {
        if let show = model.model as? Show {
            openShowFlow.start(show: show)
        } else if let movie = model.model as? Movie {
            openMovieFlow.start(movie: movie)
        } else if let episode = model.model as? Episode {
            startPlayingEpisodeFlow.start(episode: episode)
        }
    }

    private func didPressLong(model: Searchable) {
        if let show = model.model as? Show {
            showShowOptionsFlow.start(show: show) {
                self.viewWillAppear()
            }
        } else if let movie = model.model as? Movie {
            showMovieOptionsFlow.start(movie: movie) {
                self.viewWillAppear()
            }
        } else if let episode = model.model as? Episode {
            showShowOptionsFlow.start(episode: episode) {
                self.viewWillAppear()
            }
        }
    }

    private func updateViewController() {
        let movies = obtainFavouriteMovies()
        let shows = obtainFavouriteShows()
        let inProgress = obtainItemsInProgress()
        var favourites: [Searchable] = inProgress + movies + shows
        favourites.sort(by: { $0.title > $1.title })
        viewController.configure(with: favourites)
    }

    private func viewWillAppear() {
        updateViewController()
    }
}
