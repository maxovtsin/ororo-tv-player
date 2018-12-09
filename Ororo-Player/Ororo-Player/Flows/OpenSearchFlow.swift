//
//  OpenSearchFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Ororo_Kit

class OpenSearchFlow {

    // MARK: - Properties
    lazy var openMovieFlow: OpenMovieFlow = {
        return OpenMovieFlow(transitionHandler: transitionHandler,
                             serviceProvider: serviceProvider)
    }()
    lazy var openShowFlow: OpenShowFlow = {
        return OpenShowFlow(transitionHandler: transitionHandler,
                            serviceProvider: serviceProvider)
    }()
    private let transitionHandler: TransitionHandler
    private let serviceProvider: ServiceProvider

    // MARK: - Life cycle
    init(transitionHandler: TransitionHandler,
         serviceProvider: ServiceProvider) {
        self.transitionHandler = transitionHandler
        self.serviceProvider = serviceProvider
    }

    // MARK: - Public interface
    func start(movies: [Searchable], shows: [Searchable]) -> UINavigationController {

        let searchViewController = SearchViewController(output: self)
        let content = (movies + shows).sorted { $0.title < $1.title }

        searchViewController.configure(with: content)

        #if os(iOS)
        searchViewController.title = "Search"

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = searchViewController
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.dimsBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search shows..."
        searchViewController.navigationItem.searchController = searchController

        let searchNavController = UINavigationController(rootViewController: searchViewController)

        return searchNavController
        #elseif os(tvOS)
        let searchController = UISearchController(searchResultsController: searchViewController)
        searchController.searchResultsUpdater = searchViewController
        searchController.title = "Search"
        searchController.searchBar.placeholder = "Type something here"
        searchController.view.backgroundColor = .gray
        searchController.searchBar.keyboardAppearance = .dark

        let searchContainerViewController = UISearchContainerViewController(searchController: searchController)
        searchContainerViewController.title = "Search"
        searchContainerViewController.view.backgroundColor = .black

        let searchNavController = UINavigationController(rootViewController: searchContainerViewController)
        return searchNavController
        #endif
    }
}

extension OpenSearchFlow: SearchViewOutput {
    func didPressLong(model: Searchable) {

        if let show = model.model as? Show {
            openShowFlow.startWithLongPress(show: show)
        } else if let movie = model.model as? Movie {
            openMovieFlow.startWithLongPress(movie: movie)
        }
    }

    func didPress(model: Searchable) {

        if let show = model.model as? Show {
            openShowFlow.start(show: show)
        } else if let movie = model.model as? Movie {
            openMovieFlow.start(movie: movie)
        }
    }
}
