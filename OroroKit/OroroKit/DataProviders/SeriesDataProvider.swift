//
//  SeriesDataProvider.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Foundation

public final class SeriesDataProvider {

    // MARK: - Properties
    private let networkService: NetworkRequestsService
    private let storageService: StorageService

    // MARK: - Life cycle
    public init(networkService: NetworkRequestsService,
                storageService: StorageService) {
        self.networkService = networkService
        self.storageService = storageService
    }

    // MARK: - Public interface
    public func loadAllShows(onSuccess: @escaping ([Show]?) -> Void,
                             onError: @escaping (DataProviderError) -> Void) {

        let shows = storageService.fetchAll() as [CDShow]?
        let shows_ = shows?.map { Show(show: $0) }

        let shouldUpdateOnSuccess = shows_ == nil || shows_!.isEmpty

        if let shows = shows_, !shows.isEmpty {
            onSuccess(shows)
        }

        networkService.request(with: ApiServiceEnpoint.shows,
                               onSuccess: { (shows: Shows) in
                                self.save(shows: shows.shows!)
                                if shouldUpdateOnSuccess {
                                    onSuccess(shows.shows)
                                }
        }, onError: { (error) in
            if shouldUpdateOnSuccess { return }
            if (error as NSError).code == -1009 {
                logDebug("[DataProvider] The Internet connection appears to be offline.")
                onError(.noNetwork)
            } else {
                logDebug("[DataProvider] Error has occured \(error)")
                onError(.unknown(error))
            }
        })
    }

    public func loadShow(showId: Int,
                         onSuccess: @escaping (Show?) -> Void,
                         onError: @escaping (DataProviderError) -> Void) {

        let show: CDShow? = storageService.fetchOne("id == %@", arguments: [showId])

        if let show = show {
            onSuccess(Show(show: show))
        }

        networkService.request(with: ApiServiceEnpoint.show(id: showId),
                               onSuccess: { (show: Show) in
                                onSuccess(show)
                                self.save(shows: [show])
        }, onError: { (error) in
            if (error as NSError).code == -1009 {
                logDebug("[DataProvider] The Internet connection appears to be offline.")
                onError(.noNetwork)
            } else {
                logDebug("[DataProvider] Error has occured \(error)")
                onError(.unknown(error))
            }
        })
    }

    public func loadEpisod(episodId: Int,
                           onSuccess: @escaping (Episode?) -> Void,
                           onError: @escaping (DataProviderError) -> Void) {

        let episodes = storageService.fetchAll("id == %@",
                                               arguments: [episodId]) as [CDEpisode]?
        if let episode = episodes?.first {
            onSuccess(Episode(episode: episode))
        }

        networkService.request(with: ApiServiceEnpoint.episod(id: episodId),
                               onSuccess: { (episode: Episode) in
                                onSuccess(episode)
                                self.save(episode: episode)
        }, onError: { (error) in
            let code = (error as NSError).code
            if code == -1009 {
                logDebug("[DataProvider] The Internet connection appears to be offline.")
                onError(.noNetwork)
            } else {
                logDebug("[DataProvider] Error has occured \(error)")
                onError(.unknown(error))
            }
        })
    }

    // MARK: - Private functions

    private func save(shows: [Show]) {
        storageService.performAsync(transaction: { (context) in
            for show in shows {
                let created = CDShow.forceCreate(with: "\(show.id)",
                    into: context) as CDShow
                created.configure(with: show)
            }
        })
    }

    private func save(episode: Episode) {
        storageService.performAsync(transaction: { (context) in
            if let fetchedEpisode = context.fetchOne("id == %@", arguments: [episode.id]) as CDEpisode? {
                fetchedEpisode.configure(with: episode)
            } else {
                let createdEpisode = CDEpisode.forceCreate(with: "\(episode.id)", into: context) as CDEpisode
                createdEpisode.configure(with: episode)
            }
        })
    }
}
