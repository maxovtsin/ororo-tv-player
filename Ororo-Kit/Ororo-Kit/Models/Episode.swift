//
//  Episode.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Foundation
import CoreData

public struct Episode: Codable, DecoratedSearchable {

    public let id: Int
    public let number: String?
    public let name: String?
    public let plot: String?
    public let url: String?
    public let downloadUrl: String?
    public let season: Int
    public let subtitles: [Subtitle]?

    public let showName: String?
    public let showPosterThumb: String?

    public let downloadedId: String?
    public let isDownloading: Bool?
    public let downloadSubtitlePath: String?
    public let playbackProgress: Double?

    // MARK: - Searchable
    public var title: String {
        return "\(showName!) S:\(season) E:\(number!)"
    }

    public var posterThumb: String {
        return showPosterThumb ?? ""
    }

    // MARK: Codable
    private enum CodingKeys: String, CodingKey {
        case id, name, plot, url, season, subtitles, number, playbackProgress
        case downloadedId, isDownloading, downloadSubtitlePath, showName, showPosterThumb
        case downloadUrl = "download_url"
    }
}

@objc(CDEpisode)
public final class CDEpisode: NSManagedObject {
    @NSManaged var id: Int
    @NSManaged var number: String?
    @NSManaged var name: String?
    @NSManaged var plot: String?
    @NSManaged var url: String?
    @NSManaged var downloadUrl: String?
    @NSManaged var season: Int
    @NSManaged var subtitles: Set<CDSubtitle>?
    @NSManaged var show: CDShow?
    @NSManaged public var playbackProgress: Double

    @NSManaged public var downloadedId: String?
    @NSManaged public var isDownloading: Bool
    @NSManaged var downloadSubtitlePath: String?
}

public extension Episode {
    init(episode: CDEpisode) {
        self.id = episode.id
        self.number = episode.number
        self.name = episode.name ?? ""
        self.plot = episode.plot
        self.url = episode.url
        self.downloadUrl = episode.downloadUrl
        self.season = episode.season
        self.subtitles = episode.subtitles?.map { Subtitle(subtitle: $0) }

        self.showName = episode.show?.name
        self.showPosterThumb = episode.show?.posterThumb

        self.downloadedId = episode.downloadedId
        self.isDownloading = episode.isDownloading
        self.downloadSubtitlePath = episode.downloadSubtitlePath
        self.playbackProgress = episode.playbackProgress
    }
}

extension CDEpisode {
    func configure(with episode: Episode) {
        self.id = episode.id
        self.number = episode.number
        self.name = episode.name
        self.plot = episode.plot
        self.url = episode.url
        self.downloadUrl = episode.downloadUrl
        self.season = episode.season

        let subtitles = episode.subtitles?.map { (st) -> CDSubtitle in
            let subtitle = CDSubtitle.forceCreate(with: st.id!,
                                                  into: managedObjectContext!) as CDSubtitle
            subtitle.configure(with: st)
            return subtitle
        }

        if let subtitles = subtitles {
            self.subtitles = Set(subtitles)
        }

        self.downloadedId = episode.downloadedId
        self.downloadSubtitlePath = episode.downloadSubtitlePath
    }
}
