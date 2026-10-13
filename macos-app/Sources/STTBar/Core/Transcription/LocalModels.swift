import Foundation
import FluidAudio

/// Which on-device engine runs a local model name. Parakeet models go through
/// FluidAudio, every other name is a WhisperKit model.
enum LocalEngine: Equatable {
    case parakeet(AsrModelVersion)
    case whisper
}

/// Catalog of the local models offered in the pickers. Free text still selects
/// any WhisperKit model name.
enum LocalModels {
    static let parakeetV3 = "parakeet-v3"
    static let parakeetUltra = "parakeet-ultra"
    /// Used when the picker is on "Automatic". Measured on an M1 Max with 179 s
    /// of German speech: Ultra 1.4 % WER, v3 2.6 %, both about 1 s when warm.
    static let defaultModel = parakeetUltra

    /// Picker entries, the fastest dictation models first.
    static let presets = [parakeetUltra, parakeetV3,
                          "large-v3-v20240930_626MB", "large-v3-v20240930", "large-v3",
                          "small", "base"]

    static func engine(for name: String) -> LocalEngine {
        switch name {
        case parakeetV3: return .parakeet(.v3)
        case parakeetUltra: return .parakeet(.ultra)
        default: return .whisper
        }
    }

    /// WhisperKit names the Large V3 Turbo release after its date (2024-09-30).
    static func label(_ name: String) -> String {
        switch name {
        case parakeetV3: return L("Parakeet TDT v3 (sehr schnell, 25 Sprachen)", "Parakeet TDT v3 (very fast, 25 languages)")
        case parakeetUltra: return L("Parakeet Ultra (sehr schnell, genauer, 25 Sprachen)", "Parakeet Ultra (very fast, more accurate, 25 languages)")
        case "large-v3-v20240930_626MB": return "Whisper Large V3 Turbo (626 MB)"
        case "large-v3-v20240930": return "Whisper Large V3 Turbo"
        case "large-v3": return "Whisper Large V3"
        case "small": return "Whisper Small"
        case "base": return "Whisper Base"
        default: return name
        }
    }

    /// Download folder of a Parakeet model inside the container. FluidAudio
    /// stores each model in a folder named after the model (`Repo.folderName`).
    static func parakeetDirectory(_ version: AsrModelVersion, in dir: URL) -> URL {
        let repo = version == .ultra ? "parakeet-ultra" : "parakeet-tdt-0.6b-v3"
        return dir.appendingPathComponent("fluidaudio", isDirectory: true)
            .appendingPathComponent(repo, isDirectory: true)
    }
}

/// Load state of the in-memory local model. Settings, onboarding and the menu
/// bar show it, so a first launch never looks idle while the model loads.
@MainActor
final class LocalModelStatus: ObservableObject {
    static let shared = LocalModelStatus()

    enum State: Equatable {
        case idle
        case loading(model: String)
        case ready(model: String, seconds: Double)
        case failed(model: String, message: String)
    }

    @Published private(set) var state: State = .idle

    func set(_ state: State) { self.state = state }

    var isLoading: Bool { if case .loading = state { return true } else { return false } }

    /// One line for the UI, nil before the first load.
    var text: String? {
        switch state {
        case .idle: return nil
        case .loading(let model):
            return L("Lade \(LocalModels.label(model))… (beim ersten Mal mit Download)",
                     "Loading \(LocalModels.label(model))… (downloads on first use)")
        case .ready(let model, let seconds):
            return L("\(LocalModels.label(model)) ist bereit (geladen in \(String(format: "%.1f", seconds)) s).",
                     "\(LocalModels.label(model)) is ready (loaded in \(String(format: "%.1f", seconds)) s).")
        case .failed(_, let message):
            return L("Laden fehlgeschlagen: ", "Loading failed: ") + message
        }
    }
}
