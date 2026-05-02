import Foundation
import AVFoundation
import Combine
import SwiftUI
import UIKit

enum RepeatMode: String, Codable, CaseIterable {
    case off
    case all
    case one
}

@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
    static let shared = AudioPlayerManager()

    @Published private(set) var queue: [Track] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    /// Live audio levels in 0...1 (linear). [0]=avg, [1]=peak. Updated ~30Hz while playing.
    @Published private(set) var levels: SIMD2<Float> = .zero

    @Published var isShuffleEnabled: Bool = false {
        didSet { rebuildPlayOrderIfNeeded() }
    }
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var activeSmartMode: SmartPlayMode? = nil

    /// 0...1 master volume; persisted to AVAudioPlayer when set.
    @Published var volume: Float = 0.85 {
        didSet { player?.volume = volume }
    }
    /// -1...1 stereo balance.
    @Published var balance: Float = 0 {
        didSet { player?.pan = balance }
    }
    /// User-visible reason the most recent play attempt failed, or nil if none.
    /// Cleared when a track plays successfully or the queue empties.
    @Published private(set) var playbackError: String?

    /// Counter that increments every time `play(track:in:)` is invoked by the
    /// user. ContentView observes this to auto-present the now-playing sheet
    /// so a track tap immediately opens the Winamp interface.
    @Published private(set) var presentNowPlayingTick: Int = 0

    // MARK: - Sleep timer
    /// Non-nil when a fixed-duration timer is armed. Nil = no timer.
    @Published private(set) var sleepTimerEndsAt: Date?
    /// When true, playback stops at the natural end of the current track.
    @Published private(set) var sleepStopAtTrackEnd: Bool = false

    /// stableIDs of tracks that have started playing in this app session — fuels Discovery Mix.
    private(set) var sessionPlayedIDs: Set<String> = []

    private var player: AVAudioPlayer?
    private var sleepTimer: Timer?
    private var displayLink: CADisplayLink?
    private var accessRoot: URL?
    private var playOrder: [Int] = [] // indexes into queue
    private var orderPosition: Int = 0

    // Whether the now-playing sheet is open and the visualizer is visible.
    // When false the display link runs at 2 Hz (time-only) and metering is skipped.
    private var visualizerActive = false
    // Timestamp of last @Published currentTime write — throttled to ~2 Hz.
    private var lastPublishedTime: CFTimeInterval = 0
    private var bgObserver: NSObjectProtocol?
    private var fgObserver: NSObjectProtocol?

    override init() {
        super.init()
        setupRemoteCommands()
        bgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.stopDisplayLink() }
        }
        fgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isPlaying else { return }
                    self.startDisplayLink()
                }
        }
    }

    // MARK: - Public API

    func play(track: Track, in tracks: [Track]) {
        let normalized = tracks.isEmpty ? [track] : tracks
        let startIdx = normalized.firstIndex(of: track) ?? 0
        activeSmartMode = nil
        loadQueue(normalized, startIndex: startIdx)
        playCurrent()
        presentNowPlayingTick &+= 1
    }

    func playAll(_ tracks: [Track], startAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        activeSmartMode = nil
        loadQueue(tracks, startIndex: max(0, min(index, tracks.count - 1)))
        playCurrent()
        presentNowPlayingTick &+= 1
    }

    /// Build a queue with a SmartPlayMode and start playback. Disables manual shuffle so
    /// the curator's order is honored.
    /// Re-presents the now-playing sheet without touching playback. Used by the
    /// "Player" entry in the library when the user has dismissed the sheet and
    /// wants to get back to the current track.
    func presentNowPlaying() {
        guard currentTrack != nil else { return }
        presentNowPlayingTick &+= 1
    }

    func playSmart(mode: SmartPlayMode, from pool: [Track]) {
        let queue = SmartPlayBuilder.buildQueue(mode: mode, from: pool, recentlyPlayed: sessionPlayedIDs)
        guard !queue.isEmpty else { return }
        activeSmartMode = mode
        isShuffleEnabled = false
        loadQueue(queue, startIndex: 0)
        playCurrent()
        presentNowPlayingTick &+= 1
    }

    func togglePlayPause() {
        guard let player = player else {
            if !queue.isEmpty { playCurrent() }
            return
        }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopDisplayLink()
        } else {
            player.play()
            isPlaying = true
            startDisplayLink()
        }
        NowPlayingManager.shared.updatePlaybackState(isPlaying: isPlaying, currentTime: currentTime, rate: isPlaying ? 1.0 : 0.0)
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopDisplayLink()
        NowPlayingManager.shared.updatePlaybackState(isPlaying: false, currentTime: currentTime, rate: 0.0)
    }

    func resume() {
        guard let player = player else { return }
        player.play()
        isPlaying = true
        startDisplayLink()
        NowPlayingManager.shared.updatePlaybackState(isPlaying: true, currentTime: currentTime, rate: 1.0)
    }

    func next() {
        advance(by: 1)
    }

    func previous() {
        if currentTime > 3, let player = player {
            player.currentTime = 0
            currentTime = 0
            NowPlayingManager.shared.updatePlaybackState(isPlaying: isPlaying, currentTime: 0, rate: isPlaying ? 1.0 : 0.0)
            return
        }
        advance(by: -1)
    }

    func seek(to seconds: TimeInterval) {
        guard let player = player else { return }
        let clamped = max(0, min(seconds, player.duration))
        player.currentTime = clamped
        currentTime = clamped
        NowPlayingManager.shared.updatePlaybackState(isPlaying: isPlaying, currentTime: clamped, rate: isPlaying ? 1.0 : 0.0)
    }

    func toggleShuffle() {
        isShuffleEnabled.toggle()
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    // MARK: - Sleep timer

    func setSleepTimer(minutes: Int) {
        cancelSleepTimer()
        let interval = TimeInterval(minutes * 60)
        sleepTimerEndsAt = Date().addingTimeInterval(interval)
        sleepStopAtTrackEnd = false
        sleepTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pause()
                self?.sleepTimerEndsAt = nil
                self?.sleepTimer = nil
            }
        }
    }

    func setSleepTimerEndOfTrack() {
        cancelSleepTimer()
        sleepStopAtTrackEnd = true
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerEndsAt = nil
        sleepStopAtTrackEnd = false
    }

    /// Called by the now-playing sheet (skinned or SwiftUI) on appear/disappear.
    /// Active → 30 Hz display link + metering. Inactive → 2 Hz time-only updates.
    func setVisualizerActive(_ active: Bool) {
        visualizerActive = active
        displayLink?.preferredFramesPerSecond = active ? 30 : 2
        if !active { levels = .zero }
    }

    // MARK: - Internals

    private func loadQueue(_ tracks: [Track], startIndex: Int) {
        queue = tracks
        currentIndex = startIndex
        currentTrack = tracks[startIndex]
        rebuildPlayOrderIfNeeded()
    }

    private func rebuildPlayOrderIfNeeded() {
        guard !queue.isEmpty else { playOrder = []; orderPosition = 0; return }
        if isShuffleEnabled {
            var indices = Array(queue.indices)
            indices.removeAll { $0 == currentIndex }
            indices.shuffle()
            playOrder = [currentIndex] + indices
            orderPosition = 0
        } else {
            playOrder = Array(queue.indices)
            orderPosition = currentIndex
        }
    }

    private func playCurrent() {
        guard !queue.isEmpty, currentIndex >= 0, currentIndex < queue.count else { return }
        let track = queue[currentIndex]
        currentTrack = track

        sessionPlayedIDs.insert(track.stableID)

        do {
            stopDisplayLink()
            releaseAccessRoot()

            // Re-activate the audio session in case an interruption (phone
            // call, Siri, another app) deactivated it. Without this, the file
            // loads and "plays" but produces no audible output.
            let session = AVAudioSession.sharedInstance()
            if session.category != .playback {
                try? session.setCategory(.playback, mode: .default, options: [])
            }
            try? session.setActive(true, options: [])

            // Resolve security-scoped access for the root drive that owns this track.
            guard let root = LibraryStore.shared.roots.first(where: { $0.id == track.rootBookmarkID }) else {
                throw NSError(domain: "HarmonIQ", code: 404, userInfo: [NSLocalizedDescriptionKey: "Drive bookmark missing for this track."])
            }

            var stale = false
            let rootURL = try URL(resolvingBookmarkData: root.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            let started = rootURL.startAccessingSecurityScopedResource()
            if started { accessRoot = rootURL }

            var fileURL = rootURL
            for component in track.relativePath {
                fileURL.appendPathComponent(component)
            }

            let avPlayer = try AVAudioPlayer(contentsOf: fileURL)
            avPlayer.delegate = self
            avPlayer.isMeteringEnabled = true
            avPlayer.volume = volume
            avPlayer.pan = balance
            avPlayer.prepareToPlay()
            self.player = avPlayer
            self.duration = avPlayer.duration > 0 ? avPlayer.duration : track.duration
            avPlayer.play()
            isPlaying = true
            currentTime = 0
            playbackError = nil
            startDisplayLink()
            NowPlayingManager.shared.update(track: track, isPlaying: true, currentTime: 0, duration: self.duration)
        } catch {
            print("[HarmonIQ] Failed to play \(track.filename): \(error)")
            isPlaying = false
            stopDisplayLink()
            playbackError = "Can't play \(track.filename): \(Self.friendlyMessage(for: error))"
        }
    }

    /// Translates the most common AVFoundation playback failures into something the
    /// user can act on. Apple Music downloads (DRM-protected .m4p) and the
    /// Files-app system folders that contain them are the usual culprits on
    /// iPhone — surface that explicitly so the silence isn't mysterious.
    private static func friendlyMessage(for error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSOSStatusErrorDomain {
            // 'fmt?' / 'pty?' / -39 etc. all arrive here; whatever the OSStatus,
            // the practical answer is "this file can't be decoded by AVAudioPlayer."
            return "format not playable (DRM-protected, unsupported codec, or unreadable)"
        }
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoPermissionError {
            return "no read permission for this file"
        }
        return ns.localizedDescription
    }

    private func advance(by delta: Int) {
        guard !queue.isEmpty else { return }

        if repeatMode == .one {
            playCurrent()
            return
        }

        if isShuffleEnabled {
            let nextOrder = orderPosition + delta
            if nextOrder >= 0 && nextOrder < playOrder.count {
                orderPosition = nextOrder
                currentIndex = playOrder[orderPosition]
            } else if repeatMode == .all {
                let normalized = ((nextOrder % playOrder.count) + playOrder.count) % playOrder.count
                orderPosition = normalized
                currentIndex = playOrder[orderPosition]
            } else {
                pause()
                return
            }
        } else {
            let proposed = currentIndex + delta
            if proposed >= 0 && proposed < queue.count {
                currentIndex = proposed
            } else if repeatMode == .all {
                currentIndex = ((proposed % queue.count) + queue.count) % queue.count
            } else {
                pause()
                return
            }
        }

        playCurrent()
    }

    private func releaseAccessRoot() {
        if let url = accessRoot {
            url.stopAccessingSecurityScopedResource()
            accessRoot = nil
        }
    }

    // MARK: - Display link for time updates

    private func startDisplayLink() {
        stopDisplayLink()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFramesPerSecond = visualizerActive ? 30 : 2
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        guard let player = player else { return }
        let raw = player.currentTime

        // Throttle @Published currentTime to ~2 Hz to avoid 30 Hz SwiftUI re-renders
        // across every label, scrubber, and time display in the hierarchy.
        let now = CACurrentMediaTime()
        if now - lastPublishedTime >= 0.45 {
            currentTime = raw
            lastPublishedTime = now
        }

        // Metering is only needed when the visualizer is on screen.
        if visualizerActive && player.isMeteringEnabled {
            player.updateMeters()
            var avg: Float = 0
            var peak: Float = 0
            let channels = max(1, player.numberOfChannels)
            for ch in 0..<channels {
                avg += dbToUnit(player.averagePower(forChannel: ch))
                peak += dbToUnit(player.peakPower(forChannel: ch))
            }
            let n = Float(channels)
            levels = SIMD2<Float>(avg / n, peak / n)
        }

        NowPlayingManager.shared.updateElapsed(raw, isPlaying: player.isPlaying)
    }

    /// AVAudioPlayer reports power in dB (–160 silent, 0 max). Map to 0...1 with a soft floor.
    private func dbToUnit(_ db: Float) -> Float {
        let floor: Float = -55
        if db < floor { return 0 }
        if db >= 0 { return 1 }
        return (db - floor) / -floor
    }

    // MARK: - Remote commands

    private func setupRemoteCommands() {
        NowPlayingManager.shared.bind(
            onPlay: { [weak self] in self?.resume() },
            onPause: { [weak self] in self?.pause() },
            onTogglePlayPause: { [weak self] in self?.togglePlayPause() },
            onNext: { [weak self] in self?.next() },
            onPrevious: { [weak self] in self?.previous() },
            onSeek: { [weak self] time in self?.seek(to: time) }
        )
    }
}

extension AudioPlayerManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.sleepStopAtTrackEnd {
                self.pause()
                self.sleepStopAtTrackEnd = false
                return
            }
            if self.repeatMode == .one {
                self.playCurrent()
            } else {
                self.advance(by: 1)
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.advance(by: 1)
        }
    }
}
