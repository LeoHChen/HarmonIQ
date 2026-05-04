import Foundation
import UIKit

/// Single source-of-truth value object describing the lock-screen / Live
/// Activity state at one instant. Both `MPNowPlayingInfoCenter` and the
/// `HarmonIQLiveActivity` widget are updated from the **same** snapshot in
/// one call (see `NowPlayingManager.publish(_:)`), so the two surfaces can
/// never diverge on play state, elapsed time, or artwork. (Issue #103.)
///
/// `track == nil` is the "nothing is playing" state — publishing it clears
/// MPNowPlayingInfo and ends the running Live Activity.
struct NowPlayingSnapshot: Equatable {
    let track: Track?
    let isPlaying: Bool
    let elapsed: TimeInterval
    let duration: TimeInterval
    /// Pre-loaded artwork image. Resolved once at track-change (off the
    /// security-scoped drive — read from the local sandbox mirror) and
    /// passed unchanged to every subsequent snapshot for the same track,
    /// so `MPMediaItemArtwork`'s lazy reload callback never has to touch
    /// the file system again.
    let artwork: UIImage?
    /// Wall-clock instant the snapshot was sampled. Used as the anchor
    /// from which iOS extrapolates progress on the lock screen — both
    /// surfaces use this same instant so their extrapolation stays
    /// in lockstep.
    let sampledAt: Date

    static func empty() -> NowPlayingSnapshot {
        NowPlayingSnapshot(track: nil,
                           isPlaying: false,
                           elapsed: 0,
                           duration: 0,
                           artwork: nil,
                           sampledAt: Date())
    }

    static func == (lhs: NowPlayingSnapshot, rhs: NowPlayingSnapshot) -> Bool {
        lhs.track?.stableID == rhs.track?.stableID &&
        lhs.isPlaying == rhs.isPlaying &&
        lhs.elapsed == rhs.elapsed &&
        lhs.duration == rhs.duration &&
        lhs.artwork === rhs.artwork &&
        lhs.sampledAt == rhs.sampledAt
    }
}
