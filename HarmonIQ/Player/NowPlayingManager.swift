import Foundation
import MediaPlayer
import UIKit

@MainActor
final class NowPlayingManager {
    static let shared = NowPlayingManager()

    private var onPlay: (() -> Void)?
    private var onPause: (() -> Void)?
    private var onTogglePlayPause: (() -> Void)?
    private var onNext: (() -> Void)?
    private var onPrevious: (() -> Void)?
    private var onSeek: ((TimeInterval) -> Void)?
    private var activated = false

    func activate() {
        guard !activated else { return }
        activated = true
        let cc = MPRemoteCommandCenter.shared()

        cc.playCommand.addTarget { [weak self] _ in
            self?.onPlay?()
            return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            self?.onPause?()
            return .success
        }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onTogglePlayPause?()
            return .success
        }
        cc.nextTrackCommand.addTarget { [weak self] _ in
            self?.onNext?()
            return .success
        }
        cc.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPrevious?()
            return .success
        }
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.onSeek?(event.positionTime)
            return .success
        }
        cc.changePlaybackPositionCommand.isEnabled = true
    }

    func bind(onPlay: @escaping () -> Void,
              onPause: @escaping () -> Void,
              onTogglePlayPause: @escaping () -> Void,
              onNext: @escaping () -> Void,
              onPrevious: @escaping () -> Void,
              onSeek: @escaping (TimeInterval) -> Void) {
        self.onPlay = onPlay
        self.onPause = onPause
        self.onTogglePlayPause = onTogglePlayPause
        self.onNext = onNext
        self.onPrevious = onPrevious
        self.onSeek = onSeek
    }

    func update(track: Track, isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = track.displayTitle
        info[MPMediaItemPropertyArtist] = track.displayArtist
        info[MPMediaItemPropertyAlbumTitle] = track.displayAlbum
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        if let path = track.artworkPath {
            let url = LibraryStore.shared.artworkDirectory.appendingPathComponent(path)
            if let image = UIImage(contentsOfFile: url.path) {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func updatePlaybackState(isPlaying: Bool, currentTime: TimeInterval, rate: Float) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func updateElapsed(_ time: TimeInterval, isPlaying: Bool) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
