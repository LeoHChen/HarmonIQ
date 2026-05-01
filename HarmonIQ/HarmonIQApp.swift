import SwiftUI
import AVFoundation

@main
struct HarmonIQApp: App {
    @StateObject private var library = LibraryStore.shared
    @StateObject private var player = AudioPlayerManager.shared
    @StateObject private var indexer = MusicIndexer.shared

    init() {
        Self.configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(indexer)
                .task {
                    await library.loadFromDisk()
                    NowPlayingManager.shared.activate()
                }
        }
    }

    private static func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
        } catch {
            print("[HarmonIQ] Audio session config error: \(error)")
        }
    }
}
