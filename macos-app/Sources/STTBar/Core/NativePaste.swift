import AppKit
import Carbon.HIToolbox

enum NativePasteResult {
    case pasted
    case clipboardOnly(String)
}

enum NativePaste {
    static func copyAndPaste(_ text: String) -> NativePasteResult {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard Permissions.accessibilityTrusted else {
            return .clipboardOnly("Bedienungshilfen fehlen; Text liegt in der Zwischenablage.")
        }

        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            return .clipboardOnly("Paste-Event konnte nicht erzeugt werden; Text liegt in der Zwischenablage.")
        }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return .pasted
    }
}
