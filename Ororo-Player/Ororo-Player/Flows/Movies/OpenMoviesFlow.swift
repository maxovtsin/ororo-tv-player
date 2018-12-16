//
//  OpenMoviesFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Ororo_Kit

class OpenMoviesFlow {

    // MARK: - Properties
    lazy var openMovieFlow: OpenMovieFlow = {
        return OpenMovieFlow(transitionHandler: transitionHandler,
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

    // MARK: - Flow
    func start(movies: [Searchable]) -> UINavigationController {
        let movies = movies.sorted { $0.title < $1.title }
        let moviesController = SearchViewController(output: self)
        moviesController.title = "Movies"
        moviesController.configure(with: movies)
        return UINavigationController(rootViewController: moviesController)
    }
}

extension OpenMoviesFlow: SearchViewOutput {
    func didPressLong(model: Searchable) {
        guard let movie = model.model as? Movie else { return }
        openMovieFlow.startWithLongPress(movie: movie)
    }

    func didPress(model: Searchable) {
        guard let movie = model.model as? Movie else { return }
        openMovieFlow.start(movie: movie)
    }
}
