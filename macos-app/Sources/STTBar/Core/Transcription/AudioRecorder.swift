import AVFoundation

enum AudioRecorderError: LocalizedError {
    case engineStart(String)
    var errorDescription: String? {
        switch self {
        case .engineStart(let m): return L("Audio-Engine konnte nicht starten.", "Audio engine could not start.") + " \(m)"
        }
    }
}

/// Records microphone audio as a 16 kHz mono 16-bit WAV (replaces stt-record.sh).
/// Writes to `outputURL` so the HUD AudioLevelReader can tail the same file.
final class AudioRecorder {
    static let targetSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private(set) var isRecording = false
    private var outputURL: URL?

    func start(outputURL: URL) throws {
        self.outputURL = outputURL
        try? FileManager.default.removeItem(at: outputURL)
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let targetFormat = AVAudioFormat(settings: Self.targetSettings) else {
            throw AudioRecorderError.engineStart("invalid target format")
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        file = try AVAudioFile(forWriting: outputURL, settings: Self.targetSettings,
                               commonFormat: .pcmFormatInt16, interleaved: true)

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter, let file = self.file else { return }
            let ratio = targetFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 16)
            guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil, out.frameLength > 0 { try? file.write(from: out) }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            file = nil
            converter = nil
            throw AudioRecorderError.engineStart(error.localizedDescription)
        }
        isRecording = true
    }

    @discardableResult
    func stop() -> URL? {
        guard isRecording else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        file = nil           // closing the AVAudioFile flushes + finalizes the WAV header
        converter = nil
        return outputURL
    }

    func cancel() {
        _ = stop()
        if let url = outputURL { try? FileManager.default.removeItem(at: url) }
    }
}
