import SwiftUI
import AVFoundation

@main
struct HarmonIQApp: App {
    @StateObject private var library = LibraryStore.shared
    @StateObject private var player = AudioPlayerManager.shared
    @StateObject private var indexer = MusicIndexer.shared
    @StateObject private var skinManager = SkinManager.shared

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
                .environmentObject(skinManager)
                .preferredColorScheme(.dark)
                .tint(WinampTheme.accent)
                .task {
                    await library.loadFromDisk()
                    NowPlayingManager.shared.activate()
                }
                // Drive-online detection on foreground: if the user plugged
                // a drive in while HarmonIQ was backgrounded, this fires
                // when they tap back. Roots that came online get their
                // tracks loaded without a manual Reload tap.
                .onReceive(NotificationCenter.default.publisher(
                    for: UIApplication.didBecomeActiveNotification)) { _ in
                    library.reloadOfflineRoots()
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
        // Route through the theme so any future tweak to lcdGlow propagates
        // to the tab/nav title color too. Followup flagged on PR #76.
        let titleColor = UIColor(WinampTheme.lcdGlow)

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
