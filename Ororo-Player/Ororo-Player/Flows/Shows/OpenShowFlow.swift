//
//  OpenShowFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Ororo_Kit

class OpenShowFlow {

    // MARK: - Properties
    private let transitionHandler: TransitionHandler
    private let serviceProvider: ServiceProvider

    lazy var openPlayerFlow: OpenPlayerFlow = {
        return OpenPlayerFlow(transitionHandler: transitionHandler,
                              serviceProvider: serviceProvider)
    }()
    lazy var showShowOptionsFlow: ShowShowOptionsFlow = {
        return ShowShowOptionsFlow(transitionHandler: transitionHandler,
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

    func startWithLongPress(show: Show) {
        #if os(tvOS)
        showShowOptionsFlow.start(show: show, completion: nil)
        #endif
    }

    func start(show: Show) {
        let seasonsViewController = BaseViewController<SeasonCollectionViewCellPresenter>()
        seasonsViewController.title = show.name

        seasonsViewController.tap = {
            self.didPress(model: $0, show: show)
        }

        load(show: show) { (episodes) in
            seasonsViewController.configure(with: episodes)
        }

        transitionHandler.present(viewController: seasonsViewController, modally: false)
    }

    // MARK: - Private functions

    private func didPress(model: Season, show: Show) {

        let models = model.episodes
            .map { EpisodeModel(episode: $0, show: show) }
            .sorted(by: { Int($0.episode.number!)! < Int($1.episode.number!)! })

        let viewController = BaseViewController<EpisodeCollectionViewCellPresenter>()
        viewController.title = "\(model.number) Season"
        viewController.configure(with: models)

        viewController.tap = {
            self.startPlayingEpisodeFlow.start(episode: $0.episode)
        }

        viewController.longTap = {
            ShowShowOptionsFlow(transitionHandler: self.transitionHandler,
                                serviceProvider: self.serviceProvider)
                .start(episode: $0.episode)
        }

        transitionHandler.present(viewController: viewController, modally: false)
    }

    private func load(show: Show, completion: @escaping ([Season]) -> Void) {
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
