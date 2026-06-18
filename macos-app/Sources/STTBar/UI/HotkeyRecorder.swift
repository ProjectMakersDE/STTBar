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
        recording = true
        title = L("Taste drücken…", "Press a key…")
        window?.makeFirstResponder(self)
    }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        var mods: UInt32 = 0
        if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.shift) { mods |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.option) { mods |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
        let hk = Hotkey(keyCode: UInt32(event.keyCode), carbonModifiers: mods)
        recording = false
        hotkey = hk
        title = hk.display
        onCapture?(hk)
    }
}
