import Foundation
import AVFoundation
import Combine
import SwiftUI
import UIKit
import os

enum RepeatMode: String, Codable, CaseIterable {
    case off
    case all
    case one
}

/// Audio playback driven by `AVAudioEngine + AVAudioPlayerNode + AVAudioUnitEQ`.
///
/// Public API matches the prior `AVAudioPlayer`-based implementation so the
/// rest of the app is unchanged. The migration is what unlocks the functional
/// equalizer (issue #28) — `EqualizerManager.shared.eqUnit` is wired into the
/// graph between the player node and the main mixer.
@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
    static let shared = AudioPlayerManager()

    /// Diagnostic logger. Filter in Console.app with
    /// `subsystem:net.leochen.harmoniq category:playback` to see every
    /// finish/decode/interruption/route-change/scope-release event with
    /// context — used to investigate issue #38 (mid-track aborts).
    static let log = Logger(subsystem: "net.leochen.harmoniq", category: "playback")

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
    /// Non-nil while an AI Smart Play call is in flight. UI shows a spinner.
    @Published private(set) var aiCurating: SmartPlayMode? = nil
    /// Title + blurb returned by the most recent AI curation, for UI display.
    @Published private(set) var aiAnnotation: AIQueueAnnotation? = nil

    /// 0...1 master volume. Mapped to the player node's `volume` directly.
    @Published var volume: Float = 0.85 {
        didSet { playerNode.volume = volume }
    }
    /// -1...1 stereo balance — mapped to the player node's `pan`.
    @Published var balance: Float = 0 {
        didSet { playerNode.pan = balance }
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

    // MARK: - Engine state
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    /// File currently scheduled in `playerNode`. nil between tracks.
    private var audioFile: AVAudioFile?
    /// File-frame offset where the current schedule began. Combined with
    /// `playerNode.playerTime(forNodeTime:).sampleTime` to compute current time.
    private var seekStartFrame: AVAudioFramePosition = 0
    /// Latched current time at the moment we paused. Used so the UI keeps
    /// reading the right value while the node isn't rendering.
    private var pausedAtSeconds: TimeInterval?
    /// Generation counter — bumped on every `playCurrent()` and `seek(...)`.
    /// `scheduleFile` completion handlers compare against this to detect
    /// whether they belong to a stale schedule that was preempted.
    private var playGeneration: UInt64 = 0
    /// Tag-claimed duration (`Track.duration`, from AVAsset metadata) for the
    /// currently-playing track. Compared against the actual file frame count
    /// at completion to flag VBR-header mismatches (issue #38).
    private var metadataDurationAtPlay: TimeInterval = 0
    /// Thread-safe meter sink fed by the player-node tap.
    private let meterSink = MeterSink()

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

    override init() {
        super.init()
        setupAudioGraph()
        setupRemoteCommands()
        // Selector-based registration avoids @Sendable closure issues: UIApplication
        // lifecycle notifications are always posted on the main thread, so the @objc
        // methods below run on the main actor without any concurrency bridging.
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
        // Audio session diagnostics — logging only, no behavior change.
        // See issue #38.
        NotificationCenter.default.addObserver(
            self, selector: #selector(audioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(audioSessionRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification, object: nil)
        // The engine can stop on configuration changes (e.g. headphones plugged
        // in mid-stream). Restart it transparently so the user doesn't notice.
        NotificationCenter.default.addObserver(
            self, selector: #selector(engineConfigurationChange(_:)),
            name: .AVAudioEngineConfigurationChange, object: engine)
        // Hard reset of CoreAudio (rare). Posted when the audio server crashes
        // or restarts — e.g. background OS event. Logging only; the engine
        // would need a full re-setup to recover but that's out of scope for
        // a diagnostic-only PR (issue #38).
        NotificationCenter.default.addObserver(
            self, selector: #selector(mediaServicesWereLost(_:)),
            name: AVAudioSession.mediaServicesWereLostNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(mediaServicesWereReset(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    private func setupAudioGraph() {
        let eq = EqualizerManager.shared.eqUnit
        engine.attach(playerNode)
        engine.attach(eq)
        // Use a "common" stereo float format for connections; AVAudioEngine
        // inserts converters as needed when scheduling files of any sample
        // rate or channel layout.
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
        engine.connect(playerNode, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        playerNode.volume = volume
        playerNode.pan = balance
        // Tap on the EQ output so the visualizer reflects what the user hears
        // (post-EQ + post-volume). `format: nil` lets the engine pick the
        // actual rendered format when the graph starts — querying
        // `outputFormat(forBus: 0)` *before* `engine.start()` returns a stale
        // default that the tap then silently mismatches. Issue #41.
        let sink = meterSink
        eq.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            sink.process(buffer: buffer)
        }
    }

    @MainActor @objc private func appDidEnterBackground() {
        stopDisplayLink()
    }

    @MainActor @objc private func appWillEnterForeground() {
        if isPlaying { startDisplayLink() }
    }

    @objc private func audioSessionInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }
        let typeStr: String = (type == .began) ? "began" : "ended"
        let reasonRaw: UInt = info[AVAudioSessionInterruptionReasonKey] as? UInt ?? 0
        let optsRaw: UInt = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        let optsResume = (optsRaw & AVAudioSession.InterruptionOptions.shouldResume.rawValue) != 0
        Self.log.info("interruption type=\(typeStr, privacy: .public) reasonRaw=\(reasonRaw) optionsRaw=\(optsRaw) shouldResume=\(optsResume)")
    }

    @objc private func audioSessionRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
        else { return }
        let label: String
        switch reason {
        case .unknown:                 label = "unknown"
        case .newDeviceAvailable:      label = "newDeviceAvailable"
        case .oldDeviceUnavailable:    label = "oldDeviceUnavailable"
        case .categoryChange:          label = "categoryChange"
        case .override:                label = "override"
        case .wakeFromSleep:           label = "wakeFromSleep"
        case .noSuitableRouteForCategory: label = "noSuitableRouteForCategory"
        case .routeConfigurationChange:label = "routeConfigurationChange"
        @unknown default:              label = "unknown(\(raw))"
        }
        Self.log.info("routeChange reason=\(label, privacy: .public) reasonRaw=\(raw)")
    }

    @objc private func engineConfigurationChange(_ note: Notification) {
        // Capture engine + player node state so we can tell whether the change
        // dropped us out of running. If isPlaying flips false right after this,
        // the cause is here.
        let wasRunning = engine.isRunning
        let nodeWasPlaying = playerNode.isPlaying
        Self.log.info("engineConfigurationChange wasRunning=\(wasRunning) nodeWasPlaying=\(nodeWasPlaying) — restarting engine")
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            Self.log.error("engine restart failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// CoreAudio server crashed. Engine is now toast — would require a full
    /// re-setup to recover. We just log and let the user-visible fallout
    /// (silence) be consistent with the bug we're trying to diagnose.
    @objc private func mediaServicesWereLost(_ note: Notification) {
        let id = currentTrack?.stableID ?? "<none>"
        Self.log.error("mediaServicesWereLost stableID=\(id, privacy: .public) — CoreAudio server died, engine no longer functional until re-setup")
    }

    /// Posted after the audio server restarts. Mostly a paired notification
    /// with the above; we don't auto-recover but logging it makes the timeline
    /// in Console readable.
    @objc private func mediaServicesWereReset(_ note: Notification) {
        let id = currentTrack?.stableID ?? "<none>"
        Self.log.info("mediaServicesWereReset stableID=\(id, privacy: .public) — audio server restarted")
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

    /// Re-presents the now-playing sheet without touching playback. Used by the
    /// "Player" entry in the library when the user has dismissed the sheet and
    /// wants to get back to the current track.
    func presentNowPlaying() {
        guard currentTrack != nil else { return }
        presentNowPlayingTick &+= 1
    }

    /// Build a queue with a SmartPlayMode and start playback. Disables manual shuffle so
    /// the curator's order is honored.
    func playSmart(mode: SmartPlayMode, from pool: [Track]) {
        let queue = SmartPlayBuilder.buildQueue(mode: mode, from: pool, recentlyPlayed: sessionPlayedIDs, seed: currentTrack)
        guard !queue.isEmpty else { return }
        activeSmartMode = mode
        isShuffleEnabled = false
        aiAnnotation = nil
        loadQueue(queue, startIndex: 0)
        playCurrent()
        presentNowPlayingTick &+= 1
    }

    /// Build + play an AI-curated queue. `userPrompt` is only meaningful for
    /// `.vibeMatch`. Throws if the API key is missing or the call fails so
    /// the UI can present an error to the user.
    func playSmartAI(mode: SmartPlayMode, from pool: [Track], userPrompt: String = "") async throws {
        guard mode.requiresAI else { return }
        guard !pool.isEmpty else { return }
        aiCurating = mode
        defer { aiCurating = nil }
        let curated = try await SmartPlayAI.curate(mode: mode, userPrompt: userPrompt, pool: pool)
        // Map the returned stableIDs back to in-memory Tracks.
        let map: [String: Track] = Dictionary(uniqueKeysWithValues: pool.map { ($0.stableID, $0) })
        let resolved: [Track] = curated.trackIDs.compactMap { map[$0] }
        guard !resolved.isEmpty else { return }
        activeSmartMode = mode
        isShuffleEnabled = false
        aiAnnotation = AIQueueAnnotation(title: curated.title,
                                         blurb: curated.blurb,
                                         rationales: curated.rationales,
                                         prompt: userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : userPrompt,
                                         mode: mode.rawValue)
        loadQueue(resolved, startIndex: 0)
        playCurrent()
        presentNowPlayingTick &+= 1
    }

    func togglePlayPause() {
        if audioFile == nil {
            if !queue.isEmpty { playCurrent() }
            return
        }
        if playerNode.isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func pause() {
        // Latch current time before we pause — `playerTime(forNodeTime:)`
        // returns nil once the node stops rendering.
        pausedAtSeconds = currentTimeSeconds()
        playerNode.pause()
        isPlaying = false
        stopDisplayLink()
        NowPlayingManager.shared.updatePlaybackState(isPlaying: false, currentTime: pausedAtSeconds ?? currentTime, rate: 0.0)
        LiveActivityController.shared.tick(currentTime: pausedAtSeconds ?? currentTime, isPlaying: false)
        // Issue #38: surfacing every pause helps line up "the song stopped"
        // with the actual cause when reading the log timeline. We don't know
        // the caller here, but pairing this with the surrounding logs
        // (interruption / didFinishPlaying / sleep timer) makes it obvious.
        let id = currentTrack?.stableID ?? "<none>"
        let at = pausedAtSeconds ?? 0
        Self.log.info("pause at=\(at, format: .fixed(precision: 2)) stableID=\(id, privacy: .public)")
    }

    func resume() {
        guard audioFile != nil else { return }
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            Self.log.error("engine start failed on resume: \(String(describing: error), privacy: .public)")
            playbackError = "Audio engine couldn't start: \(error.localizedDescription)"
            return
        }
        playerNode.play()
        isPlaying = true
        pausedAtSeconds = nil
        startDisplayLink()
        NowPlayingManager.shared.updatePlaybackState(isPlaying: true, currentTime: currentTime, rate: 1.0)
        LiveActivityController.shared.tick(currentTime: currentTime, isPlaying: true)
    }

    func next() { advance(by: 1) }

    func previous() {
        if currentTimeSeconds() > 3 {
            seek(to: 0)
            return
        }
        advance(by: -1)
    }

    func seek(to seconds: TimeInterval) {
        guard let file = audioFile else { return }
        let sampleRate = file.processingFormat.sampleRate
        let totalFrames = file.length
        let target = AVAudioFramePosition(max(0, min(Double(totalFrames - 1), seconds * sampleRate)))
        let remaining = max(1, totalFrames - target)
        playGeneration &+= 1
        let gen = playGeneration

        playerNode.stop()
        seekStartFrame = target
        let resumeAfter = isPlaying

        playerNode.scheduleSegment(file,
                                   startingFrame: target,
                                   frameCount: AVAudioFrameCount(remaining),
                                   at: nil,
                                   completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                self?.handleScheduleComplete(generation: gen)
            }
        }

        // Update the published time + lock-screen state so the UI reflects the
        // new position even if we're paused right now.
        currentTime = Double(target) / sampleRate
        pausedAtSeconds = resumeAfter ? nil : currentTime
        if resumeAfter {
            do {
                if !engine.isRunning { try engine.start() }
                playerNode.play()
            } catch {
                Self.log.error("engine start failed on seek: \(String(describing: error), privacy: .public)")
            }
        }
        NowPlayingManager.shared.updatePlaybackState(isPlaying: isPlaying, currentTime: currentTime, rate: isPlaying ? 1.0 : 0.0)
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
                // Log the firing distinctly so a "track aborted mid-stream"
                // bug report can be cross-checked against this timestamp
                // in Console (issue #38).
                Self.log.info("sleepTimer fired — pausing playback")
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
            // Stop any prior playback before releasing the old drive's scope.
            playerNode.stop()
            audioFile = nil
            releaseAccessRoot()

            // Re-activate the audio session in case an interruption (phone
            // call, Siri, another app) deactivated it.
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

            let file = try AVAudioFile(forReading: fileURL)
            self.audioFile = file
            self.seekStartFrame = 0
            self.pausedAtSeconds = nil
            let sampleRate = file.processingFormat.sampleRate
            let lengthSeconds = sampleRate > 0 ? Double(file.length) / sampleRate : track.duration
            self.duration = lengthSeconds > 0 ? lengthSeconds : track.duration
            // Snapshot the metadata duration so the schedule-complete log can
            // flag a mismatch between what the tag claimed and how many frames
            // the file actually decoded. Issue #38: the most common
            // "premature end" cause is a bad VBR header where the metadata
            // duration is much longer than the audible file length.
            self.metadataDurationAtPlay = track.duration

            playGeneration &+= 1
            let gen = playGeneration
            playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    self?.handleScheduleComplete(generation: gen)
                }
            }

            if !engine.isRunning {
                try engine.start()
            }
            playerNode.play()

            isPlaying = true
            currentTime = 0
            playbackError = nil
            startDisplayLink()
            NowPlayingManager.shared.update(track: track, isPlaying: true, currentTime: 0, duration: self.duration)
            LiveActivityController.shared.updateTrack(track, isPlaying: true, currentTime: 0, duration: self.duration)
            // Mismatch between metadata duration and decoded frame count is
            // the smoking gun for "song aborts mid-playback" reports — log
            // both so the gap is visible at play-start time.
            let mismatch = abs(self.duration - track.duration) > 1.0 && track.duration > 0
            Self.log.info("playStart stableID=\(track.stableID, privacy: .public) fileSeconds=\(self.duration, format: .fixed(precision: 2)) tagSeconds=\(track.duration, format: .fixed(precision: 2)) mismatch=\(mismatch) format=\(track.fileFormat, privacy: .public)")

            // If the album has no artwork and the user opted into online
            // lookups, fire a best-effort fetch (issue #73). Off by default;
            // when off this is a cheap no-op.
            if track.artworkPath == nil {
                ArtworkFetcher.shared.fetchIfMissing(for: track)
            }
        } catch {
            print("[HarmonIQ] Failed to play \(track.filename): \(error)")
            Self.log.error("playFailed stableID=\(track.stableID, privacy: .public) error=\(String(describing: error), privacy: .public)")
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
            let id = currentTrack?.stableID ?? "<none>"
            Self.log.debug("releaseAccessRoot path=\(url.lastPathComponent, privacy: .public) currentStableID=\(id, privacy: .public)")
            url.stopAccessingSecurityScopedResource()
            accessRoot = nil
        }
    }

    /// Called from the `scheduleFile`/`scheduleSegment` completion handler.
    /// Acts only when `generation` matches the currently active schedule —
    /// stale completions (preempted by seek/track-change/stop) are ignored.
    private func handleScheduleComplete(generation: UInt64) {
        guard generation == playGeneration else { return }
        guard let file = audioFile else { return }
        let sampleRate = file.processingFormat.sampleRate
        let totalSeconds = sampleRate > 0 ? Double(file.length) / sampleRate : duration
        let observed = currentTimeSeconds()
        let early = totalSeconds > 0 && (totalSeconds - observed) > 1.0
        let id = currentTrack?.stableID ?? "<none>"
        let tagSeconds = metadataDurationAtPlay
        // If the file's actual frame count is materially shorter than the
        // tag-claimed duration, the file is the culprit (truncated or bad
        // VBR header). If they agree but `early=true`, something stopped the
        // schedule prematurely — interruption, engine reset, or AVAudioEngine
        // bug worth investigating.
        let tagShortfall = tagSeconds > 0 ? max(0, tagSeconds - totalSeconds) : 0
        let engineRunning = engine.isRunning
        let scopeHeld = (accessRoot != nil)
        Self.log.info("didFinishPlaying success=true currentTime=\(observed, format: .fixed(precision: 2)) fileSeconds=\(totalSeconds, format: .fixed(precision: 2)) tagSeconds=\(tagSeconds, format: .fixed(precision: 2)) tagShortfall=\(tagShortfall, format: .fixed(precision: 2)) endedEarly=\(early) engineRunning=\(engineRunning) scopeHeld=\(scopeHeld) stableID=\(id, privacy: .public)")

        if sleepStopAtTrackEnd {
            pause()
            sleepStopAtTrackEnd = false
            return
        }
        if repeatMode == .one {
            playCurrent()
        } else {
            advance(by: 1)
        }
    }

    /// Returns the file-frame position currently rendering as a wall-clock
    /// seconds offset from the start of the file.
    private func currentTimeSeconds() -> TimeInterval {
        if let paused = pausedAtSeconds { return paused }
        guard let file = audioFile else { return 0 }
        let sampleRate = file.processingFormat.sampleRate
        let seekSeconds = sampleRate > 0 ? Double(seekStartFrame) / sampleRate : 0
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0 else {
            return seekSeconds
        }
        let elapsed = max(0, Double(playerTime.sampleTime) / playerTime.sampleRate)
        return seekSeconds + elapsed
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
        let raw = currentTimeSeconds()

        // Throttle @Published currentTime to ~2 Hz to avoid 30 Hz SwiftUI re-renders
        // across every label, scrubber, and time display in the hierarchy.
        let now = CACurrentMediaTime()
        if now - lastPublishedTime >= 0.45 {
            currentTime = raw
            lastPublishedTime = now
        }

        // Metering is only useful when the visualizer is on screen — read the
        // tap-fed sink and convert dB → 0...1.
        if visualizerActive {
            let snap = meterSink.snapshot()
            levels = SIMD2<Float>(dbToUnit(snap.avgDb), dbToUnit(snap.peakDb))
        }

        NowPlayingManager.shared.updateElapsed(raw, isPlaying: playerNode.isPlaying)
        // The Live Activity controller throttles internally to ~1 update / sec.
        LiveActivityController.shared.tick(currentTime: raw, isPlaying: playerNode.isPlaying)
    }

    /// dBFS power → 0...1 with a soft floor.
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

// MARK: - AI Queue annotation

/// Per-queue framing returned by the AI Smart Play modes (issue #25).
/// Lives on `AudioPlayerManager.aiAnnotation` while the AI-curated queue
/// is active; cleared when the user starts a non-AI playback.
struct AIQueueAnnotation: Equatable {
    let title: String
    let blurb: String
    /// One-line rationale per stableID, when the model provided one.
    let rationales: [String: String]
    /// User's free-text prompt for prompt-driven modes (Vibe Match), or nil.
    let prompt: String?
    /// `SmartPlayMode.rawValue` that produced this queue.
    let mode: String?
}

// MARK: - Meter sink

/// Thread-safe drop-box for the latest power readings. The audio tap runs on
/// a non-main thread; the display-link tick reads on main. NSLock keeps the
/// two from tearing each other's writes.
private final class MeterSink: @unchecked Sendable {
    private let lock = NSLock()
    private var lastAvgDb: Float = -160
    private var lastPeakDb: Float = -160

    func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }
        let channelCount = Int(buffer.format.channelCount)
        var sumSq: Float = 0
        var peak: Float = 0
        for ch in 0..<channelCount {
            let p = channelData[ch]
            for i in 0..<frameLength {
                let s = p[i]
                sumSq += s * s
                let a = s < 0 ? -s : s
                if a > peak { peak = a }
            }
        }
        let n = Float(frameLength * max(1, channelCount))
        let rms = sqrtf(sumSq / n)
        let avgDb = 20 * log10f(max(rms, 1e-6))
        let peakDb = 20 * log10f(max(peak, 1e-6))
        lock.lock()
        lastAvgDb = avgDb
        lastPeakDb = peakDb
        lock.unlock()
    }

    func snapshot() -> (avgDb: Float, peakDb: Float) {
        lock.lock()
        let a = lastAvgDb, p = lastPeakDb
        lock.unlock()
        return (a, p)
    }
}
