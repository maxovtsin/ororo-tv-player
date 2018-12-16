//
//  OpenDownloadsFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Ororo_Kit

final class OpenDownloadsFlow {

    typealias ViewController = BaseViewController<DownloadEpisodeCellPresenter>

    // MARK: - Properties
    private let transitionHandler: TransitionHandler
    private var viewController = ViewController()
    private var progresses = [String: Float]()
    private let serviceProvider: ServiceProvider

    private lazy var openPlayerFlow: OpenPlayerFlow = {
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
    func start() -> UINavigationController {
        let episodes = obtainDownloadedEpisodes()

        viewController.title = "downloads".localized()

        viewController.tap = { (episode) in
            self.didPress(model: episode.episode)
        }

        viewController.viewWillAppear = {
            self.viewWillAppear()
        }

        viewController.configure(with: episodes)

        return UINavigationController(rootViewController: viewController)
    }

    // MARK: - Private functions
    private func obtainDownloadedEpisodes() -> [DownloadEpisodeModel] {
        let episodes = serviceProvider.storageService
            .fetchAll("isDownloading != NO OR downloadedId != NULL", arguments: []) as [CDEpisode]?

        let downloads = episodes?
            .map { e -> DownloadEpisodeModel in
                let episode = Episode(episode: e)
                let progress: Float
                if let downloadUrl = episode.downloadUrl {
                    progress = self.progresses[downloadUrl] ?? 0.0
                } else {
                    progress = 0.0
                }
                let download = DownloadEpisodeModel(episode: episode, progress: progress)
                return download
            }
            .sorted(by: { Int($0.episode.number!)! < Int($1.episode.number!)! })

        return downloads ?? []
    }

    private func didPress(model: Episode) {
        let episode = serviceProvider.storageService.fetchOne("id == %@", arguments: [model.id]) as CDEpisode?
        guard let fileName = episode?.downloadedId else { return }

        let cachePath = PathBuilder.videoFilePath(fileName: fileName)
        let subtitlePath = PathBuilder.subtitleFilePath(fileName: fileName)

        guard let subData = try? Data(contentsOf: subtitlePath) else { return }

        let playable = OpenPlayerFlow.Playable(url: cachePath,
                                               subtitles: nil,
                                               subtitle: subData,
                                               lang: "en",
                                               progress: model.playbackProgress ?? 0.0)

        self.openPlayerFlow
            .start(playable: playable,
                   progressObserver: { (progress) in
                    self.updateProgress(episode: model,
                                        progress: progress)
            })
    }

    private func viewWillAppear() {
        let episodes = obtainDownloadedEpisodes()
        viewController.configure(with: episodes)

        serviceProvider.downloader
            .addDownloadProgressObserver { (url, progress) in
                self.progresses[url] = progress
                let episodes = self.obtainDownloadedEpisodes()
                self.viewController.configure(with: episodes)
        }
    }

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
