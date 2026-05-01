import SwiftUI
import AVFoundation

@main
struct HarmonIQApp: App {
    @StateObject private var library = LibraryStore.shared
    @StateObject private var player = AudioPlayerManager.shared
    @StateObject private var indexer = MusicIndexer.shared

    init() {
        Self.configureAudioSession()
        Self.configureWinampAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(indexer)
                .preferredColorScheme(.dark)
                .tint(WinampTheme.accent)
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

    private static func configureWinampAppearance() {
        let titleColor = UIColor(red: 0.40, green: 1.00, blue: 0.55, alpha: 1)

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)
        tab.shadowColor = UIColor.black.withAlphaComponent(0.6)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(red: 0.10, green: 0.12, blue: 0.14, alpha: 1)
        nav.titleTextAttributes = [.foregroundColor: titleColor]
        nav.largeTitleTextAttributes = [.foregroundColor: titleColor]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        // Make every UITableView (and therefore every SwiftUI List) transparent so
        // the WinampTheme.appBackground gradient shows through.
        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear
        UICollectionView.appearance().backgroundColor = .clear
    }
}
