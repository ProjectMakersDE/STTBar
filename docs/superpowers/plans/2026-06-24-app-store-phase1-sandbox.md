# App Store Phase 1 — Sandbox Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make STTBar launch and run correctly under the macOS App Sandbox — no shell spawning, no LaunchAgent, no self-updater, runtime files in the sandbox container — so the App Store foundation is proven before the native pipeline is built.

**Architecture:** Turn on `app-sandbox` + `network.client` entitlements. Replace the `LaunchAgent` plist writer with `SMAppService` (login item). Delete `UpdateInstaller` and all update UI/tests. Relocate `RuntimePaths` from `/tmp` to the sandbox container's Application Support. Strip every `Process()`/`/bin/bash` spawn from `SttRunner`, `SettingsModel`, and `HealthCenterModel`, replacing the transcription path with a `TranscriptionBackend` seam whose Phase-1 implementation reports "native pipeline arrives in Phase 2". The app must build, launch sandboxed, show its menu/HUD/settings, and request permissions; transcription is intentionally inert until Phase 2.

**Tech Stack:** Swift 5.9+, SwiftPM (`macos-app/Package.swift`), AppKit + SwiftUI, `ServiceManagement` (SMAppService), XCTest. Built into a `.app` bundle by `macos-app/build-app.sh`.

## Global Constraints

- Bundle identifier: `de.projectmakers.sttbar` (verbatim — SMAppService and the container path depend on it).
- Minimum macOS: `14.0` (already in `Info.plist`; SMAppService.mainApp requires 13+, satisfied).
- Entitlements file: `macos-app/Resources/STTBar.entitlements`. Keep `com.apple.security.automation.apple-events` and `com.apple.security.device.audio-input`.
- Info.plist must keep `LSUIElement=true`, `LSMinimumSystemVersion=14.0`, `NSMicrophoneUsageDescription`, `NSAppleEventsUsageDescription`, and add `ITSAppUsesNonExemptEncryption=false`.
- No process spawning anywhere in `Sources/` after this phase — the sandbox forbids it; a single remaining `Process()` spawn is a phase failure.
- Every commit uses Conventional Commits, scope `app-store` or a relevant sub-scope.
- Verification per task uses `swift build --package-path macos-app` and `swift test --package-path macos-app`; the existing shell backend tests in `tests/*.sh` are NOT in scope and need not pass for App-Store work (they exercise the legacy shell that this migration removes).
- All work happens on branch `feature/app-store-phase1-sandbox` (created in Task 0).

---

### Task 0: Branch + scope confirmation

**Files:**
- None (git only)

- [ ] **Step 1: Create the feature branch off develop**

```bash
cd /Users/simon-danielmarz/Documents/GitHub/STTBar
git checkout -b feature/app-store-phase1-sandbox
```

- [ ] **Step 2: Confirm the package builds before any change (baseline)**

Run: `swift build --package-path macos-app`
Expected: build succeeds (records the pre-change baseline).

---

### Task 1: Enable App Sandbox + network client entitlements

**Files:**
- Modify: `macos-app/Resources/STTBar.entitlements`

**Interfaces:**
- Produces: a sandboxed entitlements set consumed by `build-app.sh` at codesign time.

- [ ] **Step 1: Replace the entitlements file contents**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- App Store requires the App Sandbox. -->
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<!-- Outbound connections to the transcription/LLM endpoints. -->
	<key>com.apple.security.network.client</key>
	<true/>
	<!-- Sends Apple Events (System Events paste fallback). -->
	<key>com.apple.security.automation.apple-events</key>
	<true/>
	<!-- Microphone access for speech-to-text recording. -->
	<key>com.apple.security.device.audio-input</key>
	<true/>
</dict>
</plist>
```

- [ ] **Step 2: Validate the plist parses**

Run: `plutil -lint macos-app/Resources/STTBar.entitlements`
Expected: `macos-app/Resources/STTBar.entitlements: OK`

- [ ] **Step 3: Build a signed app and confirm the sandbox entitlement is present**

```bash
bash macos-app/build-app.sh /tmp/sttbar-phase1
codesign -d --entitlements - /tmp/sttbar-phase1/STTBar.app 2>&1 | grep -A1 app-sandbox
```
Expected: output shows `com.apple.security.app-sandbox` set to `true`.

- [ ] **Step 4: Commit**

```bash
git add macos-app/Resources/STTBar.entitlements
git commit -m "feat(app-store): enable app-sandbox and network.client entitlements"
```

---

### Task 2: Add `ITSAppUsesNonExemptEncryption` to Info.plist

**Files:**
- Modify: `macos-app/Resources/Info.plist`

- [ ] **Step 1: Add the export-compliance key inside the top-level `<dict>`**

Insert after the `CFBundleVersion` entry:

```xml
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
```

- [ ] **Step 2: Validate the plist parses**

Run: `plutil -lint macos-app/Resources/Info.plist`
Expected: `macos-app/Resources/Info.plist: OK`

- [ ] **Step 3: Commit**

```bash
git add macos-app/Resources/Info.plist
git commit -m "feat(app-store): declare ITSAppUsesNonExemptEncryption=false"
```

---

### Task 3: Relocate `RuntimePaths` into the sandbox container

**Files:**
- Modify: `macos-app/Sources/STTBar/Core/RuntimePaths.swift`
- Test: `macos-app/Tests/STTBarTests/RuntimePathsTests.swift` (create)

**Interfaces:**
- Produces: `RuntimePaths.directory: URL` (now under Application Support), unchanged property names `phaseFile`, `statusFile`, `eventsFile`, `metricsFile`, `resultFile`, `pidFile`, `recordingFile`, `lockFile`, `recordingStartedFile`, `ensureDirectory()`. The legacy `/tmp` properties `legacyPidFile` and `legacyRecordingFile` are REMOVED.
- Consumed by: `SttRunner`, `AppDelegate.openLogs`.

- [ ] **Step 1: Write the failing test**

Create `macos-app/Tests/STTBarTests/RuntimePathsTests.swift`:

```swift
import XCTest
@testable import STTBar

final class RuntimePathsTests: XCTestCase {
    func testDirectoryIsUnderApplicationSupportNotTmp() {
        let path = RuntimePaths.directory.path
        XCTAssertTrue(path.contains("Application Support"), "runtime dir must live in the sandbox container's Application Support, got \(path)")
        XCTAssertFalse(path.hasPrefix("/tmp"), "runtime dir must not be under /tmp, got \(path)")
        XCTAssertFalse(path.hasPrefix("/private/tmp"), "runtime dir must not be under /tmp, got \(path)")
    }

    func testDerivedFilesLiveInsideDirectory() {
        let dir = RuntimePaths.directory.path
        XCTAssertTrue(RuntimePaths.resultFile.path.hasPrefix(dir))
        XCTAssertTrue(RuntimePaths.phaseFile.path.hasPrefix(dir))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path macos-app --filter RuntimePathsTests`
Expected: FAIL — current `directory` resolves under `TMPDIR`/`/tmp`.

- [ ] **Step 3: Rewrite `RuntimePaths.swift`**

```swift
import Foundation

enum RuntimePaths {
    /// Runtime scratch lives in the sandbox container's Application Support
    /// (`~/Library/Containers/de.projectmakers.sttbar/Data/Library/Application Support/STTBar/runtime`
    /// when sandboxed). `STT_RUNTIME_DIR` still overrides it for tests/dev.
    static var directory: URL {
        if let custom = ProcessInfo.processInfo.environment["STT_RUNTIME_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("STTBar/runtime", isDirectory: true)
    }

    static var phaseFile: URL { directory.appendingPathComponent("phase") }
    static var statusFile: URL { directory.appendingPathComponent("status.json") }
    static var eventsFile: URL { directory.appendingPathComponent("events.jsonl") }
    static var metricsFile: URL { directory.appendingPathComponent("metrics.jsonl") }
    static var resultFile: URL { directory.appendingPathComponent("last-transcript.txt") }
    static var pidFile: URL { directory.appendingPathComponent("recording.pid") }
    static var recordingFile: URL { directory.appendingPathComponent("recording.wav") }
    static var lockFile: URL { directory.appendingPathComponent("recording.lock") }
    static var recordingStartedFile: URL { directory.appendingPathComponent("recording-started-ms") }

    static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
```

- [ ] **Step 4: Fix the `legacyPidFile`/`legacyRecordingFile` references in `SttRunner`**

In `macos-app/Sources/STTBar/Core/SttRunner.swift`, `isRecording` and `watchdog` reference `RuntimePaths.legacyPidFile`. These are removed in Task 5's full SttRunner rewrite; if Task 5 has not run yet, temporarily drop the `|| pidIsAlive(RuntimePaths.legacyPidFile)` clause and the legacy block in `watchdog` so the build stays green. (Task 5 replaces this method body entirely.)

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --package-path macos-app --filter RuntimePathsTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add macos-app/Sources/STTBar/Core/RuntimePaths.swift macos-app/Tests/STTBarTests/RuntimePathsTests.swift macos-app/Sources/STTBar/Core/SttRunner.swift
git commit -m "feat(app-store): move runtime files into the sandbox container"
```

---

### Task 4: Replace LaunchAgent with SMAppService login item

**Files:**
- Create: `macos-app/Sources/STTBar/Config/LoginItem.swift`
- Delete: `macos-app/Sources/STTBar/Config/LaunchAgent.swift`
- Modify: `macos-app/Sources/STTBar/UI/SettingsView.swift:420,438-444`
- Modify: `macos-app/Sources/STTBar/Core/HealthCenterModel.swift:132-140`
- Test: `macos-app/Tests/STTBarTests/LoginItemTests.swift` (create)

**Interfaces:**
- Produces: `enum LoginItem { static var isEnabled: Bool; static func setEnabled(_ on: Bool) }`.
- Replaces: all `LaunchAgent.isEnabled` / `LaunchAgent.setEnabled(...)` / `LaunchAgent.plistURL` call sites.

- [ ] **Step 1: Write the failing test**

Create `macos-app/Tests/STTBarTests/LoginItemTests.swift`:

```swift
import XCTest
@testable import STTBar

final class LoginItemTests: XCTestCase {
    // SMAppService registration cannot run unsandboxed in CI; we only assert the
    // type surface compiles and `isEnabled` is readable without throwing.
    func testIsEnabledIsReadable() {
        _ = LoginItem.isEnabled
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path macos-app --filter LoginItemTests`
Expected: FAIL — `LoginItem` does not exist yet.

- [ ] **Step 3: Create `LoginItem.swift`**

```swift
import Foundation
import ServiceManagement

/// "Launch at login" via the modern Service Management API. Replaces the old
/// LaunchAgent plist (forbidden under the App Sandbox).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            AppLogger.log("login_item_toggle_failed on=\(on) error=\(error.localizedDescription)")
            return false
        }
    }
}
```

- [ ] **Step 4: Delete `LaunchAgent.swift`**

```bash
git rm macos-app/Sources/STTBar/Config/LaunchAgent.swift
```

- [ ] **Step 5: Update the autostart toggle in `SettingsView.swift`**

Replace line 420:

```swift
    @State private var autostart = LoginItem.isEnabled
```

Replace the `Section("Start")` block (lines 438-444) with:

```swift
            Section(L("Start", "Startup")) {
                Toggle(L("Beim Login automatisch starten", "Launch automatically at login"), isOn: $autostart)
                    .onChange(of: autostart) { _, on in
                        if !LoginItem.setEnabled(on) { autostart = LoginItem.isEnabled }
                    }
            }
```

- [ ] **Step 6: Update the health check in `HealthCenterModel.swift`**

Replace `launchAgentCheck()` (lines 132-140) with:

```swift
    private func launchAgentCheck() -> HealthCheckItem {
        let enabled = LoginItem.isEnabled
        return HealthCheckItem(title: L("Autostart", "Launch at login"),
                               detail: enabled ? L("Aktiv", "Enabled") : L("Aus", "Off"),
                               level: .ok)
    }
```

- [ ] **Step 7: Run test + build**

Run: `swift test --package-path macos-app --filter LoginItemTests && swift build --package-path macos-app`
Expected: test PASS, build succeeds, no remaining `LaunchAgent` references.

- [ ] **Step 8: Verify no LaunchAgent references remain**

Run: `grep -rn "LaunchAgent" macos-app/Sources macos-app/Tests`
Expected: only the `DefaultPrompt.swift:46` glossary word (a prompt example string), nothing functional.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat(app-store): replace LaunchAgent plist with SMAppService login item"
```

---

### Task 5: Strip shell spawning from `SttRunner` behind a `TranscriptionBackend` seam

**Files:**
- Create: `macos-app/Sources/STTBar/Core/TranscriptionBackend.swift`
- Modify: `macos-app/Sources/STTBar/Core/SttRunner.swift`
- Test: `macos-app/Tests/STTBarTests/RecordingToggleTests.swift` (must still pass — do not break the toggle).

**Interfaces:**
- Produces: `protocol TranscriptionBackend` with `start(mode:)`, `stop(mode:completion:)`, `cancel()`, `isRecording`; and `final class PlaceholderBackend: TranscriptionBackend` that reports unavailable. Phase 2 supplies the real `NativeBackend`.
- Consumes: `RecordingToggle`, `SttMode`, `NativePaste`, `StatusStore` (unchanged).
- `SttRunner.init` signature changes from `init(scriptPath:)` to `init(backend: TranscriptionBackend = PlaceholderBackend())`. `AppDelegate` (Task 6) updates the call site.

- [ ] **Step 1: Create `TranscriptionBackend.swift`**

```swift
import Foundation

/// Abstracts the record→transcribe pipeline so `SttRunner` no longer spawns a
/// shell. Phase 1 ships `PlaceholderBackend`; Phase 2 adds the native
/// AVAudioEngine + URLSession implementation behind the same protocol.
protocol TranscriptionBackend: AnyObject {
    var isRecording: Bool { get }
    func start(mode: SttMode) throws
    /// Stops recording and asynchronously delivers the transcript text.
    func stop(mode: SttMode, completion: @escaping (Result<String, Error>) -> Void)
    func cancel()
}

enum TranscriptionBackendError: LocalizedError {
    case notAvailableYet
    var errorDescription: String? {
        L("Die native Aufnahme kommt in Phase 2. In diesem Build ist die Transkription deaktiviert.",
          "Native recording arrives in Phase 2. Transcription is disabled in this build.")
    }
}

/// Phase-1 placeholder: records nothing, always reports the Phase-2 notice.
final class PlaceholderBackend: TranscriptionBackend {
    private(set) var isRecording = false
    func start(mode: SttMode) throws { isRecording = false; throw TranscriptionBackendError.notAvailableYet }
    func stop(mode: SttMode, completion: @escaping (Result<String, Error>) -> Void) {
        isRecording = false
        completion(.failure(TranscriptionBackendError.notAvailableYet))
    }
    func cancel() { isRecording = false }
}
```

- [ ] **Step 2: Rewrite `SttRunner.swift` to use the backend (no `Process`)**

Replace the whole file with:

```swift
import Foundation

/// High-level state reported to the icon + HUD.
enum SttState { case idle, recording, whisper, llm, error }

struct WatchdogReport {
    var isRecording: Bool
    var duration: TimeInterval
    var stalePidRemoved: Bool
    var exceededLimit: Bool
}

/// Drives the STT pipeline via a `TranscriptionBackend`. First trigger starts
/// recording; second stops and transcribes. `onState` reports the high-level
/// state for icon + HUD. No shell process is ever spawned.
final class SttRunner {
    private let backend: TranscriptionBackend
    let phaseFilePath: String
    var onState: ((SttState) -> Void)?
    var onTranscript: ((String, SttMode, NativePasteResult) -> Void)?
    var onProblem: ((SttStatus) -> Void)?
    private var busy = false
    private var recordingStartedAt: Date?
    private(set) var state: SttState = .idle

    private let toggle = RecordingToggle()
    private var lastTriggerAt: Date?
    private var lastRawEventAt: Date?
    private var pendingStart = false
    private var pendingMode: SttMode = .full

    init(backend: TranscriptionBackend = PlaceholderBackend()) {
        self.backend = backend
        RuntimePaths.ensureDirectory()
        self.phaseFilePath = RuntimePaths.phaseFile.path
    }

    var isRecording: Bool { backend.isRecording }

    var recordingDuration: TimeInterval {
        guard let started = recordingStartedAt else { return 0 }
        return max(0, Date().timeIntervalSince(started))
    }

    func trigger(mode: SttMode, eventTime: Date? = nil) {
        let now = Date()
        let eventAt = eventTime ?? now
        let timing = TriggerTiming(previousRawEventAt: lastRawEventAt, eventAt: eventAt, handledAt: now)
        lastRawEventAt = eventAt
        let action = toggle.decide(isLiveRecording: isRecording, isBusy: busy, lastTriggerAt: lastTriggerAt, now: now)
        AppLogger.log("trigger mode=\(mode.rawValue) decided=\(action) isRecording=\(isRecording) busy=\(busy) dtMs=\(timing.intervalToken) latencyMs=\(timing.latencyMs)")
        if action == .ignore { return }
        lastTriggerAt = now
        switch action {
        case .queueStart:
            pendingStart = true
            pendingMode = mode
        case .start:
            startRecording(mode: mode)
        case .stop:
            stopRecording(mode: mode)
        case .ignore:
            break
        }
    }

    private func startRecording(mode: SttMode) {
        busy = true
        do {
            try backend.start(mode: mode)
            recordingStartedAt = Date()
            setState(.recording)
            busy = false
        } catch {
            busy = false
            recordingStartedAt = nil
            setState(.error)
            StatusStore.writeAppStatus(event: "record_start_failed", phase: "error", severity: "error", code: "record_start_failed", message: L("Aufnahme konnte nicht gestartet werden.", "Could not start recording."), detail: error.localizedDescription)
            AppLogger.log("record_start_failed \(error.localizedDescription)")
            if let problem = StatusStore.latestProblem(limit: 50) { onProblem?(problem) }
        }
    }

    private func stopRecording(mode: SttMode) {
        busy = true
        setState(.whisper)
        backend.stop(mode: mode) { [weak self] result in
            DispatchQueue.main.async { self?.handleResult(result, mode: mode) }
        }
    }

    func cancelRecording() {
        backend.cancel()
        recordingStartedAt = nil
        busy = false
        pendingStart = false
        setState(.idle)
        StatusStore.writeAppStatus(event: "recording_cancelled_by_app", phase: "idle", severity: "info", message: L("Aufnahme abgebrochen.", "Recording cancelled."))
        AppLogger.log("recording_cancelled")
    }

    func watchdog(maxDuration: TimeInterval) -> WatchdogReport {
        let duration = recordingDuration
        let exceeded = isRecording && maxDuration > 0 && duration > maxDuration
        return WatchdogReport(isRecording: isRecording, duration: duration, stalePidRemoved: false, exceededLimit: exceeded)
    }

    func currentPhase() -> SttState? {
        switch state {
        case .whisper: return .whisper
        case .llm: return .llm
        case .error: return .error
        case .recording: return .recording
        default: return nil
        }
    }

    private func handleResult(_ result: Result<String, Error>, mode: SttMode) {
        busy = false
        recordingStartedAt = nil
        switch result {
        case .success(let text) where !text.isEmpty:
            let paste = NativePaste.copyAndPaste(text)
            switch paste {
            case .pasted:
                StatusStore.writeAppStatus(event: "native_paste_done", phase: "done", severity: "info", message: L("Transkript nativ eingefügt.", "Transcript pasted natively."), detail: "chars=\(text.count)")
                setState(.idle)
            case .clipboardOnly(let reason):
                StatusStore.writeAppStatus(event: "paste_failed_clipboard_ok", phase: "done", severity: "warning", code: "paste_permission_missing", message: L("Text liegt in der Zwischenablage.", "Text is on the clipboard."), detail: reason)
                setState(.error)
            }
            onTranscript?(text, mode, paste)
        case .success:
            setState(.idle)
        case .failure(let error):
            setState(.error)
            StatusStore.writeAppStatus(event: "transcription_failed", phase: "error", severity: "error", code: "transcription_failed", message: error.localizedDescription)
        }
        if let problem = StatusStore.latestProblem(limit: 50) { onProblem?(problem) }
        AppLogger.log("transcription_finished state=\(state)")

        if pendingStart {
            pendingStart = false
            if !isRecording {
                lastTriggerAt = Date()
                startRecording(mode: pendingMode)
            }
        }
    }

    private func setState(_ newState: SttState) {
        state = newState
        onState?(newState)
    }
}
```

- [ ] **Step 3: Run the toggle tests to confirm the decision logic is intact**

Run: `swift test --package-path macos-app --filter RecordingToggleTests`
Expected: PASS (the `RecordingToggle` and trigger flow are unchanged).

- [ ] **Step 4: Build**

Run: `swift build --package-path macos-app`
Expected: build fails only on `AppDelegate` (old `SttRunner(scriptPath:)` call) — fixed in Task 6.

- [ ] **Step 5: Commit (after Task 6 makes it build)**

Deferred — committed together with Task 6 since the `init` signature change requires the `AppDelegate` update to compile.

---

### Task 6: Update `AppDelegate` wiring and drop the script/install-dir plumbing

**Files:**
- Modify: `macos-app/Sources/STTBar/AppDelegate.swift:19,32,156-164`

**Interfaces:**
- Consumes: `SttRunner(backend:)` from Task 5.
- `installDir` and `InstallPaths` were only used to locate shell scripts and `.env`. With no shell, the runner no longer needs them, but `SettingsModel`/`HealthCenterModel` still reference `model.installDir` for settings/prompt files — keep `InstallPaths.resolve()` for now but it will be retargeted to the container in a later cleanup; it must not point the runner at scripts.

- [ ] **Step 1: Change the runner construction (line 32)**

```swift
        runner = SttRunner()
```

- [ ] **Step 2: Build**

Run: `swift build --package-path macos-app`
Expected: build succeeds.

- [ ] **Step 3: Run full test suite**

Run: `swift test --package-path macos-app`
Expected: all tests pass except `UpdateInstallerTests` (removed in Task 7) — if Task 7 has not run yet, those still pass since `UpdateInstaller` still exists.

- [ ] **Step 4: Commit Tasks 5+6 together**

```bash
git add macos-app/Sources/STTBar/Core/TranscriptionBackend.swift macos-app/Sources/STTBar/Core/SttRunner.swift macos-app/Sources/STTBar/AppDelegate.swift
git commit -m "feat(app-store): drive transcription via a backend seam, drop shell spawning in SttRunner"
```

---

### Task 7: Remove the self-updater and its UI/tests

**Files:**
- Delete: `macos-app/Sources/STTBar/Core/UpdateInstaller.swift`
- Delete: `macos-app/Tests/STTBarTests/UpdateInstallerTests.swift`
- Modify: `macos-app/Sources/STTBar/Config/SettingsModel.swift:378-404` (remove `performUpdate`) and any update-state properties it sets.
- Modify: `macos-app/Sources/STTBar/UI/SettingsView.swift` (remove the update button/section that calls `performUpdate` and shows `updateState`/`updateMessage`).

**Interfaces:**
- Produces: a `SettingsModel` with no update plumbing. The version check that only *reports* "latest release" can stay (read-only, uses `URLSession`) OR be removed; remove the install/relaunch path entirely (it spawns `/bin/bash`).

- [ ] **Step 1: Locate every update-UI reference**

Run: `grep -rn "performUpdate\|updateState\|updateMessage\|UpdateInstaller\|appAssetURL\|scriptsAssetURL\|appSha256URL" macos-app/Sources macos-app/Tests`
Expected: a list spanning `SettingsModel.swift`, `SettingsView.swift`, `UpdateInstaller.swift`, `UpdateInstallerTests.swift`.

- [ ] **Step 2: Delete the updater files**

```bash
git rm macos-app/Sources/STTBar/Core/UpdateInstaller.swift macos-app/Tests/STTBarTests/UpdateInstallerTests.swift
```

- [ ] **Step 3: Remove `performUpdate()` from `SettingsModel.swift`**

Delete the `func performUpdate() { ... }` method (lines ~378-404) and any stored properties used only by it/the update UI (`updateState`, `updateMessage`, and the asset-URL helpers if unused elsewhere). Keep the read-only "is there a newer release" check ONLY if it does not spawn a process; otherwise delete it too. Build after to find unused-symbol errors and remove them.

- [ ] **Step 4: Remove the update section from `SettingsView.swift`**

Delete the SwiftUI block that renders the update button and `updateMessage`/`updateState`. (Search result from Step 1 pinpoints the lines.)

- [ ] **Step 5: Build until clean**

Run: `swift build --package-path macos-app`
Expected: succeeds; iterate removing any dangling references the compiler flags.

- [ ] **Step 6: Confirm no updater symbols remain**

Run: `grep -rn "UpdateInstaller\|performUpdate" macos-app/Sources macos-app/Tests`
Expected: no matches.

- [ ] **Step 7: Run full test suite**

Run: `swift test --package-path macos-app`
Expected: all tests pass (UpdateInstaller tests are gone).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(app-store): remove in-app self-updater (App Store handles updates)"
```

---

### Task 8: Remove the remaining shell spawns in SettingsModel + HealthCenterModel

**Files:**
- Modify: `macos-app/Sources/STTBar/Config/SettingsModel.swift:430-…` (`runPromptEval` spawns `stt-postprocess.sh`)
- Modify: `macos-app/Sources/STTBar/Core/HealthCenterModel.swift:142-190` (`scriptCheck`, `toolCheck`, `testURL`, `run`, `shellQuote` spawn `/bin/bash`/`curl`)

**Interfaces:**
- Produces: a `HealthCenterModel` whose checks use no subprocess. `urlCheck` (pure `URL` parsing) stays. `scriptCheck`/`toolCheck` are removed (they validated the legacy shell backend, which no longer exists). `testURL` becomes a `URLSession` reachability probe (no `curl`).
- `runPromptEval` is removed in Phase 1 (prompt evaluation re-lands natively in Phase 2's LLM-cleanup work); the prompt editor's "test" button is disabled/hidden until then.

- [ ] **Step 1: Find callers of the methods being removed**

Run: `grep -rn "runPromptEval\|scriptCheck\|toolCheck\|HealthCenterModel.run\|\\.run(" macos-app/Sources`
Expected: identifies the prompt-editor caller of `runPromptEval` and the `refresh()` caller of `scriptCheck`/`toolCheck`.

- [ ] **Step 2: Remove `runPromptEval` from `SettingsModel.swift`**

Delete the `func runPromptEval(...)` method (the one spawning `/bin/bash` + `stt-postprocess.sh`) and update its caller in the prompt editor to hide/disable the "evaluate" button with a comment `// Native prompt eval returns in Phase 2 (LLM cleanup).`

- [ ] **Step 3: Rewrite `HealthCenterModel` checks without subprocess**

Replace `scriptCheck()`, `toolCheck(_:)`, `testURL(_:label:)`, `run(_:)`, `shellQuote(_:)` so that:
- the `refresh()` list drops the `scriptCheck`/`toolCheck` rows,
- `testURL` uses `URLSession` with a `HEAD`/short timeout request and reports reachability on the main queue,
- the private `run`/`shellQuote` helpers are deleted.

```swift
    private func testURL(_ url: String, label: String) {
        guard let u = URL(string: url) else {
            self.actionMessage = "\(label): \(L("ungültige URL", "invalid URL"))"
            return
        }
        var req = URLRequest(url: u)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 3
        URLSession.shared.dataTask(with: req) { _, response, error in
            DispatchQueue.main.async {
                let ok = error == nil && (response as? HTTPURLResponse).map { (200..<500).contains($0.statusCode) } ?? false
                self.actionMessage = "\(label): \(ok ? L("erreichbar", "reachable") : L("nicht erreichbar", "unreachable"))"
                self.refresh()
            }
        }.resume()
    }
```

- [ ] **Step 4: Build until clean**

Run: `swift build --package-path macos-app`
Expected: succeeds; remove any references to the deleted rows/methods the compiler flags.

- [ ] **Step 5: Confirm zero process spawns remain in Sources**

Run: `grep -rn "Process()\|/bin/bash\|/bin/sh\|executableURL" macos-app/Sources`
Expected: no matches.

- [ ] **Step 6: Run full test suite + build the app**

```bash
swift test --package-path macos-app
bash macos-app/build-app.sh /tmp/sttbar-phase1
```
Expected: tests pass; app builds and is signed.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(app-store): remove remaining shell spawns from settings + health checks"
```

---

### Task 9: Manual sandbox launch verification

**Files:**
- None (runtime verification)

- [ ] **Step 1: Launch the sandboxed build and confirm it runs**

```bash
open /tmp/sttbar-phase1/STTBar.app
ls -la ~/Library/Containers/de.projectmakers.sttbar/Data/Library/Application\ Support/STTBar/ 2>/dev/null
```
Expected: the menu-bar icon appears; the container directory is created (confirming sandbox + relocated runtime path). Settings window opens; permission rows render; autostart toggle flips without error.

- [ ] **Step 2: Confirm the sandbox is actually active**

Run: `codesign -dv --entitlements - /tmp/sttbar-phase1/STTBar.app 2>&1 | grep -E "app-sandbox|network.client|audio-input|apple-events"`
Expected: all four entitlements present.

- [ ] **Step 3: Update the task board**

```bash
python3 ~/.claude/skills/horizon-kanban/scripts/kanban.py comment TASK-350 --text "Phase 1 (Sandbox-Fundament) umgesetzt auf feature/app-store-phase1-sandbox: app-sandbox+network.client an, LaunchAgent→SMAppService, Updater entfernt, RuntimePaths in Container, alle Shell-Spawns raus. App startet sandboxed; Transkription folgt nativ in Phase 2."
```

---

## Self-Review

**Spec coverage (Phase 1 acceptance criteria):**
- `app-sandbox` + `network.client`, keep mic + apple-events → Task 1. ✅
- No `/bin/bash` spawning in SttRunner; all shell calls removed → Tasks 5, 6, 8 (and Task 7 removes updater spawns). ✅
- RuntimePaths uses container, not `/tmp`/`~/.local/share/stt` → Task 3. ✅
- LaunchAgent → SMAppService; UpdateInstaller removed → Tasks 4, 7. ✅
- Info.plist `LSUIElement`/min-macOS/`ITSAppUsesNonExemptEncryption=false`/usage strings → already present; Task 2 adds the export-compliance key. ✅

**Placeholder scan:** No "TBD"/"handle edge cases"/"similar to Task N" left; each code step shows full code or exact deletions guided by a `grep` that names the lines.

**Type consistency:** `TranscriptionBackend` protocol members (`isRecording`, `start(mode:)`, `stop(mode:completion:)`, `cancel()`) are used identically in `SttRunner`. `LoginItem.isEnabled`/`setEnabled(_:)` match all replaced `LaunchAgent` call sites. `SttRunner()` no-arg init matches the `AppDelegate` call site in Task 6.

**Note on `L(...)`:** the codebase's localization helper `L(_:_:)` is used throughout (e.g. `HealthCenterModel`, `SettingsModel`); the new code reuses it. If `TranscriptionBackend.swift` (a non-UI file) cannot see `L`, fall back to a plain English string — verified at build time in Task 6.
