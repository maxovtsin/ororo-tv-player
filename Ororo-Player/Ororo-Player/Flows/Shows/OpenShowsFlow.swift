//
//  OpenShowsFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Ororo_Kit

class OpenShowsFlow {

    // MARK: - Properties
    private let transitionHandler: TransitionHandler
    private let serviceProvider: ServiceProvider

    lazy var openShowFlow: OpenShowFlow = {
        return OpenShowFlow(transitionHandler: transitionHandler,
                            serviceProvider: serviceProvider)
    }()

    // MARK: - Life cycle
    init(transitionHandler: TransitionHandler,
         serviceProvider: ServiceProvider) {
        self.transitionHandler = transitionHandler
        self.serviceProvider = serviceProvider
    }

    // MARK: - Flow
    func start(shows: [Searchable]) -> UINavigationController {
        let shows = shows.sorted { $0.title < $1.title }
        let showsViewController = SearchViewController(output: self)
        showsViewController.title = "Shows"
        showsViewController.configure(with: shows)
        return UINavigationController(rootViewController: showsViewController)
    }
}

extension OpenShowsFlow: SearchViewOutput {
    func didPressLong(model: Searchable) {
        guard let show = model.model as? Show else { return }
        openShowFlow.startWithLongPress(show: show)
    }

    func didPress(model: Searchable) {
        guard let show = model.model as? Show else { return }
        openShowFlow.start(show: show)
    }
}
