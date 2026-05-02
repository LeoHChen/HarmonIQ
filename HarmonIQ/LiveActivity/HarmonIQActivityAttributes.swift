import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Shape of the Live Activity that surfaces background music playback on
/// the lock screen and Dynamic Island. Compiled into BOTH the host app and
/// the `HarmonIQLiveActivity` widget extension so the two agree on the wire
/// format. iOS 16.1+ (ActivityKit availability).
@available(iOS 16.1, *)
public struct HarmonIQActivityAttributes: ActivityAttributes {
    public typealias ContentState = State

    public struct State: Codable, Hashable {
        public var trackTitle: String
        public var artist: String
        /// Encoded JPEG/PNG thumbnail. Keep ≤ ~30 KB so we stay under
        /// ActivityKit's 4 KB content-state limit when bundled with the
        /// rest of the State (the system passes a separate token for
        /// larger payloads, but small thumbs are simplest).
        public var albumArt: Data?
        public var elapsed: TimeInterval
        public var duration: TimeInterval
        public var isPlaying: Bool

        public init(trackTitle: String,
                    artist: String,
                    albumArt: Data? = nil,
                    elapsed: TimeInterval,
                    duration: TimeInterval,
                    isPlaying: Bool) {
            self.trackTitle = trackTitle
            self.artist = artist
            self.albumArt = albumArt
            self.elapsed = elapsed
            self.duration = duration
            self.isPlaying = isPlaying
        }
    }

    /// Wall-clock instant the activity started, used for relative-time
    /// displays on the lock screen.
    public var sessionStart: Date

    public init(sessionStart: Date) {
        self.sessionStart = sessionStart
    }
}
#endif
