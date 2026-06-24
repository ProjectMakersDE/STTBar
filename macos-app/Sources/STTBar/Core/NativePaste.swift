import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum NativePasteResult {
    case pasted
    case clipboardOnly(String)
}

/// Inserts transcribed text into the focused app using a staged strategy so the
/// common case never touches the clipboard:
///   1. Accessibility: write into the focused element (replaces selection / inserts at caret).
///   2. Synthesized Unicode typing (CGEvent) — no clipboard.
///   3. Clipboard + Cmd+V, saving and restoring the previous clipboard contents.
enum NativePaste {
    static func copyAndPaste(_ text: String) -> NativePasteResult {
        guard !text.isEmpty else { return .pasted }

        guard Permissions.accessibilityTrusted else {
            setClipboard(text)
            return .clipboardOnly("Bedienungshilfen fehlen; Text liegt in der Zwischenablage.")
        }

        // Stage 1 — Accessibility direct write (no clipboard).
        if insertViaAccessibility(text) { return .pasted }

        // Stage 2 — Unicode typing (no clipboard).
        if typeUnicode(text) { return .pasted }

        // Stage 3 — Clipboard + Cmd+V, restoring the previous clipboard.
        return pasteViaClipboard(text)
    }

    // MARK: - Stage 1: Accessibility

    static func insertViaAccessibility(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedRef = focused else { return false }
        let element = focusedRef as! AXUIElement
        // Replacing the selected text inserts at the caret when nothing is selected.
        let status = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        return status == .success
    }

    // MARK: - Stage 2: Unicode typing

    /// Splits text into <=`size` UTF-16 chunks; the system truncates very long
    /// unicode strings posted in a single event.
    static func utf16Chunks(_ text: String, size: Int) -> [[UniChar]] {
        let units = Array(text.utf16)
        guard size > 0, !units.isEmpty else { return units.isEmpty ? [] : [units] }
        return stride(from: 0, to: units.count, by: size).map { Array(units[$0..<min($0 + size, units.count)]) }
    }

    static func typeUnicode(_ text: String) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        for chunk in utf16Chunks(text, size: 20) {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return false }
            down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            up.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        return true
    }

    // MARK: - Stage 3: Clipboard fallback

    static func pasteViaClipboard(_ text: String) -> NativePasteResult {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        setClipboard(text)

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

        // Restore the previous clipboard after the target app has had time to read ours.
        if let previous {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(previous, forType: .string)
            }
        }
        return .pasted
    }

    // MARK: - Helpers

    private static func setClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
