//
//  VideoPlayerManager.swift
//  Ororo-Player
//
//  Created by Max Ovtsin on 9/12/18.
//  Copyright © 2018 Max Ovtsin. All rights reserved.
//

import AVKit
import AVFoundation
import CoreMedia
import Ororo_Kit

final class VideoPlayerManager {

    // MARK: - Properties
    let player: AVPlayer
    private let progress: Double

    // MARK: - Life cycle
    init(url: URL, progress: Double) {
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: playerItem)
        self.progress = progress
        activateAudioSession()
    }

    func startPlaying() {
        player.play()
        guard let duration = player.currentItem?.asset.duration,
            progress != 0.0 else { return }
        let durationInSecs = CMTimeGetSeconds(duration)
        let timeOffset = durationInSecs * progress
        player.seek(to: CMTimeMakeWithSeconds(timeOffset, preferredTimescale: 1))
    }

    func addTimeObserver(period: Int64,
                         block: @escaping (Float64, Float64) -> Void) {
        player.addPeriodicTimeObserver(
            forInterval: CMTimeMake(value: period, timescale: 1),
            queue: DispatchQueue.main,
            using: { (time) -> Void in
                let p = CMTimeGetSeconds(time)
                let d: Float64
                if let duration = self.player.currentItem?.asset.duration {
                    d = CMTimeGetSeconds(duration)
                } else {
                    d = 0.0
                }
                block(p, d)
        })
    }

    // MARK: - Private functions
    private func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logDebug("[VideoPlayer] AVAudioSession activation failed")
        }
    }
}
