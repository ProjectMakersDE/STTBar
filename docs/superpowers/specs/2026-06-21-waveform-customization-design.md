# Spec: Waveform Customization (Package 3)

Date: 2026-06-21 · Branch: `develop`

## Goal

1. **Decay speed**: make the waveform's rise/release (how fast bars fall back) adjustable.
2. **Style switcher**: keep the current bars and add a few popular shapes the user can
   switch between (line, mirrored bars, dots, blocks).

## Background

`HudView.drawWave()` reads 34 live levels and smooths them per frame with
`rise = delta*30`, `fall = delta*3.2`, then draws rounded bars. The smoothing math is
inline; the style is hard-coded bars.

## Design

### New settings (UserDefaults via `AppSettings`, immediate; mirrored in `SettingsModel`)
- `hudWaveDecaySpeed: Double = 1.0` (clamped 0.3…3.0) — multiplies the fall rate, so
  higher = snappier release, lower = longer tails.
- `hudWaveStyle: HudWaveStyle = .bars` (stored as `rawValue`).

### Pure logic (TDD)
- `WaveLevelFilter.step(current:target:delta:decaySpeed:)` — the per-bucket smoothing,
  extracted. Rises with the fixed fast attack; falls with `baseFall * decaySpeed`. Tested:
  a target above current rises quickly; a target below current decays, and a larger
  `decaySpeed` decays more per frame; result stays in 0…1.
- `HudWaveStyle: String, CaseIterable` = `bars, line, mirror, dots, blocks` — with a
  `label`; `rawValue` round-trips for persistence. (User explicitly asked for ~5 switchable
  shapes; each reuses the same `levels[]`, so no extra data, just a draw branch.)

### Wiring
- `HudView` uses `WaveLevelFilter.step` with `AppSettings.shared.hudWaveDecaySpeed`, and
  branches its center drawing on `AppSettings.shared.hudWaveStyle`. Each style renders the
  same smoothed `levels[]` array; colors/animation phase are shared.
- Settings UI: a `Picker` for the style and a `Slider` for decay speed in the Display tab.

## Out of scope (YAGNI)

No per-style parameters, no custom colors per style, no FFT/real frequency analysis.
