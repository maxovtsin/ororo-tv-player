//
//  MoviesDataProvider.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Foundation

public final class MoviesDataProvider {

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
    public func loadMovies(onSuccess: @escaping ([Movie]?) -> Void,
                           onError: @escaping (DataProviderError) -> Void) {

        let movies = storageService.fetchAll() as [CDMovie]?
        let movies_ = movies?.map { Movie(movie: $0) }

        let shouldUpdateOnSuccess = movies_ == nil || movies_!.isEmpty

        if let movies = movies_, !movies.isEmpty {
            onSuccess(movies)
        }

        networkService.request(with: ApiServiceEnpoint.movies,
                               onSuccess: { (movies: Movies) in
                                self.save(movies: movies.movies!)
                                if shouldUpdateOnSuccess {
                                    onSuccess(movies.movies)
                                }
        }, onError: { (error) in
            if !shouldUpdateOnSuccess { return }
            if (error as NSError).code == -1009 {
                logDebug("[DataProvider] The Internet connection appears to be offline.")
                onError(.noNetwork)
            } else {
                logDebug("[DataProvider] Error has occured \(error)")
                onError(.unknown(error))
            }
        })
    }

    public func loadMovie(with id: Int,
                          onSuccess: @escaping (Movie?) -> Void,
                          onError: @escaping (DataProviderError) -> Void) {

        let movies = storageService.fetchAll("id == %@",
                                             arguments: [id]) as [CDMovie]?

        if let movie = movies?.first {
            onSuccess(Movie(movie: movie))
        }

        networkService.request(with: ApiServiceEnpoint.movie(id: id),
                               onSuccess: { (movie: Movie) in
                                self.save(movies: [movie])
                                onSuccess(movie)
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

    // MARK: - Private functions
    private func save(movies: [Movie]) {
        storageService.performAsync(transaction: { (context) in
            movies.forEach {
                let movie = CDMovie.forceCreate(with: "\($0.id)",
                    into: context) as CDMovie
                movie.configure(with: $0)
            }
        })
    }
}
