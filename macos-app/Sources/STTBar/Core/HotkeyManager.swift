import AppKit
import Carbon.HIToolbox

struct HotkeyRegistrationStatus: Identifiable, Equatable {
    var id: SttMode { mode }
    var mode: SttMode
    var hotkey: Hotkey
    var state: State
    var message: String

    enum State: String {
        case registered, duplicate, conflict, invalid
    }
}

/// Registers up to three global hotkeys and invokes `onTrigger(mode)` on the
/// main thread. Re-register by calling `reload()` after settings change.
final class HotkeyManager {
    var onTrigger: ((SttMode) -> Void)?
    var onStatusesChanged: (([HotkeyRegistrationStatus]) -> Void)?
    private var refs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    private var idToMode: [UInt32: SttMode] = [:]

    func install() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let this = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, ctx in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(ctx!).takeUnretainedValue()
            if let mode = mgr.idToMode[hkID.id] { DispatchQueue.main.async { mgr.onTrigger?(mode) } }
            return noErr
        }, 1, &spec, this, &handler)
        reload()
    }

    func reload() {
        for r in refs { if let r { UnregisterEventHotKey(r) } }
        refs.removeAll(); idToMode.removeAll()
        let sig = OSType(0x53545442) // 'STTB'
        var seen: [Hotkey: SttMode] = [:]
        var statuses: [HotkeyRegistrationStatus] = []
        for (i, mode) in SttMode.allCases.enumerated() {
            let hk = AppSettings.shared.hotkey(mode)
            if let other = seen[hk] {
                statuses.append(HotkeyRegistrationStatus(mode: mode, hotkey: hk, state: .duplicate, message: "Doppelt mit \(other.label)"))
                continue
            }
            seen[hk] = mode
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: sig, id: UInt32(i + 1))
            let err = RegisterEventHotKey(hk.keyCode, hk.carbonModifiers, id, GetEventDispatcherTarget(), 0, &ref)
            if err == noErr {
                refs.append(ref); idToMode[UInt32(i + 1)] = mode
                statuses.append(HotkeyRegistrationStatus(mode: mode, hotkey: hk, state: .registered, message: "Registriert"))
            } else {
                statuses.append(HotkeyRegistrationStatus(mode: mode, hotkey: hk, state: .conflict, message: "Carbon-Fehler \(err)"))
            }
        }
        onStatusesChanged?(statuses)
    }
}
