//
//  OpenMovieFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import OroroKit
import Transitions

final class OpenMovieFlow: Flow {

    struct Injection {
        let movie: Movie
        let serviceProvider: ServiceProvider
        let isLongPressed: Bool
    }

    // MARK: - Flow
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
                ShowMovieOptionsFlow.self,
                injection: ShowMovieOptionsFlow.Injection(
                    movie: injection.movie,
                    serviceProvider: injection.serviceProvider,
                    completion: nil
                )
            )
            #endif
            return
        }

        injection.serviceProvider.moviesDataProvider
            .loadMovie(
                with: injection.movie.id,
                onSuccess: { (movie) in
                    self.startPlaying(
                        movie: movie,
                        serviceProvider: injection.serviceProvider
                    )
            }, onError: { (_) in }
        )
    }

    // MARK: - Private function
    private func startPlaying(
        movie: Movie?,
        serviceProvider: ServiceProvider
        ) {
        if let movie = movie,
            let url = movie.url,
            let _url = URL(string: url),
            let subtitles = movie.subtitles {

            let playable = OpenPlayerFlow.Playable(
                url: _url,
                subtitles: subtitles,
                subtitle: nil,
                lang: "en",
                progress: movie.playbackProgress ?? 0.0
            )

            coordinator.show(
                OpenPlayerFlow.self,
                injection: OpenPlayerFlow.Injection(
                    playable: playable,
                    serviceProvider: serviceProvider,
                    progressUpdate: { (progress) in
                        self.updateProgress(
                            movie: movie,
                            serviceProvider: serviceProvider,
                            progress: progress
                        )
                })
            )
        }
    }

    private func updateProgress(
        movie: Movie,
        serviceProvider: ServiceProvider,
        progress: Float64
        ) {
        serviceProvider.storageService
            .performAsync(transaction: { (context) in
                let movie = context.fetchOne(
                    "id == %@",
                    arguments: [movie.id]
                    ) as CDMovie?
                movie?.playbackProgress = progress
            })
    }
}
