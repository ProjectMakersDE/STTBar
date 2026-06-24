# App Store Phase 3 — Local Whisper (WhisperKit) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fully offline transcription source — WhisperKit/CoreML running in-process — selectable alongside the existing server / self-host modes, with on-demand model download into the sandbox container, a size picker with a RAM recommendation, and an Acknowledgements (license) view.

**Architecture:** Introduce a `Transcriber` protocol with two implementations — `RemoteTranscriber` (wraps the Phase-2 `WhisperClient`) and `LocalTranscriber` (wraps WhisperKit). The Phase-2 `NativeBackend` keeps owning recording + LLM cleanup + replacements, but delegates the transcribe step to whichever `Transcriber` the selected `TranscriptionSource` maps to. A `WhisperModelManager` wraps WhisperKit's model download/list into the container with progress/cancel. WhisperKit (MIT, v1.0.0) is a SwiftPM dependency.

**Tech Stack:** Swift 5.9+, SwiftPM, WhisperKit (`/argmaxinc/argmax-oss-swift`, tag `v1.0.0`), CoreML, `ProcessInfo.physicalMemory`, XCTest. Apple Silicon recommended; Intel works but slow on large models.

## Global Constraints

- WhisperKit dependency pinned: `https://github.com/argmaxinc/WhisperKit.git`, `.upToNextMajor(from: "1.0.0")` (MIT — confirmed reachable; tag `v1.0.0` exists).
- WhisperKit core API (verified via SDK docs): `let pipe = try await WhisperKit(WhisperKitConfig(model: <name>))`; `let text = try await pipe.transcribe(audioPath: <path>)?.text`. Models auto-download from Hugging Face and cache; an unspecified model auto-selects a device-recommended one.
- Models download INTO the sandbox container (reuse `RuntimePaths.directory`'s parent Application Support, e.g. `Application Support/STTBar/models`). Verify the exact `WhisperKitConfig` field for the download location (`downloadBase` / `modelFolder`) against the installed SDK version; do NOT guess — read the SDK's `WhisperKitConfig` declaration.
- Local mode runs offline: no `network.client` use during transcription (only during the one-time model download).
- Acknowledgements must include the MIT license texts for WhisperKit and the Whisper models (license obligation from the design spec).
- `TranscriptionSource`: `.server` (remote URL), `.selfHost` (localhost URL — same code path as server, different default URL + setup guide), `.local` (WhisperKit). Persisted in settings.
- Reuse the Phase-2 `TranscriptionBackend` seam — do NOT reintroduce any shell or process spawning.
- Branch `feature/app-store-phase3-local-whisper`, off `feature/app-store-phase2-native-pipeline`.

---

### Task 1: Add the WhisperKit dependency

**Files:**
- Modify: `macos-app/Package.swift`

- [ ] **Step 1: Add the package + product dependency**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "STTBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", .upToNextMajor(from: "1.0.0")),
    ],
    targets: [
        .executableTarget(name: "STTBar",
                          dependencies: [.product(name: "WhisperKit", package: "WhisperKit")],
                          path: "Sources/STTBar"),
        .testTarget(name: "STTBarTests", dependencies: ["STTBar"], path: "Tests/STTBarTests"),
    ]
)
```

- [ ] **Step 2: Resolve + build**

Run: `swift build --package-path macos-app`
Expected: WhisperKit resolves and the package builds (first resolve fetches the dependency; allow time).

- [ ] **Step 3: Commit**

```bash
git add macos-app/Package.swift macos-app/Package.resolved
git commit -m "feat(app-store): add WhisperKit (MIT) dependency for local transcription"
```

---

### Task 2: `TranscriptionSource` setting + config field

**Files:**
- Modify: `macos-app/Sources/STTBar/Config/SettingsModel.swift` (add `@Published var transcriptionSource: String` persisted to `.env` key `STT_SOURCE`)
- Modify: `macos-app/Sources/STTBar/Core/Transcription/TranscriptionConfig.swift` (add `source: String`, `localModel: String`)
- Test: extend `TranscriptionPipelineTests.swift`

**Interfaces:**
- Produces: `enum TranscriptionSource: String { case server, selfHost = "selfhost", local }`; `TranscriptionConfig.source: String`, `.localModel: String`.
- Consumed by: the `Transcriber` selection in Task 4.

- [ ] **Step 1: Write the failing test**

```swift
func testSourceMapping() {
    XCTAssertEqual(TranscriptionSource(rawValue: "local"), .local)
    XCTAssertEqual(TranscriptionSource.selfHost.rawValue, "selfhost")
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path macos-app --filter testSourceMapping`
Expected: FAIL — type does not exist.

- [ ] **Step 3: Add the enum + settings field + config field**

Create `macos-app/Sources/STTBar/Config/TranscriptionSource.swift`:

```swift
import Foundation

enum TranscriptionSource: String, CaseIterable {
    case server, selfHost = "selfhost", local
}
```

Add to `SettingsModel`: `@Published var transcriptionSource: String = "server"` plus its `.env` read/write (`STT_SOURCE`) and `@Published var localModel: String = ""` (`STT_LOCAL_MODEL`), mirroring the existing `whisperURL`/`whisperModel` persistence pattern. Add `source` + `localModel` to `TranscriptionConfig` and `TranscriptionConfig.from(_:)`.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path macos-app --filter testSourceMapping`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(app-store): add transcription-source setting (server/self-host/local)"
```

---

### Task 3: `WhisperModelManager` — list, download (progress/cancel), locate

**Files:**
- Create: `macos-app/Sources/STTBar/Core/Transcription/WhisperModelManager.swift`
- Test: `macos-app/Tests/STTBarTests/WhisperModelManagerTests.swift`

**Interfaces:**
- Produces: `final class WhisperModelManager: ObservableObject { @Published var available: [String]; @Published var downloaded: [String]; @Published var progress: Double?; func modelsDirectory() -> URL; func recommendedModel(physicalMemoryBytes: UInt64) -> String; func isDownloaded(_ model: String) -> Bool; func download(_ model: String) async throws; func cancel() }`.
- The RAM recommendation is pure and unit-testable; WhisperKit network calls are not unit-tested.

- [ ] **Step 1: Write the failing test (pure RAM recommendation)**

```swift
import XCTest
@testable import STTBar

final class WhisperModelManagerTests: XCTestCase {
    func testRecommendationScalesWithRAM() {
        let m = WhisperModelManager()
        XCTAssertEqual(m.recommendedModel(physicalMemoryBytes: 8 * 1_073_741_824), "base")
        XCTAssertEqual(m.recommendedModel(physicalMemoryBytes: 16 * 1_073_741_824), "small")
        XCTAssertEqual(m.recommendedModel(physicalMemoryBytes: 32 * 1_073_741_824), "large-v3-v20240930_626MB")
    }

    func testModelsDirectoryIsInContainer() {
        XCTAssertTrue(WhisperModelManager().modelsDirectory().path.contains("Application Support"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path macos-app --filter WhisperModelManagerTests`
Expected: FAIL.

- [ ] **Step 3: Implement `WhisperModelManager`**

Implement `recommendedModel` thresholds (≤8 GB → `tiny`/`base`; ≤16 GB → `small`/`medium`; >16 GB → `large-v3-v20240930_626MB`), `modelsDirectory()` = Application Support `STTBar/models`, `isDownloaded` = directory exists + non-empty, and `download(_:)` that calls WhisperKit's model download API with a progress callback writing `progress` on the main actor, into `modelsDirectory()`. **Verify the exact WhisperKit download API + `WhisperKitConfig` download-folder field against the installed SDK** — read `WhisperKitConfig` and the model-management symbols rather than guessing. `available` seeds from a static preset list (`tiny`, `base`, `small`, `medium`, `large-v3-v20240930_626MB`) plus anything already downloaded.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path macos-app --filter WhisperModelManagerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(app-store): WhisperKit model manager (container download + RAM recommendation)"
```

---

### Task 4: `Transcriber` abstraction + `LocalTranscriber`; route from source

**Files:**
- Create: `macos-app/Sources/STTBar/Core/Transcription/Transcriber.swift`
- Modify: `macos-app/Sources/STTBar/Core/Transcription/NativeBackend.swift`
- Test: extend `TranscriptionPipelineTests.swift`

**Interfaces:**
- Produces: `protocol Transcriber { func transcribe(audioURL: URL, config: TranscriptionConfig) async throws -> String }`; `struct RemoteTranscriber: Transcriber` (delegates to `WhisperClient`); `final class LocalTranscriber: Transcriber` (lazily builds a cached `WhisperKit` for the configured model and calls `transcribe(audioPath:)?.text`). `static func makeTranscriber(for source: TranscriptionSource) -> Transcriber` (pure mapping; `.server`/`.selfHost` → remote, `.local` → local).
- `NativeBackend.stop` calls `transcriber.transcribe(...)` instead of `whisper.transcribe(...)` directly, selecting the transcriber from `config.source`.

- [ ] **Step 1: Write the failing test (pure source→transcriber mapping)**

```swift
func testSourceSelectsTranscriberKind() {
    XCTAssertTrue(Transcribers.isLocal(.local))
    XCTAssertFalse(Transcribers.isLocal(.server))
    XCTAssertFalse(Transcribers.isLocal(.selfHost))
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path macos-app --filter testSourceSelectsTranscriberKind`
Expected: FAIL.

- [ ] **Step 3: Implement `Transcriber.swift`**

```swift
import Foundation
import WhisperKit

protocol Transcriber {
    func transcribe(audioURL: URL, config: TranscriptionConfig) async throws -> String
}

struct RemoteTranscriber: Transcriber {
    var client = WhisperClient()
    func transcribe(audioURL: URL, config: TranscriptionConfig) async throws -> String {
        try await client.transcribe(audioURL: audioURL, config: config)
    }
}

final class LocalTranscriber: Transcriber {
    private var pipe: WhisperKit?
    private var loadedModel: String?

    func transcribe(audioURL: URL, config: TranscriptionConfig) async throws -> String {
        if pipe == nil || loadedModel != config.localModel {
            let cfg = config.localModel.isEmpty ? WhisperKitConfig() : WhisperKitConfig(model: config.localModel)
            pipe = try await WhisperKit(cfg)
            loadedModel = config.localModel
        }
        let text = try await pipe?.transcribe(audioPath: audioURL.path)?.text
        return (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum Transcribers {
    static func isLocal(_ source: TranscriptionSource) -> Bool { source == .local }
    static func make(for source: TranscriptionSource) -> Transcriber {
        isLocal(source) ? LocalTranscriber() : RemoteTranscriber()
    }
}
```

(Verify `transcribe(audioPath:)` return type's `.text` against the installed SDK; adjust if the SDK returns `[TranscriptionResult]`.)

- [ ] **Step 4: Route in `NativeBackend`**

Hold a `RemoteTranscriber` and a `LocalTranscriber`; in `stop`, after recording, pick `Transcribers.isLocal(source) ? local : remote` based on `TranscriptionSource(rawValue: config.source)` and call its `transcribe`. Keep the rest (LLM cleanup, replacements, fallback) unchanged.

- [ ] **Step 5: Run + build**

Run: `swift test --package-path macos-app --filter testSourceSelectsTranscriberKind && swift build --package-path macos-app`
Expected: PASS + build.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(app-store): route transcription to remote or local WhisperKit by source"
```

---

### Task 5: Settings UI — source picker, model dropdown + download, self-host guide

**Files:**
- Modify: `macos-app/Sources/STTBar/UI/SettingsView.swift`

**Interfaces:**
- Consumes: `TranscriptionSource`, `WhisperModelManager`, `SettingsModel.transcriptionSource`/`localModel`.

- [ ] **Step 1: Add a 3-mode source picker**

Segmented `Picker` bound to `model.transcriptionSource` (Server-URL · Selbst hosten · Eingebaut/lokal). Show the Whisper URL/model fields only for `.server`/`.selfHost`.

- [ ] **Step 2: Local-mode model controls**

When `.local`: a model-size dropdown (manager `available`), a RAM-recommendation caption (`ProcessInfo.processInfo.physicalMemory`), a Download button with a `ProgressView` bound to the manager's `progress`, and a Cancel button.

- [ ] **Step 3: Self-host guide**

When `.selfHost`: a button opening step-by-step instructions (whisper.cpp-server / faster-whisper / MLX-server) and pre-filling the URL field with `http://localhost:8000/v1/audio/transcriptions`.

- [ ] **Step 4: Build**

Run: `swift build --package-path macos-app`
Expected: Build complete.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(app-store): settings UI for transcription source + local model management"
```

---

### Task 6: Acknowledgements (license) view

**Files:**
- Create: `macos-app/Sources/STTBar/UI/AcknowledgementsView.swift`
- Modify: `macos-app/Sources/STTBar/UI/MenuBarController.swift` (menu entry) or Settings (a section)

- [ ] **Step 1: Bundle the MIT texts**

Add a scrollable view listing the MIT license texts for WhisperKit and the Whisper models (and whisper.cpp if referenced). Reachable from the menu or a Settings "About/Acknowledgements" section.

- [ ] **Step 2: Build + commit**

```bash
swift build --package-path macos-app
git add -A
git commit -m "feat(app-store): add Acknowledgements view with WhisperKit + Whisper MIT licenses"
```

---

### Task 7: End-to-end manual verification (local mode)

**Files:** none (runtime)

- [ ] **Step 1: Build, quit production, launch, pick local + download a small model**

```bash
bash macos-app/build-app.sh /tmp/sttbar-phase3
open /tmp/sttbar-phase3/STTBar.app
```
In Settings choose "Eingebaut/lokal", pick `base`, download (watch progress), then dictate with no server configured. Expected: offline transcription pastes text. Confirm the model lives under `~/Library/Containers/de.projectmakers.sttbar/Data/Library/Application Support/STTBar/models`.

- [ ] **Step 2: Update the board**

```bash
python3 ~/.claude/skills/horizon-kanban/scripts/kanban.py comment TASK-350 --text "Phase 3 (lokales WhisperKit) fertig: WhisperKit-Dependency, lokale In-Process-Transkription, Modell-Download-Manager (Container, Fortschritt/Abbruch), Größen-Dropdown + RAM-Empfehlung, Acknowledgements (MIT). Offline-Modus läuft Ende-zu-Ende."
```

---

## Self-Review

**Spec coverage (Phase 3 acceptance criteria):**
- WhisperKit in-process offline transcription → Tasks 1, 4. ✅
- Model download manager (HF → container, progress/cancel) → Task 3. ✅
- Model-size dropdown + RAM recommendation → Tasks 3, 5. ✅
- Acknowledgements with MIT texts → Task 6. ✅

**Placeholder scan:** WhisperKit's exact download-folder config field and the `transcribe` return shape are explicitly flagged as "verify against the installed SDK" rather than fabricated — the implementer must read `WhisperKitConfig`/the model-management API once the dependency resolves (Task 1). All pure logic (RAM recommendation, source mapping) has complete code.

**Type consistency:** `TranscriptionSource` raw values (`server`/`selfhost`/`local`) are used identically in settings, config, and `Transcribers`. `Transcriber.transcribe(audioURL:config:)` matches the call site in `NativeBackend`. `WhisperModelManager` published properties match the Settings UI bindings.

**Risks:** WhisperKit pulls a large dependency + CoreML; first model download is ~MBs–GB (e.g. large-v3-turbo ~626 MB–1.5 GB). Intel CoreML is slow on large models — manage expectations in store copy. The exact WhisperKit 1.0.0 API for download progress must be confirmed in Task 1/3.
