//
//  ApiServiceEnpoint.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Foundation

enum ApiServiceEnpoint: Endpoint {

    case shows
    case show(id: Int)
    case episod(id: Int)
    case movies
    case movie(id: Int)

    var path: String {
        switch self {
        case .shows:
            return "https://ororo.tv/api/v2/shows"
        case .show(let showId):
            return "https://ororo.tv/api/v2/shows/\(showId)"
        case .episod(let episodId):
            return "https://ororo.tv/api/v2/episodes/\(episodId)"
        case .movies:
            return "https://ororo.tv/api/v2/movies"
        case .movie(let episodId):
            return ApiServiceEnpoint.movies.path + "/\(episodId)"
        }
    }
}
