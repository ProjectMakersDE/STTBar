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
        let map: [Int: String] = [kVK_Return: "↩", kVK_Escape: "⎋", kVK_Tab: "⇥"]
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
