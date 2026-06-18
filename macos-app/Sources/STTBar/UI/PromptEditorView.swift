import SwiftUI

/// Editor for a single prompt: title + multi-line body, saved back to the store.
struct PromptEditorView: View {
    @ObservedObject var model: SettingsModel
    let promptId: String

    @State private var title: String = ""
    @State private var body_: String = ""
    @State private var note: String = ""
    @State private var evalInput: String = "kannst du mal prüfen ob die url h t t p doppelpunkt slash slash localhost slash api erreichbar ist"
    @State private var evalOutput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Titel", text: $title)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $body_)
                .font(.system(.body, design: .monospaced))
                .border(Color(NSColor.separatorColor))
            TextField("Versionsnotiz", text: $note)
                .textFieldStyle(.roundedBorder)
            HStack {
                if promptId == model.prompts.activeId {
                    Label("Aktiver Prompt – wird live verwendet", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Auf Standard zurücksetzen") { body_ = DefaultPrompt.body }
                Button("Speichern") { model.updatePrompt(promptId, title: title, body: body_, note: note); note = "" }
                    .keyboardShortcut("s")
            }
            Divider()
            HStack {
                TextField("Mini-Eval Rohtext", text: $evalInput)
                Button("Testen") {
                    model.runPromptEval(promptId: promptId, input: evalInput) { evalOutput = $0 }
                }
            }
            Text(evalOutput.isEmpty ? "Noch kein Ergebnis" : evalOutput)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(3)
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
