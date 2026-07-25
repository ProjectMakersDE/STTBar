# Daten-Ordner-Zugang und Temp-Aufräumen — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aus dem Allgemein-Tab und der Menüleiste heraus die drei Daten-Ordner der App im Finder öffnen und die temporären Dateien löschen können.

**Architecture:** Zwei neue Core-Typen tragen die Logik: `DataLocation` (welche Ordner gibt es, wie groß sind sie) und `TempFileCleanup` (welche Dateien dürfen gelöscht werden, als explizite Positivliste). Die UI besteht aus einer neuen `Section` im Allgemein-Tab mit einem kleinen eigenen `ObservableObject`, plus einem Untermenü in der Menüleiste. Beide rufen nur die Core-Typen auf, sodass Größenberechnung und Löschlogik ohne UI unter `swift test` prüfbar sind.

**Tech Stack:** Swift 5.9, SwiftPM, SwiftUI + AppKit, XCTest. Keine neuen Abhängigkeiten.

**Spec:** `docs/superpowers/specs/2026-07-25-data-folder-access-design.md`

## Global Constraints

- Zielplattform ist macOS 14 (`Package.swift`, `platforms: [.macOS(.v14)]`).
- Jeder nutzersichtbare Text läuft über `L("Deutsch", "English")` aus `Config/Localization.swift`.
- Keine neuen Package-Abhängigkeiten.
- Pfade kommen ausschließlich aus den vorhandenen Auflösern `InstallPaths.resolve()`, `RuntimePaths.directory` und `AppLogger.logURL`. Keine neue Pfad-Logik, keine hartkodierten Container-Pfade.
- Gelöscht wird nur über eine explizite Dateinamen-Liste. Kein `removeItem` auf ein Verzeichnis, kein Muster-Matching.
- Commits nach Conventional Commits (`feat(scope): …`), da Semantic Release auf `master` läuft.
- Abnahme nach jeder Aufgabe: `swift test --package-path macos-app` läuft grün.

---

### Task 1: Ordner-Modell und Größenberechnung

**Files:**
- Create: `macos-app/Sources/STTBar/Core/DataLocations.swift`
- Test: `macos-app/Tests/STTBarTests/DataLocationsTests.swift`

**Interfaces:**
- Consumes: `InstallPaths.resolve()` (`AppDelegate.swift:205`), `RuntimePaths.directory` (`Core/RuntimePaths.swift:7`), `AppLogger.logURL` (`Core/AppLogger.swift:4`), `L(_:_:)` (`Config/Localization.swift`)
- Produces:
  - `enum DataLocation: String, CaseIterable, Identifiable` mit den Fällen `config`, `runtime`, `logs` und den Membern `title: String`, `detail: String`, `url: URL`, `byteCount: Int64`, `func reveal()`
  - `enum DirectorySize` mit `static func bytes(of directory: URL, excluding excluded: URL? = nil) -> Int64`

- [ ] **Step 1: Write the failing test**

Create `macos-app/Tests/STTBarTests/DataLocationsTests.swift`:

```swift
import XCTest
@testable import STTBar

final class DataLocationsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DataLocationsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ byteCount: Int, to url: URL) throws {
        try Data(repeating: 0x41, count: byteCount).write(to: url)
    }

    func testSumsFilesRecursively() throws {
        try write(10, to: root.appendingPathComponent("a.txt"))
        let sub = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try write(20, to: sub.appendingPathComponent("b.txt"))
        XCTAssertEqual(DirectorySize.bytes(of: root), 30)
    }

    func testCountsDotFiles() throws {
        // `.env` ist die wichtigste Datei im Konfigurations-Ordner; ein
        // Hidden-File-Skip würde sie stillschweigend aus der Größe werfen.
        try write(5, to: root.appendingPathComponent(".env"))
        XCTAssertEqual(DirectorySize.bytes(of: root), 5)
    }

    func testExcludesNestedDirectory() throws {
        try write(10, to: root.appendingPathComponent("a.txt"))
        let runtime = root.appendingPathComponent("runtime")
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
        try write(20, to: runtime.appendingPathComponent("recording.wav"))
        XCTAssertEqual(DirectorySize.bytes(of: root, excluding: runtime), 10)
    }

    func testExcludingDoesNotMatchSiblingPrefix() throws {
        // "runtime-old" beginnt mit "runtime"; ein blankes hasPrefix würde den
        // Nachbarordner fälschlich mit ausklammern.
        let runtime = root.appendingPathComponent("runtime")
        let sibling = root.appendingPathComponent("runtime-old")
        for dir in [runtime, sibling] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try write(20, to: runtime.appendingPathComponent("recording.wav"))
        try write(7, to: sibling.appendingPathComponent("keep.txt"))
        XCTAssertEqual(DirectorySize.bytes(of: root, excluding: runtime), 7)
    }

    func testMissingDirectoryIsZero() {
        XCTAssertEqual(DirectorySize.bytes(of: root.appendingPathComponent("nope")), 0)
    }

    func testRuntimeLocationIsInsideConfigLocation() throws {
        // Der Größen-Ausschluss lohnt sich nur, solange diese Verschachtelung gilt.
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless((env["STT_INSTALL_DIR"] ?? "").isEmpty && (env["STT_RUNTIME_DIR"] ?? "").isEmpty,
                          "Pfad-Overrides heben die hier geprüfte Verschachtelung auf")
        XCTAssertTrue(DataLocation.runtime.url.path.hasPrefix(DataLocation.config.url.path + "/"))
    }

    func testEveryLocationHasATitle() {
        for location in DataLocation.allCases {
            XCTAssertFalse(location.title.isEmpty, location.rawValue)
            XCTAssertFalse(location.detail.isEmpty, location.rawValue)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path macos-app --filter DataLocationsTests`
Expected: Compile-Fehler, `cannot find 'DirectorySize' in scope` und `cannot find 'DataLocation' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `macos-app/Sources/STTBar/Core/DataLocations.swift`:

```swift
import AppKit
import Foundation

/// The three on-disk areas STTBar owns. Paths come from the existing
/// resolvers; this enum only groups and labels them for the UI.
enum DataLocation: String, CaseIterable, Identifiable {
    case config, runtime, logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .config: return L("Konfiguration", "Configuration")
        case .runtime: return L("Laufzeit (temporär)", "Runtime (temporary)")
        case .logs: return L("Logs", "Logs")
        }
    }

    var detail: String {
        switch self {
        case .config: return L("Einstellungen, Prompts, Wörterbuch, Verlauf",
                               "Settings, prompts, vocabulary, history")
        case .runtime: return L("Aufnahme, Events, Metriken, Status",
                                "Recording, events, metrics, status")
        case .logs: return L("Protokolldatei sttbar.log", "Log file sttbar.log")
        }
    }

    var url: URL {
        switch self {
        case .config: return InstallPaths.resolve()
        case .runtime: return RuntimePaths.directory
        case .logs: return AppLogger.logURL.deletingLastPathComponent()
        }
    }

    /// `runtime` sits inside `config`. Counting it in both would report the
    /// same bytes twice and make the three numbers add up to nonsense.
    var excludedFromSize: URL? { self == .config ? RuntimePaths.directory : nil }

    var byteCount: Int64 { DirectorySize.bytes(of: url, excluding: excludedFromSize) }

    /// Opens the folder itself in Finder. `open` rather than
    /// `activateFileViewerSelecting`: the point is to look *inside* the folder,
    /// not to select it in its parent.
    func reveal() {
        let url = self.url
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}

enum DirectorySize {
    /// Recursive sum of regular-file sizes. A missing directory is 0, not an
    /// error. Hidden files are counted — `.env` is the whole point of the
    /// config folder.
    static func bytes(of directory: URL, excluding excluded: URL? = nil) -> Int64 {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: directory,
                                         includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
        else { return 0 }
        let skip = excluded?.standardizedFileURL.path
        var total: Int64 = 0
        for case let url as URL in walker {
            if let skip {
                let path = url.standardizedFileURL.path
                if path == skip || path.hasPrefix(skip + "/") { continue }
            }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path macos-app --filter DataLocationsTests`
Expected: PASS, 7 Tests (einer davon evtl. übersprungen, falls `STT_INSTALL_DIR`/`STT_RUNTIME_DIR` gesetzt sind).

- [ ] **Step 5: Run the full suite**

Run: `swift test --package-path macos-app`
Expected: PASS, keine Regressionen.

- [ ] **Step 6: Commit**

```bash
git add macos-app/Sources/STTBar/Core/DataLocations.swift macos-app/Tests/STTBarTests/DataLocationsTests.swift
git commit -m "feat(data): add data locations and directory size helper"
```

---

### Task 2: Löschlogik für temporäre Dateien

**Files:**
- Create: `macos-app/Sources/STTBar/Core/TempFileCleanup.swift`
- Test: `macos-app/Tests/STTBarTests/TempFileCleanupTests.swift`

**Interfaces:**
- Consumes: nichts aus Task 1. Ordner-URLs werden hereingereicht, damit die Funktion gegen ein Temp-Verzeichnis testbar ist.
- Produces:
  - `enum TempFileCleanup` mit `static let runtimeFileNames: [String]`, `static let logFileNames: [String]`
  - `struct TempFileCleanup.Result: Equatable { var removedFiles: Int; var freedBytes: Int64 }`
  - `static func removableURLs(runtime: URL, logs: URL) -> [URL]`
  - `@discardableResult static func run(runtime: URL, logs: URL) -> Result`

- [ ] **Step 1: Write the failing test**

Create `macos-app/Tests/STTBarTests/TempFileCleanupTests.swift`:

```swift
import XCTest
@testable import STTBar

final class TempFileCleanupTests: XCTestCase {
    private var root: URL!
    private var config: URL!
    private var runtime: URL!
    private var logs: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TempFileCleanupTests-\(UUID().uuidString)")
        config = root.appendingPathComponent("Application Support/STTBar")
        runtime = config.appendingPathComponent("runtime")
        logs = root.appendingPathComponent("Logs/STTBar")
        for dir in [config!, runtime!, logs!] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ byteCount: Int, to url: URL) throws {
        try Data(repeating: 0x41, count: byteCount).write(to: url)
    }

    func testRemovesOnlyDisposableFiles() throws {
        try write(100, to: runtime.appendingPathComponent("recording.wav"))
        try write(10, to: runtime.appendingPathComponent("events.jsonl"))
        try write(10, to: runtime.appendingPathComponent("metrics.jsonl"))
        try write(10, to: runtime.appendingPathComponent("status.json"))
        try write(5, to: runtime.appendingPathComponent("phase"))
        try write(15, to: runtime.appendingPathComponent("last-transcript.txt"))
        try write(50, to: logs.appendingPathComponent("sttbar.log"))

        let survivors = [
            runtime.appendingPathComponent("recording.pid"),
            runtime.appendingPathComponent("recording.lock"),
            config.appendingPathComponent(".env"),
            config.appendingPathComponent("prompts.json"),
            config.appendingPathComponent("active-prompt.txt"),
            config.appendingPathComponent("stt-replacements.tsv"),
            config.appendingPathComponent("transcript-history.json"),
            config.appendingPathComponent(".env.backup-1782398573"),
        ]
        for url in survivors { try write(8, to: url) }

        let result = TempFileCleanup.run(runtime: runtime, logs: logs)

        XCTAssertEqual(result, TempFileCleanup.Result(removedFiles: 7, freedBytes: 200))
        for name in TempFileCleanup.runtimeFileNames {
            XCTAssertFalse(FileManager.default.fileExists(atPath: runtime.appendingPathComponent(name).path), name)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: logs.appendingPathComponent("sttbar.log").path))
        for url in survivors {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.lastPathComponent)
        }
    }

    func testEmptyDirectoriesAreANoOp() {
        let result = TempFileCleanup.run(runtime: runtime, logs: logs)
        XCTAssertEqual(result, TempFileCleanup.Result(removedFiles: 0, freedBytes: 0))
    }

    func testDoesNotRemoveADirectoryNamedLikeATempFile() throws {
        let trap = runtime.appendingPathComponent("phase")
        try FileManager.default.createDirectory(at: trap, withIntermediateDirectories: true)
        try write(4, to: trap.appendingPathComponent("inside.txt"))

        let result = TempFileCleanup.run(runtime: runtime, logs: logs)

        XCTAssertEqual(result, TempFileCleanup.Result(removedFiles: 0, freedBytes: 0))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trap.path))
    }

    func testNoRemovableURLPointsAtTheConfigDirectory() {
        for url in TempFileCleanup.removableURLs(runtime: runtime, logs: logs) {
            XCTAssertNotEqual(url.deletingLastPathComponent().standardizedFileURL,
                              config.standardizedFileURL,
                              "\(url.lastPathComponent) darf nicht im Konfigurations-Ordner liegen")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path macos-app --filter TempFileCleanupTests`
Expected: Compile-Fehler, `cannot find 'TempFileCleanup' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `macos-app/Sources/STTBar/Core/TempFileCleanup.swift`:

```swift
import Foundation

/// Deletes the app's disposable scratch files.
///
/// Deliberately an explicit allowlist of file names: no directory removal, no
/// glob. Even if a path ever resolves wrong, this cannot take out `.env`, the
/// prompts, or the transcript history — they are simply not on the list.
enum TempFileCleanup {
    static let runtimeFileNames = ["recording.wav", "events.jsonl", "metrics.jsonl",
                                   "status.json", "phase", "last-transcript.txt"]
    static let logFileNames = ["sttbar.log"]

    struct Result: Equatable {
        var removedFiles: Int
        var freedBytes: Int64
    }

    static func removableURLs(runtime: URL, logs: URL) -> [URL] {
        runtimeFileNames.map { runtime.appendingPathComponent($0) }
            + logFileNames.map { logs.appendingPathComponent($0) }
    }

    /// A missing file is not an error and is not counted. Directories are
    /// skipped even when named like a scratch file.
    @discardableResult
    static func run(runtime: URL, logs: URL) -> Result {
        let fm = FileManager.default
        var result = Result(removedFiles: 0, freedBytes: 0)
        for url in removableURLs(runtime: runtime, logs: logs) {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? 0)
            do { try fm.removeItem(at: url) } catch { continue }
            result.removedFiles += 1
            result.freedBytes += size
        }
        return result
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path macos-app --filter TempFileCleanupTests`
Expected: PASS, 4 Tests.

- [ ] **Step 5: Run the full suite**

Run: `swift test --package-path macos-app`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add macos-app/Sources/STTBar/Core/TempFileCleanup.swift macos-app/Tests/STTBarTests/TempFileCleanupTests.swift
git commit -m "feat(data): add temp file cleanup with an explicit allowlist"
```

---

### Task 3: Sektion „Dateien & Speicher" im Allgemein-Tab

**Files:**
- Create: `macos-app/Sources/STTBar/UI/DataFolderSection.swift`
- Modify: `macos-app/Sources/STTBar/UI/SettingsView.swift` (Zeile 5-24 `SettingsView`, Zeile 428-433 `GeneralTab`, Sektion nach Zeile 473)
- Modify: `macos-app/Sources/STTBar/UI/SettingsWindow.swift:10-28`
- Modify: `macos-app/Sources/STTBar/AppDelegate.swift:123-126` (`showSettings`)

**Interfaces:**
- Consumes: `DataLocation` (Task 1), `TempFileCleanup.run(runtime:logs:)` und `TempFileCleanup.Result` (Task 2), `RuntimePaths.directory`, `AppLogger.log(_:)`, `SttRunner.state` (`Core/SttRunner.swift:24`, `enum SttState` in Zeile 4)
- Produces:
  - `final class DataFolderModel: ObservableObject` mit `init(isIdle: @escaping () -> Bool)`, `@Published var sizes: [DataLocation: Int64]`, `@Published var isBusy: Bool`, `@Published var lastCleanupMessage: String?`, `func refresh()`, `func cleanUp()`
  - `struct DataFolderSection: View` mit `init(model: DataFolderModel)`
  - `SettingsView(model:dataFolders:openEditor:)` — der Parameter `dataFolders` kommt neu dazu
  - `SettingsWindow(model:isIdle:)` — der Parameter `isIdle` kommt neu dazu

Diese Aufgabe hat keine automatisierten Tests: sie ist reine SwiftUI/AppKit-Verdrahtung über die bereits in Task 1 und 2 geprüfte Logik. Abnahme ist ein sauberer Build plus ein Blick in das laufende Fenster.

- [ ] **Step 1: Create the section view and its model**

Create `macos-app/Sources/STTBar/UI/DataFolderSection.swift`:

```swift
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
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build --package-path macos-app`
Expected: Build erfolgreich (die Sektion wird noch nirgends angezeigt).

- [ ] **Step 3: Add the section to the General tab**

In `macos-app/Sources/STTBar/UI/SettingsView.swift`, `GeneralTab` um die Property erweitern — aus:

```swift
private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var loc = Localization.shared
    @State private var autostart = LoginItem.isEnabled
```

wird:

```swift
private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var dataFolders: DataFolderModel
    @ObservedObject private var loc = Localization.shared
    @State private var autostart = LoginItem.isEnabled
```

Direkt nach der `Import/Export`-Sektion (endet auf Zeile 473 mit `}`) und vor `Section(L("Version", "Version"))` einfügen:

```swift
            DataFolderSection(model: dataFolders)
```

- [ ] **Step 4: Thread the model through SettingsView**

In derselben Datei, `SettingsView` — aus:

```swift
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var loc = Localization.shared
    var openEditor: (String) -> Void
```

wird:

```swift
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var dataFolders: DataFolderModel
    @ObservedObject private var loc = Localization.shared
    var openEditor: (String) -> Void
```

und die `GeneralTab`-Zeile in der `TabView` — aus:

```swift
            GeneralTab(model: model).tabItem { Label(L("Allgemein", "General"), systemImage: "gearshape") }
```

wird:

```swift
            GeneralTab(model: model, dataFolders: dataFolders).tabItem { Label(L("Allgemein", "General"), systemImage: "gearshape") }
```

- [ ] **Step 5: Own the model in SettingsWindow**

`macos-app/Sources/STTBar/UI/SettingsWindow.swift` ersetzen durch:

```swift
import AppKit
import SwiftUI

/// Hosts `SettingsView` in a native titled window.
final class SettingsWindow {
    private var window: NSWindow?
    private let model: SettingsModel
    private let dataFolders: DataFolderModel
    private var editor: PromptEditorWindow?

    init(model: SettingsModel, isIdle: @escaping () -> Bool) {
        self.model = model
        self.dataFolders = DataFolderModel(isIdle: isIdle)
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model,
                                                                  dataFolders: dataFolders,
                                                                  openEditor: { [weak self] id in
                self?.openEditor(id)
            }))
            let w = NSWindow(contentViewController: host)
            w.title = L("STTBar – Einstellungen", "STTBar – Settings")
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 780, height: 620))
            window = w
        }
        // The window is reused, so re-read sizes and the busy flag on every open.
        dataFolders.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func openEditor(_ id: String) {
        let e = PromptEditorWindow(model: model, promptId: id)
        e.show()
        editor = e
    }
}
```

- [ ] **Step 6: Supply the idle check from AppDelegate**

In `macos-app/Sources/STTBar/AppDelegate.swift`, `showSettings()` — aus:

```swift
    private func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow(model: model) }
        settingsWindow?.show()
    }
```

wird:

```swift
    private func showSettings() {
        if settingsWindow == nil {
            // Cleanup must stay locked during whisper/llm too: the backend is
            // still reading recording.wav in those phases.
            settingsWindow = SettingsWindow(model: model,
                                            isIdle: { [weak self] in self?.runner.state == .idle })
        }
        settingsWindow?.show()
    }
```

- [ ] **Step 7: Verify build and tests**

Run: `swift build --package-path macos-app && swift test --package-path macos-app`
Expected: Build erfolgreich, alle Tests grün.

- [ ] **Step 8: Check it in the running app**

Run: `bash macos-app/build-app.sh /tmp/sttbar-build-check && open /tmp/sttbar-build-check/STTBar.app`

Prüfen: Einstellungen → Allgemein zeigt „Dateien & Speicher" mit drei Zeilen, Größen ungleich „…", Pfaden und je einem Button. „Im Finder öffnen" öffnet den jeweiligen Ordner. „Temporäre Dateien löschen" fragt nach, löscht danach und meldet die freigegebenen Bytes; `.env` und `prompts.json` sind danach noch da. Danach die Test-App wieder beenden.

- [ ] **Step 9: Commit**

```bash
git add macos-app/Sources/STTBar/UI/DataFolderSection.swift macos-app/Sources/STTBar/UI/SettingsView.swift macos-app/Sources/STTBar/UI/SettingsWindow.swift macos-app/Sources/STTBar/AppDelegate.swift
git commit -m "feat(settings): add files & storage section to the general tab"
```

---

### Task 4: Menüleisten-Untermenü „Dateien"

**Files:**
- Modify: `macos-app/Sources/STTBar/UI/MenuBarController.swift:15` (Callback), `:100-101` (Menüeintrag), `:140` (Action)
- Modify: `macos-app/Sources/STTBar/AppDelegate.swift:90` (Verdrahtung), `:162-166` (`openLogs`)

**Interfaces:**
- Consumes: `DataLocation` und `DataLocation.reveal()` (Task 1)
- Produces: `MenuBarController.onOpenDataFolder: ((DataLocation) -> Void)?` ersetzt `onOpenLogs`

- [ ] **Step 1: Replace the callback**

In `macos-app/Sources/STTBar/UI/MenuBarController.swift` — aus:

```swift
    var onOpenLogs: (() -> Void)?
```

wird:

```swift
    var onOpenDataFolder: ((DataLocation) -> Void)?
```

- [ ] **Step 2: Replace the menu item with a submenu**

In `buildMenu()` — aus:

```swift
        let logs = NSMenuItem(title: L("Logs öffnen", "Open logs"), action: #selector(openLogs), keyEquivalent: "")
        logs.target = self; menu.addItem(logs)
```

wird (Aufbau analog zum bestehenden Sprach-Untermenü weiter unten in derselben Methode):

```swift
        // One folder per entry: the old single item revealed files from two
        // different directories, which made Finder open two windows.
        let files = NSMenuItem(title: L("Dateien", "Files"), action: nil, keyEquivalent: "")
        let filesMenu = NSMenu()
        for location in DataLocation.allCases {
            let fi = NSMenuItem(title: location.title, action: #selector(openDataFolder(_:)), keyEquivalent: "")
            fi.target = self
            fi.representedObject = location.rawValue
            filesMenu.addItem(fi)
        }
        files.submenu = filesMenu
        menu.addItem(files)
```

- [ ] **Step 3: Replace the action**

Am Ende derselben Datei — aus:

```swift
    @objc private func openLogs() { onOpenLogs?() }
```

wird:

```swift
    @objc private func openDataFolder(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let location = DataLocation(rawValue: raw) {
            onOpenDataFolder?(location)
        }
    }
```

- [ ] **Step 4: Rewire AppDelegate**

In `macos-app/Sources/STTBar/AppDelegate.swift` — aus:

```swift
        menu.onOpenLogs = { Self.openLogs() }
```

wird:

```swift
        menu.onOpenDataFolder = { $0.reveal() }
```

und die Methode — aus:

```swift
    private static func openLogs() {
        NSWorkspace.shared.activateFileViewerSelecting([AppLogger.logURL, RuntimePaths.eventsFile, RuntimePaths.metricsFile].filter {
            FileManager.default.fileExists(atPath: $0.path)
        })
    }
```

wird: ersatzlos gelöscht. Das Öffnen liegt jetzt in `DataLocation.reveal()`.

- [ ] **Step 5: Verify build and tests**

Run: `swift build --package-path macos-app && swift test --package-path macos-app`
Expected: Build erfolgreich, alle Tests grün. Falls der Compiler `openLogs` noch irgendwo findet, ist ein Aufrufer übersehen worden — `grep -rn "onOpenLogs\|openLogs" macos-app/Sources` muss leer sein.

- [ ] **Step 6: Check it in the running app**

Run: `bash macos-app/build-app.sh /tmp/sttbar-build-check && open /tmp/sttbar-build-check/STTBar.app`

Prüfen: Das Menüleisten-Menü zeigt „Dateien" mit drei Untereinträgen statt „Logs öffnen"; jeder öffnet genau ein Finder-Fenster mit dem passenden Ordner. Danach die Test-App wieder beenden.

- [ ] **Step 7: Run the shell backend tests**

Run: `for t in tests/*.sh; do bash "$t"; done`
Expected: PASS. (Der Shell-Backend ist nicht betroffen, aber der Lauf gehört zur Abnahme aus `CLAUDE.md`.)

- [ ] **Step 8: Commit**

```bash
git add macos-app/Sources/STTBar/UI/MenuBarController.swift macos-app/Sources/STTBar/AppDelegate.swift
git commit -m "feat(menu): replace open logs with a files submenu"
```

---

## Abnahme des Gesamt-Features

- [ ] `swift test --package-path macos-app` — grün
- [ ] `for t in tests/*.sh; do bash "$t"; done` — grün
- [ ] `bash macos-app/build-app.sh /tmp/sttbar-build-check` — Build erfolgreich
- [ ] `grep -rn "onOpenLogs" macos-app/Sources` — keine Treffer
- [ ] In der laufenden App: drei Ordner öffnen sich, Größen stimmen plausibel, Aufräumen fragt nach und lässt Konfiguration und Verlauf unberührt
