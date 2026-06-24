import Foundation
import WhisperKit

/// Backs the local-model UI: a RAM-based recommendation, the preset list, and a
/// one-shot "load/download model" action that triggers WhisperKit's download
/// into the sandbox container.
final class WhisperModelManager: ObservableObject {
    @Published var status: String?
    @Published var working = false

    /// Common WhisperKit model names; free text is still allowed in the field.
    static let presets = ["tiny", "base", "small", "medium", "large-v3", "large-v3-v20240930_626MB"]

    /// Pure RAM→model heuristic (testable). Bigger models need more memory.
    func recommendedModel(physicalMemoryBytes: UInt64) -> String {
        let gb = Double(physicalMemoryBytes) / 1_073_741_824
        if gb <= 8 { return "base" }
        if gb <= 16 { return "small" }
        return "large-v3-v20240930_626MB"
    }

    func recommendedForThisMac() -> String {
        recommendedModel(physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory)
    }

    /// Build a WhisperKit pipeline for `name`, which downloads + loads the model
    /// into the container. Used by the "Modell laden" button.
    func loadModel(_ name: String) {
        working = true
        status = L("Lade Modell… (kann beim ersten Mal dauern)", "Loading model… (first time can take a while)")
        let dir = LocalTranscriber.modelsDirectory
        Task {
            do {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let cfg = WhisperKitConfig(model: name.isEmpty ? nil : name, downloadBase: dir)
                _ = try await WhisperKit(cfg)
                await finish(L("Modell bereit.", "Model ready."))
            } catch {
                await finish(L("Fehler: ", "Error: ") + error.localizedDescription)
            }
        }
    }

    @MainActor private func finish(_ msg: String) {
        status = msg
        working = false
    }
}
