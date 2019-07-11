//
//  StartPlayingEpisodeFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import OroroKit
import Transitions

final class StartPlayingEpisodeFlow: Flow {

    struct Injection {
        let episode: Episode
        let serviceProvider: ServiceProvider
    }

    // MARK: - Flow
    let coordinator: Coordinator

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
    }

    func start(
        injection: Injection,
        transitionHandler: TransitionHandler) {

        injection.serviceProvider.showsDataProvider
            .loadEpisod(
                episodId: injection.episode.id,
                onSuccess: { (episod) in
                    self.didLoad(
                        episod: episod,
                        serviceProvider: injection.serviceProvider
                    )
                }, onError: { (_) in
                    //                    self?.transitionHandler.tabBarViewController
                    //                        .showToast(title: "error_title".localized())
            })
    }

    // MARK: - Private functions

    private func didLoad(
        episod: Episode?,
        serviceProvider: ServiceProvider
        ) {
        if let episod = episod,
            let url = episod.url,
            let url_ = URL(string: url),
            let subtitles = episod.subtitles {

            let playable = OpenPlayerFlow.Playable(
                url: url_,
                subtitles: subtitles,
                subtitle: nil,
                lang: "en",
                progress: episod.playbackProgress ?? 0
            )

            coordinator.show(
                OpenPlayerFlow.self,
                injection: OpenPlayerFlow.Injection(
                    playable: playable,
                    serviceProvider: serviceProvider,
                    progressUpdate: { (progress) in
                        self.updateProgress(
                            episode: episod,
                            serviceProvider: serviceProvider,
                            progress: progress)
                })
            )
        }
    }

    private func updateProgress(
        episode: Episode,
        serviceProvider: ServiceProvider,
        progress: Float64
        ) {
        serviceProvider.storageService
            .performAsync(transaction: { (context) in
                let episode = context.fetchOne(
                    "id == %@",
                    arguments: [episode.id]
                    ) as CDEpisode?
                episode?.playbackProgress = progress
            })
    }
}
