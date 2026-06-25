# Spec: HUD Placement & Layout (Package 2)

Date: 2026-06-21 · Branch: `develop`

## Goal

Quality-of-life control over the recording HUD ("Anzeige"):
1. **Position**: keep the 8 anchors, add an **X/Y offset** (fine nudge).
2. **Follow active monitor**: a toggle; show on the screen the user is active on, not
   always the main screen. Fix the existing detection where it falls back to main.
3. **Size**: an adjustable scale factor.
4. **Per-element toggles**: icon, timer (exists), waveform — with the rest **re-centering**
   when something is hidden.
5. **Background adapts** to which elements are shown (panel reflows, so the backing fits).

## Background

`HudOverlay` makes a fixed 286×64 `NSPanel`; `HudView` draws with absolute constants.
`reposition()` already calls `activeAppScreen()` (frontmost-app window → best screen),
falling back to `NSScreen.main` — likely why it "always shows on main" when the frontmost
app has no standard window. `HudAnchor.origin(for:in:margin:)` is pure.

## Design

### New settings (UserDefaults via `AppSettings`, immediate; mirrored in `SettingsModel`)
- `hudOffsetX: Int = 0`, `hudOffsetY: Int = 0` (points; +x right, +y up).
- `hudFollowActiveScreen: Bool = true`.
- `hudScale: Double = 1.0` (clamped 0.7…2.0).
- `showHudIcon: Bool = true`, `showHudWaveform: Bool = true` (`showHudTimer` already exists).

### Pure logic (TDD)
- `HudAnchor.origin(..., offset: CGSize)` — adds the offset to the computed origin.
- `HudLayout(scale:showIcon:showWaveform:showTimer:)` — computes `panelSize` and the
  content rects from base metrics × scale. Invariants:
  - `panelSize` scales linearly with `scale`.
  - `iconRect == nil` when `!showIcon`; `contentLeft` is smaller (no icon slot) so the
    wave/spinner re-centers.
  - `panelSize.height` is smaller when `!showTimer` (timer row dropped) and the visual
    center moves to the panel's vertical middle.
  - `contentRight == panelSize.width - rightMargin·scale`.
- `ScreenPicker.indexContaining(_ point:in rects:)` — pure helper used for the
  mouse-location fallback (`activeAppScreen ?? screenWithMouse ?? main`) so "follow" lands
  on the right monitor even when window detection fails.

### Wiring
- `HudOverlay.show()` recomputes `HudLayout` from current settings each time it shows
  (so changed scale/toggles take effect), resizes the panel + view, then `reposition()`
  with anchor + offset and the follow-screen choice.
- `HudView` reads its rects/flags from `HudLayout`; draws icon only if `showIcon`, the
  recording wave only if `showWaveform` (spinner for whisper/llm always shows), timer only
  if `showHudTimer`. Background fills `bounds`, so it adapts automatically to the reflow.

## Out of scope (YAGNI)

No free-drag positioning, no per-monitor pinning to a named display, no animation of resize.
