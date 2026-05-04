import Foundation
import UIKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Wraps the lifecycle of the Now Playing Live Activity.
///
/// As of issue #103 the controller is **driven by `NowPlayingSnapshot`** so
/// every update lands at the same time as the matching MPNowPlayingInfo
/// write — see `NowPlayingManager.publish(_:)`. `publish` is the only
/// public state-change entry point: pass a snapshot with `track == nil`
/// to end the activity.
///
/// Updates are still rate-limited to ~one per wall-clock second per Apple's
/// ActivityKit budget guidance, but the throttle is now keyed on the
/// snapshot — meaning a play/pause flip or a track change always pushes
/// immediately, only same-second elapsed-only updates are coalesced.
///
/// All methods are no-ops on iOS 16.0 — ActivityKit only ships with 16.1+.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    /// Last second we pushed an update for — combined with `lastIsPlaying`
    /// and `lastTrackID` to skip redundant elapsed-only updates.
    private var lastUpdateSecond: Int = -1
    private var lastIsPlaying: Bool = false
    private var lastTrackID: String? = nil

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private var activity: Activity<HarmonIQActivityAttributes>? {
        get { storage as? Activity<HarmonIQActivityAttributes> }
        set { storage = newValue }
    }
    private var storage: Any?
    #endif

    /// Atomically reflect `snapshot` on the Live Activity. Called from
    /// `NowPlayingManager.publish(_:)` — do not call from elsewhere.
    func publish(_ snapshot: NowPlayingSnapshot) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Empty snapshot -> tear the activity down.
        guard let track = snapshot.track else {
            endInternal()
            return
        }

        let trackID = track.stableID
        let trackChanged = (trackID != lastTrackID)
        let stateChanged = (snapshot.isPlaying != lastIsPlaying)
        let sec = Int(snapshot.elapsed)
        let secondChanged = (sec != lastUpdateSecond)

        // Coalesce same-second elapsed-only updates while playing/paused
        // unchanged on the same track. Play/pause flips and track changes
        // always go through immediately.
        if !trackChanged && !stateChanged && !secondChanged { return }

        let state = HarmonIQActivityAttributes.State(
            trackTitle: track.displayTitle,
            artist: track.displayArtist,
            albumArt: smallArtworkData(snapshot),
            elapsed: snapshot.elapsed,
            duration: snapshot.duration,
            isPlaying: snapshot.isPlaying
        )

        if let activity = activity, !trackChanged {
            Task { await activity.update(using: state) }
        } else {
            // Track change: end the prior activity (if any) and start a
            // fresh one. Doing it via end+start keeps the attributes
            // simple — no need to mutate `sessionStart` mid-flight.
            endInternal()
            startActivity(state: state)
        }

        lastTrackID = trackID
        lastIsPlaying = snapshot.isPlaying
        lastUpdateSecond = sec
        #endif
    }

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private func startActivity(state: HarmonIQActivityAttributes.State) {
        let attrs = HarmonIQActivityAttributes(sessionStart: Date())
        do {
            let act = try Activity<HarmonIQActivityAttributes>.request(
                attributes: attrs,
                contentState: state,
                pushType: nil
            )
            activity = act
            AudioPlayerManager.log.info("liveActivity start id=\(act.id, privacy: .public)")
        } catch {
            AudioPlayerManager.log.error("liveActivity start failed: \(String(describing: error), privacy: .public)")
        }
    }
    #endif

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private func endInternal() {
        guard let activity = activity else { return }
        Task { await activity.end(dismissalPolicy: .immediate) }
        self.activity = nil
        lastUpdateSecond = -1
        lastIsPlaying = false
        lastTrackID = nil
    }
    #endif

    /// Resize the snapshot's artwork into a small JPEG so it fits comfortably
    /// under the activity content-state size limit. Returns nil when no
    /// artwork is available — the widget then renders the same music-note
    /// placeholder MPNowPlayingInfo's empty artwork tile shows.
    private func smallArtworkData(_ snapshot: NowPlayingSnapshot) -> Data? {
        guard let image = snapshot.artwork else { return nil }
        let target = CGSize(width: 120, height: 120)
        let renderer = UIGraphicsImageRenderer(size: target)
        let small = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return small.jpegData(compressionQuality: 0.7)
    }
}
