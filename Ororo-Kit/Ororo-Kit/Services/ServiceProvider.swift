//
//  ServiceProvider.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Foundation

public final class ServiceProvider {

    public let storageService: StorageService
    public let network: NetworkRequestsService
    public let downloader: NetworkDownloadsService

    public let moviesDataProvider: MoviesDataProvider
    public let showsDataProvider: SeriesDataProvider

    public init(credentials: Credentials) {
        storageService = StorageService(modelName: "Ororo")
        network = NetworkService(requestBuilder:
            RequestBuilder(
                headers: ["Accept": "application/json"],
                credentials: credentials,
                httpMethod: .get
            )
        )

        downloader = NetworkService(requestBuilder: RequestBuilder())
        moviesDataProvider = MoviesDataProvider(networkService: network,
                                                storageService: storageService)
        showsDataProvider = SeriesDataProvider(networkService: network,
                                               storageService: storageService)
    }
}
