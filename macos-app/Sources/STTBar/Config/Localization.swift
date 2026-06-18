import Foundation
import Combine

/// App UI language. Runtime-switchable (not .lproj based).
enum AppLanguage: String, CaseIterable {
    case de, en
}

/// Observable holder for the active UI language. Views observe `shared`;
/// `L(_:_:)` reads the current value at body-evaluation time so a switch
/// re-renders every observing SwiftUI view.
final class Localization: ObservableObject {
    static let shared = Localization()
    @Published var language: AppLanguage

    private init() {
        self.language = AppSettings.shared.appLanguage
    }

    /// Persist + publish. Triggers SwiftUI re-render of observing views.
    func set(_ language: AppLanguage) {
        AppSettings.shared.appLanguage = language
        self.language = language
    }
}

/// Pick the string for the active UI language.
func L(_ de: String, _ en: String) -> String {
    Localization.shared.language == .de ? de : en
}
