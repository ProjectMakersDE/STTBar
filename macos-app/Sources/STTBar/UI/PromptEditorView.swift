import SwiftUI

/// Editor for a single prompt: title + multi-line body, saved back to the store.
struct PromptEditorView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var loc = Localization.shared
    let promptId: String

    @State private var title: String = ""
    @State private var body_: String = ""
    @State private var note: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L("Titel", "Title"), text: $title)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $body_)
                .font(.system(.body, design: .monospaced))
                .border(Color(NSColor.separatorColor))
            TextField(L("Versionsnotiz", "Version note"), text: $note)
                .textFieldStyle(.roundedBorder)
            HStack {
                if promptId == model.prompts.activeId {
                    Label(L("Aktiver Prompt – wird live verwendet", "Active prompt – used live"), systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Auf Standard zurücksetzen", "Reset to default")) { body_ = DefaultPrompt.body }
                Button(L("Speichern", "Save")) { model.updatePrompt(promptId, title: title, body: body_, note: note); note = "" }
                    .keyboardShortcut("s")
            }
            if let p = model.prompts.prompts.first(where: { $0.id == promptId }), !p.versions.isEmpty {
                List(p.versions.prefix(5)) { version in
                    VStack(alignment: .leading) {
                        Text(version.note)
                        Text(version.date.formatted()).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 90)
            }
        }
        .padding()
        .onAppear { load() }
        .onChange(of: promptId) { _, _ in load() }
    }

    private func load() {
        if let p = model.prompts.prompts.first(where: { $0.id == promptId }) {
            title = p.title; body_ = p.body
        }
    }
}
