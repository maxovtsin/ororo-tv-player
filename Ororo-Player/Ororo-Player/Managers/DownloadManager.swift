//
//  DownloadManager.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/6/19.
//  Copyright © 2019 Max Ovtsin. All rights reserved.
//

import Foundation
import OroroKit

final class DownloadManager {

    // MARK: - Flow
    private let storageService: StorageService
    private let downloader: NetworkDownloadsService
    private let showsDataProvider: SeriesDataProvider

    init(
        storageService: StorageService,
        downloader: NetworkDownloadsService,
        showsDataProvider: SeriesDataProvider
        ) {
        self.storageService = storageService
        self.downloader = downloader
        self.showsDataProvider = showsDataProvider
    }

    func startDownload(
        episode: Episode
        ) {
        showsDataProvider
            .loadEpisod(episodId: episode.id,
                        onSuccess: { [weak self] (episode) in
                            if let episode = episode,
                                episode.downloadUrl != nil {
                                self?.download(episode: episode)
                            }
                }, onError: { (_) in })
    }

    // MARK: - Private functions

    private func download(
        episode: Episode
        ) {

        saveLoadingState(episode: episode)

        let group = DispatchGroup()

        let fileName = episode.downloadUrl!.md5
        let cachePath = PathBuilder.videoFilePath(fileName: fileName)

        prepareDirectory(for: cachePath)

        group.enter()
        downloader
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
        downloader.download(with: CustomEndpoint(path: subtitle.url!)) { (url) in
            try? FileManager.default.moveItem(at: url,
                                              to: subtitlePath)
            group.leave()
        }

        group.notify(queue: .main) {
            self.save(fileId: fileName, episode: episode)
        }
    }

    private func save(fileId: String, episode: Episode) {
        storageService.performAsync(transaction: { (context) in
            let episodes = context.fetchAll(
                "id == %@",
                arguments: [episode.id]
                ) as [CDEpisode]?
            if let episode = episodes?.first {
                episode.downloadedId = fileId
            }
        })
    }

    private func saveLoadingState(episode: Episode) {
        storageService.performAsync(transaction: { (context) in
            let episodes = context.fetchAll(
                "id == %@",
                arguments: [episode.id]
                ) as [CDEpisode]?

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
                try? FileManager.default.createDirectory(
                    atPath: dirPath,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }
        }
    }
}
