//
//  RootFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Ororo_Kit

final class RootFlow: TransitionHandler {

    // MARK: - Properties
    private let serviceProvider = ServiceProvider(credentials:
        Credentials(
            username: "test@example.com",
            password: "password"
        )
    )

    private let window = UIWindow(frame: UIScreen.main.bounds)
    let tabBarViewController = UITabBarController()

    lazy var openShowsFlow: OpenShowsFlow = {
        return OpenShowsFlow(transitionHandler: self,
                             serviceProvider: serviceProvider)
    }()
    lazy var openSearchFlow: OpenSearchFlow = {
        return OpenSearchFlow(transitionHandler: self,
                              serviceProvider: serviceProvider)
    }()
    lazy var openMoviesFlow: OpenMoviesFlow = {
        return OpenMoviesFlow(transitionHandler: self,
                              serviceProvider: serviceProvider)
    }()
    lazy var openDownloadsFlow: OpenDownloadsFlow = {
        return OpenDownloadsFlow(transitionHandler: self,
                                 serviceProvider: serviceProvider)
    }()

    lazy var openFavoritesFlow: OpenFavoritesFlow = {
        return OpenFavoritesFlow(transitionHandler: self,
                                  serviceProvider: serviceProvider)
    }()

    // MARK: - Life cycle

    init() {
        window.rootViewController = BaseViewController<SearchCollectionViewCellPresenter>()
        window.rootViewController?.view.backgroundColor = .gray
        window.makeKeyAndVisible()
    }

    // MARK: - Flow
    func start() {
        loadItems { (movies, shows) in
            self.present(movies: movies, shows: shows)
        }
    }

    // MARK: - Private functions

    private func present(movies: [Searchable], shows: [Searchable]) {

        let searchViewController = openSearchFlow.start(movies: movies, shows: shows)
        let moviesViewController = openMoviesFlow.start(movies: movies)
        let showsViewController = openShowsFlow.start(shows: shows)

        #if os(iOS)
        let downloadsViewController = openDownloadsFlow.start()
        #elseif os(tvOS)
        let favouritesViewController = openFavoritesFlow.start()
        #endif

        var viewControllers = [showsViewController, moviesViewController, searchViewController]

        #if os(iOS)
        viewControllers.append(downloadsViewController)
        #elseif os(tvOS)
        viewControllers.append(favouritesViewController)
        #endif

        tabBarViewController.setViewControllers(viewControllers,
                                                animated: false)

        let items = tabBarViewController.tabBar.items!
        items[0].image = UIImage(named: "series.tabbar.icon")
        items[1].image = UIImage(named: "movies.tabbar.icon")
        items[2].image = UIImage(named: "search.tabbar.icon")

        #if os(iOS)
        items[3].image = UIImage(named: "downloads.tabbar.icon")
        #endif

        window.rootViewController = tabBarViewController
    }

    func loadItems(completion: @escaping ([Searchable], [Searchable]) -> Void) {

        var shows: [Searchable]?
        var movies: [Searchable]?

        let group = DispatchGroup()

        group.enter()
        serviceProvider.showsDataProvider
            .loadAllShows(onSuccess: {
                shows = $0?.map { Searchable(model: $0) }
                group.leave()
            }, onError: { (_) in
                group.leave()
            })

        group.enter()
        serviceProvider.moviesDataProvider
            .loadMovies(onSuccess: {
                movies = $0?.map { Searchable(model: $0) }
                group.leave()
            }, onError: { (_) in
                group.leave()
            })

        group.notify(queue: .main) {
            completion(movies ?? [], shows ?? [])
        }
    }
}
