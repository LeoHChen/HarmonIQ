import Foundation
import AVFoundation
import Combine
import SwiftUI

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

    @Published var isShuffleEnabled: Bool = false {
        didSet { rebuildPlayOrderIfNeeded() }
    }
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var activeSmartMode: SmartPlayMode? = nil

    /// stableIDs of tracks that have started playing in this app session — fuels Discovery Mix.
    private(set) var sessionPlayedIDs: Set<String> = []

    private var player: AVAudioPlayer?
    private var displayLink: CADisplayLink?
    private var accessRoot: URL?
    private var playOrder: [Int] = [] // indexes into queue
    private var orderPosition: Int = 0

    override init() {
        super.init()
        setupRemoteCommands()
    }

    // MARK: - Public API

    func play(track: Track, in tracks: [Track]) {
        let normalized = tracks.isEmpty ? [track] : tracks
        let startIdx = normalized.firstIndex(of: track) ?? 0
        activeSmartMode = nil
        loadQueue(normalized, startIndex: startIdx)
        playCurrent()
    }

    func playAll(_ tracks: [Track], startAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        activeSmartMode = nil
        loadQueue(tracks, startIndex: max(0, min(index, tracks.count - 1)))
        playCurrent()
    }

    /// Build a queue with a SmartPlayMode and start playback. Disables manual shuffle so
    /// the curator's order is honored.
    func playSmart(mode: SmartPlayMode, from pool: [Track]) {
        let queue = SmartPlayBuilder.buildQueue(mode: mode, from: pool, recentlyPlayed: sessionPlayedIDs)
        guard !queue.isEmpty else { return }
        activeSmartMode = mode
        isShuffleEnabled = false
        loadQueue(queue, startIndex: 0)
        playCurrent()
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
            avPlayer.prepareToPlay()
            self.player = avPlayer
            self.duration = avPlayer.duration > 0 ? avPlayer.duration : track.duration
            avPlayer.play()
            isPlaying = true
            currentTime = 0
            startDisplayLink()
            NowPlayingManager.shared.update(track: track, isPlaying: true, currentTime: 0, duration: self.duration)
        } catch {
            print("[HarmonIQ] Failed to play \(track.filename): \(error)")
            isPlaying = false
            stopDisplayLink()
        }
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
        link.preferredFramesPerSecond = 4
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        guard let player = player else { return }
        currentTime = player.currentTime
        NowPlayingManager.shared.updateElapsed(currentTime, isPlaying: player.isPlaying)
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
