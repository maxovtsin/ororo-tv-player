//
//  Movie.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Foundation
import CoreData

public struct Movies: Codable {
    public let movies: [Movie]?
}

public struct Movie: Codable, DecoratedSearchable {

    public let id: Int
    public let name: String
    public let desc: String
    public let posterThumb: String
    public let url: String?
    public let downloadUrl: String?
    public let subtitles: [Subtitle]?
    public let isFavourite: Bool?
    public let playbackProgress: Double?

    // MARK: - Searchable
    public var title: String {
        return name
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, desc, url, subtitles, isFavourite, playbackProgress
        case posterThumb = "poster_thumb"
        case downloadUrl = "download_url"
    }
}

@objc(CDMovie)
final public class CDMovie: NSManagedObject {
    @NSManaged var id: Int
    @NSManaged var name: String
    @NSManaged var desc: String
    @NSManaged var url: String?
    @NSManaged var downloadUrl: String?
    @NSManaged var posterThumb: String
    @NSManaged var subtitles: Set<CDSubtitle>?
    @NSManaged public var isFavourite: NSNumber
    @NSManaged public var playbackProgress: Double
}

public extension Movie {
    init(movie: CDMovie) {
        self.id = movie.id
        self.name = movie.name
        self.desc = movie.desc
        self.url = movie.url
        self.downloadUrl = movie.downloadUrl
        self.posterThumb = movie.posterThumb
        self.subtitles = movie.subtitles?.map { Subtitle(subtitle: $0) }
        self.isFavourite = movie.isFavourite.boolValue
        self.playbackProgress = movie.playbackProgress
    }
}

extension CDMovie {

    func configure(with movie: Movie) {
        self.id = movie.id
        self.name = movie.name
        self.desc = movie.desc
        self.url = movie.url
        self.downloadUrl = movie.downloadUrl
        self.posterThumb = movie.posterThumb

        let subtitles = movie.subtitles?.map { (st) -> CDSubtitle in
            let subtitle = CDSubtitle.forceCreate(with: st.id!,
                                                  into: managedObjectContext!) as CDSubtitle
            subtitle.configure(with: st)
            return subtitle
        }

        if let subtitles = subtitles {
            self.subtitles = Set(subtitles)
        }
    }
}
