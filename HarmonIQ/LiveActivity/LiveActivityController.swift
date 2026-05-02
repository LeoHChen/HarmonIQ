import Foundation
import UIKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Wraps the lifecycle of the Now Playing Live Activity.
///
/// `AudioPlayerManager` calls `start/update/end` at track-change, play/pause,
/// and tick boundaries. Updates are rate-limited (~once per second while
/// playing) per Apple's Activity update budget guidance.
///
/// All methods are no-ops on iOS 16.0 — ActivityKit only ships with 16.1+.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    /// Last second we pushed an update. Throttles tick-driven progress
    /// updates to one per second to stay well under Apple's budget.
    private var lastUpdateSecond: Int = -1

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private var activity: Activity<HarmonIQActivityAttributes>? {
        get { storage as? Activity<HarmonIQActivityAttributes> }
        set { storage = newValue }
    }
    private var storage: Any?
    #endif

    /// Start an activity for `track`, ending any prior one. No-op when
    /// activities are disabled in Settings or unavailable on this OS.
    func start(track: Track, isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // End any in-flight activity first — only one per session.
        endInternal()

        let state = HarmonIQActivityAttributes.State(
            trackTitle: track.displayTitle,
            artist: track.displayArtist,
            albumArt: smallArtworkData(for: track),
            elapsed: currentTime,
            duration: duration,
            isPlaying: isPlaying
        )
        let attrs = HarmonIQActivityAttributes(sessionStart: Date())
        do {
            let act = try Activity<HarmonIQActivityAttributes>.request(
                attributes: attrs,
                contentState: state,
                pushType: nil
            )
            activity = act
            lastUpdateSecond = Int(currentTime)
            AudioPlayerManager.log.info("liveActivity start id=\(act.id, privacy: .public)")
        } catch {
            AudioPlayerManager.log.error("liveActivity start failed: \(String(describing: error), privacy: .public)")
        }
        #endif
    }

    /// Push the current playback state to the running activity. Throttled
    /// to one update per wall-clock second to respect ActivityKit budgets.
    func tick(currentTime: TimeInterval, isPlaying: Bool) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        guard let activity = activity else { return }
        let sec = Int(currentTime)
        if sec == lastUpdateSecond && isPlaying == (activity.contentState.isPlaying) { return }
        lastUpdateSecond = sec
        var state = activity.contentState
        state.elapsed = currentTime
        state.isPlaying = isPlaying
        Task { await activity.update(using: state) }
        #endif
    }

    /// Track changed — replace the activity's title/artist/duration without
    /// ending and restarting (smoother visual transition).
    func updateTrack(_ track: Track, isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        guard let activity = activity else {
            start(track: track, isPlaying: isPlaying, currentTime: currentTime, duration: duration)
            return
        }
        let state = HarmonIQActivityAttributes.State(
            trackTitle: track.displayTitle,
            artist: track.displayArtist,
            albumArt: smallArtworkData(for: track),
            elapsed: currentTime,
            duration: duration,
            isPlaying: isPlaying
        )
        lastUpdateSecond = Int(currentTime)
        Task { await activity.update(using: state) }
        #endif
    }

    /// End the current activity. Called on queue empty / pause-too-long /
    /// app teardown.
    func end() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        endInternal()
        #endif
    }

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private func endInternal() {
        guard let activity = activity else { return }
        Task { await activity.end(dismissalPolicy: .immediate) }
        self.activity = nil
        lastUpdateSecond = -1
    }
    #endif

    /// Resize artwork into a small JPEG so it fits comfortably under the
    /// activity content-state size limit. Returns nil when no artwork is
    /// available.
    private func smallArtworkData(for track: Track) -> Data? {
        guard let path = track.artworkPath else { return nil }
        let url = LibraryStore.shared.artworkDirectory.appendingPathComponent(path)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        // Downscale to ~120×120 logical px → small JPEG; lock-screen banner
        // and Dynamic Island both render at small sizes.
        let target = CGSize(width: 120, height: 120)
        let renderer = UIGraphicsImageRenderer(size: target)
        let small = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return small.jpegData(compressionQuality: 0.7)
    }
}
