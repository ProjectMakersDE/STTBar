import AppKit
import Carbon.HIToolbox

/// A global hotkey binding: a virtual key code plus Carbon modifier flags.
struct Hotkey: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let fullDefault    = Hotkey(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey | shiftKey))
    static let rawDefault     = Hotkey(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey | shiftKey))
    static let englishDefault = Hotkey(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(shiftKey | optionKey))

    var display: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += Self.keyName(keyCode)
        return s
    }

    var systemWarning: String? {
        let cmd = carbonModifiers & UInt32(cmdKey) != 0
        let shift = carbonModifiers & UInt32(shiftKey) != 0
        let control = carbonModifiers & UInt32(controlKey) != 0
        if cmd && keyCode == UInt32(kVK_Space) { return "macOS/Spotlight-nahe Kombination" }
        if cmd && keyCode == UInt32(kVK_Tab) { return "macOS-App-Wechsel" }
        if control && keyCode == UInt32(kVK_Space) { return "Input-Source-nahe Kombination" }
        if cmd && shift && ["3", "4", "5"].contains(Self.keyName(keyCode)) { return "macOS-Screenshot-nahe Kombination" }
        return nil
    }

    static func keyName(_ code: UInt32) -> String {
        if Int(code) == kVK_Space { return "Space" }
        let map: [Int: String] = [
            kVK_Return: "↩", kVK_Escape: "⎋", kVK_Tab: "⇥",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
            kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        ]
        if let n = map[Int(code)] { return n }
        // Best-effort: map the key code through the current keyboard layout.
        if let ch = Self.character(for: code) { return ch.uppercased() }
        return "key\(code)"
    }

    private static func character(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = unsafeBitCast(layoutData, to: CFData.self)
        let layout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let err = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                 UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                 &deadKeyState, chars.count, &length, &chars)
        guard err == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
