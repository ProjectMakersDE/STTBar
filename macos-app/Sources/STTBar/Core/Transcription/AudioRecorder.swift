import AVFoundation
import AudioToolbox
import CoreAudio

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

/// Everything the render callback touches, created before the unit starts and
/// released only after it stops. The audio thread must never race the main
/// thread over these references, so ownership is handed over wholesale.
private final class CaptureSink {
    let deviceFormat: AVAudioFormat
    let targetFormat: AVAudioFormat
    let converter: AVAudioConverter
    let file: AVAudioFile
    private let bytesPerFrame: Int
    private let capacityFrames: Int
    private let storage: UnsafeMutableRawPointer
    private let list: UnsafeMutableAudioBufferListPointer

    init?(deviceFormat: AVAudioFormat, targetFormat: AVAudioFormat, file: AVAudioFile, maxFrames: Int) {
        guard let converter = AVAudioConverter(from: deviceFormat, to: targetFormat) else { return nil }
        self.deviceFormat = deviceFormat
        self.targetFormat = targetFormat
        self.converter = converter
        self.file = file
        self.capacityFrames = maxFrames
        self.bytesPerFrame = Int(deviceFormat.streamDescription.pointee.mBytesPerFrame)
        self.storage = UnsafeMutableRawPointer.allocate(byteCount: maxFrames * bytesPerFrame,
                                                       alignment: MemoryLayout<Float>.alignment)
        self.list = AudioBufferList.allocate(maximumBuffers: 1)
        list[0] = AudioBuffer(mNumberChannels: deviceFormat.channelCount,
                              mDataByteSize: UInt32(maxFrames * bytesPerFrame),
                              mData: storage)
    }

    deinit {
        storage.deallocate()
        free(list.unsafeMutablePointer)
    }

    func render(unit: AudioUnit,
                flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                timestamp: UnsafePointer<AudioTimeStamp>,
                frames: UInt32) {
        guard Int(frames) <= capacityFrames else { return }
        list[0].mDataByteSize = UInt32(Int(frames) * bytesPerFrame)
        guard AudioUnitRender(unit, flags, timestamp, 1, frames, list.unsafeMutablePointer) == noErr,
              let input = AVAudioPCMBuffer(pcmFormat: deviceFormat, bufferListNoCopy: list.unsafeMutablePointer)
        else { return }

        let ratio = targetFormat.sampleRate / deviceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio + 16)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        if error == nil, out.frameLength > 0 { try? file.write(from: out) }
    }
}

/// Records microphone audio as a 16 kHz mono 16-bit WAV (replaces stt-record.sh).
/// Writes to `outputURL` so the HUD AudioLevelReader can tail the same file.
///
/// Capture runs on a bare input-only AUHAL rather than `AVAudioEngine`. An
/// engine always owns an output node bound to the *default output device*, and
/// starting it tears that device's stream down and rebuilds it — measured at a
/// ~200 ms interruption. On a Bluetooth headset that renegotiation is plainly
/// audible as a mode switch with a volume jump, every single time a dictation
/// starts, no matter which microphone was selected. A bare input unit has no
/// output side and leaves playback devices strictly alone. This is also what
/// `sox` did in the shell backend, back when the problem did not exist.
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

    private var unit: AudioUnit?
    private var sink: CaptureSink?
    private(set) var isRecording = false
    private var outputURL: URL?

    /// A device that reports 0 Hz or 0 channels cannot be recorded from — it is
    /// what an input reports after the device it referred to went away
    /// (sleep/wake, dock or display connects).
    static func isUsableInputFormat(sampleRate: Double, channelCount: AVAudioChannelCount) -> Bool {
        sampleRate > 0 && channelCount > 0
    }

    // MARK: Unit setup

    private static func makeInputUnit() -> AudioUnit? {
        var description = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                                    componentSubType: kAudioUnitSubType_HALOutput,
                                                    componentManufacturer: kAudioUnitManufacturer_Apple,
                                                    componentFlags: 0,
                                                    componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else { return nil }
        var unit: AudioUnit?
        guard AudioComponentInstanceNew(component, &unit) == noErr, let unit else { return nil }
        // Element 1 is the input bus, element 0 the output bus. Enabling only
        // the former is what keeps this unit off every playback device.
        var on: UInt32 = 1
        var off: UInt32 = 0
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1,
                             &on, UInt32(MemoryLayout<UInt32>.size))
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0,
                             &off, UInt32(MemoryLayout<UInt32>.size))
        return unit
    }

    private static func bind(_ unit: AudioUnit, to device: AudioDeviceID) -> Bool {
        var id = device
        return AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                    &id, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr
    }

    /// The hardware format of the bound device's input bus.
    private static func hardwareFormat(_ unit: AudioUnit) -> AudioStreamBasicDescription? {
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1,
                                   &asbd, &size) == noErr else { return nil }
        return asbd
    }

    private static func maximumFrames(_ unit: AudioUnit) -> Int {
        var frames = UInt32(4096)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioUnitGetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0,
                             &frames, &size)
        return Int(frames)
    }

    // MARK: Recording

    func start(outputURL: URL, input: AudioInputResolution = .systemDefault) throws {
        self.outputURL = outputURL
        try? FileManager.default.removeItem(at: outputURL)

        guard let unit = Self.makeInputUnit() else {
            throw AudioRecorderError.engineStart("no HAL input unit")
        }
        if case .device(let deviceID) = input, !Self.bind(unit, to: deviceID) {
            AppLogger.log("audio_input_bind_failed device=\(deviceID)")
        }

        guard let hardware = Self.hardwareFormat(unit),
              Self.isUsableInputFormat(sampleRate: hardware.mSampleRate,
                                       channelCount: hardware.mChannelsPerFrame)
        else {
            AudioComponentInstanceDispose(unit)
            throw AudioRecorderError.noAudioInput
        }

        // Take the samples as interleaved float at the device's own rate and let
        // AVAudioConverter do the rate and channel reduction, exactly as before.
        guard let deviceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: hardware.mSampleRate,
                                               channels: hardware.mChannelsPerFrame,
                                               interleaved: true),
              let targetFormat = AVAudioFormat(settings: Self.targetSettings)
        else {
            AudioComponentInstanceDispose(unit)
            throw AudioRecorderError.engineStart("invalid capture format")
        }
        var clientFormat = deviceFormat.streamDescription.pointee
        guard AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
                                   &clientFormat,
                                   UInt32(MemoryLayout<AudioStreamBasicDescription>.size)) == noErr else {
            AudioComponentInstanceDispose(unit)
            throw AudioRecorderError.engineStart("device rejected the capture format")
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: outputURL, settings: Self.targetSettings,
                                   commonFormat: .pcmFormatInt16, interleaved: true)
        } catch {
            AudioComponentInstanceDispose(unit)
            throw error
        }
        guard let sink = CaptureSink(deviceFormat: deviceFormat, targetFormat: targetFormat,
                                     file: file, maxFrames: Self.maximumFrames(unit)) else {
            AudioComponentInstanceDispose(unit)
            throw AudioRecorderError.engineStart("no converter for input format")
        }

        var callback = AURenderCallbackStruct(
            inputProc: { refCon, flags, timestamp, _, frames, _ -> OSStatus in
                let recorder = Unmanaged<AudioRecorder>.fromOpaque(refCon).takeUnretainedValue()
                if let unit = recorder.unit, let sink = recorder.sink {
                    sink.render(unit: unit, flags: flags, timestamp: timestamp, frames: frames)
                }
                return noErr
            },
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                             &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size))

        // Publish before starting: the callback fires as soon as the unit runs.
        self.unit = unit
        self.sink = sink

        let initStatus = AudioUnitInitialize(unit)
        guard initStatus == noErr else {
            teardown()
            throw AudioRecorderError.engineStart("initialize failed (\(initStatus))")
        }
        let startStatus = AudioOutputUnitStart(unit)
        guard startStatus == noErr else {
            AudioUnitUninitialize(unit)
            teardown()
            throw AudioRecorderError.engineStart("start failed (\(startStatus))")
        }
        isRecording = true
    }

    @discardableResult
    func stop() -> URL? {
        guard isRecording, let unit else { return nil }
        // Stopping first guarantees the callback has returned before the sink —
        // and with it the WAV file — is released.
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        isRecording = false
        teardown()          // releasing the AVAudioFile flushes + finalizes the header
        return outputURL
    }

    func cancel() {
        _ = stop()
        if let url = outputURL { try? FileManager.default.removeItem(at: url) }
    }

    private func teardown() {
        if let unit { AudioComponentInstanceDispose(unit) }
        unit = nil
        sink = nil
    }
}
