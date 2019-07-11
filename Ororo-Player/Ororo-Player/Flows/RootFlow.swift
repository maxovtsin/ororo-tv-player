//
//  RootFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import OroroKit
import Transitions

final class RootFlow: Flow {

    // MARK: - Properties
    private let tabBarViewController = UITabBarController()

    // MARK: - Flow
    let coordinator: Coordinator

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
    }

    func start(
        injection: Injection,
        transitionHandler: TransitionHandler
        ) {

        let group = DispatchGroup()

        let serviceProvider = injection.serviceProvider

        var _shows: [Searchable]?
        var _movies: [Searchable]?

        group.enter()
        serviceProvider.showsDataProvider
            .loadAllShows(onSuccess: { (shows) in
                _shows = shows?.map { Searchable(model: $0) }
                group.leave()
            }, onError: { (_) in
                group.leave()
            })

        group.enter()
        serviceProvider.moviesDataProvider
            .loadMovies(onSuccess: { (movies) in
                _movies = movies?.map { Searchable(model: $0) }
                group.leave()
            }, onError: { (_) in
                group.leave()
            })

        group.notify(queue: .main) {
            self.present(
                serviceProvider: serviceProvider,
                movies: _movies!,
                shows: _shows!
            )
        }

        transitionHandler.present(
            flow: self,
            transition: BaseTransition.root,
            params: tabBarViewController
        )
    }

    // MARK: - Private functions

    private func present(
        serviceProvider: ServiceProvider,
        movies: [Searchable],
        shows: [Searchable]
        ) {

        coordinator.show(
            OpenSearchFlow.self,
            injection: OpenSearchFlow.Injection(
                movies: movies,
                shows: shows,
                serviceProvider: serviceProvider
            )
        )

        coordinator.show(
            OpenMoviesFlow.self,
            injection: OpenMoviesFlow.Injection(
                items: movies,
                serviceProvider: serviceProvider
            )
        )

        coordinator.show(
            OpenShowsFlow.self,
            injection: OpenShowsFlow.Injection(
                items: shows,
                serviceProvider: serviceProvider
            )
        )

        #if os(iOS)
        coordinator.show(
            OpenDownloadsFlow.self,
            injection: serviceProvider
        )
        #elseif os(tvOS)
        coordinator.show(
            OpenFavoritesFlow.self,
            injection: serviceProvider
        )
        #endif
    }

    // MARK: - Inner type
    struct Injection {
        let serviceProvider: ServiceProvider
    }
}
