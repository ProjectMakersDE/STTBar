import SwiftUI

/// Native settings window content bound to `SettingsModel`.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var openEditor: (String) -> Void

    var body: some View {
        TabView {
            ServerTab(model: model).tabItem { Label("Server", systemImage: "server.rack") }
            ProfilesTab(model: model).tabItem { Label("Profile", systemImage: "switch.2") }
            VocabularyTab(model: model).tabItem { Label("Wörterbuch", systemImage: "text.book.closed") }
            PromptsTab(model: model, openEditor: openEditor).tabItem { Label("Prompts", systemImage: "text.bubble") }
            ShortcutsTab(model: model).tabItem { Label("Shortcuts", systemImage: "command") }
            DisplayTab(model: model).tabItem { Label("Anzeige", systemImage: "rectangle.on.rectangle") }
            PrivacyTab(model: model).tabItem { Label("Datenschutz", systemImage: "lock") }
            GeneralTab(model: model).tabItem { Label("Allgemein", systemImage: "gearshape") }
        }
        .frame(width: 780, height: 620)
        .padding()
    }
}

private struct ServerTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Whisper") {
                TextField("Whisper-URL", text: $model.whisperURL)
                Picker("Whisper-Modell", selection: $model.whisperModel) {
                    ForEach(SettingsModel.whisperPresets, id: \.self) { Text($0).tag($0) }
                    if !SettingsModel.whisperPresets.contains(model.whisperModel) {
                        Text(model.whisperModel).tag(model.whisperModel)
                    }
                }
                TextField("Whisper-Modell", text: $model.whisperModel)
                TextField("Sprache", text: $model.language)
                TextField("Whisper-Timeout (s)", text: $model.transcribeTimeout)
            }
            Section("Nachbearbeitung") {
                Toggle("LLM aktiv", isOn: $model.postprocessEnabled)
                Picker("Provider", selection: $model.provider) {
                    Text("LM Studio").tag("lmstudio")
                    Text("OpenAI-kompatibel").tag("openai")
                }
                TextField("LLM-URL", text: $model.lmStudioURL)
                TextField("LLM-Modell", text: $model.llmModel)
                TextField("LLM-Timeout (s)", text: $model.postprocessTimeout)
                TextField("Warnschwelle (s)", text: $model.postprocessWarnSeconds)
                Toggle("Raw-Fallback bei LLM-Fehler", isOn: $model.autoRawFallback)
            }
            Section {
                HStack {
                    Button("Anwenden") { model.applyEnvChanges() }
                        .keyboardShortcut("s")
                    Button("Rückgängig") { model.revertEnvChanges() }
                    Spacer()
                    if let message = model.validationMessage ?? model.saveMessage {
                        Text(message).font(.caption)
                            .foregroundStyle(model.validationMessage == nil ? Color.secondary : Color.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProfilesTab: View {
    @ObservedObject var model: SettingsModel
    @State private var selected: String?
    @State private var profileName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Profilname", text: $profileName)
                Button("Aktuelles Profil speichern") {
                    model.saveCurrentProfile(name: profileName.isEmpty ? "Neues Profil" : profileName)
                    selected = model.profiles.activeId
                }
            }
            List(selection: $selected) {
                ForEach(model.profiles.profiles) { profile in
                    VStack(alignment: .leading) {
                        Text(profile.name)
                        Text("\(profile.whisperModel) · \(profile.postprocessEnabled ? profile.postprocessModel : "Raw")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(profile.id)
                }
            }
            HStack {
                Button("Aktivieren") {
                    if let id = selected, let p = model.profiles.profiles.first(where: { $0.id == id }) {
                        model.applyProfile(p)
                    }
                }
                .disabled(selected == nil)
                Button("Profil testen") { model.applyEnvChanges() }
                    .disabled(selected == nil)
                Button("Löschen", role: .destructive) { if let id = selected { model.removeProfile(id); selected = nil } }
                    .disabled(selected == nil)
            }
        }
        .padding(.top, 4)
        .onAppear { selected = model.profiles.activeId }
    }
}

private struct VocabularyTab: View {
    @ObservedObject var model: SettingsModel
    @State private var entries: [ReplacementEntry] = []
    @State private var previewInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Eintrag hinzufügen") { entries.append(ReplacementEntry(from: "", to: "")) }
                Button("Speichern") { model.saveReplacements(entries) }
                Button("Neu laden") { entries = model.replacements.entries }
                Spacer()
                Text(model.replacements.url.path).font(.caption).foregroundStyle(.secondary)
            }
            List {
                ForEach($entries) { $entry in
                    HStack {
                        Toggle("", isOn: $entry.enabled).labelsHidden()
                        TextField("von", text: $entry.from)
                        Image(systemName: "arrow.right")
                        TextField("nach", text: $entry.to)
                        TextField("Kategorie", text: $entry.category)
                        TextField("Kommentar", text: $entry.comment)
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
                TextField("Vorschau-Text", text: $previewInput)
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
    var openEditor: (String) -> Void
    @State private var selection: String?
    @State private var evalInput = "also ich glaub wir sollten mal den endpoint prüfen"
    @State private var evalOutput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            List(selection: $selection) {
                ForEach(model.prompts.prompts) { p in
                    HStack {
                        Image(systemName: p.id == model.prompts.activeId ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(p.id == model.prompts.activeId ? Color.accentColor : .secondary)
                        VStack(alignment: .leading) {
                            Text(p.title)
                            Text("\(p.versions.count) Versionen").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .tag(p.id)
                }
            }
            .frame(minHeight: 170)
            HStack {
                Button("Aktiv setzen") { if let id = selection { model.setActive(id) } }
                    .disabled(selection == nil)
                Button("Bearbeiten…") { if let id = selection ?? model.prompts.activePrompt?.id { openEditor(id) } }
                Button("Neu") {
                    model.addPrompt(title: "Neuer Prompt", body: "")
                    selection = model.prompts.prompts.last?.id
                }
                Button("Duplizieren") {
                    if let id = selection, let p = model.prompts.prompts.first(where: { $0.id == id }) {
                        model.addPrompt(title: p.title + " (Kopie)", body: p.body)
                    }
                }
                Button("Löschen", role: .destructive) { if let id = selection { model.removePrompt(id) } }
                    .disabled(selection == nil || model.prompts.prompts.count <= 1)
            }
            Divider()
            TextField("Mini-Eval Rohtext", text: $evalInput)
            HStack {
                Button("Prompt testen") {
                    if let id = selection ?? model.prompts.activePrompt?.id {
                        model.runPromptEval(promptId: id, input: evalInput) { evalOutput = $0 }
                    }
                }
                Text(evalOutput.isEmpty ? "Noch kein Ergebnis" : evalOutput)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .onAppear { selection = model.prompts.activeId }
        .padding(.top, 4)
    }
}

private struct ShortcutsTab: View {
    @ObservedObject var model: SettingsModel

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
                        Button("Standard") { model.resetHotkey(mode) }
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
    private let anchors = HudAnchor.allCases

    var body: some View {
        Form {
            Section("HUD") {
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
                Toggle("Timer anzeigen", isOn: $model.showHudTimer)
                Toggle("Phasenlabel anzeigen", isOn: $model.showHudPhaseLabel)
                Toggle("Warnung bei niedrigem Pegel", isOn: $model.lowMicWarningEnabled)
            }
            Section("Hintergrund") {
                Toggle("Hintergrund anzeigen", isOn: $model.hudBackground)
                ColorPicker("Hintergrundfarbe & Transparenz",
                            selection: $model.hudBackgroundColor, supportsOpacity: true)
                    .disabled(!model.hudBackground)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacyTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Verlauf") {
                Toggle("Sensitive Mode", isOn: $model.sensitiveMode)
                Toggle("Transkriptverlauf speichern", isOn: $model.historyEnabled)
                    .disabled(model.sensitiveMode)
                TextField("Auto-Löschen nach Stunden", text: $model.historyRetentionHours)
                    .disabled(model.sensitiveMode || !model.historyEnabled)
            }
            Section("Laufzeit") {
                TextField("Maximale Aufnahmedauer (s)", text: $model.maxRecordingSeconds)
                Toggle("Server warm halten", isOn: $model.prewarmEnabled)
                TextField("Warmhalte-Intervall (s)", text: $model.keepModelWarmSeconds)
            }
            Section {
                HStack {
                    Button("Anwenden") { model.applyEnvChanges() }
                    Button("Rückgängig") { model.revertEnvChanges() }
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
                Button(granted == true ? "Öffnen" : "Erlauben…", action: action)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel
    @State private var autostart = LaunchAgent.isEnabled

    var body: some View {
        let version = VersionInfo.load(installDir: model.installDir)
        Form {
            Section("Start") {
                Toggle("Beim Login automatisch starten", isOn: $autostart)
                    .onChange(of: autostart) { _, on in
                        let appPath = Bundle.main.bundlePath
                        LaunchAgent.setEnabled(on, appPath: appPath, installDir: model.installDir.path)
                    }
            }
            Section("Berechtigungen") {
                PermissionRow(
                    title: "Bedienungshilfen",
                    detail: "Nötig zum Einfügen des Texts ins aktive Feld.",
                    granted: Permissions.accessibilityTrusted,
                    action: { Permissions.promptAccessibility(); Permissions.openAccessibility() })
                PermissionRow(
                    title: "Mikrofon",
                    detail: "Nötig für die Audioaufnahme.",
                    granted: Permissions.microphoneStatus == .authorized,
                    action: { Permissions.requestMicrophone(); Permissions.openMicrophone() })
                PermissionRow(
                    title: "Automatisierung",
                    detail: "Nur für den AppleScript-Fallback relevant.",
                    granted: nil,
                    action: { Permissions.primeAutomation(); Permissions.openAutomation() })
            }
            Section("Import/Export") {
                HStack {
                    Button("Exportieren") { model.exportBundle() }
                    Button("Importieren") { model.importBundle() }
                }
            }
            Section("Version") {
                Text("App: \(version.appCommit)")
                Text("Scripts: \(version.scriptCommit)")
                Text("Installiert: \(version.installedAt)")
                HStack {
                    Button("Nach Updates suchen") { model.checkForUpdates() }
                    if let message = model.updateMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
