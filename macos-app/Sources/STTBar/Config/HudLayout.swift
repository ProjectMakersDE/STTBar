import AppKit

/// Pure geometry of the HUD panel. Base coordinates are scale-independent; the
/// view draws under a single `scale` context transform, so only `panelSize`
/// multiplies by `scale`. Hiding the icon drops its left slot (content
/// re-centers); hiding the timer drops the bottom row (the panel gets shorter
/// and the visual content centers vertically) — which is why the background,
/// drawn over the panel bounds, automatically adapts to what is shown.
struct HudLayout: Equatable {
    let scale: CGFloat
    let showIcon: Bool
    let showWaveform: Bool
    let showTimer: Bool

    // Base (scale = 1) constants, matching the original fixed 286×64 design.
    private static let rightMargin: CGFloat = 12
    private static let leftMarginNoIcon: CGFloat = 12
    private static let iconInset: CGFloat = 10
    private static let iconSize: CGFloat = 24
    private static let iconToContentGap: CGFloat = 12
    private static let waveContentWidth: CGFloat = 228
    // Collapsed center: only used when BOTH the waveform and the timer are off,
    // so it just needs to hold the whisper/llm spinner. When the timer is shown
    // we keep the full wave width, because the combined `mm:ss + mm:ss = mm:ss`
    // row needs that room and would otherwise overflow the panel/background.
    private static let collapsedContentWidth: CGFloat = 64
    private static let heightWithTimer: CGFloat = 64
    private static let heightNoTimer: CGFloat = 44
    private static let visualCenterWithTimer: CGFloat = 40

    var contentLeft: CGFloat {
        showIcon ? Self.iconInset + Self.iconSize + Self.iconToContentGap : Self.leftMarginNoIcon
    }
    /// Width of the central area. Collapses only when the waveform AND the timer
    /// are both hidden; a visible timer keeps the full width so it cannot overflow.
    var contentAreaWidth: CGFloat { (showWaveform || showTimer) ? Self.waveContentWidth : Self.collapsedContentWidth }
    var baseWidth: CGFloat { contentLeft + contentAreaWidth + Self.rightMargin }
    var baseHeight: CGFloat { showTimer ? Self.heightWithTimer : Self.heightNoTimer }
    var contentRight: CGFloat { baseWidth - Self.rightMargin }
    var contentCenterX: CGFloat { (contentLeft + contentRight) / 2 }
    var visualCenterY: CGFloat { showTimer ? Self.visualCenterWithTimer : baseHeight / 2 }

    /// Icon slot, in base coordinates; nil when the icon is hidden.
    var iconRect: NSRect? {
        guard showIcon else { return nil }
        return NSRect(x: Self.iconInset, y: visualCenterY - Self.iconSize / 2,
                      width: Self.iconSize, height: Self.iconSize)
    }

    var timerPillY: CGFloat { 6 }
    var timerPillHeight: CGFloat { 17 }
    var barMaxHeight: CGFloat { 30 }
    var barWidth: CGFloat { 3.2 }
    var cornerRadius: CGFloat { 10 }

    /// The panel's pixel size — the only value that scales.
    var panelSize: NSSize { NSSize(width: baseWidth * scale, height: baseHeight * scale) }

    /// Clamp a user-supplied scale to a sane range.
    static func clampScale(_ raw: Double) -> CGFloat {
        CGFloat(min(2.0, max(0.7, raw)))
    }
}

/// Pure screen selection used when picking the monitor to show the HUD on.
enum ScreenPicker {
    /// Index of the first rect that contains `point` (mouse-location fallback).
    static func indexContaining(_ point: CGPoint, in rects: [CGRect]) -> Int? {
        rects.firstIndex { $0.contains(point) }
    }

    /// Index of the screen a window sits on. `CGWindowBounds` are top-left
    /// (y grows down); AppKit `screenFrames` are bottom-left. Flip the window
    /// center through `primaryHeight` before matching, or multi-monitor layouts
    /// pick the wrong display.
    static func indexForWindow(topLeftBounds cg: CGRect, primaryHeight: CGFloat, in screenFrames: [CGRect]) -> Int? {
        let center = CGPoint(x: cg.midX, y: primaryHeight - cg.midY)
        return indexContaining(center, in: screenFrames)
    }
}
