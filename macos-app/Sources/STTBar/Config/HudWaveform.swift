import Foundation

/// Pure per-bucket smoothing for the HUD waveform. Levels rise quickly (fast
/// attack) and fall back slowly (release); `decaySpeed` scales the release so the
/// user can make the wave snappier (higher) or give it longer tails (lower).
enum WaveLevelFilter {
    static let attackRate: Double = 30.0
    static let baseFallRate: Double = 3.2

    static func step(current: Double, target: Double, delta: Double, decaySpeed: Double) -> Double {
        let rise = min(1, delta * attackRate)
        let fall = min(1, delta * baseFallRate * decaySpeed)
        let rate = target >= current ? rise : fall
        let next = current + (target - current) * rate
        return min(1, max(0, next))
    }

    /// Clamp a user-supplied decay speed to a sane range.
    static func clampDecaySpeed(_ raw: Double) -> Double { min(3.0, max(0.3, raw)) }
}

/// Selectable waveform shapes. All render the same smoothed `levels[]`, so
/// switching is just a draw branch — no extra data. `rawValue` persists.
enum HudWaveStyle: String, CaseIterable, Codable {
    case bars, line, mirror, dots, blocks

    var label: String {
        switch self {
        case .bars:   return L("Balken", "Bars")
        case .line:   return L("Linie", "Line")
        case .mirror: return L("Spiegel", "Mirror")
        case .dots:   return L("Punkte", "Dots")
        case .blocks: return L("Blöcke", "Blocks")
        }
    }
}
