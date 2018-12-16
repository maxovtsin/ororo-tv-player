//
//  StartPlayingEpisodeFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Ororo_Kit

class StartPlayingEpisodeFlow {

    // MARK: - Properties
    private let transitionHandler: TransitionHandler
    private let serviceProvider: ServiceProvider

    lazy var openPlayerFlow: OpenPlayerFlow = {
        return OpenPlayerFlow(transitionHandler: transitionHandler,
                              serviceProvider: serviceProvider)
    }()

    // MARK: - Life cycle
    init(transitionHandler: TransitionHandler,
         serviceProvider: ServiceProvider) {
        self.transitionHandler = transitionHandler
        self.serviceProvider = serviceProvider
    }

    // MARK: - Flow
    func start(episode: Episode) {
        serviceProvider.showsDataProvider
            .loadEpisod(episodId: episode.id,
                        onSuccess: { (episod) in
                            if let url = episod?.url,
                                let url_ = URL(string: url),
                                let subtitles = episod?.subtitles {

                                let playable = OpenPlayerFlow.Playable(url: url_,
                                                                       subtitles: subtitles,
                                                                       subtitle: nil,
                                                                       lang: "en",
                                                                       progress: episode.playbackProgress ?? 0.0)

                                self.openPlayerFlow
                                    .start(playable: playable,
                                           progressObserver: { (progress) in
                                            self.updateProgress(episode: episode, progress: progress)
                                    })
                            }
            }, onError: { (_) in

            })
    }

    // MARK: - Private functions
    private func updateProgress(episode: Episode,
                                progress: Float64) {
        serviceProvider.storageService
            .performAsync(transaction: { (context) in
                let episode = context.fetchOne("id == %@",
                                               arguments: [episode.id]) as CDEpisode?
                episode?.playbackProgress = progress
            })
    }
}
