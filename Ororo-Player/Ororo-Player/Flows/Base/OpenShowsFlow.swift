//
//  OpenShowsFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import OroroKit
import Transitions

final class OpenShowsFlow: Flow {

    struct Injection {
        let items: [Searchable]
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

        let shows = injection.items.sorted { $0.title < $1.title }
        let showsViewController = SearchViewController(output: self)
        showsViewController.title = "shows".localized()
        showsViewController.configure(with: shows)

        let navigationController = UINavigationController(
            rootViewController: showsViewController
        )

        transitionHandler.present(
            flow: self,
            transition: BaseTransition.inTabBar,
            params: (
                navigationController,
                UIImage(named: "series.tabbar.icon")
            )
        )
    }
}

extension OpenShowsFlow: SearchViewOutput {
    func didPressLong(model: Searchable) {
        guard let show = model.model as? Show else { return }
        coordinator.show(
            OpenShowFlow.self,
            injection: OpenShowFlow.Injection(
                show: show,
                serviceProvider: serviceProvider,
                comletion: nil,
                isLongPressed: true
            )
        )
    }

    func didPress(model: Searchable) {
        guard let show = model.model as? Show else { return }
        coordinator.show(
            OpenShowFlow.self,
            injection: OpenShowFlow.Injection(
                show: show,
                serviceProvider: serviceProvider,
                comletion: nil,
                isLongPressed: false
            )
        )
    }
}
