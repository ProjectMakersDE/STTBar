# App-Language (DE/EN), In-App-Updater & General-Tab Polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a runtime DE/EN app-language switch (UI + Whisper default + active prompt), polish the General settings tab (ProjectMakers footer, GitHub/Releases links), and ship a real in-app updater that downloads the latest release (app + scripts) and self-installs.

**Architecture:** A `Localization` singleton (`ObservableObject`) plus a free `L(de,en)` function drives runtime UI translation; SwiftUI views observe it, the AppKit menu rebuilds on change. `SettingsModel.setAppLanguage` couples language → `STT_LANGUAGE` + active built-in prompt. The updater (`UpdateInstaller`) parses GitHub release assets, downloads app + scripts zips, swaps the running bundle in place (APFS-safe), refreshes scripts (preserving user data), and relaunches via a detached helper. CI (`prepare-release.sh` + `.releaserc.json`) gains a `stt-scripts.zip` asset.

**Tech Stack:** Swift 5.9 / SwiftPM executable (macOS 14+), SwiftUI + AppKit, Combine, Foundation `Process`/`URLSession`; Bash; semantic-release.

## Global Constraints

- macOS deployment target: **14.0** (`.macOS(.v14)`); Swift tools **5.9**.
- Default app language is **`.de`** — existing users stay German until they switch.
- Localization is **runtime-switchable**, not `.lproj`-based: every user-facing Swift string uses `L("<de>", "<en>")`.
- Status-event **codes** (e.g. `whisper_failed`) stay unchanged; only human-readable `message`/`detail` text is translated.
- Shell scripts become **English-only static** (no runtime bilingual logic).
- Update repository default: **`ProjectMakersDE/STTBar`** (env `STTBAR_UPDATE_REPOSITORY`).
- Updater must **never overwrite user data**: `.env`, `prompts.json`, `profiles.json`, `active-prompt.txt`, `stt-replacements.tsv`.
- Conventional Commits required (semantic-release). Features → minor bump.
- Verification per change: `swift test --package-path macos-app`; `for t in tests/*.sh; do bash "$t"; done`; `bash macos-app/build-app.sh /tmp/sttbar-build-check`.

---

## File Structure

**New:**
- `macos-app/Sources/STTBar/Config/Localization.swift` — `AppLanguage`, `Localization` (ObservableObject), `L(_:_:)`.
- `macos-app/Sources/STTBar/Core/UpdateInstaller.swift` — release-asset parsing + download/swap/relaunch.
- `macos-app/Tests/STTBarTests/LocalizationTests.swift`
- `macos-app/Tests/STTBarTests/UpdateInstallerTests.swift`

**Modified:**
- `Config/AppSettings.swift` — `appLanguage`; `SttMode.label`/`.detail` via `L`.
- `Config/SettingsModel.swift` — `setAppLanguage`, updater state + glue, localized messages.
- `UI/MenuBarController.swift` — localized titles, `rebuild()`, `onSetLanguage`, language submenu.
- `UI/SettingsView.swift` — full localization, language picker, footer, GitHub/Releases links, updater UI.
- `UI/PromptEditorView.swift`, `UI/PromptEditorWindow.swift`, `UI/StatusWindow.swift`, `UI/HudOverlay.swift`, `UI/SettingsWindow.swift`, `UI/HotkeyRecorder.swift`, `Core/HealthCenterModel.swift` — localization.
- `AppDelegate.swift` — language subscription → menu rebuild; `onSetLanguage` wiring; single-instance guard.
- `stt-global-mac.sh`, `stt-global.sh`, `stt-record.sh`, `stt-transcribe.sh`, `stt-postprocess.sh` — English strings.
- `scripts/prepare-release.sh`, `.releaserc.json` — `stt-scripts.zip` asset.
- `README.md` — confirm English + mention new features.

---

## Task 1: Localization core (`AppLanguage`, `Localization`, `L`)

**Files:**
- Create: `macos-app/Sources/STTBar/Config/Localization.swift`
- Modify: `macos-app/Sources/STTBar/Config/AppSettings.swift` (add `appLanguage`)
- Test: `macos-app/Tests/STTBarTests/LocalizationTests.swift`

**Interfaces:**
- Produces:
  - `enum AppLanguage: String, CaseIterable { case de, en }`
  - `final class Localization: ObservableObject { static let shared; @Published var language: AppLanguage; func set(_:) }`
  - `func L(_ de: String, _ en: String) -> String`
  - `AppSettings.shared.appLanguage: AppLanguage { get set }`

- [ ] **Step 1: Write the failing test**

```swift
// macos-app/Tests/STTBarTests/LocalizationTests.swift
import XCTest
@testable import STTBar

final class LocalizationTests: XCTestCase {
    func testLReturnsPerLanguageString() {
        Localization.shared.language = .de
        XCTAssertEqual(L("Hallo", "Hello"), "Hallo")
        Localization.shared.language = .en
        XCTAssertEqual(L("Hallo", "Hello"), "Hello")
        Localization.shared.language = .de // restore default for other tests
    }

    func testAppLanguageRoundTrips() {
        AppSettings.shared.appLanguage = .en
        XCTAssertEqual(AppSettings.shared.appLanguage, .en)
        AppSettings.shared.appLanguage = .de
        XCTAssertEqual(AppSettings.shared.appLanguage, .de)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path macos-app --filter LocalizationTests`
Expected: FAIL (compile error: `Localization` / `L` / `appLanguage` not found).

- [ ] **Step 3: Create `Localization.swift`**

```swift
import Foundation
import Combine

/// App UI language. Runtime-switchable (not .lproj based).
enum AppLanguage: String, CaseIterable {
    case de, en
}

/// Observable holder for the active UI language. Views observe `shared`;
/// `L(_:_:)` reads the current value at body-evaluation time.
final class Localization: ObservableObject {
    static let shared = Localization()
    @Published var language: AppLanguage

    private init() {
        self.language = AppSettings.shared.appLanguage
    }

    /// Persist + publish. Triggers SwiftUI re-render of observing views.
    func set(_ language: AppLanguage) {
        AppSettings.shared.appLanguage = language
        self.language = language
    }
}

/// Pick the string for the active UI language.
func L(_ de: String, _ en: String) -> String {
    Localization.shared.language == .de ? de : en
}
```

- [ ] **Step 4: Add `appLanguage` to `AppSettings`**

Add inside `final class AppSettings` (after `hudBackgroundColor`):

```swift
var appLanguage: AppLanguage {
    get { AppLanguage(rawValue: d.string(forKey: "appLanguage") ?? "") ?? .de }
    set { d.set(newValue.rawValue, forKey: "appLanguage") }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --package-path macos-app --filter LocalizationTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add macos-app/Sources/STTBar/Config/Localization.swift \
        macos-app/Sources/STTBar/Config/AppSettings.swift \
        macos-app/Tests/STTBarTests/LocalizationTests.swift
git commit -m "feat(macos): add runtime DE/EN localization core"
```

---

## Task 2: Couple language → Whisper + prompt (`setAppLanguage`)

**Files:**
- Modify: `macos-app/Sources/STTBar/Config/SettingsModel.swift`
- Modify: `macos-app/Sources/STTBar/Config/AppSettings.swift` (SttMode labels — done here for test coverage)
- Test: `macos-app/Tests/STTBarTests/LocalizationTests.swift` (add cases)

**Interfaces:**
- Consumes: `Localization.shared`, `DefaultPrompt.germanTitle`/`.englishTitle`, `PromptStore.setActive`, `env`.
- Produces: `SettingsModel.setAppLanguage(_ lang: AppLanguage)`.

- [ ] **Step 1: Write the failing test**

```swift
func testSetAppLanguageSwitchesWhisperAndPrompt() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("sttbar-lang-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let model = SettingsModel(installDir: dir)
    model.setAppLanguage(.en)
    XCTAssertEqual(Localization.shared.language, .en)
    XCTAssertEqual(model.language, "en")
    XCTAssertEqual(model.prompts.activePrompt?.title, DefaultPrompt.englishTitle)

    model.setAppLanguage(.de)
    XCTAssertEqual(model.language, "de")
    XCTAssertEqual(model.prompts.activePrompt?.title, DefaultPrompt.germanTitle)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path macos-app --filter LocalizationTests`
Expected: FAIL (`setAppLanguage` not found).

- [ ] **Step 3: Implement `setAppLanguage`**

Add to `SettingsModel` (near `applyProfile`):

```swift
/// Single entry point for the DE/EN app-language switch: flips the UI
/// language, the Whisper default (STT_LANGUAGE) and the active built-in
/// prompt, then persists `.env` + active-prompt mirror.
func setAppLanguage(_ lang: AppLanguage) {
    Localization.shared.set(lang)

    language = (lang == .de) ? "de" : "en"
    write("STT_LANGUAGE", language)

    let wantedTitle = (lang == .de) ? DefaultPrompt.germanTitle : DefaultPrompt.englishTitle
    if let prompt = prompts.prompts.first(where: { $0.title == wantedTitle }) {
        try? prompts.setActive(prompt.id)
        write("STT_POSTPROCESS_PROMPT_FILE", prompts.activeFileURL.path)
    }
    try? env.save()
    objectWillChange.send()
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path macos-app --filter LocalizationTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macos-app/Sources/STTBar/Config/SettingsModel.swift \
        macos-app/Tests/STTBarTests/LocalizationTests.swift
git commit -m "feat(macos): couple app language to Whisper language + active prompt"
```

---

## Task 3: Localize `SttMode` labels

**Files:**
- Modify: `macos-app/Sources/STTBar/Config/AppSettings.swift`

**Interfaces:**
- Consumes: `L(_:_:)`.
- Produces: localized `SttMode.label` / `SttMode.detail` (rawValues unchanged).

- [ ] **Step 1: Replace the `label`/`detail` bodies**

```swift
var label: String {
    switch self {
    case .full: return L("Bereinigt (LLM)", "Cleaned (LLM)")
    case .raw: return L("Roh (ohne LLM)", "Raw (no LLM)")
    case .english: return L("Englisch (übersetzt)", "English (translated)")
    }
}
var detail: String {
    switch self {
    case .full: return L("Transkript mit LLM-Bereinigung in der Quellsprache.",
                         "Transcript with LLM cleanup in the source language.")
    case .raw: return L("Reines Transkript ohne LLM (Textersetzungen greifen weiter).",
                        "Raw transcript without LLM (text replacements still apply).")
    case .english: return L("LLM-Bereinigung, Ausgabe ins Englische übersetzt.",
                            "LLM cleanup, output translated to English.")
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build --package-path macos-app`
Expected: builds without error.

- [ ] **Step 3: Commit**

```bash
git add macos-app/Sources/STTBar/Config/AppSettings.swift
git commit -m "feat(macos): localize SttMode labels (DE/EN)"
```

---

## Task 4: Menu bar — localization, language submenu, rebuild hook

**Files:**
- Modify: `macos-app/Sources/STTBar/UI/MenuBarController.swift`

**Interfaces:**
- Consumes: `L(_:_:)`, `AppLanguage`, `Localization.shared`.
- Produces:
  - `var onSetLanguage: ((AppLanguage) -> Void)?`
  - `func rebuild()` (public wrapper over `buildMenu()`)

- [ ] **Step 1: Add the callback + public rebuild**

Add property near the other `on…` closures:

```swift
var onSetLanguage: ((AppLanguage) -> Void)?
```

Add method:

```swift
/// Rebuild the menu + tooltip (e.g. after a language change).
func rebuild() {
    item.button?.toolTip = tooltip
    buildMenu()
}
```

- [ ] **Step 2: Localize all titles + tooltip**

Replace the German literals in `tooltip` and `buildMenu()` with `L(...)`:

```swift
private var tooltip: String {
    let stateText: String
    switch state {
    case .idle: stateText = L("Bereit", "Ready")
    case .recording: stateText = L("Aufnahme", "Recording")
    case .whisper: stateText = L("Whisper", "Whisper")
    case .llm: stateText = L("LLM", "LLM")
    case .error: stateText = L("Fehler", "Error")
    }
    return ["STTBar", stateText, lastRunSummary].filter { !$0.isEmpty }.joined(separator: " - ")
}
```

In `buildMenu()`:

```swift
let title = state == .recording
    ? "\(L("Stoppen", "Stop")): \(mode.label)"
    : "\(L("Aufnahme", "Record")): \(mode.label)"
...
let cancel = NSMenuItem(title: L("Aufnahme abbrechen", "Cancel recording"), action: #selector(cancelRecording), keyEquivalent: "")
...
let reinsert = NSMenuItem(title: L("Letztes Transkript erneut einfügen", "Re-insert last transcript"), ...)
let copy = NSMenuItem(title: L("Letztes Transkript kopieren", "Copy last transcript"), ...)
let error = NSMenuItem(title: L("Letzten Fehler anzeigen", "Show last error"), ...)
let logs = NSMenuItem(title: L("Logs öffnen", "Open logs"), ...)
...
let status = NSMenuItem(title: L("Status & Diagnose…", "Status & diagnostics…"), ...)
let settings = NSMenuItem(title: L("Einstellungen…", "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
let edit = NSMenuItem(title: L("Prompt bearbeiten…", "Edit prompt…"), ...)
...
menu.addItem(NSMenuItem(title: L("STTBar beenden", "Quit STTBar"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
```

- [ ] **Step 3: Add the language submenu**

Before the final separator/quit in `buildMenu()`, add:

```swift
menu.addItem(.separator())
let langItem = NSMenuItem(title: L("Sprache", "Language"), action: nil, keyEquivalent: "")
let langMenu = NSMenu()
for lang in AppLanguage.allCases {
    let name = lang == .de ? "Deutsch" : "English"
    let li = NSMenuItem(title: name, action: #selector(selectLanguage(_:)), keyEquivalent: "")
    li.target = self
    li.representedObject = lang.rawValue
    li.state = (Localization.shared.language == lang) ? .on : .off
    langMenu.addItem(li)
}
langItem.submenu = langMenu
menu.addItem(langItem)
```

Add the action:

```swift
@objc private func selectLanguage(_ sender: NSMenuItem) {
    if let raw = sender.representedObject as? String, let lang = AppLanguage(rawValue: raw) {
        onSetLanguage?(lang)
    }
}
```

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build --package-path macos-app`
Expected: builds without error.

- [ ] **Step 5: Commit**

```bash
git add macos-app/Sources/STTBar/UI/MenuBarController.swift
git commit -m "feat(macos): localize menu bar + add DE/EN language submenu"
```

---

## Task 5: SettingsView — localize, language picker, footer, links

**Files:**
- Modify: `macos-app/Sources/STTBar/UI/SettingsView.swift`

**Interfaces:**
- Consumes: `L(_:_:)`, `Localization.shared`, `AppLanguage`, `model.setAppLanguage`, `model.updateState` (Task 10).
- Produces: localized settings UI; language picker; ProjectMakers footer; GitHub/Releases links. (Updater buttons are wired in Task 12.)

- [ ] **Step 1: Make every view observe the language**

In `SettingsView` and each private sub-view struct (`ServerTab`, `ProfilesTab`, `VocabularyTab`, `PromptsTab`, `ShortcutsTab`, `DisplayTab`, `PrivacyTab`, `GeneralTab`, `PermissionRow` parents), add:

```swift
@ObservedObject private var loc = Localization.shared
```

(`PermissionRow` takes plain strings from its parent, so it needs no observer.)

- [ ] **Step 2: Replace every user-facing German literal with `L(...)`**

Apply mechanically. Reference translations (use these exact pairs):

| German | English |
|---|---|
| Server | Server |
| Profile | Profiles |
| Wörterbuch | Vocabulary |
| Prompts | Prompts |
| Shortcuts | Shortcuts |
| Anzeige | Display |
| Datenschutz | Privacy |
| Allgemein | General |
| Whisper-URL | Whisper URL |
| Whisper-Modell | Whisper model |
| Sprache | Language |
| Whisper-Timeout (s) | Whisper timeout (s) |
| Nachbearbeitung | Post-processing |
| LLM aktiv | LLM enabled |
| Provider | Provider |
| LLM-URL | LLM URL |
| LLM-Modell | LLM model |
| LLM-Timeout (s) | LLM timeout (s) |
| Warnschwelle (s) | Warn threshold (s) |
| Raw-Fallback bei LLM-Fehler | Raw fallback on LLM error |
| Anwenden | Apply |
| Rückgängig | Revert |
| Profilname | Profile name |
| Aktuelles Profil speichern | Save current profile |
| Aktivieren | Activate |
| Profil testen | Test profile |
| Löschen | Delete |
| Eintrag hinzufügen | Add entry |
| Speichern | Save |
| Neu laden | Reload |
| von | from |
| nach | to |
| Kategorie | Category |
| Kommentar | Comment |
| Vorschau-Text | Preview text |
| Aktiv setzen | Set active |
| Bearbeiten… | Edit… |
| Neu | New |
| Duplizieren | Duplicate |
| Mini-Eval | Mini eval |
| Teste… | Testing… |
| Prompt testen | Test prompt |
| Ausgabe | Output |
| Prompt wird getestet… | Testing prompt… |
| Noch nicht getestet. | Not tested yet. |
| Standard | Default |
| Doppelt belegt | Duplicate binding |
| HUD | HUD |
| Timer anzeigen | Show timer |
| Hintergrund | Background |
| Hintergrund anzeigen | Show background |
| Hintergrundfarbe & Transparenz | Background color & opacity |
| Verlauf | History |
| Sensitive Mode | Sensitive mode |
| Transkriptverlauf speichern | Store transcript history |
| Auto-Löschen nach Stunden | Auto-delete after hours |
| Laufzeit | Runtime |
| Maximale Aufnahmedauer (s) | Max recording duration (s) |
| Server warm halten | Keep server warm |
| Warmhalte-Intervall (s) | Keep-warm interval (s) |
| Start | Startup |
| Beim Login automatisch starten | Launch automatically at login |
| Berechtigungen | Permissions |
| Bedienungshilfen | Accessibility |
| Nötig zum Einfügen des Texts ins aktive Feld. | Required to paste text into the active field. |
| Mikrofon | Microphone |
| Nötig für die Audioaufnahme. | Required for audio recording. |
| Automatisierung | Automation |
| Nur für den AppleScript-Fallback relevant. | Only relevant for the AppleScript fallback. |
| Öffnen | Open |
| Erlauben… | Grant… |
| Import/Export | Import/Export |
| Exportieren | Export |
| Importieren | Import |
| Version | Version |
| Nach Updates suchen | Check for updates |
| Release öffnen | Open release |

For interpolated status strings shown in this view that originate in `SettingsModel` (e.g. "Gespeichert"), those are localized in Task 11/their own model methods — leave the bindings as-is here.

- [ ] **Step 3: Add language picker to `GeneralTab`**

Add a new `Section` at the top of `GeneralTab`'s `Form` (before "Start"):

```swift
Section(L("Sprache", "Language")) {
    Picker(L("App-Sprache", "App language"), selection: Binding(
        get: { Localization.shared.language },
        set: { model.setAppLanguage($0) })) {
        Text("Deutsch").tag(AppLanguage.de)
        Text("English").tag(AppLanguage.en)
    }
    .pickerStyle(.segmented)
    Text(L("Schaltet Oberfläche, Whisper-Sprache und den aktiven Prompt um.",
           "Switches the interface, Whisper language and the active prompt."))
        .font(.caption).foregroundStyle(.secondary)
}
```

- [ ] **Step 4: Add GitHub + Releases links to the Version section**

Inside `GeneralTab`'s "Version" section, compute the repo and add links. Replace the version section's trailing `VStack` with:

```swift
let repo = model.updateRepository
HStack {
    Link(L("GitHub-Repository", "GitHub repository"),
         destination: URL(string: "https://github.com/\(repo)")!)
    Link(L("Releases öffnen", "Open releases"),
         destination: URL(string: "https://github.com/\(repo)/releases")!)
}
.font(.caption)
```

(Updater buttons/status are added in Task 12; `model.updateRepository` is added in Task 10.)

- [ ] **Step 5: Add the ProjectMakers footer**

Add as the **last** element inside `GeneralTab`'s `Form` (after all sections):

```swift
Section {
    HStack(spacing: 4) {
        Spacer()
        Text(L("made with", "made with"))
        Image(systemName: "heart.fill").foregroundStyle(.red)
        Text(L("by", "by"))
        Link("ProjectMakers.de", destination: URL(string: "https://projectmakers.de")!)
        Spacer()
    }
    .font(.caption)
    .foregroundStyle(.secondary)
}
```

- [ ] **Step 6: Build to verify it compiles**

Run: `swift build --package-path macos-app`
Expected: builds (will fail only if Task 10's `model.updateRepository` is missing — implement Task 10 first if so; otherwise temporarily inline the default string `ProjectMakersDE/STTBar`).

> **Sequencing note:** Implement **Task 10 before Step 4/6 of this task** so `model.updateRepository` and `model.updateState` exist. If executing strictly in order, replace `model.updateRepository` with `SettingsModel.defaultUpdateRepository` here and revisit in Task 12.

- [ ] **Step 7: Commit**

```bash
git add macos-app/Sources/STTBar/UI/SettingsView.swift
git commit -m "feat(macos): localize settings, add language picker, links and footer"
```

---

## Task 6: Localize remaining UI files

**Files:**
- Modify: `macos-app/Sources/STTBar/UI/PromptEditorView.swift`
- Modify: `macos-app/Sources/STTBar/UI/PromptEditorWindow.swift`
- Modify: `macos-app/Sources/STTBar/UI/StatusWindow.swift`
- Modify: `macos-app/Sources/STTBar/UI/HudOverlay.swift`
- Modify: `macos-app/Sources/STTBar/UI/SettingsWindow.swift`
- Modify: `macos-app/Sources/STTBar/UI/HotkeyRecorder.swift`
- Modify: `macos-app/Sources/STTBar/Core/HealthCenterModel.swift`

**Interfaces:**
- Consumes: `L(_:_:)`, `Localization.shared`.

- [ ] **Step 1: Inspect each file's German strings**

Run: `for f in macos-app/Sources/STTBar/UI/PromptEditorView.swift macos-app/Sources/STTBar/UI/PromptEditorWindow.swift macos-app/Sources/STTBar/UI/StatusWindow.swift macos-app/Sources/STTBar/UI/HudOverlay.swift macos-app/Sources/STTBar/UI/SettingsWindow.swift macos-app/Sources/STTBar/UI/HotkeyRecorder.swift macos-app/Sources/STTBar/Core/HealthCenterModel.swift; do echo "== $f =="; grep -nE '"[A-ZÄÖÜ][^"]*[a-zäöü]' "$f"; done`

- [ ] **Step 2: Replace each user-facing literal with `L("<de>", "<en>")`**

For SwiftUI views, add `@ObservedObject private var loc = Localization.shared` to each `View` struct that renders translated text so it re-renders on switch. Window titles set via AppKit (`NSWindow.title`) should be set from `L(...)` at creation; they will not live-update (acceptable — reopening reflects the new language). Translate window titles such as `"Prompt-Editor"` → `L("Prompt-Editor", "Prompt editor")`, `"Status & Diagnose"` → `L("Status & Diagnose", "Status & diagnostics")`, `"Einstellungen"` → `L("Einstellungen", "Settings")`.

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build --package-path macos-app`
Expected: builds without error.

- [ ] **Step 4: Commit**

```bash
git add macos-app/Sources/STTBar/UI/PromptEditorView.swift \
        macos-app/Sources/STTBar/UI/PromptEditorWindow.swift \
        macos-app/Sources/STTBar/UI/StatusWindow.swift \
        macos-app/Sources/STTBar/UI/HudOverlay.swift \
        macos-app/Sources/STTBar/UI/SettingsWindow.swift \
        macos-app/Sources/STTBar/UI/HotkeyRecorder.swift \
        macos-app/Sources/STTBar/Core/HealthCenterModel.swift
git commit -m "feat(macos): localize prompt editor, status, HUD and remaining UI"
```

---

## Task 7: AppDelegate — language subscription, menu wiring, single-instance guard

**Files:**
- Modify: `macos-app/Sources/STTBar/AppDelegate.swift`

**Interfaces:**
- Consumes: `MenuBarController.onSetLanguage`, `MenuBarController.rebuild()`, `model.setAppLanguage`, `Localization.shared.$language`.

- [ ] **Step 1: Add Combine import + cancellable storage**

At the top: `import Combine`. Add property: `private var cancellables = Set<AnyCancellable>()`.

- [ ] **Step 2: Wire language switching + menu rebuild**

In `applicationDidFinishLaunching`, after `menu.onOpenLogs = …`:

```swift
menu.onSetLanguage = { [weak self] lang in self?.model.setAppLanguage(lang) }
Localization.shared.$language
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in self?.menu.rebuild() }
    .store(in: &cancellables)
```

- [ ] **Step 3: Add single-instance guard**

At the very start of `applicationDidFinishLaunching`:

```swift
let me = NSRunningApplication.current
let dupes = NSRunningApplication.runningApplications(withBundleIdentifier: me.bundleIdentifier ?? "de.projectmakers.sttbar")
    .filter { $0.processIdentifier != me.processIdentifier }
if !dupes.isEmpty {
    // Another STTBar is already running (e.g. relaunch race during update). Yield.
    NSApp.terminate(nil)
    return
}
```

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build --package-path macos-app`
Expected: builds without error.

- [ ] **Step 5: Manual smoke (optional, local)**

Run: `bash macos-app/build-app.sh /tmp/sttbar-build-check` then launch `/tmp/sttbar-build-check/STTBar.app`; switch language in the menu; confirm UI + menu flip.

- [ ] **Step 6: Commit**

```bash
git add macos-app/Sources/STTBar/AppDelegate.swift
git commit -m "feat(macos): live language switching + single-instance guard"
```

---

## Task 8: Shell scripts → English strings

**Files:**
- Modify: `stt-global-mac.sh`, `stt-global.sh`, `stt-record.sh`, `stt-transcribe.sh`, `stt-postprocess.sh`

**Interfaces:** none (string-only changes; status-event codes unchanged).

- [ ] **Step 1: Find all German message/detail strings**

Run: `grep -nE 'stt_status_event|notify' stt-global-mac.sh stt-global.sh stt-record.sh stt-transcribe.sh stt-postprocess.sh | grep -E '[a-zäöü]ß|ä|ö|ü|Aufnahme|fehlgeschlagen|Bereit|gestoppt|erreichbar|empfangen|Nachbearbeitung|langsam'`

- [ ] **Step 2: Translate each human-readable `message`/`detail`**

Edit only the quoted human-readable text (5th+ args of `stt_status_event` and `notify` text), keeping the `event`/`phase`/`severity`/`code` positional args unchanged. Reference pairs:

| German | English |
|---|---|
| Aufnahme wird gestoppt und transkribiert. | Stopping recording and transcribing. |
| Transkription fehlgeschlagen. | Transcription failed. |
| Whisper-Anfrage gestartet. | Whisper request started. |
| Whisper-Server nicht erreichbar. | Whisper server unreachable. |
| Whisper meldet HTTP $http_code. | Whisper returned HTTP $http_code. |
| Whisper lieferte keinen Text. | Whisper returned no text. |
| Whisper-Transkript empfangen. | Whisper transcript received. |
| Nachbearbeitung fehlgeschlagen, Rohtext/Ersatzwoerter verwendet. | Post-processing failed, used raw text/replacements. |
| Nachbearbeitung fehlgeschlagen und Raw-Fallback ist deaktiviert. | Post-processing failed and raw fallback is disabled. |
| LLM langsam, Raw-Modus kann fuer kurze Diktate sinnvoll sein. | LLM slow; raw mode may help for short dictations. |
| Aufnahme beendet. | Recording stopped. |
| Alte /tmp-Aufnahme wird gestoppt. | Stopping stale /tmp recording. |
| Alte /tmp-Aufnahme ohne PID-Datei wird gestoppt. | Stopping stale /tmp recording without PID file. |
| Transkript fuer STTBar bereit. | Transcript ready for STTBar. |
| Aufnahme wegen Maximaldauer abgebrochen. | Recording cancelled due to max duration. |

(Already-English `notify` texts like "Transcription failed. Is the whisper server running?" stay as-is. Apply the same rule to any remaining German strings the grep surfaces.)

- [ ] **Step 3: Syntax-check the scripts**

Run: `bash -n stt-global-mac.sh stt-global.sh stt-record.sh stt-transcribe.sh stt-postprocess.sh`
Expected: no output (no syntax errors).

- [ ] **Step 4: Run the shell test suite**

Run: `for t in tests/*.sh; do echo "== $t =="; bash "$t"; done`
Expected: all pass (tests do not assert on German strings).

- [ ] **Step 5: Commit**

```bash
git add stt-global-mac.sh stt-global.sh stt-record.sh stt-transcribe.sh stt-postprocess.sh
git commit -m "refactor(shell): use English status/notification strings"
```

---

## Task 9: README — confirm English + document new features

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Verify README is English**

Run: `grep -nE 'ä|ö|ü|ß|Einstellungen|Aufnahme' README.md || echo "already English"`
Expected: `already English` (README is already in English).

- [ ] **Step 2: Add the new features to the feature list**

Add bullets under `## Features`:

```markdown
- One-click in-app updater (downloads the latest release and self-installs).
- DE/EN app-language switch (interface, Whisper language, and active prompt).
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document language switch and in-app updater"
```

---

## Task 10: Release-asset parsing + updater state on the model

**Files:**
- Modify: `macos-app/Sources/STTBar/Config/SettingsModel.swift`
- Test: `macos-app/Tests/STTBarTests/UpdateInstallerTests.swift`

**Interfaces:**
- Produces:
  - `enum UpdateState { case idle, checking, upToDate, available, downloading, installing, failed }`
  - `SettingsModel.updateState: UpdateState`
  - `SettingsModel.updateRepository: String`
  - `SettingsModel.latestVersion: String?`, `appAssetURL: URL?`, `scriptsAssetURL: URL?`, `appSha256URL: URL?`
  - `struct GitHubAsset: Decodable { let name: String; let url: URL }` (maps `browser_download_url`)
  - `static func pickAsset(_ assets: [GitHubAsset], name: String) -> URL?`

- [ ] **Step 1: Write the failing test**

```swift
// macos-app/Tests/STTBarTests/UpdateInstallerTests.swift
import XCTest
@testable import STTBar

final class UpdateInstallerTests: XCTestCase {
    func testPickAssetByName() {
        let json = """
        {"tag_name":"v1.1.0","html_url":"https://x/r","assets":[
          {"name":"STTBar.app.zip","browser_download_url":"https://x/app.zip"},
          {"name":"stt-scripts.zip","browser_download_url":"https://x/scripts.zip"},
          {"name":"STTBar.app.zip.sha256","browser_download_url":"https://x/app.sha"}
        ]}
        """.data(using: .utf8)!
        let release = try! JSONDecoder().decode(GitHubRelease.self, from: json)
        XCTAssertEqual(SettingsModel.pickAsset(release.assets, name: "STTBar.app.zip")?.absoluteString, "https://x/app.zip")
        XCTAssertEqual(SettingsModel.pickAsset(release.assets, name: "stt-scripts.zip")?.absoluteString, "https://x/scripts.zip")
        XCTAssertNil(SettingsModel.pickAsset(release.assets, name: "missing.zip"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path macos-app --filter UpdateInstallerTests`
Expected: FAIL (`GitHubRelease.assets` / `pickAsset` not found).

- [ ] **Step 3: Extend the model state + GitHubRelease + asset parsing**

In `SettingsModel`, add published state near `updateMessage`:

```swift
enum UpdateState: Equatable { case idle, checking, upToDate, available, downloading, installing, failed }
@Published var updateState: UpdateState = .idle
@Published var latestVersion: String?
var appAssetURL: URL?
var scriptsAssetURL: URL?
var appSha256URL: URL?

var updateRepository: String { env.value("STTBAR_UPDATE_REPOSITORY") ?? Self.defaultUpdateRepository }
```

Make `GitHubRelease` internal (drop `private`) and add assets:

```swift
struct GitHubAsset: Decodable {
    let name: String
    let url: URL
    enum CodingKeys: String, CodingKey { case name; case url = "browser_download_url" }
}

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let assets: [GitHubAsset]
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

static func pickAsset(_ assets: [GitHubAsset], name: String) -> URL? {
    assets.first { $0.name == name }?.url
}
```

In `checkForUpdates()`, set `updateState = .checking` at start; after decoding, capture assets and state:

```swift
let assetList = release.assets
DispatchQueue.main.async {
    self.appAssetURL = Self.pickAsset(assetList, name: "STTBar.app.zip")
    self.scriptsAssetURL = Self.pickAsset(assetList, name: "stt-scripts.zip")
    self.appSha256URL = Self.pickAsset(assetList, name: "STTBar.app.zip.sha256")
    self.latestVersion = latest
}
```

and set `self.updateState` in the `switch`: `.orderedDescending` → `.available`; `.orderedSame`/`.orderedAscending` → `.upToDate`. On error/404/decode-fail → `.failed`/`.upToDate` as appropriate. Localize the messages with `L(...)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path macos-app --filter UpdateInstallerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macos-app/Sources/STTBar/Config/SettingsModel.swift \
        macos-app/Tests/STTBarTests/UpdateInstallerTests.swift
git commit -m "feat(macos): parse release assets and track update state"
```

---

## Task 11: `UpdateInstaller` — download, swap, scripts, relaunch

**Files:**
- Create: `macos-app/Sources/STTBar/Core/UpdateInstaller.swift`
- Modify: `macos-app/Sources/STTBar/Config/SettingsModel.swift` (add `performUpdate()`)
- Test: `macos-app/Tests/STTBarTests/UpdateInstallerTests.swift` (add helper-script test)

**Interfaces:**
- Consumes: `appAssetURL`, `scriptsAssetURL`, `appSha256URL`, `installDir`, `Bundle.main.bundlePath`.
- Produces:
  - `enum UpdateError: Error { case missingAsset, download, checksum, unpack, swap }`
  - `static func relaunchHelperScript(appPath: String, stagedApp: String, backupApp: String, scriptsZip: String?, installDir: String, pid: Int32, preserve: [String]) -> String`
  - `static func performUpdate(appZip: URL, scriptsZip: URL?, sha256: URL?, appBundlePath: String, installDir: URL, log: @escaping (String)->Void, done: @escaping (Result<Void,Error>)->Void)`

- [ ] **Step 1: Write the failing test for the helper script generator**

```swift
func testRelaunchHelperPreservesUserData() {
    let script = UpdateInstaller.relaunchHelperScript(
        appPath: "/Applications/STTBar.app",
        stagedApp: "/tmp/u/STTBar.app",
        backupApp: "/Applications/STTBar.app.old",
        scriptsZip: "/tmp/u/stt-scripts.zip",
        installDir: "/Users/me/.local/share/stt",
        pid: 4242,
        preserve: [".env", "prompts.json", "profiles.json", "active-prompt.txt", "stt-replacements.tsv"])
    XCTAssertTrue(script.contains("kill -0 4242"))         // waits for app exit
    XCTAssertTrue(script.contains("ditto"))                 // installs new bundle
    XCTAssertTrue(script.contains("com.apple.quarantine"))  // de-quarantine
    XCTAssertTrue(script.contains("-x '.env'"))             // rsync excludes user data
    XCTAssertTrue(script.contains("/Applications/STTBar.app")) // target path quoted in
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path macos-app --filter UpdateInstallerTests`
Expected: FAIL (`UpdateInstaller` not found).

- [ ] **Step 3: Create `UpdateInstaller.swift`**

```swift
import Foundation

enum UpdateError: Error { case missingAsset, download, checksum, unpack, swap }

enum UpdateInstaller {
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Generates a detached relaunch helper. It waits for the running app to
    /// exit, removes the .old backup, refreshes scripts (preserving user data),
    /// and re-opens the app only if the KeepAlive LaunchAgent has not already
    /// brought it back. The bundle swap itself happens in `performUpdate`
    /// (in-place, while running) so launchd relaunches the NEW binary.
    static func relaunchHelperScript(appPath: String, stagedApp: String, backupApp: String,
                                     scriptsZip: String?, installDir: String, pid: Int32,
                                     preserve: [String]) -> String {
        let q = shellQuote
        var script = """
        #!/bin/bash
        set -u
        APP=\(q(appPath))
        BACKUP=\(q(backupApp))
        INSTALL=\(q(installDir))
        # 1) Wait for the old process to exit.
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        # 2) Drop quarantine on the freshly-installed bundle.
        /usr/bin/xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
        # 3) Remove the backup of the previous version.
        rm -rf "$BACKUP" 2>/dev/null || true

        """
        if let zip = scriptsZip {
            // Extract scripts to a temp dir, then rsync into install dir while
            // excluding user-owned files, then chmod the scripts.
            let excludes = preserve.map { "-x \(q($0))" }.joined(separator: " ")
            script += """
            # 4) Refresh backend scripts without touching user data.
            STAGE="$(mktemp -d)"
            /usr/bin/ditto -x -k \(q(zip)) "$STAGE" 2>/dev/null || true
            mkdir -p "$INSTALL"
            if command -v rsync >/dev/null 2>&1; then
              rsync -a \(excludes) "$STAGE"/ "$INSTALL"/ 2>/dev/null || true
            else
              for f in "$STAGE"/*; do
                base="$(basename "$f")"
                case "$base" in
            """
            for p in preserve { script += "      \(p)) continue ;;\n" }
            script += """
                esac
                cp -f "$f" "$INSTALL/$base" 2>/dev/null || true
              done
            fi
            chmod +x "$INSTALL"/*.sh 2>/dev/null || true
            rm -rf "$STAGE" 2>/dev/null || true

            """
        }
        script += """
        # 5) Relaunch only if launchd (KeepAlive) didn't already.
        sleep 1
        if ! /usr/bin/pgrep -f "$APP/Contents/MacOS/STTBar" >/dev/null 2>&1; then
          /usr/bin/open "$APP"
        fi
        """
        return script
    }

    /// Downloads + verifies + swaps the bundle in place, then spawns the helper.
    static func performUpdate(appZip: URL, scriptsZip: URL?, sha256: URL?,
                              appBundlePath: String, installDir: URL,
                              log: @escaping (String) -> Void,
                              done: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fm = FileManager.default
                let work = fm.temporaryDirectory.appendingPathComponent("STTBar-update-\(UUID().uuidString)")
                try fm.createDirectory(at: work, withIntermediateDirectories: true)

                log(L("Lade App…", "Downloading app…"))
                let appZipLocal = work.appendingPathComponent("STTBar.app.zip")
                try Data(contentsOf: appZip).write(to: appZipLocal)

                if let sha256 {
                    let expected = (try? String(contentsOf: sha256, encoding: .utf8))?
                        .trimmingCharacters(in: .whitespacesAndNewlines).prefix(64)
                    if let expected, !expected.isEmpty {
                        let actual = try sha256Hex(of: appZipLocal)
                        if actual.lowercased() != expected.lowercased() { throw UpdateError.checksum }
                    }
                }

                var scriptsZipLocal: URL?
                if let scriptsZip {
                    log(L("Lade Skripte…", "Downloading scripts…"))
                    let local = work.appendingPathComponent("stt-scripts.zip")
                    try Data(contentsOf: scriptsZip).write(to: local)
                    scriptsZipLocal = local
                }

                log(L("Entpacke…", "Unpacking…"))
                let stagedDir = work.appendingPathComponent("staged")
                try fm.createDirectory(at: stagedDir, withIntermediateDirectories: true)
                try run("/usr/bin/ditto", ["-x", "-k", appZipLocal.path, stagedDir.path])
                let stagedApp = stagedDir.appendingPathComponent("STTBar.app")
                guard fm.fileExists(atPath: stagedApp.path) else { throw UpdateError.unpack }
                try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", stagedApp.path])

                log(L("Installiere…", "Installing…"))
                let backup = appBundlePath + ".old"
                try? fm.removeItem(atPath: backup)
                // In-place swap while running (APFS keeps the live process intact).
                try fm.moveItem(atPath: appBundlePath, toPath: backup)
                try run("/usr/bin/ditto", [stagedApp.path, appBundlePath])

                let helper = work.appendingPathComponent("relaunch.sh")
                let helperText = relaunchHelperScript(
                    appPath: appBundlePath, stagedApp: stagedApp.path, backupApp: backup,
                    scriptsZip: scriptsZipLocal?.path, installDir: installDir.path,
                    pid: ProcessInfo.processInfo.processIdentifier,
                    preserve: [".env", "prompts.json", "profiles.json", "active-prompt.txt", "stt-replacements.tsv"])
                try helperText.write(to: helper, atomically: true, encoding: .utf8)

                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/bash")
                task.arguments = [helper.path]
                try task.run()  // detached; survives our termination

                done(.success(()))
            } catch {
                done(.failure(error))
            }
        }
    }

    private static func run(_ path: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw UpdateError.unpack }
    }

    private static func sha256Hex(of url: URL) throws -> String {
        let p = Process()
        let out = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        p.arguments = ["-a", "256", url.path]
        p.standardOutput = out
        try p.run(); p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let line = String(data: data, encoding: .utf8) ?? ""
        return String(line.prefix(64))
    }
}
```

- [ ] **Step 4: Add `performUpdate()` glue on `SettingsModel`**

```swift
func performUpdate() {
    guard let appZip = appAssetURL else {
        updateState = .failed
        updateMessage = L("Kein App-Asset im Release gefunden.", "No app asset found in the release.")
        return
    }
    updateState = .downloading
    UpdateInstaller.performUpdate(
        appZip: appZip, scriptsZip: scriptsAssetURL, sha256: appSha256URL,
        appBundlePath: Bundle.main.bundlePath, installDir: installDir,
        log: { msg in DispatchQueue.main.async { self.updateMessage = msg } },
        done: { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.updateState = .installing
                    self.updateMessage = L("Update installiert. Starte neu…", "Update installed. Relaunching…")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
                case .failure:
                    self.updateState = .failed
                    self.updateMessage = L("Update fehlgeschlagen. Bitte install.sh manuell ausführen.",
                                           "Update failed. Please run install.sh manually.")
                }
            }
        })
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --package-path macos-app --filter UpdateInstallerTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add macos-app/Sources/STTBar/Core/UpdateInstaller.swift \
        macos-app/Sources/STTBar/Config/SettingsModel.swift \
        macos-app/Tests/STTBarTests/UpdateInstallerTests.swift
git commit -m "feat(macos): in-app updater (download, swap, refresh scripts, relaunch)"
```

---

## Task 12: Update UI — Aktualisieren button + states

**Files:**
- Modify: `macos-app/Sources/STTBar/UI/SettingsView.swift` (`GeneralTab` Version section)

**Interfaces:**
- Consumes: `model.updateState`, `model.updateMessage`, `model.updateURL`, `model.checkForUpdates`, `model.performUpdate`.

- [ ] **Step 1: Replace the Version section's action row**

```swift
VStack(alignment: .leading, spacing: 8) {
    HStack {
        Button(L("Nach Updates suchen", "Check for updates")) { model.checkForUpdates() }
        if model.updateState == .available {
            Button(L("Aktualisieren", "Update")) { model.performUpdate() }
                .buttonStyle(.borderedProminent)
        }
        if let url = model.updateURL {
            Button(L("Release öffnen", "Open release")) { NSWorkspace.shared.open(url) }
        }
    }
    if model.updateState == .downloading || model.updateState == .installing {
        ProgressView().controlSize(.small)
    }
    if let message = model.updateMessage {
        Text(message).font(.caption).foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 2: Ensure `GeneralTab` observes the model (it already does via `@ObservedObject var model`)**

No change needed — `model` is `@ObservedObject`, so `updateState` changes re-render.

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build --package-path macos-app`
Expected: builds without error.

- [ ] **Step 4: Commit**

```bash
git add macos-app/Sources/STTBar/UI/SettingsView.swift
git commit -m "feat(macos): update button + progress states in General tab"
```

---

## Task 13: CI — ship `stt-scripts.zip` release asset

**Files:**
- Modify: `scripts/prepare-release.sh`
- Modify: `.releaserc.json`

**Interfaces:** produces release assets `dist/stt-scripts.zip` + `.sha256` in install-ready layout (`stt-global.sh` = the macOS script).

- [ ] **Step 1: Extend `prepare-release.sh`**

After the existing app-zip + sha256 lines, append:

```bash
# Stage the backend scripts in install-ready layout (stt-global.sh = macOS variant)
SCRIPTS_STAGE="$DIST/scripts-stage"
rm -rf "$SCRIPTS_STAGE"
mkdir -p "$SCRIPTS_STAGE"
cp "$ROOT/stt.zsh" "$ROOT/stt-runtime.sh" "$ROOT/stt-record.sh" \
   "$ROOT/stt-transcribe.sh" "$ROOT/stt-postprocess.sh" \
   "$ROOT/stt-replacements.tsv" "$ROOT/docker-compose.yml" \
   "$ROOT/.env.example" "$SCRIPTS_STAGE/"
cp "$ROOT/stt-global-mac.sh" "$SCRIPTS_STAGE/stt-global.sh"
chmod +x "$SCRIPTS_STAGE"/*.sh
( cd "$SCRIPTS_STAGE" && ditto -c -k --sequesterRsrc . "$DIST/stt-scripts.zip" )
shasum -a 256 "$DIST/stt-scripts.zip" | awk '{print $1}' > "$DIST/stt-scripts.zip.sha256"
rm -rf "$SCRIPTS_STAGE"
```

- [ ] **Step 2: Add assets to `.releaserc.json`**

In the `@semantic-release/github` `assets` array, after the existing two entries:

```json
,
{
  "path": "dist/stt-scripts.zip",
  "label": "STTBar backend scripts"
},
{
  "path": "dist/stt-scripts.zip.sha256",
  "label": "STTBar scripts SHA256"
}
```

- [ ] **Step 3: Syntax-check + dry validate**

Run: `bash -n scripts/prepare-release.sh && python3 -c "import json;json.load(open('.releaserc.json'))" && echo OK`
Expected: `OK`.

- [ ] **Step 4: Local end-to-end build of the asset**

Run: `bash scripts/prepare-release.sh 0.0.0-test && ls -la dist/stt-scripts.zip dist/stt-scripts.zip.sha256 && unzip -l dist/stt-scripts.zip`
Expected: zip exists and lists `stt-global.sh`, `stt-postprocess.sh`, etc. Then restore the Info.plist version: `git checkout -- macos-app/Resources/Info.plist`.

- [ ] **Step 5: Commit**

```bash
git add scripts/prepare-release.sh .releaserc.json
git commit -m "ci(release): publish stt-scripts.zip asset for in-app updater"
```

---

## Task 14: Final verification, push, local install

**Files:** none (process task).

- [ ] **Step 1: Full test + build gate**

Run:
```bash
swift test --package-path macos-app
for t in tests/*.sh; do echo "== $t =="; bash "$t"; done
bash -n stt-global-mac.sh stt-global.sh stt-record.sh stt-transcribe.sh stt-postprocess.sh
bash macos-app/build-app.sh /tmp/sttbar-build-check
```
Expected: all green; app bundle built.

- [ ] **Step 2: Push to master (triggers release)**

```bash
git push origin master
```
Then watch the release workflow: `gh run watch` (or `gh run list --workflow=release.yml`). Confirm the new release has assets `STTBar.app.zip`, `stt-scripts.zip` (+ sha256).

- [ ] **Step 3: Stop the running local instance cleanly**

```bash
launchctl unload "$HOME/Library/LaunchAgents/de.projectmakers.sttbar.plist" 2>/dev/null || true
osascript -e 'tell application "STTBar" to quit' 2>/dev/null || true
pkill -x STTBar 2>/dev/null || true
sleep 1
```

- [ ] **Step 4: Install the freshly built version**

```bash
bash install.sh
```
Expected: builds + installs `STTBar.app`, copies scripts, (re)loads the LaunchAgent.

- [ ] **Step 5: Confirm it is running**

```bash
launchctl list | grep de.projectmakers.sttbar || open -a STTBar
pgrep -x STTBar && echo "running"
```
Expected: STTBar process running; menu-bar icon visible.

- [ ] **Step 6: Report to the user**

Summarize: released version number, that the language switch + footer/links are live, and how to test the updater (needs a newer release than installed — offer to make a follow-up patch commit so "Aktualisieren" has a target).

---

## Self-Review Notes

- **Spec coverage:** Part 1 → Tasks 1–7; shell/README → Tasks 8–9; Part 2 → Task 5 (footer/links) + Task 12 (update UI); Part 3 → Tasks 10–11 (+ CI Task 13); deploy/install → Task 14. All spec sections mapped.
- **Sequencing caveat:** Task 5 references `model.updateRepository`/`model.updateState` from Task 10. Resolution noted inline in Task 5 (implement Task 10 first, or temporarily inline `SettingsModel.defaultUpdateRepository`). Recommended execution order: 1, 2, 3, 4, 10, 5, 6, 7, 11, 12, 8, 9, 13, 14.
- **Type consistency:** `UpdateState`, `GitHubRelease.assets`, `GitHubAsset(name,url)`, `pickAsset`, `performUpdate`, `relaunchHelperScript`, `setAppLanguage`, `updateRepository` are used with identical signatures across Tasks 5, 10, 11, 12.
- **Risk (documented in spec 3.4):** KeepAlive relaunch vs. helper `open` race — mitigated by in-place swap before terminate, `pgrep` guard in the helper, and the single-instance guard (Task 7).
