//
//  DownloadFlow.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit
import Ororo_Kit

final class DownloadFlow {

    // MARK: - Properties
    private let serviceProvider: ServiceProvider

    // MARK: - Life cycle
    init(serviceProvider: ServiceProvider) {
        self.serviceProvider = serviceProvider
    }

    // MARK: - Public interface
    func start(episode: Episode) {

        saveLoadingState(episode: episode)

        let group = DispatchGroup()

        let fileName = episode.downloadUrl!.md5()
        let cachePath = PathBuilder.videoFilePath(fileName: fileName)

        prepareDirectory(for: cachePath)

        group.enter()
        serviceProvider.downloader
            .download(with: CustomEndpoint(path: episode.downloadUrl!)) { (url) in
                try? FileManager.default.moveItem(at: url,
                                                  to: cachePath)
                group.leave()
        }

        let subtitlePath = PathBuilder.subtitleFilePath(fileName: fileName)
        prepareDirectory(for: subtitlePath)

        let _subtitle = episode.subtitles?.first { $0.lang == "en" }
        guard let subtitle = _subtitle else { return }

        group.enter()
        serviceProvider.downloader
            .download(with: CustomEndpoint(path: subtitle.url!)) { (url) in
                try? FileManager.default.moveItem(at: url,
                                                  to: subtitlePath)
                group.leave()
        }

        group.notify(queue: .main) {
            self.save(fileId: fileName, episode: episode)
        }
    }

    // MARK: - Private functions
    private func save(fileId: String, episode: Episode) {
        serviceProvider.storageService
            .performAsync(transaction: { (context) in
                let episodes = context.fetchAll("id == %@",
                                                arguments: [episode.id]) as [CDEpisode]?
                if let episode = episodes?.first {
                    episode.downloadedId = fileId
                }
            })
    }

    private func saveLoadingState(episode: Episode) {
        serviceProvider.storageService
            .performAsync(transaction: { (context) in
                let episodes = context.fetchAll("id == %@",
                                                arguments: [episode.id]) as [CDEpisode]?

                if let episode = episodes?.first {
                    episode.isDownloading = true
                }
            })
    }

    private func prepareDirectory(for path: URL) {
        if FileManager.default.fileExists(atPath: path.path) {
            try? FileManager.default.removeItem(at: path)
        } else {
            let dirPath = (path.path as NSString).deletingLastPathComponent
            if !FileManager.default.fileExists(atPath: dirPath) {
                try? FileManager.default.createDirectory(atPath: dirPath,
                                                         withIntermediateDirectories: true,
                                                         attributes: nil)
            }
        }
    }
}
