//
//  OpenSearchFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import OroroKit
import Transitions

final class OpenSearchFlow: Flow {

    struct Injection {
        let movies: [Searchable]
        let shows: [Searchable]
        let serviceProvider: ServiceProvider
    }

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

        let searchViewController = SearchViewController(output: self)
        let content = (injection.movies + injection.shows)
            .sorted { $0.title < $1.title }

        searchViewController.configure(with: content)

        let viewController = getSearchController(
            searchViewController: searchViewController
        )
        #if os(iOS)
        searchViewController.title = "search".localized()
        #endif

        transitionHandler.present(
            flow: self,
            transition: BaseTransition.inTabBar,
            params: (
                viewController,
                UIImage(named: "search.tabbar.icon")
            )
        )
    }

    // MARK: - Private functions
    #if os(iOS)
    private func getSearchController(
        searchViewController: SearchViewController
        ) -> UINavigationController {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = searchViewController
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.dimsBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "search_placeholder".localized()
        searchViewController.navigationItem.searchController = searchController

        let searchNavController = UINavigationController(
            rootViewController: searchViewController
        )

        return searchNavController
    }
    #endif

    #if os(tvOS)
    private func getSearchController(
        searchViewController: SearchViewController
        ) -> UINavigationController {
        let searchController = UISearchController(
            searchResultsController: searchViewController
        )
        searchController.searchResultsUpdater = searchViewController
        searchController.title = "search".localized()
        searchController.searchBar.placeholder = "search_placeholder".localized()
        searchController.view.backgroundColor = .gray
        searchController.searchBar.keyboardAppearance = .dark

        let searchContainerViewController = UISearchContainerViewController(
            searchController: searchController
        )
        searchContainerViewController.title = "search".localized()
        searchContainerViewController.view.backgroundColor = .black

        let searchNavController = UINavigationController(
            rootViewController: searchContainerViewController
        )
        return searchNavController
    }
    #endif
}

extension OpenSearchFlow: SearchViewOutput {

    func didPressLong(model: Searchable) {
        if let show = model.model as? Show {
            coordinator.show(
                OpenShowFlow.self,
                injection: OpenShowFlow.Injection(
                    show: show,
                    serviceProvider: serviceProvider,
                    comletion: nil,
                    isLongPressed: true
                )
            )
        } else if let movie = model.model as? Movie {
            coordinator.show(
                OpenMovieFlow.self,
                injection: OpenMovieFlow.Injection(
                    movie: movie,
                    serviceProvider: serviceProvider,
                    isLongPressed: true
                )
            )
        }
    }

    func didPress(model: Searchable) {
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
        }
    }
}
