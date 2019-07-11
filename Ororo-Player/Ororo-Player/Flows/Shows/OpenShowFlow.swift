//
//  OpenShowFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import OroroKit
import Transitions

final class OpenShowFlow: Flow {

    struct Injection {
        let show: Show
        let serviceProvider: ServiceProvider
        let comletion: (() -> Void)?
        let isLongPressed: Bool
    }

    // MARK: - Life cycle
    let coordinator: Coordinator

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
    }

    func start(
        injection: Injection,
        transitionHandler: TransitionHandler
        ) {

        if injection.isLongPressed {
            #if os(tvOS)
            coordinator.show(
                ShowShowOptionsFlow.self,
                injection: ShowShowOptionsFlow.Injection(
                    show: injection.show,
                    serviceProvider: injection.serviceProvider,
                    completion: injection.comletion
                )
            )
            #endif
            return
        }

        let seasonsViewController = BaseViewController<SeasonCollectionViewCellPresenter>()
        seasonsViewController.title = injection.show.name

        seasonsViewController.tap = {
            self.didPress(
                model: $0,
                show: injection.show,
                transitionHandler: transitionHandler,
                serviceProvider: injection.serviceProvider
            )
        }

        load(
            show: injection.show,
            serviceProvider: injection.serviceProvider,
            completion: { (episodes) in
                seasonsViewController.configure(with: episodes)
        }
        )

        transitionHandler.present(
            flow: self,
            transition: BaseTransition.push,
            params: seasonsViewController
        )
    }

    // MARK: - Private functions

    private func didPress(
        model: Season,
        show: Show,
        transitionHandler: TransitionHandler,
        serviceProvider: ServiceProvider
        ) {

        let models = model.episodes
            .map { EpisodeModel(episode: $0, show: show) }
            .sorted(by: { Int($0.episode.number!)! < Int($1.episode.number!)! })

        let viewController = BaseViewController<EpisodeCollectionViewCellPresenter>()
        viewController.title = String(model.number) + " " + "season".localized()
        viewController.configure(with: models)

        viewController.tap = { [weak self] in
            self?.coordinator.show(
                StartPlayingEpisodeFlow.self,
                injection: StartPlayingEpisodeFlow.Injection(
                    episode: $0.episode,
                    serviceProvider: serviceProvider
                )
            )
        }

        viewController.longTap = { [weak self] in
            self?.coordinator.show(
                ShowEpisodeOptionsFlow.self,
                injection: ShowEpisodeOptionsFlow.Injection(
                    episode: $0.episode,
                    serviceProvider: serviceProvider,
                    completion: nil
                )
            )
        }

        transitionHandler.present(
            flow: self, transition:
            BaseTransition.push,
            params: viewController
        )
    }

    private func load(
        show: Show,
        serviceProvider: ServiceProvider,
        completion: @escaping ([Season]) -> Void
        ) {
        serviceProvider.showsDataProvider
            .loadShow(showId: show.id,
                      onSuccess: { (show) in
                        if let show = show,
                            let episodes = show.episodes, !episodes.isEmpty {
                            completion(self.parseSeasons(show: show))
                        }
            }, onError: { (_) in })
    }

    private func parseSeasons(show: Show) -> [Season] {
        var seasons = [Int: [Episode]]()
        for episode in show.episodes! {
            if let s = seasons[episode.season] {
                seasons[episode.season] = [episode] + s
            } else {
                seasons[episode.season] = [episode]
            }
        }
        let seasons_ = seasons
            .map { Season(number: $0.key, posterThumb: show.posterThumb, episodes: $0.value) }
            .sorted(by: { $0.number < $1.number })

        return seasons_
    }
}
