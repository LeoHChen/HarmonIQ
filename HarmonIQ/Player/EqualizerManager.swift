import Foundation
import AVFoundation
import Combine

/// Standard 10-band Winamp graphic-EQ frequencies, in Hz.
let equalizerFrequencies: [Float] = [60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000]

/// Built-in named preset (band gains in dB, preamp in dB).
struct EqualizerPreset: Codable, Hashable, Identifiable {
    var id: String { name }
    let name: String
    let bands: [Float]   // length 10, dB
    let preamp: Float    // dB

    static let flat = EqualizerPreset(
        name: "Flat",
        bands: Array(repeating: 0, count: 10), preamp: 0)
    static let rock = EqualizerPreset(
        name: "Rock",
        bands: [5, 4, 2, -1, -3, -2, 2, 4, 5, 5], preamp: 0)
    static let pop = EqualizerPreset(
        name: "Pop",
        bands: [-1, 0, 2, 4, 5, 4, 2, 0, -1, -2], preamp: 0)
    static let jazz = EqualizerPreset(
        name: "Jazz",
        bands: [4, 3, 1, 2, -1, -1, 0, 1, 3, 4], preamp: 0)
    static let classical = EqualizerPreset(
        name: "Classical",
        bands: [3, 2, 0, 0, 0, 0, -2, -3, -3, -4], preamp: 0)
    static let bassBoost = EqualizerPreset(
        name: "Bass Boost",
        bands: [8, 7, 5, 3, 1, 0, 0, 0, 0, 0], preamp: -2)
    static let vocalBoost = EqualizerPreset(
        name: "Vocal Boost",
        bands: [-3, -2, -1, 1, 4, 4, 3, 2, 0, -1], preamp: 0)

    static let allBuiltIn: [EqualizerPreset] = [
        .flat, .rock, .pop, .jazz, .classical, .bassBoost, .vocalBoost,
    ]
}

/// Owns the `AVAudioUnitEQ` instance + the persisted band gains, preamp,
/// master enable, and active preset name. `AudioPlayerManager` reads
/// `eqUnit` and inserts it into the engine graph; UI binds to the
/// @Published properties.
@MainActor
final class EqualizerManager: ObservableObject {
    static let shared = EqualizerManager()

    /// 10-band parametric EQ. Insert into the engine graph between the
    /// player node and the main mixer.
    let eqUnit: AVAudioUnitEQ

    /// dB gain per band, length 10. -12...+12.
    @Published var bands: [Float] {
        didSet { applyBands(); if !suppressPersist { persist() } }
    }
    /// dB preamp (-12...+12) — mapped to `eqUnit.globalGain`.
    @Published var preamp: Float {
        didSet { applyPreamp(); if !suppressPersist { persist() } }
    }
    /// Master bypass. When false, all bands are passed through unchanged.
    @Published var isEnabled: Bool {
        didSet { applyBypass(); if !suppressPersist { persist() } }
    }

    /// When true, didSet observers skip the per-write `persist()` so a
    /// multi-property update like `applyPreset` only triggers one
    /// UserDefaults write. Issue #83 — avoids back-to-back synchronous
    /// UserDefaults serialization that the user could feel on tap.
    private var suppressPersist = false
    /// Active preset name (built-in or "Custom" when band gains have been
    /// hand-tuned). Used by the UI to highlight the active row.
    @Published private(set) var activePreset: String

    private let bandsKey = "harmoniq.eq.bands"
    private let preampKey = "harmoniq.eq.preamp"
    private let enabledKey = "harmoniq.eq.enabled"
    private let presetKey = "harmoniq.eq.preset"

    init() {
        let eq = AVAudioUnitEQ(numberOfBands: equalizerFrequencies.count)
        for (i, freq) in equalizerFrequencies.enumerated() {
            eq.bands[i].filterType = .parametric
            eq.bands[i].frequency = freq
            eq.bands[i].bandwidth = 1.0   // octaves
            eq.bands[i].gain = 0
            eq.bands[i].bypass = false
        }
        eq.globalGain = 0
        // Bypass off by default until user enables EQ — see applyBypass.
        eq.bypass = true
        self.eqUnit = eq

        // Load persisted state.
        let d = UserDefaults.standard
        let savedBands = (d.array(forKey: bandsKey) as? [Double])?.map { Float($0) } ?? Array(repeating: 0, count: 10)
        self.bands = savedBands.count == 10 ? savedBands : Array(repeating: 0, count: 10)
        self.preamp = (d.object(forKey: preampKey) as? Double).map { Float($0) } ?? 0
        self.isEnabled = (d.object(forKey: enabledKey) as? Bool) ?? false
        self.activePreset = d.string(forKey: presetKey) ?? EqualizerPreset.flat.name

        applyBands()
        applyPreamp()
        applyBypass()
    }

    func applyPreset(_ preset: EqualizerPreset) {
        // Coalesce all the writes into a single persist() at the end so a
        // preset commit feels instant — issue #83. Without this, setting
        // bands then preamp triggers two separate UserDefaults serializations
        // back-to-back on the main thread.
        suppressPersist = true
        bands = preset.bands
        preamp = preset.preamp
        suppressPersist = false
        activePreset = preset.name
        UserDefaults.standard.set(preset.name, forKey: presetKey)
        persist()
    }

    func resetToFlat() { applyPreset(.flat) }

    /// Mark the current band layout as "Custom" — called when the user
    /// drags an individual slider away from the active preset.
    func markCustomIfDiverged() {
        if matchingPreset() == nil && activePreset != "Custom" {
            activePreset = "Custom"
            UserDefaults.standard.set("Custom", forKey: presetKey)
        }
    }

    private func matchingPreset() -> EqualizerPreset? {
        EqualizerPreset.allBuiltIn.first { p in
            p.bands == bands && p.preamp == preamp
        }
    }

    // MARK: - Apply to the unit

    private func applyBands() {
        let count = min(bands.count, eqUnit.bands.count)
        for i in 0..<count {
            eqUnit.bands[i].gain = bands[i]
        }
    }

    private func applyPreamp() {
        eqUnit.globalGain = preamp
    }

    private func applyBypass() {
        eqUnit.bypass = !isEnabled
    }

    // MARK: - Persistence

    private func persist() {
        let d = UserDefaults.standard
        d.set(bands.map { Double($0) }, forKey: bandsKey)
        d.set(Double(preamp), forKey: preampKey)
        d.set(isEnabled, forKey: enabledKey)
    }
}
