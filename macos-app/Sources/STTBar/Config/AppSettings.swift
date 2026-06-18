import Foundation

enum SttMode: String, CaseIterable {
    case full, raw, english
    var label: String {
        switch self {
        case .full: return "Bereinigt (LLM)"
        case .raw: return "Roh (ohne LLM)"
        case .english: return "Englisch (übersetzt)"
        }
    }
    /// One-line description of what the mode does, shown in the Shortcuts tab.
    var detail: String {
        switch self {
        case .full: return "Transkript mit LLM-Bereinigung in der Quellsprache."
        case .raw: return "Reines Transkript ohne LLM (Textersetzungen greifen weiter)."
        case .english: return "LLM-Bereinigung, Ausgabe ins Englische übersetzt."
        }
    }
}

/// App-owned settings persisted in UserDefaults (HUD appearance + hotkeys).
final class AppSettings {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    var hudAnchor: HudAnchor {
        get { HudAnchor(rawValue: d.string(forKey: "hudAnchor") ?? "") ?? .topCenter }
        set { d.set(newValue.rawValue, forKey: "hudAnchor") }
    }
    var hudBackground: Bool {
        get { d.object(forKey: "hudBackground") == nil ? true : d.bool(forKey: "hudBackground") }
        set { d.set(newValue, forKey: "hudBackground") }
    }
    /// HUD backing color incl. alpha. Defaults to a clearly visible light gray
    /// (more opaque than the original 0.18 so the icons stand out).
    var hudBackgroundColor: RGBAColor {
        get {
            if let data = d.data(forKey: "hudBackgroundColor"),
               let c = try? JSONDecoder().decode(RGBAColor.self, from: data) { return c }
            return RGBAColor(r: 0.5, g: 0.5, b: 0.5, a: 0.55)
        }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "hudBackgroundColor") }
    }
    /// Active app UI language. Defaults to German (existing users stay DE).
    var appLanguage: AppLanguage {
        get { AppLanguage(rawValue: d.string(forKey: "appLanguage") ?? "") ?? .de }
        set { d.set(newValue.rawValue, forKey: "appLanguage") }
    }
    func hotkey(_ mode: SttMode) -> Hotkey {
        if let data = d.data(forKey: "hotkey.\(mode.rawValue)"),
           let hk = try? JSONDecoder().decode(Hotkey.self, from: data) { return hk }
        switch mode {
        case .full: return .fullDefault
        case .raw: return .rawDefault
        case .english: return .englishDefault
        }
    }
    func setHotkey(_ hk: Hotkey, for mode: SttMode) {
        d.set(try? JSONEncoder().encode(hk), forKey: "hotkey.\(mode.rawValue)")
    }

    func resetHotkey(_ mode: SttMode) {
        d.removeObject(forKey: "hotkey.\(mode.rawValue)")
    }

    var showHudTimer: Bool {
        get { d.object(forKey: "showHudTimer") == nil ? true : d.bool(forKey: "showHudTimer") }
        set { d.set(newValue, forKey: "showHudTimer") }
    }

    var sensitiveMode: Bool {
        get { d.bool(forKey: "sensitiveMode") }
        set { d.set(newValue, forKey: "sensitiveMode") }
    }

    var historyEnabled: Bool {
        get { d.bool(forKey: "historyEnabled") }
        set { d.set(newValue, forKey: "historyEnabled") }
    }

    var historyRetentionHours: Int {
        get {
            let value = d.integer(forKey: "historyRetentionHours")
            return value == 0 ? 24 : value
        }
        set { d.set(max(1, newValue), forKey: "historyRetentionHours") }
    }

    var maxRecordingSeconds: Int {
        get {
            let value = d.integer(forKey: "maxRecordingSeconds")
            return value == 0 ? 1200 : value
        }
        set { d.set(max(30, newValue), forKey: "maxRecordingSeconds") }
    }

    var prewarmEnabled: Bool {
        get { d.bool(forKey: "prewarmEnabled") }
        set { d.set(newValue, forKey: "prewarmEnabled") }
    }

    var keepModelWarmSeconds: Int {
        get { d.integer(forKey: "keepModelWarmSeconds") }
        set { d.set(max(0, newValue), forKey: "keepModelWarmSeconds") }
    }
}
