import Foundation
import MediaPlayer
import UIKit

/// Bridges `MPRemoteCommandCenter` / `MPNowPlayingInfoCenter` to
/// `AudioPlayerManager` and is the **single fan-out point** for now-playing
/// state. All updates flow through `publish(_:)` (issue #103) so the
/// MPNowPlayingInfo widget and the Live Activity always carry the same
/// snapshot — they cannot disagree on play state, elapsed time, or artwork.
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

    /// Atomically push `snapshot` to **both** MPNowPlayingInfoCenter and the
    /// Live Activity. Caller responsibility: pass the same snapshot you want
    /// the user to see on the lock screen — the two surfaces are always
    /// derived from this one value here, never read independently.
    func publish(_ snapshot: NowPlayingSnapshot) {
        writeNowPlayingInfo(snapshot)
        LiveActivityController.shared.publish(snapshot)
    }

    private func writeNowPlayingInfo(_ snapshot: NowPlayingSnapshot) {
        guard let track = snapshot.track else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = track.displayTitle
        info[MPMediaItemPropertyArtist] = track.displayArtist
        info[MPMediaItemPropertyAlbumTitle] = track.displayAlbum
        info[MPMediaItemPropertyPlaybackDuration] = snapshot.duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = snapshot.elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = snapshot.isPlaying ? 1.0 : 0.0
        if let image = snapshot.artwork {
            // Capturing `image` directly means the system never has to
            // re-read the file when the lazy `requestHandler` fires —
            // critical because the source may be the local sandbox mirror
            // and we want the same image the Live Activity is showing.
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
