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

    private func reposition() {
        guard let panel else { return }
        let screen = activeAppScreen() ?? NSScreen.main
        let origin = AppSettings.shared.hudAnchor.origin(for: panel.frame.size, in: screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero)
        panel.setFrameOrigin(origin)
    }

    private func show(_ state: SttState) {
        hideWork?.cancel()
        ensurePanel(); reposition()
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
        }), let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
        let rect = CGRect(x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0, width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0)
        return NSScreen.screens.max { a, b in
            a.frame.intersection(rect).width * a.frame.intersection(rect).height <
                b.frame.intersection(rect).width * b.frame.intersection(rect).height
        }
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
    // Left icon slot — where the mic used to sit.
    private let iconRect = NSRect(x: 10, y: 28, width: 24, height: 24)
    private var contentLeft: CGFloat { 46 }
    private var contentRight: CGFloat { bounds.width - 12 }
    private var contentCenterX: CGFloat { (contentLeft + contentRight) / 2 }
    private let visualCenterY: CGFloat = 40

    override func draw(_ dirty: NSRect) {
        let now = Date()
        let delta = min(1.0 / 15.0, max(0, now.timeIntervalSince(lastFrameAt)))
        lastFrameAt = now
        phase += delta
        if showBackground {
            backgroundColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        }
        switch state {
        case .recording:
            drawSymbol("mic.fill", color: recColor, in: iconRect)
            drawWave(delta: delta)
            drawTimerRow(now: now)
        case .whisper:
            drawSymbol("waveform", color: whisperColor, in: iconRect)
            drawSpinner(color: whisperColor)
            drawTimerRow(now: now)
        case .llm:
            drawSymbol("sparkles", color: llmColor, in: iconRect)
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

        let rise = min(1, delta * 30.0)
        let fall = min(1, delta * 3.2)
        for i in 0..<count {
            let raw = interpolated(target, at: Double(i) + waveTravel)
            let shimmer = 0.90 + 0.10 * sin(phase * 16.0 + Double(i) * 0.62)
            let next = min(1, max(0, raw * shimmer))
            let rate = next >= levels[i] ? rise : fall
            levels[i] += (next - levels[i]) * rate
        }

        let barWidth: CGFloat = 3.2
        let spacing = (contentRight - contentLeft - barWidth) / CGFloat(max(1, count - 1))
        for i in 0..<count {
            let h = 2.0 + CGFloat(levels[i]) * 30.0
            let a = 0.12 + CGFloat(levels[i]) * 0.88
            recColor.withAlphaComponent(a).setFill()
            let r = NSRect(x: contentLeft + CGFloat(i) * spacing,
                           y: visualCenterY - h / 2,
                           width: barWidth,
                           height: h)
            NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5).fill()
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
        guard AppSettings.shared.showHudTimer else { return }
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
        let pill = NSRect(x: pillX, y: 6, width: pillWidth, height: 17)
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
