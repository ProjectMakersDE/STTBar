import AppKit

/// Borderless click-through overlay panel that mirrors the Hammerspoon HUD:
/// a mic + live waveform while recording, a spinner during whisper/llm, and a
/// red dot on error. Positioned at the configured 8-anchor point with an
/// optional light-gray backing.
final class HudOverlay {
    private let runner: SttRunner
    private let reader = AudioLevelReader(bucketCount: 22)
    private var panel: NSPanel?
    private var view: HudView?
    private var timer: Timer?
    private var hideWork: DispatchWorkItem?

    init(runner: SttRunner) { self.runner = runner }

    func update(_ state: SttState) {
        switch state {
        case .idle: hide()
        case .error: show(.error); scheduleHide(after: 1.4)
        default: show(state)
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let size = NSSize(width: 190, height: 46)
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
        guard let panel, let screen = NSScreen.main else { return }
        let origin = AppSettings.shared.hudAnchor.origin(for: panel.frame.size, in: screen.frame)
        panel.setFrameOrigin(origin)
    }

    private func show(_ state: SttState) {
        hideWork?.cancel()
        ensurePanel(); reposition()
        view?.state = state
        view?.showBackground = AppSettings.shared.hudBackground
        view?.backgroundColor = AppSettings.shared.hudBackgroundColor.nsColor
        view?.needsDisplay = true
        panel?.orderFrontRegardless()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self, let view = self.view else { return }
                if let phase = self.runner.currentPhase(), view.state == .whisper || view.state == .llm {
                    view.state = phase
                }
                view.needsDisplay = true
            }
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
    var showBackground = false
    var backgroundColor: NSColor = NSColor(white: 0.5, alpha: 0.55)
    private let reader: AudioLevelReader
    private let runner: SttRunner
    private var levels = [Double](repeating: 0, count: 22)
    private var phase = 0.0
    private let wav = "/tmp/stt-recording.wav"

    init(frame: NSRect, reader: AudioLevelReader, runner: SttRunner) {
        self.reader = reader; self.runner = runner
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    // State colors (shared by the left icon and the right animation).
    private let recColor = NSColor(red: 0.08, green: 0.95, blue: 0.68, alpha: 1)
    private let whisperColor = NSColor(red: 0.20, green: 0.64, blue: 1.0, alpha: 1)
    private let llmColor = NSColor(red: 0.78, green: 0.54, blue: 1.0, alpha: 1)
    // Left icon slot — where the mic used to sit.
    private let iconRect = NSRect(x: 9, y: 11, width: 24, height: 24)

    override func draw(_ dirty: NSRect) {
        phase += 0.11
        if showBackground {
            backgroundColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        }
        switch state {
        case .recording:
            drawSymbol("mic.fill", color: recColor, in: iconRect)
            drawWave()
        case .whisper:
            drawSymbol("waveform", color: whisperColor, in: iconRect)
            drawSpinner(color: whisperColor)
        case .llm:
            drawSymbol("sparkles", color: llmColor, in: iconRect)
            drawSpinner(color: llmColor)
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

    private func drawWave() {
        let target = reader.levels(from: URL(fileURLWithPath: wav))
        for i in 0..<levels.count { levels[i] = levels[i] * 0.28 + target[i] * 0.72 }
        let centerY = 23.0
        for i in 0..<levels.count {
            let h = 3 + levels[i] * 32
            let a = 0.10 + levels[i] * 0.90
            recColor.withAlphaComponent(a).setFill()
            let r = NSRect(x: 45 + Double(i) * 6, y: centerY - h / 2, width: 3, height: h)
            NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    private func drawSpinner(color: NSColor) {
        let cx = 100.0, cy = 23.0, radius = 15.0, count = 12
        let active = Int(phase * 9)
        for i in 0..<count {
            let angle = Double(i) / Double(count) * .pi * 2
            let rank = ((i + active) % count) + 1
            let a = 0.13 + (Double(rank) / Double(count)) * 0.87
            color.withAlphaComponent(a).setFill()
            let x = cx + cos(angle) * radius, y = cy + sin(angle) * radius
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 4, height: 4)).fill()
        }
    }

    private func drawError() {
        NSColor(red: 1.0, green: 0.26, blue: 0.24, alpha: 0.95).setFill()
        NSBezierPath(ovalIn: NSRect(x: 84, y: 12, width: 22, height: 22)).fill()
    }
}
