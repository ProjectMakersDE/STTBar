import SwiftUI
import Carbon.HIToolbox

/// A click-to-record field that captures the next key+modifier chord.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: Hotkey
    var onChange: () -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let b = RecorderButton()
        b.onCapture = { hk in hotkey = hk; onChange() }
        b.hotkey = hotkey
        return b
    }
    func updateNSView(_ nsView: RecorderButton, context: Context) { nsView.hotkey = hotkey }
}

final class RecorderButton: NSButton {
    var onCapture: ((Hotkey) -> Void)?
    var hotkey: Hotkey = .fullDefault { didSet { if !recording { title = hotkey.display } } }
    private var recording = false
    /// Captures the next chord ahead of AppKit's own key handling. A plain
    /// `keyDown` override is not enough: a focused NSButton swallows Space and
    /// Return to "click" itself, so Space-based chords (e.g. ⌃⇧Space) never
    /// reach it. A local monitor sees the event first and consumes it.
    private var monitor: Any?

    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(begin)
        title = hotkey.display
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func begin() {
        guard !recording else { return }
        recording = true
        title = L("Taste drücken…", "Press a key…")
        window?.makeFirstResponder(self)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.capture(event)
            return nil // swallow so the key does not also reach the button/app
        }
    }

    private func capture(_ event: NSEvent) {
        // Escape cancels recording without changing the binding.
        if Int(event.keyCode) == kVK_Escape {
            endRecording()
            return
        }
        var mods: UInt32 = 0
        if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.shift) { mods |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.option) { mods |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
        let hk = Hotkey(keyCode: UInt32(event.keyCode), carbonModifiers: mods)
        hotkey = hk
        endRecording()
        onCapture?(hk)
    }

    private func endRecording() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        title = hotkey.display
    }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        if recording { endRecording() }
        return super.resignFirstResponder()
    }

    deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
}
