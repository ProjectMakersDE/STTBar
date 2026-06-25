import AppKit
import SwiftUI

/// First-run wizard content. Binds to the shared `SettingsModel`, walks the user
/// from welcome → working dictation, and reuses the existing model/permission/
/// hotkey controls. Each step is a small `@ViewBuilder` block.
struct OnboardingView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var flow: OnboardingModel
    @ObservedObject private var loc = Localization.shared
    @StateObject private var models = WhisperModelManager()
    /// Forces re-read of live permission/model status on a slow tick.
    @State private var refreshTick = 0
    private let tick = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var onFinish: () -> Void
    var onStartRawTest: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView { content.frame(maxWidth: .infinity, alignment: .leading).padding(22) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 640, height: 560)
        .onReceive(tick) { _ in refreshTick &+= 1 }
    }

    // MARK: Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill").foregroundStyle(.tint)
                Text(L("STTBar einrichten", "Set up STTBar")).font(.headline)
                Spacer()
                Text("\(flow.stepIndex + 1)/\(flow.steps.count)").font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: flow.progress)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            if flow.canBack {
                Button(L("Zurück", "Back")) { flow.back() }
            }
            Spacer()
            if flow.isLast {
                Button(L("Fertig", "Finish")) { onFinish() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(L("Weiter", "Next")) { advance() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    /// Persist source/endpoint choices to `.env` before leaving those steps.
    private func advance() {
        if flow.step == .source || flow.step == .configure {
            model.applyEnvChanges()
        }
        flow.next()
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch flow.step {
        case .welcome:     welcomeStep
        case .source:      sourceStep
        case .permissions: permissionsStep
        case .configure:   configureStep
        case .hotkey:      hotkeyStep
        case .test:        testStep
        case .done:        doneStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Willkommen bei STTBar", "Welcome to STTBar")).font(.title2).bold()
            Text(L("STTBar diktiert per Tastenkürzel: aufnehmen → transkribieren → in die aktive App einfügen.",
                   "STTBar dictates with a hotkey: record → transcribe → paste into the active app."))
            Label(L("Standardmäßig läuft alles lokal auf deinem Mac (offline).",
                    "By default everything runs locally on your Mac (offline)."), systemImage: "lock.shield")
            Label(L("In wenigen Schritten ist alles eingerichtet.",
                    "A few steps and you're ready."), systemImage: "checkmark.seal")
            Spacer(minLength: 0)
        }
    }

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Wo soll transkribiert werden?", "Where should transcription run?")).font(.title3).bold()
            Picker("", selection: $model.transcriptionSource) {
                Text(L("Lokal (offline, empfohlen)", "Local (offline, recommended)")).tag(TranscriptionSource.local.rawValue)
                Text(L("Eigener Server", "Your server")).tag(TranscriptionSource.server.rawValue)
                Text(L("Selbst hosten", "Self-host")).tag(TranscriptionSource.selfHost.rawValue)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Text(model.transcriptionSource == TranscriptionSource.local.rawValue
                 ? L("WhisperKit läuft direkt auf dem Mac. Kein Server, keine Cloud — du lädst im nächsten Schritt einmalig ein Modell.",
                     "WhisperKit runs on the Mac itself. No server, no cloud — you download a model once in the next step.")
                 : L("Du verbindest im nächsten Schritt deinen Whisper-Endpunkt (und optional einen LLM-Cleanup).",
                     "Next you connect your Whisper endpoint (and optionally an LLM cleanup)."))
                .font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var permissionsStep: some View {
        let _ = refreshTick
        return VStack(alignment: .leading, spacing: 14) {
            Text(L("Berechtigungen", "Permissions")).font(.title3).bold()
            WizardPermissionRow(
                title: L("Mikrofon", "Microphone"),
                detail: L("Nötig für die Audioaufnahme.", "Required for audio recording."),
                granted: Permissions.microphoneStatus == .authorized,
                action: { Permissions.requestMicrophone(); Permissions.openMicrophone() })
            WizardPermissionRow(
                title: L("Bedienungshilfen", "Accessibility"),
                detail: L("Empfohlen, damit der Text direkt eingefügt wird (sonst nur Zwischenablage).",
                          "Recommended so text is pasted directly (otherwise clipboard only)."),
                granted: Permissions.accessibilityTrusted,
                action: { Permissions.promptAccessibility(); Permissions.openAccessibility() })
            Text(L("Mikrofon ist Pflicht; Bedienungshilfen sind empfohlen. Nach dem Erlauben aktualisiert sich der Status automatisch.",
                   "Microphone is required; Accessibility is recommended. The status refreshes automatically after you grant it."))
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var configureStep: some View {
        let _ = refreshTick
        if model.transcriptionSource == TranscriptionSource.local.rawValue {
            localConfigure
        } else {
            serverConfigure
        }
    }

    private var localConfigure: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Lokales Modell laden", "Download local model")).font(.title3).bold()
            HStack {
                Image(systemName: OnboardingReadiness.localModelDownloaded() ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(OnboardingReadiness.localModelDownloaded() ? .green : .secondary)
                Text(OnboardingReadiness.localModelDownloaded()
                     ? L("Ein Modell ist bereits geladen.", "A model is already downloaded.")
                     : L("Noch kein Modell geladen.", "No model downloaded yet."))
                    .foregroundStyle(.secondary)
            }
            Picker(L("Modell", "Model"), selection: $model.localModel) {
                Text(L("Automatisch (empfohlen)", "Automatic (recommended)")).tag("")
                ForEach(WhisperModelManager.presets, id: \.self) { Text($0).tag($0) }
                if !model.localModel.isEmpty && !WhisperModelManager.presets.contains(model.localModel) {
                    Text(model.localModel).tag(model.localModel)
                }
            }
            Text(L("Empfehlung für diesen Mac: ", "Recommended for this Mac: ") + models.recommendedForThisMac())
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L("Modell laden", "Download model")) { models.loadModel(model.localModel) }
                    .disabled(models.working)
                if models.working { ProgressView().controlSize(.small) }
                if let s = models.status { Text(s).font(.caption).foregroundStyle(.secondary) }
            }
            Text(L("Größere Modelle sind genauer, brauchen aber mehr RAM und laden länger.",
                   "Larger models are more accurate but need more RAM and take longer to download."))
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var serverConfigure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Server verbinden", "Connect server")).font(.title3).bold()
            HStack {
                Image(systemName: OnboardingReadiness.isValidHTTPURL(model.whisperURL) ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(OnboardingReadiness.isValidHTTPURL(model.whisperURL) ? .green : .orange)
                Text(L("Whisper-Endpunkt", "Whisper endpoint")).font(.callout)
            }
            TextField("http://…/v1/audio/transcriptions", text: $model.whisperURL)
            TextField(L("Whisper-Modell", "Whisper model"), text: $model.whisperModel)
            TextField(L("Sprache", "Language"), text: $model.language)
            if model.transcriptionSource == TranscriptionSource.selfHost.rawValue {
                Button(L("localhost einsetzen + Anleitung öffnen", "Use localhost + open guide")) {
                    model.whisperURL = "http://localhost:8000/v1/audio/transcriptions"
                    if let url = URL(string: "https://github.com/ProjectMakersDE/STTBar#self-hosting") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Divider().padding(.vertical, 2)
            Toggle(L("LLM-Cleanup aktiv", "LLM cleanup enabled"), isOn: $model.postprocessEnabled)
            if model.postprocessEnabled {
                TextField(L("LLM-URL", "LLM URL"), text: $model.lmStudioURL)
                TextField(L("LLM-Modell", "LLM model"), text: $model.llmModel)
            }
            Spacer(minLength: 0)
        }
    }

    private var hotkeyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Tastenkürzel", "Hotkeys")).font(.title3).bold()
            ForEach(SttMode.allCases, id: \.self) { mode in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(mode.label)
                        Text(mode.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HotkeyRecorder(
                        hotkey: Binding(get: { model.hotkey(mode) }, set: { model.setHotkey($0, for: mode) }),
                        onChange: {})
                        .frame(width: 170, height: 26)
                }
            }
            Divider().padding(.vertical, 2)
            Label {
                Text(L("Die Mikrofon-/Diktat-Taste deines Macs lässt sich nicht verwenden — macOS reserviert sie fest für die Diktatfunktion. Wähle oben eine Tastenkombination.",
                       "Your Mac's microphone/dictation key can't be used — macOS reserves it for Dictation. Pick a key combo above instead."))
            } icon: { Image(systemName: "info.circle") }
                .font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var testStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Probe-Diktat", "Test dictation")).font(.title3).bold()
            Text(L("Drücke dein Tastenkürzel (oder den Knopf), sprich kurz, und stoppe wieder. Das Ergebnis erscheint unten.",
                   "Press your hotkey (or the button), say something briefly, then stop. The result shows below."))
                .foregroundStyle(.secondary)
            HStack {
                Button(L("Roh-Aufnahme starten/stoppen", "Start/stop raw recording")) { onStartRawTest() }
                Label(stateLabel(flow.liveState), systemImage: stateIcon(flow.liveState))
                    .foregroundStyle(.secondary)
            }
            GroupBox(L("Letztes Transkript", "Last transcript")) {
                Text(flow.lastTestTranscript?.isEmpty == false ? flow.lastTestTranscript! : L("— noch nichts —", "— nothing yet —"))
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                    .textSelection(.enabled)
                    .foregroundStyle(flow.lastTestTranscript?.isEmpty == false ? .primary : .secondary)
            }
            Text(L("Dieser Schritt ist optional — du kannst auch direkt auf »Weiter« gehen.",
                   "This step is optional — you can just press \"Next\"."))
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 40)).foregroundStyle(.green)
            Text(L("Fertig eingerichtet", "All set")).font(.title2).bold()
            Text(L("Du kannst jederzeit über das Menüleisten-Symbol → »Einrichtung erneut starten« hierher zurück.",
                   "You can return anytime via the menu-bar icon → \"Run setup again\"."))
                .foregroundStyle(.secondary)
            Text(L("Tipp: Dein Tastenkürzel ist ", "Tip: your hotkey is ") + model.hotkey(.full).display + ".")
                .font(.callout)
            Spacer(minLength: 0)
        }
    }

    // MARK: Helpers

    private func stateLabel(_ s: SttState) -> String {
        switch s {
        case .idle: return L("Bereit", "Ready")
        case .recording: return L("Aufnahme…", "Recording…")
        case .whisper: return L("Transkribiere…", "Transcribing…")
        case .llm: return "LLM…"
        case .error: return L("Fehler", "Error")
        }
    }

    private func stateIcon(_ s: SttState) -> String {
        switch s {
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .whisper: return "waveform"
        case .llm: return "sparkles"
        case .error: return "exclamationmark.triangle"
        }
    }
}

/// One permission line in the wizard: status dot, title/detail, grant button.
private struct WizardPermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(granted ? L("Erlaubt", "Granted") : L("Erlauben…", "Grant…"), action: action)
                .disabled(granted)
        }
        .padding(.vertical, 2)
    }
}
