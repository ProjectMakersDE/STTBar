import AppKit
import SwiftUI

/// Native settings window content bound to `SettingsModel`.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var loc = Localization.shared
    var openEditor: (String) -> Void

    var body: some View {
        TabView {
            ServerTab(model: model).tabItem { Label(L("Server", "Server"), systemImage: "server.rack") }
            ProfilesTab(model: model).tabItem { Label(L("Profile", "Profiles"), systemImage: "switch.2") }
            VocabularyTab(model: model).tabItem { Label(L("Wörterbuch", "Vocabulary"), systemImage: "text.book.closed") }
            PromptsTab(model: model, openEditor: openEditor).tabItem { Label(L("Prompts", "Prompts"), systemImage: "text.bubble") }
            ShortcutsTab(model: model).tabItem { Label(L("Shortcuts", "Shortcuts"), systemImage: "command") }
            DisplayTab(model: model).tabItem { Label(L("Anzeige", "Display"), systemImage: "rectangle.on.rectangle") }
            PrivacyTab(model: model).tabItem { Label(L("Datenschutz", "Privacy"), systemImage: "lock") }
            GeneralTab(model: model).tabItem { Label(L("Allgemein", "General"), systemImage: "gearshape") }
        }
        .frame(width: 780, height: 620)
        .padding()
    }
}

private struct ServerTab: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var loc = Localization.shared
    @State private var audioDevices: [String] = []

    var body: some View {
        Form {
            Section(L("Audio-Eingang", "Audio input")) {
                Picker(L("Mikrofon", "Microphone"), selection: $model.audioInputDevice) {
                    ForEach(AudioInputCatalog.deviceIds(available: audioDevices, current: model.audioInputDevice), id: \.self) { id in
                        Text(audioDeviceLabel(id)).tag(id)
                    }
                }
                Text(L("Automatisch nutzt das Standard-Mikrofon (Bluetooth-Headsets werden vermieden). Wird nach Anwenden aktiv.",
                       "Automatic uses the default microphone (Bluetooth headsets are avoided). Takes effect after Apply."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Whisper") {
                TextField(L("Whisper-URL", "Whisper URL"), text: $model.whisperURL)
                Picker(L("Whisper-Modell", "Whisper model"), selection: $model.whisperModel) {
                    ForEach(SettingsModel.whisperPresets, id: \.self) { Text($0).tag($0) }
                    if !SettingsModel.whisperPresets.contains(model.whisperModel) {
                        Text(model.whisperModel).tag(model.whisperModel)
                    }
                }
                TextField(L("Whisper-Modell", "Whisper model"), text: $model.whisperModel)
                TextField(L("Sprache", "Language"), text: $model.language)
                TextField(L("Whisper-Timeout (s)", "Whisper timeout (s)"), text: $model.transcribeTimeout)
            }
            Section(L("Nachbearbeitung", "Post-processing")) {
                Toggle(L("LLM aktiv", "LLM enabled"), isOn: $model.postprocessEnabled)
                Picker(L("Provider", "Provider"), selection: $model.provider) {
                    Text("LM Studio").tag("lmstudio")
                    Text(L("OpenAI-kompatibel", "OpenAI-compatible")).tag("openai")
                }
                TextField(L("LLM-URL", "LLM URL"), text: $model.lmStudioURL)
                TextField(L("LLM-Modell", "LLM model"), text: $model.llmModel)
                TextField(L("LLM-Timeout (s)", "LLM timeout (s)"), text: $model.postprocessTimeout)
                TextField(L("Warnschwelle (s)", "Warn threshold (s)"), text: $model.postprocessWarnSeconds)
                Toggle(L("Raw-Fallback bei LLM-Fehler", "Raw fallback on LLM error"), isOn: $model.autoRawFallback)
            }
            Section {
                HStack {
                    Button(L("Anwenden", "Apply")) { model.applyEnvChanges() }
                        .keyboardShortcut("s")
                    Button(L("Rückgängig", "Revert")) { model.revertEnvChanges() }
                    Spacer()
                    if let message = model.validationMessage ?? model.saveMessage {
                        Text(message).font(.caption)
                            .foregroundStyle(model.validationMessage == nil ? Color.secondary : Color.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { audioDevices = AudioInputDevices.available() }
    }

    /// Display label for an audio-device env value in the picker.
    private func audioDeviceLabel(_ id: String) -> String {
        if id.isEmpty { return L("Automatisch", "Automatic") }
        return audioDevices.contains(id) ? id : id + L(" (nicht verbunden)", " (disconnected)")
    }
}

private struct ProfilesTab: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var loc = Localization.shared
    @State private var selected: String?
    @State private var profileName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField(L("Profilname", "Profile name"), text: $profileName)
                Button(L("Aktuelles Profil speichern", "Save current profile")) {
                    model.saveCurrentProfile(name: profileName.isEmpty ? L("Neues Profil", "New profile") : profileName)
                    selected = model.profiles.activeId
                }
            }
            List(selection: $selected) {
                ForEach(model.profiles.profiles) { profile in
                    VStack(alignment: .leading) {
                        Text(profile.name)
                        Text("\(profile.whisperModel) · \(profile.postprocessEnabled ? profile.postprocessModel : L("Raw", "Raw"))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(profile.id)
                }
            }
            HStack {
                Button(L("Aktivieren", "Activate")) {
                    if let id = selected, let p = model.profiles.profiles.first(where: { $0.id == id }) {
                        model.applyProfile(p)
                    }
                }
                .disabled(selected == nil)
                Button(L("Profil testen", "Test profile")) { model.applyEnvChanges() }
                    .disabled(selected == nil)
                Button(L("Löschen", "Delete"), role: .destructive) { if let id = selected { model.removeProfile(id); selected = nil } }
                    .disabled(selected == nil)
            }
        }
        .padding(.top, 4)
        .onAppear { selected = model.profiles.activeId }
    }
}

private struct VocabularyTab: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var loc = Localization.shared
    @State private var entries: [ReplacementEntry] = []
    @State private var previewInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(L("Eintrag hinzufügen", "Add entry")) { entries.append(ReplacementEntry(from: "", to: "")) }
                Button(L("Speichern", "Save")) { model.saveReplacements(entries) }
                Button(L("Neu laden", "Reload")) { entries = model.replacements.entries }
                Spacer()
                Text(model.replacements.url.path).font(.caption).foregroundStyle(.secondary)
            }
            List {
                ForEach($entries) { $entry in
                    HStack {
                        Toggle("", isOn: $entry.enabled).labelsHidden()
                        TextField(L("von", "from"), text: $entry.from)
                        Image(systemName: "arrow.right")
                        TextField(L("nach", "to"), text: $entry.to)
                        TextField(L("Kategorie", "Category"), text: $entry.category)
                        TextField(L("Kommentar", "Comment"), text: $entry.comment)
                        Button {
                            entries.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            HStack {
                TextField(L("Vorschau-Text", "Preview text"), text: $previewInput)
                Text(preview(entries, input: previewInput)).foregroundStyle(.secondary)
            }
        }
        .onAppear { entries = model.replacements.entries }
    }

    private func preview(_ entries: [ReplacementEntry], input: String) -> String {
        var output = input
        for entry in entries where entry.enabled && !entry.from.isEmpty {
            output = output.replacingOccurrences(of: entry.from, with: entry.to, options: [.caseInsensitive, .diacriticInsensitive])
        }
        return output
    }
}

private struct PromptsTab: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var loc = Localization.shared
    var openEditor: (String) -> Void
    @State private var selection: String?
    @State private var evalInput = DefaultPrompt.evalInput
    @State private var evalOutput = ""
    @State private var evalRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            List(selection: $selection) {
                ForEach(model.prompts.prompts) { p in
                    HStack {
                        Image(systemName: p.id == model.prompts.activeId ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(p.id == model.prompts.activeId ? Color.accentColor : .secondary)
                        VStack(alignment: .leading) {
                            Text(p.title)
                            Text("\(p.versions.count) \(L("Versionen", "versions"))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .tag(p.id)
                }
            }
            .frame(minHeight: 170)
            HStack {
                Button(L("Aktiv setzen", "Set active")) { if let id = selection { model.setActive(id) } }
                    .disabled(selection == nil)
                Button(L("Bearbeiten…", "Edit…")) { if let id = selection ?? model.prompts.activePrompt?.id { openEditor(id) } }
                Button(L("Neu", "New")) {
                    model.addPrompt(title: L("Neuer Prompt", "New prompt"), body: "")
                    selection = model.prompts.prompts.last?.id
                }
                Button(L("Duplizieren", "Duplicate")) {
                    if let id = selection, let p = model.prompts.prompts.first(where: { $0.id == id }) {
                        model.addPrompt(title: p.title + L(" (Kopie)", " (copy)"), body: p.body)
                    }
                }
                Button(L("Löschen", "Delete"), role: .destructive) { if let id = selection { model.removePrompt(id) } }
                    .disabled(selection == nil || model.prompts.prompts.count <= 1)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Mini-Eval", "Mini eval")).font(.headline)
                TextEditor(text: $evalInput)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 58)
                    .border(Color(NSColor.separatorColor))
                HStack {
                    Button(evalRunning ? L("Teste…", "Testing…") : L("Prompt testen", "Test prompt")) {
                        if let id = selection ?? model.prompts.activePrompt?.id {
                            evalRunning = true
                            evalOutput = ""
                            model.runPromptEval(promptId: id, input: evalInput) {
                                evalOutput = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                evalRunning = false
                            }
                        }
                    }
                    .disabled(evalRunning || evalInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Ausgabe", "Output")).font(.caption).foregroundStyle(.secondary)
                    Text(evalRunning ? L("Prompt wird getestet…", "Testing prompt…") : (evalOutput.isEmpty ? L("Noch nicht getestet.", "Not tested yet.") : evalOutput))
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(evalOutput.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor)))
                }
            }
        }
        .onAppear { selection = model.prompts.activeId }
        .padding(.top, 4)
    }
}

private struct ShortcutsTab: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var loc = Localization.shared

    var body: some View {
        Form {
            ForEach(SttMode.allCases, id: \.self) { mode in
                Section(mode.label) {
                    Text(mode.detail).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        HotkeyRecorder(
                            hotkey: Binding(
                                get: { model.hotkey(mode) },
                                set: { model.setHotkey($0, for: mode) }),
                            onChange: {}
                        )
                        .frame(width: 180, height: 26)
                        Button(L("Standard", "Default")) { model.resetHotkey(mode) }
                    }
                    if let status = model.hotkeyStatuses.first(where: { $0.mode == mode }) {
                        Label(status.message, systemImage: status.state == .registered ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(status.state == .registered ? .green : .orange)
                    }
                    if let warning = model.hotkeyWarning(for: mode) {
                        Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DisplayTab: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var loc = Localization.shared
    private let anchors = HudAnchor.allCases

    var body: some View {
        Form {
            Section(L("Position", "Position")) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(130)), count: 2), alignment: .leading) {
                    ForEach(anchors, id: \.self) { anchor in
                        Button {
                            model.hudAnchor = anchor
                        } label: {
                            Label(anchor.label, systemImage: model.hudAnchor == anchor ? "largecircle.fill.circle" : "circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Toggle(L("Auf aktivem Monitor anzeigen", "Show on active monitor"), isOn: $model.hudFollowActiveScreen)
                Stepper(L("Versatz X: \(model.hudOffsetX) pt", "Offset X: \(model.hudOffsetX) pt"),
                        value: $model.hudOffsetX, in: -600...600, step: 4)
                Stepper(L("Versatz Y: \(model.hudOffsetY) pt", "Offset Y: \(model.hudOffsetY) pt"),
                        value: $model.hudOffsetY, in: -600...600, step: 4)
            }
            Section(L("Größe", "Size")) {
                HStack {
                    Text(L("Skalierung", "Scale"))
                    Slider(value: $model.hudScale, in: 0.7...2.0, step: 0.05)
                    Text("\(Int((model.hudScale * 100).rounded()))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            Section(L("Elemente", "Elements")) {
                Toggle(L("Symbol anzeigen", "Show icon"), isOn: $model.showHudIcon)
                Toggle(L("Timer anzeigen", "Show timer"), isOn: $model.showHudTimer)
                Toggle(L("Waveform anzeigen", "Show waveform"), isOn: $model.showHudWaveform)
            }
            Section("Waveform") {
                Picker(L("Stil", "Style"), selection: $model.hudWaveStyle) {
                    ForEach(HudWaveStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                .disabled(!model.showHudWaveform)
                HStack {
                    Text(L("Abkling-Geschwindigkeit", "Release speed"))
                    Slider(value: $model.hudWaveDecaySpeed, in: 0.3...3.0, step: 0.1)
                    Text(String(format: "%.1f×", model.hudWaveDecaySpeed)).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                .disabled(!model.showHudWaveform)
            }
            Section(L("Hintergrund", "Background")) {
                Toggle(L("Hintergrund anzeigen", "Show background"), isOn: $model.hudBackground)
                ColorPicker(L("Hintergrundfarbe & Transparenz", "Background color & opacity"),
                            selection: $model.hudBackgroundColor, supportsOpacity: true)
                    .disabled(!model.hudBackground)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacyTab: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var loc = Localization.shared

    var body: some View {
        Form {
            Section(L("Verlauf", "History")) {
                Toggle(L("Sensitive Mode", "Sensitive mode"), isOn: $model.sensitiveMode)
                Toggle(L("Transkriptverlauf speichern", "Store transcript history"), isOn: $model.historyEnabled)
                    .disabled(model.sensitiveMode)
                TextField(L("Auto-Löschen nach Stunden", "Auto-delete after hours"), text: $model.historyRetentionHours)
                    .disabled(model.sensitiveMode || !model.historyEnabled)
            }
            Section(L("Laufzeit", "Runtime")) {
                TextField(L("Maximale Aufnahmedauer (s)", "Max recording duration (s)"), text: $model.maxRecordingSeconds)
                Toggle(L("Server warm halten", "Keep server warm"), isOn: $model.prewarmEnabled)
                TextField(L("Warmhalte-Intervall (s)", "Keep-warm interval (s)"), text: $model.keepModelWarmSeconds)
            }
            Section {
                HStack {
                    Button(L("Anwenden", "Apply")) { model.applyEnvChanges() }
                    Button(L("Rückgängig", "Revert")) { model.revertEnvChanges() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// One permission: name, why it's needed, a status dot, and a grant button
/// that triggers the system prompt and opens the relevant settings pane.
private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool?
    let openLabel: String
    let grantLabel: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: granted == true ? "checkmark.circle.fill"
                      : (granted == false ? "exclamationmark.circle.fill" : "questionmark.circle"))
                    .foregroundStyle(granted == true ? Color.green
                                     : (granted == false ? Color.orange : Color.secondary))
                Text(title)
                Spacer()
                Button(granted == true ? openLabel : grantLabel, action: action)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var loc = Localization.shared
    @State private var autostart = LaunchAgent.isEnabled

    var body: some View {
        let version = VersionInfo.load(installDir: model.installDir)
        let repo = model.updateRepository
        Form {
            Section(L("Sprache", "Language")) {
                Picker(L("App-Sprache", "App language"), selection: Binding(
                    get: { Localization.shared.language },
                    set: { model.setAppLanguage($0) })) {
                    Text("Deutsch").tag(AppLanguage.de)
                    Text("English").tag(AppLanguage.en)
                }
                .pickerStyle(.segmented)
                Text(L("Schaltet Oberfläche, Whisper-Sprache und den aktiven Prompt um.",
                       "Switches the interface, Whisper language and the active prompt."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Start", "Startup")) {
                Toggle(L("Beim Login automatisch starten", "Launch automatically at login"), isOn: $autostart)
                    .onChange(of: autostart) { _, on in
                        let appPath = Bundle.main.bundlePath
                        LaunchAgent.setEnabled(on, appPath: appPath, installDir: model.installDir.path)
                    }
            }
            Section(L("Berechtigungen", "Permissions")) {
                PermissionRow(
                    title: L("Bedienungshilfen", "Accessibility"),
                    detail: L("Nötig zum Einfügen des Texts ins aktive Feld.", "Required to paste text into the active field."),
                    granted: Permissions.accessibilityTrusted,
                    openLabel: L("Öffnen", "Open"), grantLabel: L("Erlauben…", "Grant…"),
                    action: { Permissions.promptAccessibility(); Permissions.openAccessibility() })
                PermissionRow(
                    title: L("Mikrofon", "Microphone"),
                    detail: L("Nötig für die Audioaufnahme.", "Required for audio recording."),
                    granted: Permissions.microphoneStatus == .authorized,
                    openLabel: L("Öffnen", "Open"), grantLabel: L("Erlauben…", "Grant…"),
                    action: { Permissions.requestMicrophone(); Permissions.openMicrophone() })
                PermissionRow(
                    title: L("Automatisierung", "Automation"),
                    detail: L("Nur für den AppleScript-Fallback relevant.", "Only relevant for the AppleScript fallback."),
                    granted: nil,
                    openLabel: L("Öffnen", "Open"), grantLabel: L("Erlauben…", "Grant…"),
                    action: { Permissions.primeAutomation(); Permissions.openAutomation() })
            }
            Section("Import/Export") {
                HStack {
                    Button(L("Exportieren", "Export")) { model.exportBundle() }
                    Button(L("Importieren", "Import")) { model.importBundle() }
                }
            }
            Section(L("Version", "Version")) {
                Text("App: v\(version.appVersion) (Build \(version.appBuild))")
                Text("App-Commit: \(version.appCommit)")
                Text(L("Scripts-Commit: ", "Scripts commit: ") + version.scriptCommit)
                Text(L("Installiert: ", "Installed: ") + version.installedAt)
                HStack {
                    Link(L("GitHub-Repository", "GitHub repository"),
                         destination: URL(string: "https://github.com/\(repo)")!)
                    Link(L("Releases öffnen", "Open releases"),
                         destination: URL(string: "https://github.com/\(repo)/releases")!)
                }
                .font(.caption)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(L("Nach Updates suchen", "Check for updates")) { model.checkForUpdates() }
                        if model.updateState == .available {
                            Button(L("Aktualisieren", "Update")) { model.performUpdate() }
                                .buttonStyle(.borderedProminent)
                        }
                        if let url = model.updateURL {
                            Button(L("Release öffnen", "Open release")) { NSWorkspace.shared.open(url) }
                        }
                    }
                    if model.updateState == .downloading || model.updateState == .installing {
                        ProgressView().controlSize(.small)
                    }
                    if let message = model.updateMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                HStack(spacing: 4) {
                    Spacer()
                    Text("made with")
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                    Text("by")
                    Link("ProjectMakers.de", destination: URL(string: "https://projectmakers.de")!)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
