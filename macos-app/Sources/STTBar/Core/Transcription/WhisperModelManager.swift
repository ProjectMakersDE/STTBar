import Foundation

/// Backs the local-model UI: the recommendation, the preset list, and a
/// one-shot "load/download model" action into the sandbox container.
final class WhisperModelManager: ObservableObject {
    @Published var status: String?
    @Published var working = false
    /// nil = never attempted, true/false = last load outcome. Lets the wizard
    /// advance only once a model is actually downloaded.
    @Published var lastSucceeded: Bool?
    /// Called on the main actor when a load finishes (success flag).
    var onFinished: ((Bool) -> Void)?

    /// Picker entries; free text still selects any WhisperKit model.
    static let presets = LocalModels.presets

    /// Parakeet needs about 1 GB of memory and beats every Whisper size on
    /// speed, so it is the recommendation for every Apple Silicon Mac.
    func recommendedModel(physicalMemoryBytes: UInt64) -> String {
        LocalModels.defaultModel
    }

    func recommendedForThisMac() -> String {
        recommendedModel(physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory)
    }

    /// Downloads, loads and warms `name` in the shared transcriber, so the
    /// model stays in memory for the next dictation. Used by "Modell laden".
    func loadModel(_ name: String) {
        guard !working else { return }
        working = true
        status = L("Lade Modell… (kann beim ersten Mal dauern)", "Loading model… (first time can take a while)")
        Task {
            do {
                try await LocalTranscriber.shared.prepare(model: name)
                await finish(L("Modell bereit.", "Model ready."), success: true)
            } catch {
                await finish(L("Fehler: ", "Error: ") + error.localizedDescription, success: false)
            }
        }
    }

    @MainActor private func finish(_ msg: String, success: Bool) {
        status = msg
        working = false
        lastSucceeded = success
        onFinished?(success)
    }
}
