import SwiftUI

/// Winamp-style 10-band graphic equalizer + preamp + on/off + presets.
///
/// **Currently visual only** — moving sliders does not yet alter the audio.
/// Hooking real EQ into AudioPlayerManager requires switching from
/// `AVAudioPlayer` to `AVAudioEngine` + `AVAudioUnitEQ`, which is a separate,
/// bigger change. The slider state lives here so the UI feels alive and the
/// settings can be migrated over once the audio path moves to AVAudioEngine.
struct SkinnedEqualizerView: View {
    @StateObject private var state = EqualizerState.shared

    private let bands: [String] = ["60", "170", "310", "600", "1K", "3K", "6K", "12K", "14K", "16K"]

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack(spacing: 8) {
                Text("EQUALIZER")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(WinampTheme.lcdGlow)
                Spacer()
                Toggle(isOn: $state.isEnabled) {
                    Text("ON")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(state.isEnabled ? WinampTheme.lcdGlow : WinampTheme.lcdDim)
                }
                .toggleStyle(.button)
                .tint(WinampTheme.accent)
                Toggle(isOn: $state.autoMode) {
                    Text("AUTO")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(state.autoMode ? WinampTheme.lcdGlow : WinampTheme.lcdDim)
                }
                .toggleStyle(.button)
                .tint(WinampTheme.accent)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(LinearGradient(colors: [Color(white: 0.18), Color(white: 0.10)], startPoint: .top, endPoint: .bottom))

            // Band sliders + preamp
            HStack(alignment: .bottom, spacing: 6) {
                bandSlider(title: "PRE", value: $state.preamp, isPreamp: true)
                Rectangle().fill(Color(white: 0.2)).frame(width: 1)
                ForEach(bands.indices, id: \.self) { i in
                    bandSlider(title: bands[i], value: $state.bands[i], isPreamp: false)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // Footer note
            Text("Visual only — full audio EQ coming with AVAudioEngine")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(WinampTheme.lcdDim)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
        }
        .background(Color.black)
        .overlay(Rectangle().stroke(Color(white: 0.25), lineWidth: 1))
    }

    private func bandSlider(title: String, value: Binding<Double>, isPreamp: Bool) -> some View {
        VStack(spacing: 2) {
            VerticalDbSlider(value: value, enabled: state.isEnabled)
                .frame(width: 22, height: 90)
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(isPreamp ? WinampTheme.accent : (state.isEnabled ? WinampTheme.lcdGlow : WinampTheme.lcdDim))
        }
    }
}

/// -12 dB ... +12 dB vertical slider with a center notch line. Drawn in a
/// hand-rolled style so it matches the Winamp aesthetic without requiring
/// per-skin sprite atlases.
private struct VerticalDbSlider: View {
    @Binding var value: Double // -1...1, center 0 = 0 dB
    var enabled: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let centerY = h / 2
            let knobH: CGFloat = 8
            let travel = h - knobH
            // value -1..1 → 0..travel (top is +12 dB i.e. value = +1)
            let knobY = (1 - (value + 1) / 2) * travel

            ZStack(alignment: .topLeading) {
                // Track groove
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(white: 0.08))
                    .frame(width: 4, height: h)
                    .offset(x: (w - 4) / 2, y: 0)

                // Center 0 dB line
                Rectangle()
                    .fill(WinampTheme.lcdDim.opacity(0.4))
                    .frame(width: w, height: 1)
                    .offset(x: 0, y: centerY)

                // Knob
                RoundedRectangle(cornerRadius: 2)
                    .fill(enabled ? WinampTheme.lcdGlow : WinampTheme.lcdDim)
                    .frame(width: w, height: knobH)
                    .offset(x: 0, y: knobY)
                    .shadow(color: enabled ? WinampTheme.lcdGlow.opacity(0.5) : .clear, radius: 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let raw = (drag.location.y - knobH / 2) / max(1, travel)
                        let clamped = max(0, min(1, raw))
                        // top = +1, bottom = -1
                        value = (1 - clamped) * 2 - 1
                    }
            )
            .onTapGesture(count: 2) {
                value = 0 // double-tap centers
            }
        }
    }
}

@MainActor
final class EqualizerState: ObservableObject {
    static let shared = EqualizerState()

    @Published var isEnabled: Bool = false
    @Published var autoMode: Bool = false
    @Published var preamp: Double = 0
    @Published var bands: [Double] = Array(repeating: 0, count: 10)
}
