import SwiftUI

/// Editor for a single prompt: title + multi-line body, saved back to the store.
struct PromptEditorView: View {
    @ObservedObject var model: SettingsModel
    let promptId: String

    @State private var title: String = ""
    @State private var body_: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Titel", text: $title)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $body_)
                .font(.system(.body, design: .monospaced))
                .border(Color(NSColor.separatorColor))
            HStack {
                if promptId == model.prompts.activeId {
                    Label("Aktiver Prompt – wird live verwendet", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Auf Standard zurücksetzen") { body_ = DefaultPrompt.body }
                Button("Speichern") { model.updatePrompt(promptId, title: title, body: body_) }
                    .keyboardShortcut("s")
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
