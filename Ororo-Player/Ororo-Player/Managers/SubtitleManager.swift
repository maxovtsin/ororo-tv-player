//
//  SubtitleManager.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import Ororo_Kit

class SubtitleManager {

    // MARK: - Properties
    private var subtitleIntervals: [SubtitleParser.Interval]?

    // MARK: - Lifecycle
    func configure(subtitlePayload: Data) {
        guard let subtitleString = String(data: subtitlePayload,
                                          encoding: .utf8) else { return }
        subtitleIntervals = SubtitleParser.parse(payload: subtitleString)
    }

    func configure(label: UILabel, time: Double) {
        guard let subtitleIntervals = subtitleIntervals else { return }
        let subtitleString = SubtitleParser.searchSubtitles(payload: subtitleIntervals,
                                                            time: time)
        label.text = subtitleString
    }
}
