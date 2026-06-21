import AppKit

/// Borderless click-through overlay panel: a mic + live waveform while
/// recording, a spinner during whisper/llm, and a red dot on error. Positioned
/// at the configured 8-anchor point with an optional light-gray backing.
final class HudOverlay {
    private let runner: SttRunner
    private let reader = AudioLevelReader(bucketCount: 34)
    private var panel: NSPanel?
    private var view: HudView?
    private var timer: Timer?
    private var hideWork: DispatchWorkItem?
    private var state: SttState = .idle
    private var timeline = HudPhaseTimeline()

    init(runner: SttRunner) { self.runner = runner }

    func update(_ state: SttState) {
        transition(to: state, at: Date())
        switch state {
        case .idle: hide()
        case .error: show(.error); scheduleHide(after: 1.4)
        default: show(state)
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let size = NSSize(width: 286, height: 64)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let v = HudView(frame: NSRect(origin: .zero, size: size), reader: reader, runner: runner)
        p.contentView = v
        panel = p; view = v
    }

    private func currentLayout() -> HudLayout {
        HudLayout(scale: HudLayout.clampScale(AppSettings.shared.hudScale),
                  showIcon: AppSettings.shared.showHudIcon,
                  showWaveform: AppSettings.shared.showHudWaveform,
                  showTimer: AppSettings.shared.showHudTimer)
    }

    private func reposition() {
        guard let panel else { return }
        let screen = targetScreen()
        let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let offset = CGSize(width: CGFloat(AppSettings.shared.hudOffsetX),
                            height: CGFloat(AppSettings.shared.hudOffsetY))
        let origin = AppSettings.shared.hudAnchor.origin(for: panel.frame.size, in: visible, offset: offset)
        panel.setFrameOrigin(origin)
    }

    /// The screen to show the HUD on. When "follow active screen" is on, prefer
    /// the frontmost app's screen, then the screen under the mouse, then main —
    /// so it lands on the right monitor even when window detection comes up empty.
    private func targetScreen() -> NSScreen? {
        guard AppSettings.shared.hudFollowActiveScreen else { return NSScreen.main }
        return activeAppScreen() ?? screenWithMouse() ?? NSScreen.main
    }

    private func screenWithMouse() -> NSScreen? {
        let rects = NSScreen.screens.map { $0.frame }
        guard let idx = ScreenPicker.indexContaining(NSEvent.mouseLocation, in: rects) else { return nil }
        return NSScreen.screens[idx]
    }

    private func show(_ state: SttState) {
        hideWork?.cancel()
        ensurePanel()
        let layout = currentLayout()
        panel?.setContentSize(layout.panelSize)
        view?.frame = NSRect(origin: .zero, size: layout.panelSize)
        view?.layout = layout
        reposition()
        view?.state = state
        view?.showBackground = AppSettings.shared.hudBackground
        view?.backgroundColor = AppSettings.shared.hudBackgroundColor.nsColor
        view?.timeline = timeline
        view?.needsDisplay = true
        panel?.orderFrontRegardless()
        if timer == nil {
            let displayTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                guard let self, let view = self.view else { return }
                if let phase = self.runner.currentPhase(),
                   view.state == .whisper || view.state == .llm,
                   phase != view.state {
                    self.transition(to: phase, at: Date())
                    if phase == .error { self.scheduleHide(after: 1.4) }
                }
                view.state = self.state
                view.timeline = self.timeline
                view.needsDisplay = true
                view.displayIfNeeded()
            }
            displayTimer.tolerance = 0.002
            RunLoop.main.add(displayTimer, forMode: .common)
            timer = displayTimer
        }
    }

    private func transition(to newState: SttState, at now: Date) {
        timeline.transition(to: newState, from: state, at: now)
        state = newState
    }

    private func activeAppScreen() -> NSScreen? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        guard let window = windows.first(where: { info in
            (info[kCGWindowOwnerPID as String] as? Int) == Int(app.processIdentifier) &&
            (info[kCGWindowLayer as String] as? Int) == 0
        }), let b = window[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
        // CGWindowBounds are in top-left global coordinates (y grows downward);
        // NSScreen.frame is bottom-left. Convert the window center into AppKit
        // space before matching it to a screen, or multi-monitor layouts pick
        // the wrong display (the cause of the HUD always landing on main).
        let cg = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        guard let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.screens.first?.frame.height else { return nil }
        let rects = NSScreen.screens.map { $0.frame }
        return ScreenPicker.indexForWindow(topLeftBounds: cg, primaryHeight: primaryHeight, in: rects)
            .map { NSScreen.screens[$0] }
    }

    private func scheduleHide(after s: TimeInterval) {
        let w = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: w)
    }

    private func hide() {
        timer?.invalidate(); timer = nil
        panel?.orderOut(nil)
    }
}

/// Custom drawing; mirrors the Lua canvas shapes closely enough.
final class HudView: NSView {
    var state: SttState = .recording
    var timeline = HudPhaseTimeline()
    var showBackground = false
    var backgroundColor: NSColor = NSColor(white: 0.5, alpha: 0.55)
    /// Geometry + element toggles for the current frame; set by HudOverlay.show().
    var layout = HudLayout(scale: 1, showIcon: true, showWaveform: true, showTimer: true)
    private let reader: AudioLevelReader
    private let runner: SttRunner
    private var levels: [Double]
    private var lastFrameAt = Date()
    private var phase = 0.0
    private var waveTravel = 0.0
    private let wav = RuntimePaths.recordingFile.path

    init(frame: NSRect, reader: AudioLevelReader, runner: SttRunner) {
        self.reader = reader; self.runner = runner
        self.levels = [Double](repeating: 0, count: reader.bucketCount)
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    // State colors (shared by the left icon and the right animation).
    private let recColor = NSColor(red: 0.08, green: 0.95, blue: 0.68, alpha: 1)
    private let whisperColor = NSColor(red: 0.20, green: 0.64, blue: 1.0, alpha: 1)
    private let llmColor = NSColor(red: 0.78, green: 0.54, blue: 1.0, alpha: 1)
    // Geometry comes from `layout` (base coordinates); the whole frame is drawn
    // under a single scale transform so nothing else needs to know about scale.
    private var contentLeft: CGFloat { layout.contentLeft }
    private var contentRight: CGFloat { layout.contentRight }
    private var contentCenterX: CGFloat { layout.contentCenterX }
    private var visualCenterY: CGFloat { layout.visualCenterY }

    override func draw(_ dirty: NSRect) {
        let now = Date()
        let delta = min(1.0 / 15.0, max(0, now.timeIntervalSince(lastFrameAt)))
        lastFrameAt = now
        phase += delta

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.scale(by: layout.scale)
        transform.concat()

        if showBackground {
            backgroundColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: layout.baseWidth, height: layout.baseHeight),
                         xRadius: layout.cornerRadius, yRadius: layout.cornerRadius).fill()
        }
        switch state {
        case .recording:
            if let r = layout.iconRect { drawSymbol("mic.fill", color: recColor, in: r) }
            if layout.showWaveform { drawWave(delta: delta) }
            drawTimerRow(now: now)
        case .whisper:
            if let r = layout.iconRect { drawSymbol("waveform", color: whisperColor, in: r) }
            drawSpinner(color: whisperColor)
            drawTimerRow(now: now)
        case .llm:
            if let r = layout.iconRect { drawSymbol("sparkles", color: llmColor, in: r) }
            drawSpinner(color: llmColor)
            drawTimerRow(now: now)
        case .error:
            drawError()
        case .idle:
            break
        }
    }

    /// Renders an SF Symbol tinted in `color`, centered in `rect`.
    private func drawSymbol(_ name: String, color: NSColor, in rect: NSRect) {
        let cfg = NSImage.SymbolConfiguration(pointSize: rect.height, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) else { return }
        let size = img.size
        let dx = rect.minX + (rect.width - size.width) / 2
        let dy = rect.minY + (rect.height - size.height) / 2
        img.draw(in: NSRect(x: dx, y: dy, width: size.width, height: size.height))
    }

    private func drawWave(delta: TimeInterval) {
        let target = reader.levels(from: URL(fileURLWithPath: wav))
        let count = min(levels.count, target.count)
        guard count > 0 else { return }
        waveTravel = (waveTravel + delta * 20.0).truncatingRemainder(dividingBy: Double(count))

        let decaySpeed = WaveLevelFilter.clampDecaySpeed(AppSettings.shared.hudWaveDecaySpeed)
        for i in 0..<count {
            let raw = interpolated(target, at: Double(i) + waveTravel)
            let shimmer = 0.90 + 0.10 * sin(phase * 16.0 + Double(i) * 0.62)
            let next = min(1, max(0, raw * shimmer))
            levels[i] = WaveLevelFilter.step(current: levels[i], target: next, delta: delta, decaySpeed: decaySpeed)
        }

        switch AppSettings.shared.hudWaveStyle {
        case .bars:   drawWaveBars(count: count)
        case .line:   drawWaveLine(count: count)
        case .mirror: drawWaveMirror(count: count)
        case .dots:   drawWaveDots(count: count)
        case .blocks: drawWaveBlocks(count: count)
        }
    }

    /// X position of bucket `i` so `width`-wide marks span content edge to edge.
    private func waveX(_ i: Int, count: Int, width: CGFloat) -> CGFloat {
        let spacing = (contentRight - contentLeft - width) / CGFloat(max(1, count - 1))
        return contentLeft + CGFloat(i) * spacing
    }

    private func drawWaveBars(count: Int) {
        let barWidth = layout.barWidth
        for i in 0..<count {
            let h = 2.0 + CGFloat(levels[i]) * layout.barMaxHeight
            let a = 0.12 + CGFloat(levels[i]) * 0.88
            recColor.withAlphaComponent(a).setFill()
            let r = NSRect(x: waveX(i, count: count, width: barWidth), y: visualCenterY - h / 2, width: barWidth, height: h)
            NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    private func drawWaveLine(count: Int) {
        let path = NSBezierPath()
        path.lineWidth = 1.8
        let spacing = (contentRight - contentLeft) / CGFloat(max(1, count - 1))
        let amplitude = layout.barMaxHeight / 2
        for i in 0..<count {
            // Oscilloscope line: amplitude tracks the level, so silence is a flat
            // line through the center and louder swings further up and down.
            let osc = sin(phase * 6.0 + Double(i) * 0.5)
            let p = NSPoint(x: contentLeft + CGFloat(i) * spacing,
                            y: visualCenterY + CGFloat(levels[i]) * amplitude * CGFloat(osc))
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        recColor.withAlphaComponent(0.92).setStroke()
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func drawWaveMirror(count: Int) {
        let barWidth = layout.barWidth
        for i in 0..<count {
            let half = (2.0 + CGFloat(levels[i]) * layout.barMaxHeight) / 2
            let x = waveX(i, count: count, width: barWidth)
            let a = 0.12 + CGFloat(levels[i]) * 0.88
            recColor.withAlphaComponent(a).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: visualCenterY + 1, width: barWidth, height: half), xRadius: 1.4, yRadius: 1.4).fill()
            recColor.withAlphaComponent(a * 0.45).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: visualCenterY - 1 - half, width: barWidth, height: half), xRadius: 1.4, yRadius: 1.4).fill()
        }
    }

    private func drawWaveDots(count: Int) {
        for i in 0..<count {
            let d = 2.0 + CGFloat(levels[i]) * (layout.barMaxHeight * 0.5)
            let x = waveX(i, count: count, width: d)
            let a = 0.16 + CGFloat(levels[i]) * 0.84
            recColor.withAlphaComponent(a).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: visualCenterY - d / 2, width: d, height: d)).fill()
        }
    }

    private func drawWaveBlocks(count: Int) {
        let barWidth = layout.barWidth
        let blockH: CGFloat = 3.0
        let gap: CGFloat = 1.5
        for i in 0..<count {
            let total = 2.0 + CGFloat(levels[i]) * layout.barMaxHeight
            let x = waveX(i, count: count, width: barWidth)
            let a = 0.14 + CGFloat(levels[i]) * 0.86
            recColor.withAlphaComponent(a).setFill()
            let segments = max(1, Int(total / (blockH + gap)))
            for s in 0..<segments {
                let y = visualCenterY - total / 2 + CGFloat(s) * (blockH + gap)
                NSBezierPath(rect: NSRect(x: x, y: y, width: barWidth, height: blockH)).fill()
            }
        }
    }

    private func interpolated(_ values: [Double], at index: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let count = values.count
        let wrapped = index.truncatingRemainder(dividingBy: Double(count))
        let lower = Int(floor(wrapped))
        let upper = (lower + 1) % count
        let fraction = wrapped - Double(lower)
        return values[lower] * (1 - fraction) + values[upper] * fraction
    }

    private func drawSpinner(color: NSColor) {
        let radius: CGFloat = 15.0
        let count = 12
        let head = (phase * 1.55).truncatingRemainder(dividingBy: 1.0)
        for i in 0..<count {
            let angle = Double(i) / Double(count) * .pi * 2
            let progress = Double(i) / Double(count)
            let wrappedDistance = (progress - head + 1.0).truncatingRemainder(dividingBy: 1.0)
            let distance = min(wrappedDistance, 1.0 - wrappedDistance)
            let intensity = pow(max(0, 1.0 - distance * 2.4), 1.5)
            let alpha = 0.16 + intensity * 0.84
            let dot = CGFloat(3.6 + intensity * 1.1)
            color.withAlphaComponent(alpha).setFill()
            let x = contentCenterX + CGFloat(cos(angle)) * radius - dot / 2
            let y = visualCenterY + CGFloat(sin(angle)) * radius - dot / 2
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dot, height: dot)).fill()
        }
    }

    private func drawError() {
        NSColor(red: 1.0, green: 0.26, blue: 0.24, alpha: 0.95).setFill()
        NSBezierPath(ovalIn: NSRect(x: contentCenterX - 11, y: visualCenterY - 11, width: 22, height: 22)).fill()
    }

    private func drawTimerRow(now: Date) {
        guard layout.showTimer else { return }
        let durations = timeline.durations(at: now, state: state)
        let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let operatorFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let operatorColor = NSColor.white.withAlphaComponent(0.52)
        let totalColor = NSColor.white.withAlphaComponent(0.90)
        var items: [(text: String, attrs: [NSAttributedString.Key: Any])] = []

        func attrs(_ color: NSColor, _ font: NSFont = digitFont) -> [NSAttributedString.Key: Any] {
            [.font: font, .foregroundColor: color.withAlphaComponent(0.94)]
        }

        if let recording = durations.recording {
            items.append((formatDuration(recording), attrs(recColor)))
        }
        if let whisper = durations.whisper {
            items.append(("+", attrs(operatorColor, operatorFont)))
            items.append((formatDuration(whisper), attrs(whisperColor)))
        }
        if let llm = durations.llm {
            items.append(("+", attrs(operatorColor, operatorFont)))
            items.append((formatDuration(llm), attrs(llmColor)))
        }
        if durations.whisper != nil || durations.llm != nil {
            items.append(("=", attrs(operatorColor, operatorFont)))
            items.append((formatDuration(durations.total), attrs(totalColor)))
        }
        guard !items.isEmpty else { return }

        let gap: CGFloat = 5
        let widths = items.map { $0.text.size(withAttributes: $0.attrs).width }
        let textWidth = widths.reduce(0, +) + gap * CGFloat(max(0, items.count - 1))
        let pillWidth = min(contentRight - contentLeft, max(58, textWidth + 18))
        let pillX = min(max(contentLeft, contentCenterX - pillWidth / 2), contentRight - pillWidth)
        let pill = NSRect(x: pillX, y: layout.timerPillY, width: pillWidth, height: layout.timerPillHeight)
        NSColor.black.withAlphaComponent(0.24).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 8.5, yRadius: 8.5).fill()

        var x = pill.midX - textWidth / 2
        for (index, item) in items.enumerated() {
            item.text.draw(at: NSPoint(x: x, y: pill.minY + 3), withAttributes: item.attrs)
            x += widths[index] + gap
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
