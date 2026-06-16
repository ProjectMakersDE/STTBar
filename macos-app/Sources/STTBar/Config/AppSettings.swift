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
        get { d.bool(forKey: "hudBackground") }
        set { d.set(newValue, forKey: "hudBackground") }
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
}
