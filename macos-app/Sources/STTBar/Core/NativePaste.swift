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
    /// Modifier bits a still-held hotkey chord (e.g. Raw = Ctrl+Shift+Space) can
    /// leak into a synthesized paste. Caps-lock and Fn are deliberately ignored.
    static let relevantModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskShift, .maskAlternate]

    /// The relevant modifiers currently present in `flags`.
    static func heldModifiers(_ flags: CGEventFlags) -> CGEventFlags {
        flags.intersection(relevantModifiers)
    }

    /// Human-readable modifier list for the diagnostic log; stable order.
    static func describe(_ flags: CGEventFlags) -> String {
        var parts: [String] = []
        if flags.contains(.maskCommand) { parts.append("cmd") }
        if flags.contains(.maskControl) { parts.append("ctrl") }
        if flags.contains(.maskShift) { parts.append("shift") }
        if flags.contains(.maskAlternate) { parts.append("opt") }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
    }

    /// Polls `currentFlags` until no relevant modifier is held or `timeout`
    /// elapses, returning whatever is still held (empty == cleared). The clock,
    /// flag source and sleep are injected so the loop is testable without HID.
    @discardableResult
    static func waitForModifiersToClear(
        timeout: TimeInterval,
        pollInterval: TimeInterval,
        now: () -> TimeInterval,
        currentFlags: () -> CGEventFlags,
        sleep: (TimeInterval) -> Void
    ) -> CGEventFlags {
        let start = now()
        var held = heldModifiers(currentFlags())
        while !held.isEmpty, now() - start < timeout {
            sleep(pollInterval)
            held = heldModifiers(currentFlags())
        }
        return held
    }

    /// Polls the live session modifier state off the main thread, invoking
    /// `completion` on the main queue with whatever is still held (empty ==
    /// cleared). Uses main-queue scheduling instead of a blocking sleep so the
    /// HUD and menu stay responsive while a held chord is waited out. Generous
    /// timeout — it returns the instant the keys are released, so it only runs
    /// the full duration if the user deliberately keeps the chord down.
    static func awaitModifiersClear(timeout: TimeInterval = 2.5,
                                    pollInterval: TimeInterval = 0.01,
                                    completion: @escaping (CGEventFlags) -> Void) {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        func poll() {
            let held = heldModifiers(CGEventSource.flagsState(.combinedSessionState))
            if held.isEmpty || ProcessInfo.processInfo.systemUptime >= deadline {
                completion(held)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) { poll() }
            }
        }
        poll()
    }

    /// Inserts `text` and delivers the outcome to `completion` on the main
    /// queue. When the hotkey chord is still held, the wait is asynchronous so
    /// the app never freezes.
    static func copyAndPaste(_ text: String, completion: @escaping (NativePasteResult) -> Void) {
        guard !text.isEmpty else { return completion(.pasted) }

        guard Permissions.accessibilityTrusted else {
            setClipboard(text)
            return completion(.clipboardOnly("Bedienungshilfen fehlen; Text liegt in der Zwischenablage."))
        }

        // A fast dictation can reach here while the hotkey chord (Raw =
        // Ctrl+Shift+Space) is still physically down. Synthesized key events are
        // delivered at the HID tap and combine with the live modifier state, so a
        // typed character or Cmd+V becomes a Ctrl/Shift chord — in a terminal that
        // moves the caret (Ctrl bindings) instead of inserting. Wait briefly for
        // the user to lift the keys before injecting anything.
        let held = heldModifiers(CGEventSource.flagsState(.combinedSessionState))
        AppLogger.log("native_paste begin held_mods=\(describe(held)) chars=\(text.count)")
        guard !held.isEmpty else { return completion(inject(text)) }

        awaitModifiersClear { remaining in
            AppLogger.log("native_paste waited remaining_mods=\(describe(remaining))")
            if !remaining.isEmpty {
                // Still held after the wait. Injecting now would type into the live
                // modifiers and insert nothing, losing the transcript — so leave it
                // on the clipboard for a manual paste instead.
                setClipboard(text)
                AppLogger.log("native_paste stage=clipboard_only_modifiers_held")
                return completion(.clipboardOnly("Modifier-Tasten gehalten; Text liegt in der Zwischenablage (⌘V)."))
            }
            completion(inject(text))
        }
    }

    /// The staged, non-blocking injection: Accessibility, then Unicode typing,
    /// then clipboard + Cmd+V. Assumes accessibility is granted and no modifier
    /// chord is held (both checked by `copyAndPaste`).
    private static func inject(_ text: String) -> NativePasteResult {
        // Stage 1 — Accessibility direct write (no clipboard).
        if insertViaAccessibility(text) { AppLogger.log("native_paste stage=ax"); return .pasted }

        // Stage 2 — Unicode typing (no clipboard).
        if typeUnicode(text) { AppLogger.log("native_paste stage=unicode"); return .pasted }

        // Stage 3 — Clipboard + Cmd+V, restoring the previous clipboard.
        AppLogger.log("native_paste stage=clipboard")
        return pasteViaClipboard(text)
    }

    // MARK: - Stage 1: Accessibility

    static func insertViaAccessibility(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedRef = focused else { AppLogger.log("native_paste ax focus=missing"); return false }
        let element = focusedRef as! AXUIElement
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleRef as? String) ?? "?"
        // Replacing the selected text inserts at the caret when nothing is selected.
        let status = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        AppLogger.log("native_paste ax role=\(role) status=\(status.rawValue)")
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
        if AppSettings.shared.sensitiveMode {
            // nspasteboard.org convention: clipboard managers skip entries
            // marked as concealed, so sensitive dictations stay out of their
            // histories.
            pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        }
    }
}
