//
//  ServiceProvider.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/6/19.
//  Copyright © 2019 Max Ovtsin. All rights reserved.
//

import Foundation
import OroroKit

final class ServiceProvider {

    let storageService: StorageService
    let network: NetworkRequestsService
    let downloader: NetworkDownloadsService

    let moviesDataProvider: MoviesDataProvider
    let showsDataProvider: SeriesDataProvider

    let downloadManager: DownloadManager

    init(credentials: Credentials) {
        storageService = StorageService(modelName: "Ororo")
        network = NetworkService(
            requestBuilder: RequestBuilder(
                headers: ["Accept": "application/json"],
                credentials: credentials,
                httpMethod: .get
            )
        )

        downloader = NetworkService(
            requestBuilder: RequestBuilder()
        )
        moviesDataProvider = MoviesDataProvider(
            networkService: network,
            storageService: storageService
        )
        showsDataProvider = SeriesDataProvider(
            networkService: network,
            storageService: storageService
        )

        downloadManager = DownloadManager(
            storageService: storageService,
            downloader: downloader,
            showsDataProvider: showsDataProvider
        )
    }
}
