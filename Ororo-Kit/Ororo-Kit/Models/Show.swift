//
//  Show.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Foundation
import CoreData

public struct Shows: Codable {
    public let shows: [Show]?
}

public struct Show: Codable, DecoratedSearchable {

    public let id: Int
    public let name: String
    public let desc: String?
    public let episodes: [Episode]?
    public let posterThumb: String?
    public let isFavourite: Bool?

    // MARK: - Searchable
    public var title: String {
        return name
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, desc, episodes, isFavourite
        case posterThumb = "poster_thumb"
    }
}

@objc(CDShow)
final public class CDShow: NSManagedObject {
    @NSManaged var id: Int
    @NSManaged var name: String
    @NSManaged var desc: String
    @NSManaged var episodes: Set<CDEpisode>?
    @NSManaged var posterThumb: String
    @NSManaged public var isFavourite: NSNumber
}

extension Show {
    public init(show: CDShow) {
        self.id = show.id
        self.name = show.name
        self.desc = show.desc
        self.episodes = show.episodes?.map { Episode(episode: $0) }
        self.posterThumb = show.posterThumb
        self.isFavourite = show.isFavourite.boolValue
    }
}

extension CDShow {
    func configure(with show: Show) {
        self.id = show.id
        self.name = show.name
        self.desc = show.desc ?? ""
        self.posterThumb = show.posterThumb ?? ""

        let episodes = show.episodes?.map { (ep) -> CDEpisode in
            let episode = CDEpisode.forceCreate(with: "\(ep.id)",
                                                  into: managedObjectContext!) as CDEpisode
            episode.configure(with: ep)
            return episode
        }

        if let episodes = episodes {
            self.episodes = Set(episodes)
        }
    }
}
