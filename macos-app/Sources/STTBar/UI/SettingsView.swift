import SwiftUI

/// The native settings window content: five tabs bound to `SettingsModel`.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    /// Opens the separate titled prompt editor for the given prompt id.
    var openEditor: (String) -> Void

    var body: some View {
        TabView {
            ServerTab(model: model).tabItem { Label("Server", systemImage: "server.rack") }
            PromptsTab(model: model, openEditor: openEditor).tabItem { Label("Prompts", systemImage: "text.bubble") }
            ShortcutsTab(model: model).tabItem { Label("Shortcuts", systemImage: "command") }
            DisplayTab(model: model).tabItem { Label("Anzeige", systemImage: "rectangle.on.rectangle") }
            GeneralTab(model: model).tabItem { Label("Allgemein", systemImage: "gearshape") }
        }
        .frame(width: 540, height: 440)
        .padding()
    }
}

private struct ServerTab: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            Section("Whisper-Server") {
                TextField("Whisper-URL / IP", text: $model.whisperURL)
                Picker("Whisper-Modell", selection: $model.whisperModel) {
                    ForEach(SettingsModel.whisperPresets, id: \.self) { Text($0).tag($0) }
                    if !SettingsModel.whisperPresets.contains(model.whisperModel) {
                        Text(model.whisperModel).tag(model.whisperModel)
                    }
                }
                TextField("Whisper-Modell (frei)", text: $model.whisperModel)
                TextField("Sprache (de / en / auto)", text: $model.language)
            }
            Section("Nachbearbeitung (LM Studio)") {
                Toggle("LLM-Nachbearbeitung aktiv", isOn: $model.postprocessEnabled)
                TextField("LM-Studio-URL / IP", text: $model.lmStudioURL)
                TextField("LLM-ID (z. B. qwen/qwen3.5-9b)", text: $model.llmModel)
                Picker("Provider", selection: $model.provider) {
                    Text("LM Studio").tag("lmstudio")
                    Text("OpenAI-kompatibel").tag("openai")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PromptsTab: View {
    @ObservedObject var model: SettingsModel
    var openEditor: (String) -> Void
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading) {
            Text("Aktiver Prompt wird live verwendet (kein Neustart nötig).")
                .font(.caption).foregroundStyle(.secondary)
            List(selection: $selection) {
                ForEach(model.prompts.prompts) { p in
                    HStack {
                        Image(systemName: p.id == model.prompts.activeId ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(p.id == model.prompts.activeId ? Color.accentColor : .secondary)
                        Text(p.title)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .tag(p.id)
                }
            }
            .frame(minHeight: 180)
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
                    HotkeyRecorder(
                        hotkey: Binding(
                            get: { model.hotkey(mode) },
                            set: { model.setHotkey($0, for: mode) }),
                        onChange: {}
                    )
                    .frame(width: 180, height: 26)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DisplayTab: View {
    @ObservedObject var model: SettingsModel
    // 3x3 grid; center is empty. Maps grid cells to the 8 anchors.
    private let grid: [[HudAnchor?]] = [
        [.leftTop,    .topCenter, .rightTop],
        [nil,         nil,        nil],
        [.bottomLeft, nil,        .bottomRight],
    ]
    // The remaining four "edge" anchors offered as a secondary row.
    private let edges: [HudAnchor] = [.leftBottom, .rightBottom, .topRight, .bottomLeft]

    var body: some View {
        Form {
            Section("Position der Aufnahme-Animation") {
                VStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { r in
                        HStack(spacing: 6) {
                            ForEach(0..<3, id: \.self) { c in
                                anchorCell(grid[r][c])
                            }
                        }
                    }
                }
                Picker("Weitere Position", selection: $model.hudAnchor) {
                    ForEach(HudAnchor.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            Section("Sichtbarkeit") {
                Toggle("Leicht grauer Hintergrund", isOn: $model.hudBackground)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private func anchorCell(_ anchor: HudAnchor?) -> some View {
        if let anchor {
            Button {
                model.hudAnchor = anchor
            } label: {
                Image(systemName: model.hudAnchor == anchor ? "largecircle.fill.circle" : "circle")
                    .frame(width: 40, height: 28)
            }
            .buttonStyle(.bordered)
            .help(anchor.label)
        } else {
            Color.clear.frame(width: 40, height: 28)
        }
    }
}

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel
    @State private var autostart = LaunchAgent.isEnabled

    var body: some View {
        Form {
            Section("Start") {
                Toggle("Beim Login automatisch starten", isOn: $autostart)
                    .onChange(of: autostart) { _, on in
                        let appPath = Bundle.main.bundlePath
                        LaunchAgent.setEnabled(on, appPath: appPath, installDir: model.installDir.path)
                    }
            }
            Section("Hammerspoon") {
                Text("STTBar übernimmt Menü-Icon, Hotkeys und HUD. Der Hammerspoon-STT-Block kann entfernt werden (siehe install.sh).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Berechtigungen") {
                Button("Bedienungshilfen öffnen (für Einfügen)") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
