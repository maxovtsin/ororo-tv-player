//
//  OpenDownloadsFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import OroroKit
import Transitions

final class OpenDownloadsFlow: Flow {

    typealias ViewController = BaseViewController<
        DownloadEpisodeCellPresenter
    >

    // MARK: - Properties
    private var progresses = [String: Float]()

    // MARK: - Flow
    let coordinator: Coordinator

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
    }

    func start(
        injection: ServiceProvider,
        transitionHandler: TransitionHandler
        ) {

        let episodes = obtainDownloadedEpisodes(
            storageService: injection.storageService
        )

        let viewController = ViewController()
        viewController.title = "downloads".localized()
        viewController.tap = { (episode) in
            self.didPress(
                model: episode.episode,
                serviceProvider: injection
            )
        }

        viewController.viewWillAppear = {
            self.viewWillAppear(
                viewController: viewController,
                serviceProvider: injection
            )
        }

        viewController.configure(with: episodes)

        let navigationController = UINavigationController(
            rootViewController: viewController
        )

        transitionHandler.present(
            flow: self,
            transition: BaseTransition.inTabBar,
            params: (
                navigationController,
                UIImage(named: "downloads.tabbar.icon")!
            )
        )
    }

    // MARK: - Private functions
    private func obtainDownloadedEpisodes(
        storageService: StorageService
        ) -> [DownloadEpisodeModel] {

        let episodes = storageService
            .fetchAll(
                "isDownloading != NO OR downloadedId != NULL",
                arguments: []
            ) as [CDEpisode]?

        let downloads = episodes?
            .map { e -> DownloadEpisodeModel in
                let episode = Episode(episode: e)
                let progress: Float
                if let downloadUrl = episode.downloadUrl {
                    progress = self.progresses[downloadUrl] ?? 0.0
                } else {
                    progress = 0.0
                }
                let download = DownloadEpisodeModel(
                    episode: episode,
                    progress: progress
                )
                return download
            }
            .sorted(by: { Int($0.episode.number!)! < Int($1.episode.number!)! })

        return downloads ?? []
    }

    private func didPress(
        model: Episode,
        serviceProvider: ServiceProvider
        ) {
        
        let episode = serviceProvider.storageService
            .fetchOne("id == %@", arguments: [model.id]) as CDEpisode?
        guard let fileName = episode?.downloadedId else { return }

        let cachePath = PathBuilder.videoFilePath(fileName: fileName)
        let subtitlePath = PathBuilder.subtitleFilePath(fileName: fileName)

        guard let subData = try? Data(contentsOf: subtitlePath) else { return }

        let playable = OpenPlayerFlow.Playable(
            url: cachePath,
            subtitles: nil,
            subtitle: subData,
            lang: "en",
            progress: model.playbackProgress ?? 0.0
        )

        let injection = OpenPlayerFlow.Injection(
            playable: playable,
            serviceProvider: serviceProvider,
            progressUpdate: { (progress) in
                self.updateProgress(
                    episode: model,
                    progress: progress,
                    storageService: serviceProvider.storageService
                )
        })

        coordinator.show(
            OpenPlayerFlow.self,
            injection: injection
        )
    }

    private func viewWillAppear(
        viewController: ViewController,
        serviceProvider: ServiceProvider
        ) {
        let episodes = obtainDownloadedEpisodes(
            storageService: serviceProvider.storageService
        )
        viewController.configure(with: episodes)

        serviceProvider.downloader
            .addDownloadProgressObserver { (url, progress) in
                self.progresses[url] = progress
                let episodes = self.obtainDownloadedEpisodes(
                    storageService: serviceProvider.storageService
                )
                viewController.configure(with: episodes)
        }
    }

    private func updateProgress(
        episode: Episode,
        progress: Float64,
        storageService: StorageService
        ) {
        storageService.performAsync(transaction: { (context) in
            let episode = context.fetchOne(
                "id == %@",
                arguments: [episode.id]
                ) as CDEpisode?
            episode?.playbackProgress = progress
        })
    }
}
