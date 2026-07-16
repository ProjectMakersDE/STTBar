import Foundation

/// Progress signal a backend emits from its async stop pipeline so the UI can
/// distinguish transcription from the optional LLM cleanup pass.
enum TranscriptionPhase { case transcribing, postprocessing }

/// Abstracts the record→transcribe pipeline so `SttRunner` no longer spawns a
/// shell. Phase 1 ships `PlaceholderBackend`; Phase 2 adds the native
/// AVAudioEngine + URLSession implementation behind the same protocol.
protocol TranscriptionBackend: AnyObject {
    var isRecording: Bool { get }
    func start(mode: SttMode) throws
    /// Stops recording and asynchronously delivers the transcript text.
    /// `onPhase` reports pipeline progress (may fire on a background thread).
    func stop(mode: SttMode,
              onPhase: @escaping (TranscriptionPhase) -> Void,
              completion: @escaping (Result<String, Error>) -> Void)
    func cancel()
}

enum TranscriptionBackendError: LocalizedError {
    case notAvailableYet
    var errorDescription: String? {
        L("Die native Aufnahme kommt in Phase 2. In diesem Build ist die Transkription deaktiviert.",
          "Native recording arrives in Phase 2. Transcription is disabled in this build.")
    }
}

/// Phase-1 placeholder: records nothing, always reports the Phase-2 notice.
final class PlaceholderBackend: TranscriptionBackend {
    private(set) var isRecording = false
    func start(mode: SttMode) throws {
        isRecording = false
        throw TranscriptionBackendError.notAvailableYet
    }
    func stop(mode: SttMode,
              onPhase: @escaping (TranscriptionPhase) -> Void,
              completion: @escaping (Result<String, Error>) -> Void) {
        isRecording = false
        completion(.failure(TranscriptionBackendError.notAvailableYet))
    }
    func cancel() { isRecording = false }
}
