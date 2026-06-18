import SwiftUI

/// Editor for a single prompt: title + multi-line body, saved back to the store.
struct PromptEditorView: View {
    @ObservedObject var model: SettingsModel
    let promptId: String

    @State private var title: String = ""
    @State private var body_: String = ""
    @State private var note: String = ""
    @State private var evalInput: String = DefaultPrompt.evalInput
    @State private var evalOutput: String = ""
    @State private var evalRunning = false

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
            VStack(alignment: .leading, spacing: 8) {
                Text("Mini-Eval").font(.headline)
                TextEditor(text: $evalInput)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 58)
                    .border(Color(NSColor.separatorColor))
                HStack {
                    Button(evalRunning ? "Teste…" : "Prompt testen") {
                        evalRunning = true
                        evalOutput = ""
                        model.runPromptEval(promptId: promptId, input: evalInput) {
                            evalOutput = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                            evalRunning = false
                        }
                    }
                    .disabled(evalRunning || evalInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ausgabe").font(.caption).foregroundStyle(.secondary)
                    Text(evalRunning ? "Prompt wird getestet…" : (evalOutput.isEmpty ? "Noch nicht getestet." : evalOutput))
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
