import SwiftUI
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(ActivityKit)
@available(iOS 16.1, *)
struct HarmonIQLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HarmonIQActivityAttributes.self) { context in
            // Lock-screen banner.
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(Color(red: 0.40, green: 1.0, blue: 0.55))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Artwork(state: context.state, size: 38)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.trackTitle)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                        Text(context.state.artist)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "play.fill" : "pause.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: progressFraction(state: context.state))
                        .tint(Color(red: 0.40, green: 1.0, blue: 0.55))
                }
            } compactLeading: {
                Artwork(state: context.state, size: 18)
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "play.fill" : "pause.fill")
                    .foregroundStyle(.green)
            } minimal: {
                Image(systemName: "music.note")
                    .foregroundStyle(.green)
            }
            .widgetURL(URL(string: "harmoniq://now-playing"))
            .keylineTint(Color(red: 0.40, green: 1.0, blue: 0.55))
        }
    }
}

@available(iOS 16.1, *)
private struct LockScreenView: View {
    let state: HarmonIQActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Artwork(state: state, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.trackTitle)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(state.artist)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                ProgressView(value: progressFraction(state: state))
                    .tint(Color(red: 0.40, green: 1.0, blue: 0.55))
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
            Image(systemName: state.isPlaying ? "play.fill" : "pause.fill")
                .font(.title2)
                .foregroundStyle(Color(red: 0.40, green: 1.0, blue: 0.55))
                .padding(.trailing, 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

@available(iOS 16.1, *)
private struct Artwork: View {
    let state: HarmonIQActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        Group {
            if let data = state.albumArt, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.black.opacity(0.6)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(Color(red: 0.40, green: 1.0, blue: 0.55))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

@available(iOS 16.1, *)
private func progressFraction(state: HarmonIQActivityAttributes.ContentState) -> Double {
    guard state.duration > 0 else { return 0 }
    return min(1, max(0, state.elapsed / state.duration))
}
#endif
