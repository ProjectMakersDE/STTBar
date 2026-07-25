import AppKit
import SwiftUI

/// Sizes and cleanup state for the "Dateien & Speicher" section. Kept out of
/// `SettingsModel`, which already carries the entire `.env` surface.
final class DataFolderModel: ObservableObject {
    @Published private(set) var sizes: [DataLocation: Int64] = [:]
    @Published private(set) var isBusy = false
    @Published private(set) var lastCleanupMessage: String?

    private let isIdle: () -> Bool

    init(isIdle: @escaping () -> Bool) {
        self.isIdle = isIdle
    }

    /// Re-reads the busy flag right away and the folder sizes off the main
    /// thread, so switching to the tab never stalls the form.
    func refresh() {
        isBusy = !isIdle()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let next = Dictionary(uniqueKeysWithValues:
                DataLocation.allCases.map { ($0, $0.byteCount) })
            DispatchQueue.main.async { self?.sizes = next }
        }
    }

    func reveal(_ location: DataLocation) { location.reveal() }

    func cleanUp() {
        // Re-check at click time: the window may have been open since before
        // the current run started.
        isBusy = !isIdle()
        guard !isBusy else { return }
        guard confirmDeletion() else { return }

        let result = TempFileCleanup.run(runtime: RuntimePaths.directory,
                                         logs: DataLocation.logs.url)
        AppLogger.log("temp_cleanup files=\(result.removedFiles) bytes=\(result.freedBytes)")
        let freed = ByteCountFormatter.string(fromByteCount: result.freedBytes, countStyle: .file)
        lastCleanupMessage = result.removedFiles == 0
            ? L("Nichts zu löschen.", "Nothing to delete.")
            : L("\(result.removedFiles) Dateien gelöscht, \(freed) freigegeben.",
                "Deleted \(result.removedFiles) files, freed \(freed).")
        refresh()
    }

    private func confirmDeletion() -> Bool {
        let alert = NSAlert()
        alert.messageText = L("Temporäre Dateien löschen?", "Delete temporary files?")
        alert.informativeText = L(
            "Entfernt Aufnahme, Events, Metriken, Status und das Log. Einstellungen, Prompts, Wörterbuch und Transkriptverlauf bleiben erhalten.",
            "Removes the recording, events, metrics, status and the log. Settings, prompts, vocabulary and transcript history are kept.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Löschen", "Delete"))
        alert.addButton(withTitle: L("Abbrechen", "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// One `Form` section listing the three data folders plus the cleanup button.
struct DataFolderSection: View {
    @ObservedObject var model: DataFolderModel

    var body: some View {
        Section(L("Dateien & Speicher", "Files & storage")) {
            ForEach(DataLocation.allCases) { location in
                DataFolderRow(location: location,
                              byteCount: model.sizes[location],
                              reveal: { model.reveal(location) })
            }
            VStack(alignment: .leading, spacing: 4) {
                Button(L("Temporäre Dateien löschen", "Delete temporary files")) { model.cleanUp() }
                    .disabled(model.isBusy)
                if model.isBusy {
                    Text(L("Nicht möglich, solange eine Aufnahme oder Transkription läuft.",
                           "Not available while a recording or transcription is running."))
                        .font(.caption).foregroundStyle(.secondary)
                } else if let message = model.lastCleanupMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { model.refresh() }
    }
}

private struct DataFolderRow: View {
    let location: DataLocation
    let byteCount: Int64?
    let reveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(location.title)
                    Text(location.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(byteCount.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "…")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Button(L("Im Finder öffnen", "Open in Finder"), action: reveal)
            }
            // The container path is unfindable by hand; showing it is half the
            // point of this section.
            Text(location.url.path)
                .font(.caption).foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .lineLimit(2).truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }
}
