import AppKit
import SwiftUI

/// Sizes and cleanup state for the "Dateien & Speicher" section. Kept out of
/// `SettingsModel`, which already carries the entire `.env` surface.
final class DataFolderModel: ObservableObject {
    @Published private(set) var sizes: [DataLocation: Int64] = [:]
    @Published private(set) var isBusy = false
    @Published private(set) var lastCleanupMessage: String?

    /// Resolved once at construction, not re-read from a SwiftUI body:
    /// `.logs` resolves through `AppLogger.logURL`, which creates its
    /// directory as a side effect on every read.
    let urls: [DataLocation: URL]

    private let isIdle: () -> Bool
    private let confirm: () -> Bool
    private let runtime: URL
    private let logs: URL

    init(isIdle: @escaping () -> Bool,
         confirm: @escaping () -> Bool = DataFolderModel.confirmDeletionAlert,
         runtime: URL = DataLocation.runtime.url,
         logs: URL = DataLocation.logs.url) {
        self.isIdle = isIdle
        self.confirm = confirm
        self.runtime = runtime
        self.logs = logs
        self.urls = Dictionary(uniqueKeysWithValues: DataLocation.allCases.map { ($0, $0.url) })
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

    /// Pushed by the caller's `runner.onState` fan-out so the button reflects
    /// the live run state even while the window stays open across a run.
    /// The re-check inside `cleanUp()` remains the actual safety gate; this
    /// only keeps the disabled hint from going stale.
    func setRunActive(_ active: Bool) { isBusy = active }

    func reveal(_ location: DataLocation) { location.reveal() }

    func cleanUp() {
        // Re-check at click time: the window may have been open since before
        // the current run started.
        isBusy = !isIdle()
        guard !isBusy else { return }
        guard confirm() else { return }

        let result = TempFileCleanup.run(runtime: runtime, logs: logs)
        AppLogger.log("temp_cleanup files=\(result.removedFiles) bytes=\(result.freedBytes)")
        let freed = ByteCountFormatter.string(fromByteCount: result.freedBytes, countStyle: .file)
        if result.removedFiles == 0 {
            lastCleanupMessage = L("Nichts zu löschen.", "Nothing to delete.")
        } else {
            let files = result.removedFiles == 1
                ? L("1 Datei", "1 file")
                : L("\(result.removedFiles) Dateien", "\(result.removedFiles) files")
            lastCleanupMessage = L("\(files) gelöscht, \(freed) freigegeben.",
                                   "Deleted \(files), freed \(freed).")
        }
        refresh()
    }

    /// The production confirmation flow: a blocking `NSAlert`. Kept as a
    /// static default so tests can inject a stub without a modal appearing,
    /// while every real caller gets the alert without asking for it.
    private static func confirmDeletionAlert() -> Bool {
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
                              url: model.urls[location] ?? location.url,
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
    let url: URL
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
            // point of this section. `url` is resolved once by the parent
            // model, not here — re-resolving `.logs` on every body
            // evaluation would `mkdir` as a SwiftUI rendering side effect.
            Text(url.path)
                .font(.caption).foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .lineLimit(2).truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }
}
