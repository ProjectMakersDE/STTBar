import Foundation

/// Where transcription happens. `selfHost` shares the remote code path with
/// `server` (just a localhost URL + a setup guide); `local` runs WhisperKit.
enum TranscriptionSource: String, CaseIterable {
    case server
    case selfHost = "selfhost"
    case local
}
