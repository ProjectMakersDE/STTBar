import AVFoundation

enum AudioRecorderError: LocalizedError {
    case engineStart(String)
    case noAudioInput
    var errorDescription: String? {
        switch self {
        case .engineStart(let m): return L("Audio-Engine konnte nicht starten.", "Audio engine could not start.") + " \(m)"
        case .noAudioInput: return L("Kein Mikrofon verfügbar. Bitte Audio-Eingang prüfen und erneut versuchen.", "No microphone available. Please check your audio input and try again.")
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

    private var engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private(set) var isRecording = false
    private var outputURL: URL?

    /// `installTap` raises an uncatchable Objective-C exception when handed a
    /// 0 Hz / 0-channel format, which the input node reports after the default
    /// input device changed underneath a cached engine (sleep/wake, dock or
    /// display connects). Formats must pass this gate before reaching the tap.
    static func isUsableInputFormat(sampleRate: Double, channelCount: AVAudioChannelCount) -> Bool {
        sampleRate > 0 && channelCount > 0
    }

    private func usableInputFormat() -> AVAudioFormat? {
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard Self.isUsableInputFormat(sampleRate: format.sampleRate, channelCount: format.channelCount) else { return nil }
        return format
    }

    func start(outputURL: URL) throws {
        self.outputURL = outputURL
        try? FileManager.default.removeItem(at: outputURL)
        var liveFormat = usableInputFormat()
        if liveFormat == nil {
            // Stale engine after a device change: a fresh engine re-resolves
            // the current default input device.
            engine = AVAudioEngine()
            liveFormat = usableInputFormat()
        }
        guard let inputFormat = liveFormat else {
            throw AudioRecorderError.noAudioInput
        }
        let input = engine.inputNode
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
            // A failed start usually means the engine's device went away;
            // drop it so the next attempt resolves the current device fresh.
            engine = AVAudioEngine()
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
