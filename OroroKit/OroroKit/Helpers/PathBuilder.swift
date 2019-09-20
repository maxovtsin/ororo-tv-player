//
//  PathBuilder.swift
//  Ororo-Kit
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import UIKit

public final class PathBuilder {

    public static func videoFilePath(fileName: String) -> URL {
        let path = URL.documentDirectory()
            .appendingPathComponent("\(Constants.DirectoryName)/")
            .appendingPathComponent("\(fileName)/")
            .appendingPathComponent("\(Constants.VideoFileName)")
        return path
    }

    public static func subtitleFilePath(fileName: String) -> URL {
        let path = URL.documentDirectory()
            .appendingPathComponent("\(Constants.DirectoryName)/")
            .appendingPathComponent("\(fileName)/")
            .appendingPathComponent("\(Constants.SubtitleFileName)")
        return path
    }

    // MARK: - Inner types
    private enum Constants {
        static let DirectoryName = "Downloads"
        static let VideoFileName = "video.mp4"
        static let SubtitleFileName = "subtitle.vtt"
    }
}

private extension URL {

    static func documentDirectory() -> URL {
        return FileManager.default.urls(for: .documentDirectory,
                                        in: .userDomainMask).first! as URL
    }
}
