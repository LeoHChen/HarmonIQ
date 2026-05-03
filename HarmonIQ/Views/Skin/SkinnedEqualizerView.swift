import SwiftUI

/// Winamp-style 10-band graphic equalizer: preamp + 10 sliders + on/off + presets.
/// Drives `EqualizerManager.shared`, which feeds the `AVAudioUnitEQ` inserted
/// between the player node and the main mixer (issue #28).
struct SkinnedEqualizerView: View {
    @StateObject private var eq = EqualizerManager.shared
    @EnvironmentObject var skinManager: SkinManager
    @State private var showPresetMenu = false

    private let bandLabels: [String] = ["60", "170", "310", "600", "1K", "3K", "6K", "12K", "14K", "16K"]

    var body: some View {
        let palette = SkinPalette(skin: skinManager.activeSkin)
        let activeColor = palette.current
        let dimColor = palette.normal.opacity(0.6)

        VStack(spacing: 0) {
            // Title bar
            HStack(spacing: 8) {
                Text("EQUALIZER")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(activeColor)
                Spacer()
                Toggle(isOn: $eq.isEnabled) {
                    Text("ON")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(eq.isEnabled ? activeColor : dimColor)
                }
                .toggleStyle(.button)
                .tint(activeColor)
                Menu {
                    ForEach(EqualizerPreset.allBuiltIn) { preset in
                        Button {
                            eq.applyPreset(preset)
                        } label: {
                            if preset.name == eq.activePreset {
                                Label(preset.name, systemImage: "checkmark")
                            } else {
                                Text(preset.name)
                            }
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        eq.resetToFlat()
                    } label: {
                        Label("Reset to Flat", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    // Issue #83: bumped font 10→11, padding h:6/v:2 → h:10/v:6
                    // (~74×26 visible chip + outer .padding extends the hit
                    // surface another 4pt). The EQ header is space-
                    // constrained so we can't quite hit Apple's 44pt HIG
                    // minimum, but this is well above the previous ~50×14 and
                    // first-tap dispatch on the SwiftUI Menu becomes reliable
                    // because the label's hit shape is now meaningfully
                    // larger than the surrounding text.
                    HStack(spacing: 4) {
                        Text(eq.activePreset.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(activeColor)
                    .background(activeColor.opacity(0.18))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(activeColor.opacity(0.55)))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(4)
                    .contentShape(Rectangle())
                }
                .menuOrder(.fixed)
                .accessibilityLabel("Equalizer presets")
                .accessibilityHint("Active preset: \(eq.activePreset)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(LinearGradient(colors: [Color(white: 0.18), Color(white: 0.10)], startPoint: .top, endPoint: .bottom))

            // Band sliders + preamp
            HStack(alignment: .bottom, spacing: 6) {
                bandSlider(title: "PRE",
                           value: dbBinding(get: { eq.preamp },
                                            set: { newDb in eq.preamp = newDb; eq.markCustomIfDiverged() }),
                           isPreamp: true,
                           activeColor: activeColor, dimColor: dimColor)
                Rectangle().fill(Color(white: 0.2)).frame(width: 1)
                ForEach(bandLabels.indices, id: \.self) { i in
                    bandSlider(title: bandLabels[i],
                               value: dbBinding(get: { eq.bands[i] },
                                                set: { newDb in
                                                    var copy = eq.bands
                                                    copy[i] = newDb
                                                    eq.bands = copy
                                                    eq.markCustomIfDiverged()
                                                }),
                               isPreamp: false,
                               activeColor: activeColor, dimColor: dimColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(palette.background)
        .overlay(Rectangle().stroke(Color(white: 0.25), lineWidth: 1))
    }

    /// Slider works in -1...1; the manager stores -12...+12 dB. Bridge them.
    private func dbBinding(get: @escaping () -> Float, set: @escaping (Float) -> Void) -> Binding<Double> {
        Binding<Double>(
            get: { Double(get() / 12.0) },
            set: { newVal in set(Float(max(-1, min(1, newVal)) * 12.0)) }
        )
    }

    private func bandSlider(title: String, value: Binding<Double>, isPreamp: Bool,
                            activeColor: Color, dimColor: Color) -> some View {
        VStack(spacing: 2) {
            VerticalDbSlider(value: value, enabled: eq.isEnabled,
                             activeColor: activeColor, dimColor: dimColor)
                .frame(width: 22, height: 90)
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(isPreamp ? activeColor : (eq.isEnabled ? activeColor : dimColor))
        }
    }
}

/// -12 dB ... +12 dB vertical slider with a center notch line. Drawn in a
/// hand-rolled style so it matches the Winamp aesthetic without requiring
/// per-skin sprite atlases.
private struct VerticalDbSlider: View {
    @Binding var value: Double // -1...1, center 0 = 0 dB
    var enabled: Bool
    var activeColor: Color
    var dimColor: Color

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
                    .fill(dimColor.opacity(0.5))
                    .frame(width: w, height: 1)
                    .offset(x: 0, y: centerY)

                // Knob
                RoundedRectangle(cornerRadius: 2)
                    .fill(enabled ? activeColor : dimColor)
                    .frame(width: w, height: knobH)
                    .offset(x: 0, y: knobY)
                    .shadow(color: enabled ? activeColor.opacity(0.5) : .clear, radius: 2)
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
