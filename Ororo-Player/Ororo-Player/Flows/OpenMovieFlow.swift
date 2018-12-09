//
//  OpenMovieFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Ororo_Kit

class OpenMovieFlow {

    // MARK: - Properties
    private let transitionHandler: TransitionHandler
    private let serviceProvider: ServiceProvider

    lazy var openOptionsFlow: ShowMovieOptionsFlow = {
        return ShowMovieOptionsFlow(transitionHandler: transitionHandler,
                                    serviceProvider: serviceProvider)
    }()
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
    func start(movie: Movie) {
        serviceProvider.moviesDataProvider
            .loadMovie(with: movie.id,
                       onSuccess: { (movie) in
                        self.startPlaying(movie: movie)
            }, onError: { (_) in })
    }

    func startWithLongPress(movie: Movie) {
        #if os(tvOS)
        openOptionsFlow.start(movie: movie, completion: nil)
        #endif
    }

    // MARK: - Private function
    private func startPlaying(movie: Movie?) {
        if let movie = movie,
            let url = movie.url,
            let _url = URL(string: url),
            let subtitles = movie.subtitles {

            let playable = OpenPlayerFlow.Playable(url: _url,
                                                   subtitles: subtitles,
                                                   subtitle: nil,
                                                   lang: "en",
                                                   progress: movie.playbackProgress ?? 0.0)

            self.openPlayerFlow
                .start(playable: playable,
                       progressObserver: { (progress) in
                        self.updateProgress(movie: movie,
                                            progress: progress)
                })
        }
    }

    private func updateProgress(movie: Movie,
                                progress: Float64) {
        serviceProvider.storageService
            .performAsync(transaction: { (context) in
                let movie = context.fetchOne("id == %@",
                                             arguments: [movie.id]) as CDMovie?
                movie?.playbackProgress = progress
            })
    }
}
