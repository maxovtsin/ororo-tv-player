//
//  Subtitle.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Foundation
import CoreData

public struct Subtitle: Codable {
    public var id: String? { return url }
    public let lang: String?
    public let url: String?
}

@objc(CDSubtitle)
final class CDSubtitle: NSManagedObject {
    @NSManaged var id: String?
    @NSManaged var lang: String?
    @NSManaged var url: String?
    @NSManaged var episode: CDEpisode
    @NSManaged var movie: CDEpisode
}

extension Subtitle {
    init(subtitle: CDSubtitle) {
        self.lang = subtitle.lang
        self.url = subtitle.url
    }
}

extension CDSubtitle {
    func configure(with subtitle: Subtitle) {
        self.id = subtitle.id
        self.lang = subtitle.lang
        self.url = subtitle.url
    }
}
