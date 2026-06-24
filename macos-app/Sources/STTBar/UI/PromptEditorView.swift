import SwiftUI

/// Editor for a single prompt: title + multi-line body, saved back to the store.
struct PromptEditorView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var loc = Localization.shared
    let promptId: String

    @State private var title: String = ""
    @State private var body_: String = ""
    @State private var note: String = ""
    @State private var evalInput: String = DefaultPrompt.evalInput
    @State private var evalOutput: String = ""
    @State private var evalRunning = false

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
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Mini-Eval", "Mini eval")).font(.headline)
                TextEditor(text: $evalInput)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 58)
                    .border(Color(NSColor.separatorColor))
                HStack {
                    Button(evalRunning ? L("Teste…", "Testing…") : L("Prompt testen", "Test prompt")) {
                        // Native prompt eval returns in Phase 2 (LLM cleanup).
                        evalOutput = L("Prompt-Test kehrt in Phase 2 (LLM-Cleanup) zurück.",
                                       "Prompt testing returns in Phase 2 (LLM cleanup).")
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
