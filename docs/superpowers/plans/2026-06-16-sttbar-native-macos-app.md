# STTBar Native macOS App Implementation Plan

> Historical implementation snapshot: the native app has since been extended by
> the 2026-06-18 comfort/performance rollout. Current code uses
> `${TMPDIR:-/tmp}/de.projectmakers.stt` runtime files, structured
> status/events/metrics, Health Center, native paste, profiles, vocabulary
> editing, and apply/undo settings. Treat code and `CLAUDE.md` as authoritative.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native Swift menu-bar app (`STTBar.app`) that replaces the Hammerspoon front-end — menu icon, rebindable global hotkeys, ported HUD overlay, and a native SwiftUI settings window — while reusing the existing shell backend and keeping `.env` as the source of truth.

**Architecture:** Historical baseline: a SwiftPM executable (`macos-app/`, LSUIElement) spawned the same `stt-global.sh` pipeline Hammerspoon spawned and watched global `/tmp/stt-*` files. Current behavior is superseded as noted above.

**Tech Stack:** Swift 6 / SwiftPM, AppKit (NSStatusItem, NSPanel, CALayer), SwiftUI (settings), Carbon (RegisterEventHotKey), bash (backend + installer).

---

## File Structure

```
macos-app/
  Package.swift                      SwiftPM manifest (executable STTBar + test target)
  Sources/STTBar/
    main.swift                       @main entry, NSApplication bootstrap
    AppDelegate.swift                wiring, install-dir discovery
    Config/
      EnvStore.swift                 parse/update .env preserving comments
      PromptStore.swift              prompts.json + active-prompt.txt
      AppSettings.swift              UserDefaults: hud anchor/bg, hotkeys
      HudAnchor.swift                8-anchor enum + frame math
      Hotkey.swift                   keyCode+modifiers value type + display
    Core/
      SttRunner.swift                Process lifecycle, recording state, watchdog
      AudioLevelReader.swift         wav-tail RMS/peak buckets
      HotkeyManager.swift            Carbon global hotkey registration
    UI/
      MenuBarController.swift        NSStatusItem + menu, state icon
      HudOverlay.swift               NSPanel + CALayer animation (Lua port)
      SettingsWindow.swift           NSWindow host for SettingsView
      SettingsView.swift             SwiftUI TabView (Server/Prompts/Shortcuts/Anzeige/Allgemein)
      PromptEditorWindow.swift       separate titled NSWindow + editor
      HotkeyRecorder.swift           NSView-backed key recorder for SwiftUI
  Tests/STTBarTests/
    EnvStoreTests.swift
    PromptStoreTests.swift
    AudioLevelReaderTests.swift
  Resources/Info.plist               LSUIElement, NSMicrophoneUsageDescription
  build-app.sh                       swift build + assemble STTBar.app bundle
```

Backend (modified): `stt-postprocess.sh` (prompt-from-file). Installer: `install.sh` (macOS branch: build app, LaunchAgent, HS stand-down).

---

## Task 1: Backend — prompt-from-file in stt-postprocess.sh

**Files:**
- Modify: `stt-postprocess.sh` (the `prompt=` resolution, ~line 176)
- Test: `tests/test-postprocess-prompt-file.sh` (new)

- [ ] **Step 1: Write the failing test**

Create `tests/test-postprocess-prompt-file.sh`:

```bash
#!/usr/bin/env bash
# Verifies STT_POSTPROCESS_PROMPT_FILE is honored, with correct precedence.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$SCRIPT_DIR/stt-postprocess.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Disable the LLM and replacements so we test prompt resolution in isolation
# by sourcing the resolver indirectly: we assert via a dry-run flag.
prompt_file="$tmp/p.txt"
printf 'PROMPT_FROM_FILE_MARKER' > "$prompt_file"

# STT_POSTPROCESS_PRINT_PROMPT=1 makes the script print the resolved prompt
# and exit 0 without calling any model (added in Step 3).
out="$(printf 'hello' | STT_POSTPROCESS_PRINT_PROMPT=1 \
    STT_POSTPROCESS_PROMPT_FILE="$prompt_file" \
    STT_REPLACEMENTS_ENABLED=0 STT_POSTPROCESS_LOG_ENABLED=0 \
    "$SUT")"
case "$out" in
    *PROMPT_FROM_FILE_MARKER*) echo "PASS file-prompt" ;;
    *) echo "FAIL file-prompt: got [$out]"; exit 1 ;;
esac

# Inline STT_POSTPROCESS_PROMPT must win over the file.
out="$(printf 'hello' | STT_POSTPROCESS_PRINT_PROMPT=1 \
    STT_POSTPROCESS_PROMPT='INLINE_WINS' \
    STT_POSTPROCESS_PROMPT_FILE="$prompt_file" \
    STT_REPLACEMENTS_ENABLED=0 STT_POSTPROCESS_LOG_ENABLED=0 \
    "$SUT")"
case "$out" in
    *INLINE_WINS*) echo "PASS inline-precedence" ;;
    *) echo "FAIL inline-precedence: got [$out]"; exit 1 ;;
esac
echo "ALL PASS"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-postprocess-prompt-file.sh`
Expected: FAIL (no `STT_POSTPROCESS_PRINT_PROMPT` handling, file not read).

- [ ] **Step 3: Implement prompt-from-file + dry-run hook**

In `stt-postprocess.sh`, replace the line `prompt="${STT_POSTPROCESS_PROMPT:-$default_prompt}"` with:

```bash
# Resolve the prompt: explicit inline var wins; else a prompt file (used by
# the STTBar app for live prompt switching); else the built-in default.
if [[ -n "${STT_POSTPROCESS_PROMPT:-}" ]]; then
    prompt="$STT_POSTPROCESS_PROMPT"
elif [[ -n "${STT_POSTPROCESS_PROMPT_FILE:-}" && -r "${STT_POSTPROCESS_PROMPT_FILE}" ]]; then
    prompt="$(cat "$STT_POSTPROCESS_PROMPT_FILE")"
else
    prompt="$default_prompt"
fi

# Test hook: print the resolved prompt and exit without calling a model.
if [[ "${STT_POSTPROCESS_PRINT_PROMPT:-0}" == "1" ]]; then
    printf '%s' "$prompt"
    exit 0
fi
```

(Place the dry-run hook AFTER the `translate_to` block so translation is reflected too — i.e. move the `STT_POSTPROCESS_PRINT_PROMPT` check to just before `prompt_input=`.)

- [ ] **Step 4: Run it to verify it passes**

Run: `bash tests/test-postprocess-prompt-file.sh`
Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add stt-postprocess.sh tests/test-postprocess-prompt-file.sh
git commit -m "feat(postprocess): read prompt from STT_POSTPROCESS_PROMPT_FILE"
```

---

## Task 2: SwiftPM scaffold

**Files:**
- Create: `macos-app/Package.swift`, `macos-app/Sources/STTBar/main.swift`, `macos-app/Resources/Info.plist`, `macos-app/.gitignore`

- [ ] **Step 1: Package.swift**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "STTBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "STTBar", path: "Sources/STTBar"),
        .testTarget(name: "STTBarTests", dependencies: ["STTBar"], path: "Tests/STTBarTests"),
    ]
)
```

- [ ] **Step 2: Minimal main.swift (compiles, shows a status item placeholder)**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // LSUIElement-equivalent at runtime
app.run()
```

- [ ] **Step 3: Placeholder AppDelegate so it builds** (replaced in Task 6)

Create `Sources/STTBar/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("STTBar launched")
    }
}
```

- [ ] **Step 4: Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>STTBar</string>
  <key>CFBundleIdentifier</key><string>de.projectmakers.sttbar</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>STTBar</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>STTBar records audio for speech-to-text transcription.</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
```

- [ ] **Step 5: .gitignore + build check**

Create `macos-app/.gitignore` with `.build/`.
Run: `cd macos-app && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add macos-app/Package.swift macos-app/Sources macos-app/Resources macos-app/.gitignore
git commit -m "feat(macos): scaffold STTBar SwiftPM executable"
```

---

## Task 3: EnvStore (TDD)

**Files:**
- Create: `macos-app/Sources/STTBar/Config/EnvStore.swift`
- Test: `macos-app/Tests/STTBarTests/EnvStoreTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import STTBar

final class EnvStoreTests: XCTestCase {
    private func temp(_ contents: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("env-\(UUID().uuidString)")
        try! contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testReadsQuotedAndUnquotedValues() throws {
        let url = temp("# c\nSTT_MODEL=\"foo\"\nSTT_LANGUAGE=de\n")
        let store = try EnvStore(url: url)
        XCTAssertEqual(store.value("STT_MODEL"), "foo")
        XCTAssertEqual(store.value("STT_LANGUAGE"), "de")
    }

    func testUpdatePreservesCommentsAndUnknownKeys() throws {
        let url = temp("# header\nSTT_MODEL=\"old\"\nOTHER=keep\n")
        var store = try EnvStore(url: url)
        store.set("STT_MODEL", "new")
        try store.save()
        let out = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(out.contains("# header"))
        XCTAssertTrue(out.contains("OTHER=keep"))
        XCTAssertTrue(out.contains("STT_MODEL=\"new\""))
        XCTAssertFalse(out.contains("old"))
    }

    func testSetUnknownKeyAppends() throws {
        let url = temp("STT_MODEL=x\n")
        var store = try EnvStore(url: url)
        store.set("STT_POSTPROCESS_PROMPT_FILE", "/tmp/p.txt")
        try store.save()
        let out = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(out.contains("STT_POSTPROCESS_PROMPT_FILE=\"/tmp/p.txt\""))
    }
}
```

- [ ] **Step 2: Run, expect fail**

Run: `cd macos-app && swift test --filter EnvStoreTests 2>&1 | tail -15`
Expected: compile error / no type `EnvStore`.

- [ ] **Step 3: Implement EnvStore**

```swift
import Foundation

/// Reads and writes a shell `.env` file, preserving comments, blank lines, and
/// keys the app does not manage. Only `KEY=value` / `KEY="value"` lines are
/// recognized; everything else is passed through verbatim on save.
struct EnvStore {
    let url: URL
    private var lines: [String]

    init(url: URL) throws {
        self.url = url
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        self.lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
    }

    private static func parse(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { return nil }
        let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
        guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
        else { return nil }
        var val = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        if val.count >= 2, val.hasPrefix("\""), val.hasSuffix("\"") {
            val = String(val.dropFirst().dropLast())
        }
        return (key, val)
    }

    func value(_ key: String) -> String? {
        for line in lines { if let p = Self.parse(line), p.key == key { return p.value } }
        return nil
    }

    mutating func set(_ key: String, _ value: String) {
        let rendered = "\(key)=\"\(value)\""
        for i in lines.indices {
            if let p = Self.parse(lines[i]), p.key == key { lines[i] = rendered; return }
        }
        if let last = lines.last, last.isEmpty { lines.insert(rendered, at: lines.count - 1) }
        else { lines.append(rendered) }
    }

    func save() throws {
        let text = lines.joined(separator: "\n")
        let tmp = url.appendingPathExtension("tmp")
        try text.write(to: tmp, atomically: true, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }
}
```

- [ ] **Step 4: Run, expect pass**

Run: `cd macos-app && swift test --filter EnvStoreTests 2>&1 | tail -10`
Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add macos-app/Sources/STTBar/Config/EnvStore.swift macos-app/Tests/STTBarTests/EnvStoreTests.swift
git commit -m "feat(macos): EnvStore for comment-preserving .env edits"
```

---

## Task 4: PromptStore (TDD)

**Files:**
- Create: `macos-app/Sources/STTBar/Config/PromptStore.swift`
- Test: `macos-app/Tests/STTBarTests/PromptStoreTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import STTBar

final class PromptStoreTests: XCTestCase {
    private func dir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func testSeedsDefaultAndMirrorsActiveFile() throws {
        let d = dir()
        let store = try PromptStore(directory: d, defaultBody: "DEFAULT_BODY")
        XCTAssertEqual(store.prompts.count, 1)
        XCTAssertEqual(store.activePrompt?.body, "DEFAULT_BODY")
        let mirrored = try String(contentsOf: d.appendingPathComponent("active-prompt.txt"), encoding: .utf8)
        XCTAssertEqual(mirrored, "DEFAULT_BODY")
    }

    func testAddSwitchAndPersist() throws {
        let d = dir()
        var store = try PromptStore(directory: d, defaultBody: "A")
        let id = try store.add(title: "Second", body: "B")
        try store.setActive(id)
        XCTAssertEqual(store.activePrompt?.body, "B")
        let mirrored = try String(contentsOf: d.appendingPathComponent("active-prompt.txt"), encoding: .utf8)
        XCTAssertEqual(mirrored, "B")
        // Reload from disk preserves state
        let reloaded = try PromptStore(directory: d, defaultBody: "A")
        XCTAssertEqual(reloaded.activePrompt?.body, "B")
        XCTAssertEqual(reloaded.prompts.count, 2)
    }

    func testUpdateActiveBodyRewritesMirror() throws {
        let d = dir()
        var store = try PromptStore(directory: d, defaultBody: "A")
        let id = store.activePrompt!.id
        try store.update(id, title: "Renamed", body: "A2")
        let mirrored = try String(contentsOf: d.appendingPathComponent("active-prompt.txt"), encoding: .utf8)
        XCTAssertEqual(mirrored, "A2")
    }
}
```

- [ ] **Step 2: Run, expect fail**

Run: `cd macos-app && swift test --filter PromptStoreTests 2>&1 | tail -15`
Expected: no type `PromptStore`.

- [ ] **Step 3: Implement PromptStore**

```swift
import Foundation

struct Prompt: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var body: String
}

/// Persists named prompts to `prompts.json` and mirrors the active prompt body
/// to `active-prompt.txt`, which `.env`'s STT_POSTPROCESS_PROMPT_FILE points at.
struct PromptStore {
    private let directory: URL
    private let jsonURL: URL
    let activeFileURL: URL
    private(set) var prompts: [Prompt]
    private(set) var activeId: String

    var activePrompt: Prompt? { prompts.first { $0.id == activeId } }

    private struct Persisted: Codable { var activeId: String; var prompts: [Prompt] }

    init(directory: URL, defaultBody: String) throws {
        self.directory = directory
        self.jsonURL = directory.appendingPathComponent("prompts.json")
        self.activeFileURL = directory.appendingPathComponent("active-prompt.txt")
        if let data = try? Data(contentsOf: jsonURL),
           let p = try? JSONDecoder().decode(Persisted.self, from: data), !p.prompts.isEmpty {
            self.prompts = p.prompts
            self.activeId = p.prompts.contains { $0.id == p.activeId } ? p.activeId : p.prompts[0].id
        } else {
            let seed = Prompt(id: UUID().uuidString, title: "Agent-Standard (DE)", body: defaultBody)
            self.prompts = [seed]
            self.activeId = seed.id
        }
        try persist()
    }

    @discardableResult
    mutating func add(title: String, body: String) throws -> String {
        let p = Prompt(id: UUID().uuidString, title: title, body: body)
        prompts.append(p); try persist(); return p.id
    }

    mutating func update(_ id: String, title: String, body: String) throws {
        guard let i = prompts.firstIndex(where: { $0.id == id }) else { return }
        prompts[i].title = title; prompts[i].body = body; try persist()
    }

    mutating func remove(_ id: String) throws {
        guard prompts.count > 1 else { return }
        prompts.removeAll { $0.id == id }
        if activeId == id { activeId = prompts[0].id }
        try persist()
    }

    mutating func setActive(_ id: String) throws {
        guard prompts.contains(where: { $0.id == id }) else { return }
        activeId = id; try persist()
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(Persisted(activeId: activeId, prompts: prompts))
        try data.write(to: jsonURL, options: .atomic)
        try (activePrompt?.body ?? "").write(to: activeFileURL, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 4: Run, expect pass**

Run: `cd macos-app && swift test --filter PromptStoreTests 2>&1 | tail -10`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add macos-app/Sources/STTBar/Config/PromptStore.swift macos-app/Tests/STTBarTests/PromptStoreTests.swift
git commit -m "feat(macos): PromptStore with active-prompt.txt mirroring"
```

---

## Task 5: AudioLevelReader + HudAnchor + Hotkey + AppSettings (TDD where logic)

**Files:**
- Create: `macos-app/Sources/STTBar/Core/AudioLevelReader.swift`,
  `macos-app/Sources/STTBar/Config/HudAnchor.swift`,
  `macos-app/Sources/STTBar/Config/Hotkey.swift`,
  `macos-app/Sources/STTBar/Config/AppSettings.swift`
- Test: `macos-app/Tests/STTBarTests/AudioLevelReaderTests.swift`

- [ ] **Step 1: Failing test for AudioLevelReader**

```swift
import XCTest
@testable import STTBar

final class AudioLevelReaderTests: XCTestCase {
    /// Builds a fake 44-byte-header + N int16 samples wav-ish file (only the
    /// PCM tail matters to the reader).
    private func wav(samples: [Int16]) -> URL {
        var data = Data(count: 44) // dummy header
        for s in samples { withUnsafeBytes(of: s.littleEndian) { data.append(contentsOf: $0) } }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try! data.write(to: u); return u
    }

    func testSilenceIsLow() {
        let r = AudioLevelReader(bucketCount: 22)
        let levels = r.levels(from: wav(samples: Array(repeating: 0, count: 4400)))
        XCTAssertEqual(levels.count, 22)
        XCTAssertTrue(levels.allSatisfy { $0 < 0.05 })
    }

    func testLoudIsHigher() {
        let r = AudioLevelReader(bucketCount: 22)
        let loud = r.levels(from: wav(samples: Array(repeating: 30000, count: 4400)))
        let quiet = r.levels(from: wav(samples: Array(repeating: 200, count: 4400)))
        XCTAssertGreaterThan(loud.reduce(0,+), quiet.reduce(0,+))
    }

    func testMissingFileReturnsZeros() {
        let r = AudioLevelReader(bucketCount: 22)
        let levels = r.levels(from: URL(fileURLWithPath: "/no/such.wav"))
        XCTAssertEqual(levels, Array(repeating: 0, count: 22))
    }
}
```

- [ ] **Step 2: Run, expect fail**

Run: `cd macos-app && swift test --filter AudioLevelReaderTests 2>&1 | tail -15`
Expected: no type `AudioLevelReader`.

- [ ] **Step 3: Implement AudioLevelReader** (port of Lua `readAudioLevels`)

```swift
import Foundation

/// Computes per-bucket audio levels from the tail of a 16-bit PCM wav file.
/// Stateless w.r.t. smoothing — the caller (HUD) applies temporal smoothing.
struct AudioLevelReader {
    let bucketCount: Int
    private let headerBytes = 44
    private let bytesPerBucketTarget = 480

    func levels(from url: URL) -> [Double] {
        let zeros = Array(repeating: 0.0, count: bucketCount)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return zeros }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > UInt64(headerBytes) else { return zeros }
        let available = Int(size) - headerBytes
        var readBytes = min(available, bucketCount * bytesPerBucketTarget)
        readBytes -= readBytes % 2
        guard readBytes > 0 else { return zeros }
        try? handle.seek(toOffset: size - UInt64(readBytes))
        guard let data = try? handle.read(upToCount: readBytes), !data.isEmpty else { return zeros }

        let sampleCount = data.count / 2
        guard sampleCount > 0 else { return zeros }
        let samples: [Int16] = data.withUnsafeBytes { raw in
            let buf = raw.bindMemory(to: Int16.self)
            return (0..<sampleCount).map { Int16(littleEndian: buf[$0]) }
        }
        let per = max(1, sampleCount / bucketCount)
        var out = zeros
        for b in 0..<bucketCount {
            let start = b * per
            let end = (b == bucketCount - 1) ? sampleCount : min(sampleCount, (b + 1) * per)
            if start >= end { continue }
            var sumSq = 0.0, peak = 0.0, n = 0.0
            for i in start..<end {
                let norm = abs(Double(samples[i])) / 32768.0
                peak = max(peak, norm); sumSq += norm * norm; n += 1
            }
            let rms = n > 0 ? (sumSq / n).squareRoot() : 0
            let voice = max(rms * 1.45, peak * 0.46)
            let gated = max(0, voice - 0.003)
            out[b] = min(1, pow(gated * 31.0, 0.52))
        }
        return out
    }
}
```

- [ ] **Step 4: Run, expect pass**

Run: `cd macos-app && swift test --filter AudioLevelReaderTests 2>&1 | tail -10`
Expected: pass.

- [ ] **Step 5: Implement HudAnchor.swift**

```swift
import AppKit

/// The eight screen anchor points from the spec. `center` is intentionally absent.
enum HudAnchor: String, CaseIterable, Codable {
    case topCenter, topRight, bottomRight, bottomLeft
    case leftBottom, leftTop, rightBottom, rightTop

    var label: String {
        switch self {
        case .topCenter: return "Oben Mitte";   case .topRight: return "Oben Rechts"
        case .bottomRight: return "Unten Rechts"; case .bottomLeft: return "Unten Links"
        case .leftBottom: return "Links Unten";   case .leftTop: return "Links Oben"
        case .rightBottom: return "Rechts Unten"; case .rightTop: return "Rechts Oben"
        }
    }

    /// Origin for a panel of `size` on `screen`, with `margin` inset. AppKit's
    /// origin is bottom-left.
    func origin(for size: NSSize, in screen: NSRect, margin: CGFloat = 26) -> NSPoint {
        let leftX = screen.minX + margin
        let rightX = screen.maxX - size.width - margin
        let centerX = screen.midX - size.width / 2
        let topY = screen.maxY - size.height - margin
        let bottomY = screen.minY + margin
        switch self {
        case .topCenter:    return NSPoint(x: centerX, y: topY)
        case .topRight:     return NSPoint(x: rightX,  y: topY)
        case .bottomRight:  return NSPoint(x: rightX,  y: bottomY)
        case .bottomLeft:   return NSPoint(x: leftX,   y: bottomY)
        case .leftBottom:   return NSPoint(x: leftX,   y: bottomY)
        case .leftTop:      return NSPoint(x: leftX,   y: topY)
        case .rightBottom:  return NSPoint(x: rightX,  y: bottomY)
        case .rightTop:     return NSPoint(x: rightX,  y: topY)
        }
    }
}
```

- [ ] **Step 6: Implement Hotkey.swift**

```swift
import AppKit
import Carbon.HIToolbox

/// A global hotkey binding: a virtual key code plus Carbon modifier flags.
struct Hotkey: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let fullDefault    = Hotkey(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey | shiftKey))
    static let rawDefault     = Hotkey(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey | shiftKey))
    static let englishDefault = Hotkey(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(shiftKey | optionKey))

    var display: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += Self.keyName(keyCode)
        return s
    }

    static func keyName(_ code: UInt32) -> String {
        if Int(code) == kVK_Space { return "Space" }
        let map: [Int: String] = [kVK_Return: "↩", kVK_Escape: "⎋", kVK_Tab: "⇥"]
        if let n = map[Int(code)] { return n }
        return "key\(code)"
    }
}
```

- [ ] **Step 7: Implement AppSettings.swift**

```swift
import Foundation

/// App-owned settings persisted in UserDefaults (HUD appearance + hotkeys).
final class AppSettings {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    var hudAnchor: HudAnchor {
        get { HudAnchor(rawValue: d.string(forKey: "hudAnchor") ?? "") ?? .topCenter }
        set { d.set(newValue.rawValue, forKey: "hudAnchor") }
    }
    var hudBackground: Bool {
        get { d.bool(forKey: "hudBackground") }
        set { d.set(newValue, forKey: "hudBackground") }
    }
    func hotkey(_ mode: SttMode) -> Hotkey {
        if let data = d.data(forKey: "hotkey.\(mode.rawValue)"),
           let hk = try? JSONDecoder().decode(Hotkey.self, from: data) { return hk }
        switch mode { case .full: return .fullDefault; case .raw: return .rawDefault; case .english: return .englishDefault }
    }
    func setHotkey(_ hk: Hotkey, for mode: SttMode) {
        d.set(try? JSONEncoder().encode(hk), forKey: "hotkey.\(mode.rawValue)")
    }
}

enum SttMode: String, CaseIterable { case full, raw, english
    var label: String { switch self { case .full: return "Bereinigt (LLM)"; case .raw: return "Roh (ohne LLM)"; case .english: return "Englisch (übersetzt)" } }
}
```

- [ ] **Step 8: Build + full test run**

Run: `cd macos-app && swift build 2>&1 | tail -3 && swift test 2>&1 | tail -6`
Expected: build complete, all tests pass.

- [ ] **Step 9: Commit**

```bash
git add macos-app/Sources/STTBar/Core/AudioLevelReader.swift macos-app/Sources/STTBar/Config/HudAnchor.swift macos-app/Sources/STTBar/Config/Hotkey.swift macos-app/Sources/STTBar/Config/AppSettings.swift macos-app/Tests/STTBarTests/AudioLevelReaderTests.swift
git commit -m "feat(macos): audio levels, HUD anchors, hotkey + settings model"
```

---

## Task 6: HotkeyManager + SttRunner + MenuBarController (wire-up, build-verified)

**Files:**
- Create: `macos-app/Sources/STTBar/Core/HotkeyManager.swift`,
  `macos-app/Sources/STTBar/Core/SttRunner.swift`,
  `macos-app/Sources/STTBar/UI/MenuBarController.swift`
- Modify: `macos-app/Sources/STTBar/AppDelegate.swift`

- [ ] **Step 1: HotkeyManager.swift (Carbon RegisterEventHotKey)**

```swift
import AppKit
import Carbon.HIToolbox

/// Registers up to three global hotkeys and invokes `onTrigger(mode)` on the
/// main thread. Re-register by calling `reload()` after settings change.
final class HotkeyManager {
    var onTrigger: ((SttMode) -> Void)?
    private var refs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    private var idToMode: [UInt32: SttMode] = [:]

    func install() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let this = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, ctx in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(ctx!).takeUnretainedValue()
            if let mode = mgr.idToMode[hkID.id] { DispatchQueue.main.async { mgr.onTrigger?(mode) } }
            return noErr
        }, 1, &spec, this, &handler)
        reload()
    }

    func reload() {
        for r in refs { if let r { UnregisterEventHotKey(r) } }
        refs.removeAll(); idToMode.removeAll()
        let sig = OSType(0x53545442) // 'STTB'
        for (i, mode) in SttMode.allCases.enumerated() {
            let hk = AppSettings.shared.hotkey(mode)
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: sig, id: UInt32(i + 1))
            if RegisterEventHotKey(hk.keyCode, hk.carbonModifiers, id, GetEventDispatcherTarget(), 0, &ref) == noErr {
                refs.append(ref); idToMode[UInt32(i + 1)] = mode
            }
        }
    }
}
```

- [ ] **Step 2: SttRunner.swift (Process lifecycle — port of launchSttToggle)**

```swift
import Foundation

/// Drives the shell STT pipeline. First trigger starts recording; second stops
/// and transcribes. `onState` reports the high-level state for icon + HUD.
enum SttState { case idle, recording, whisper, llm, error }

final class SttRunner {
    private let scriptPath: String
    private let phaseFile = "/tmp/stt-overlay-phase"
    private let pidFile = "/tmp/stt-recording.pid"
    let phaseFilePath: String
    var onState: ((SttState) -> Void)?
    private var task: Process?
    private var busy = false

    init(scriptPath: String) { self.scriptPath = scriptPath; self.phaseFilePath = phaseFile }

    var isRecording: Bool {
        guard let pid = try? String(contentsOfFile: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), let p = Int32(pid) else { return false }
        return kill(p, 0) == 0
    }

    func trigger(mode: SttMode) {
        if busy { onState?(isRecording ? .recording : .whisper); return }
        let wasRecording = isRecording
        try? FileManager.default.removeItem(atPath: phaseFile)
        busy = true
        onState?(wasRecording ? .whisper : .recording)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-lc", "exec \(shellQuote(scriptPath))"]
        var env = ProcessInfo.processInfo.environment
        env["STT_MODE"] = mode.rawValue
        env["STT_NOTIFICATIONS"] = "0"
        env["STT_PHASE_FILE"] = phaseFile
        p.environment = env
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false; self.task = nil
                if wasRecording {
                    try? FileManager.default.removeItem(atPath: self.phaseFile)
                    self.onState?(proc.terminationStatus == 0 ? .idle : .error)
                } else {
                    self.onState?(self.isRecording ? .recording : .error)
                }
            }
        }
        do { try p.run(); task = p } catch { busy = false; onState?(.error) }
    }

    /// Reads the phase file the shell pipeline writes (whisper|llm|done|error).
    func currentPhase() -> SttState? {
        guard let v = try? String(contentsOfFile: phaseFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        switch v { case "whisper": return .whisper; case "llm": return .llm
                   case "error": return .error; case "recording": return .recording; default: return nil }
    }

    private func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
```

- [ ] **Step 3: MenuBarController.swift**

```swift
import AppKit

/// Owns the menu-bar status item: a state-driven SF Symbol and a dropdown menu.
final class MenuBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var onTrigger: ((SttMode) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onEditPrompt: (() -> Void)?

    init() { setState(.idle); buildMenu() }

    func setState(_ state: SttState) {
        let name: String
        switch state {
        case .idle: name = "mic"; case .recording: name = "mic.fill"
        case .whisper: name = "waveform"; case .llm: name = "sparkles"; case .error: name = "exclamationmark.triangle"
        }
        item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "STT")
    }

    private func buildMenu() {
        let menu = NSMenu()
        for mode in SttMode.allCases {
            let mi = NSMenuItem(title: "Aufnahme: \(mode.label)", action: #selector(triggerMode(_:)), keyEquivalent: "")
            mi.target = self; mi.representedObject = mode.rawValue; menu.addItem(mi)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Einstellungen…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        let edit = NSMenuItem(title: "Prompt bearbeiten…", action: #selector(editPrompt), keyEquivalent: "")
        edit.target = self; menu.addItem(edit)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "STTBar beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    @objc private func triggerMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let m = SttMode(rawValue: raw) { onTrigger?(m) }
    }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func editPrompt() { onEditPrompt?() }
}
```

- [ ] **Step 4: Rewrite AppDelegate.swift to wire it together (HUD + settings stubbed until Tasks 7-8)**

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menu: MenuBarController!
    private var hotkeys: HotkeyManager!
    private var runner: SttRunner!
    private var hud: HudOverlay!
    private var settingsWindow: SettingsWindow?
    private var promptWindow: PromptEditorWindow?
    let installDir = InstallPaths.resolve()

    func applicationDidFinishLaunching(_ notification: Notification) {
        runner = SttRunner(scriptPath: installDir.appendingPathComponent("stt-global.sh").path)
        hud = HudOverlay(runner: runner)
        menu = MenuBarController()
        hotkeys = HotkeyManager()

        runner.onState = { [weak self] state in
            self?.menu.setState(state)
            self?.hud.update(state)
        }
        let trigger: (SttMode) -> Void = { [weak self] mode in self?.runner.trigger(mode: mode) }
        menu.onTrigger = trigger
        hotkeys.onTrigger = trigger
        menu.onOpenSettings = { [weak self] in self?.showSettings() }
        menu.onEditPrompt = { [weak self] in self?.showPromptEditor() }
        hotkeys.install()
    }

    private func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow(installDir: installDir, onHotkeysChanged: { [weak self] in self?.hotkeys.reload() }) }
        settingsWindow?.show()
    }
    private func showPromptEditor() {
        if promptWindow == nil { promptWindow = PromptEditorWindow(installDir: installDir) }
        promptWindow?.show()
    }
}

/// Resolves the directory containing the shell scripts + .env. Order: env var,
/// the standard install dir, else the app bundle's parent.
enum InstallPaths {
    static func resolve() -> URL {
        if let p = ProcessInfo.processInfo.environment["STT_INSTALL_DIR"] { return URL(fileURLWithPath: p) }
        let std = (NSHomeDirectory() as NSString).appendingPathComponent(".local/share/stt")
        if FileManager.default.fileExists(atPath: (std as NSString).appendingPathComponent("stt-global.sh")) {
            return URL(fileURLWithPath: std)
        }
        return URL(fileURLWithPath: std)
    }
}
```

- [ ] **Step 5: Build (will fail until HUD/Settings stubs exist — create minimal stubs)**

Create minimal stubs so the project links; they are fully implemented in Tasks 7-8.
`HudOverlay.swift`:
```swift
import AppKit
final class HudOverlay { init(runner: SttRunner) {}; func update(_ state: SttState) {} }
```
`SettingsWindow.swift`:
```swift
import AppKit
final class SettingsWindow { init(installDir: URL, onHotkeysChanged: @escaping () -> Void) {}; func show() {} }
```
`PromptEditorWindow.swift`:
```swift
import AppKit
final class PromptEditorWindow { init(installDir: URL) {}; func show() {} }
```

Run: `cd macos-app && swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add macos-app/Sources/STTBar
git commit -m "feat(macos): hotkey manager, STT runner, menu bar wiring"
```

---

## Task 7: HudOverlay (CALayer port of the Lua animation)

**Files:**
- Replace: `macos-app/Sources/STTBar/UI/HudOverlay.swift`

- [ ] **Step 1: Implement the overlay panel + animation**

Implement an `NSPanel` (borderless, `.statusBar`+1 level, `ignoresMouseEvents`, `canJoinAllSpaces`, `.stationary`) hosting a layer-backed view. A 20 fps `CADisplayLink`/`Timer` drives:
- `recording`: waveform from `AudioLevelReader.levels(from: /tmp/stt-recording.wav)` with the Lua smoothing `level = level*0.28 + target*0.72`; bars colored rec-green.
- `whisper`/`llm`: a 12-dot spinner (whisper=blue, llm=purple), reading `runner.currentPhase()` to switch whisper→llm live.
- `error`: a red dot, auto-hide after 1.4 s.
The panel repositions from `AppSettings.shared.hudAnchor.origin(...)` each show; if `hudBackground` is on, draw a rounded gray backing (`NSColor.gray.withAlphaComponent(0.18)`).

```swift
import AppKit

final class HudOverlay {
    private let runner: SttRunner
    private let reader = AudioLevelReader(bucketCount: 22)
    private var panel: NSPanel?
    private var view: HudView?
    private var timer: Timer?
    private var hideWork: DispatchWorkItem?

    init(runner: SttRunner) { self.runner = runner }

    func update(_ state: SttState) {
        switch state {
        case .idle: hide()
        case .error: show(.error); scheduleHide(after: 1.4)
        default: show(state)
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let size = NSSize(width: 190, height: 46)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let v = HudView(frame: NSRect(origin: .zero, size: size), reader: reader, runner: runner)
        p.contentView = v
        panel = p; view = v
    }

    private func reposition() {
        guard let panel, let screen = NSScreen.main else { return }
        let origin = AppSettings.shared.hudAnchor.origin(for: panel.frame.size, in: screen.frame)
        panel.setFrameOrigin(origin)
    }

    private func show(_ state: SttState) {
        hideWork?.cancel()
        ensurePanel(); reposition()
        view?.state = state
        view?.showBackground = AppSettings.shared.hudBackground
        panel?.orderFrontRegardless()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                if let phase = self?.runner.currentPhase(),
                   self?.view?.state == .whisper || self?.view?.state == .llm { self?.view?.state = phase }
                self?.view?.needsDisplay = true
            }
        }
    }

    private func scheduleHide(after s: TimeInterval) {
        let w = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = w; DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: w)
    }

    private func hide() {
        timer?.invalidate(); timer = nil
        panel?.orderOut(nil)
    }
}

/// Layer-light custom drawing; mirrors the Lua canvas shapes closely enough.
final class HudView: NSView {
    var state: SttState = .recording
    var showBackground = false
    private let reader: AudioLevelReader
    private let runner: SttRunner
    private var levels = [Double](repeating: 0, count: 22)
    private var phase = 0.0
    private let wav = "/tmp/stt-recording.wav"

    init(frame: NSRect, reader: AudioLevelReader, runner: SttRunner) {
        self.reader = reader; self.runner = runner; super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        phase += 0.11
        if showBackground {
            NSColor(white: 0.5, alpha: 0.18).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        }
        switch state {
        case .recording: drawWave(ctx)
        case .whisper: drawSpinner(ctx, color: NSColor(red: 0.20, green: 0.64, blue: 1.0, alpha: 1))
        case .llm: drawSpinner(ctx, color: NSColor(red: 0.78, green: 0.54, blue: 1.0, alpha: 1))
        case .error: drawError(ctx)
        case .idle: break
        }
    }

    private func drawWave(_ ctx: CGContext) {
        let target = reader.levels(from: URL(fileURLWithPath: wav))
        for i in 0..<levels.count { levels[i] = levels[i]*0.28 + (target[i])*0.72 }
        let centerY = 23.0
        for i in 0..<levels.count {
            let h = 3 + levels[i]*32
            let a = 0.10 + levels[i]*0.90
            NSColor(red: 0.08, green: 0.95, blue: 0.68, alpha: a).setFill()
            let r = NSRect(x: 45 + Double(i)*6, y: centerY - h/2, width: 3, height: h)
            NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5).fill()
        }
        // mic glyph
        NSColor(red: 0.08, green: 0.95, blue: 0.68, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 14, y: 12, width: 12, height: 21), xRadius: 6, yRadius: 6).fill()
    }

    private func drawSpinner(_ ctx: CGContext, color: NSColor) {
        let cx = 100.0, cy = 23.0, radius = 15.0, count = 12
        let active = Int(phase * 9)
        for i in 0..<count {
            let angle = Double(i)/Double(count) * .pi * 2
            let rank = ((i + active) % count) + 1
            let a = 0.13 + (Double(rank)/Double(count))*0.87
            color.withAlphaComponent(a).setFill()
            let x = cx + cos(angle)*radius, y = cy + sin(angle)*radius
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 4, height: 4)).fill()
        }
    }

    private func drawError(_ ctx: CGContext) {
        NSColor(red: 1.0, green: 0.26, blue: 0.24, alpha: 0.95).setFill()
        NSBezierPath(ovalIn: NSRect(x: 84, y: 12, width: 22, height: 22)).fill()
    }
}
```

- [ ] **Step 2: Build**

Run: `cd macos-app && swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add macos-app/Sources/STTBar/UI/HudOverlay.swift
git commit -m "feat(macos): native HUD overlay (waveform + spinner + anchors)"
```

---

## Task 8: SettingsView + SettingsWindow + PromptEditorWindow + HotkeyRecorder

**Files:**
- Create: `macos-app/Sources/STTBar/UI/SettingsView.swift`, `HotkeyRecorder.swift`
- Replace: `macos-app/Sources/STTBar/UI/SettingsWindow.swift`, `PromptEditorWindow.swift`
- Create: `macos-app/Sources/STTBar/Config/SettingsModel.swift`

- [ ] **Step 1: SettingsModel.swift (ObservableObject bridging stores)**

```swift
import SwiftUI

/// Single source the SwiftUI views bind to. Wraps EnvStore + PromptStore +
/// AppSettings and writes through on change.
final class SettingsModel: ObservableObject {
    private var env: EnvStore
    @Published var prompts: PromptStore
    let installDir: URL
    var onHotkeysChanged: (() -> Void)?

    @Published var whisperURL: String { didSet { write("STT_SERVER_URL", whisperURL) } }
    @Published var whisperModel: String { didSet { write("STT_MODEL", whisperModel) } }
    @Published var language: String { didSet { write("STT_LANGUAGE", language) } }
    @Published var postprocessEnabled: Bool { didSet { write("STT_POSTPROCESS_ENABLED", postprocessEnabled ? "1" : "0") } }
    @Published var lmStudioURL: String { didSet { write("STT_POSTPROCESS_URL", lmStudioURL) } }
    @Published var llmModel: String { didSet { write("STT_POSTPROCESS_MODEL", llmModel) } }
    @Published var provider: String { didSet { write("STT_POSTPROCESS_PROVIDER", provider) } }
    @Published var hudAnchor: HudAnchor { didSet { AppSettings.shared.hudAnchor = hudAnchor } }
    @Published var hudBackground: Bool { didSet { AppSettings.shared.hudBackground = hudBackground } }

    static let defaultPrompt = DefaultPrompt.body

    init(installDir: URL) {
        self.installDir = installDir
        let envURL = installDir.appendingPathComponent(".env")
        self.env = (try? EnvStore(url: envURL)) ?? (try! EnvStore(url: envURL))
        self.prompts = (try? PromptStore(directory: installDir, defaultBody: DefaultPrompt.body))
            ?? (try! PromptStore(directory: installDir, defaultBody: DefaultPrompt.body))
        whisperURL = env.value("STT_SERVER_URL") ?? ""
        whisperModel = env.value("STT_MODEL") ?? "Systran/faster-whisper-large-v3-turbo"
        language = env.value("STT_LANGUAGE") ?? "de"
        postprocessEnabled = (env.value("STT_POSTPROCESS_ENABLED") ?? "0") == "1"
        lmStudioURL = env.value("STT_POSTPROCESS_URL") ?? ""
        llmModel = env.value("STT_POSTPROCESS_MODEL") ?? ""
        provider = env.value("STT_POSTPROCESS_PROVIDER") ?? "lmstudio"
        hudAnchor = AppSettings.shared.hudAnchor
        hudBackground = AppSettings.shared.hudBackground
        // Ensure .env points at the mirrored active prompt file.
        write("STT_POSTPROCESS_PROMPT_FILE", prompts.activeFileURL.path)
    }

    private func write(_ key: String, _ value: String) { env.set(key, value); try? env.save() }

    // Prompt operations re-publish the store.
    func addPrompt(title: String, body: String) { _ = try? prompts.add(title: title, body: body); objectWillChange.send() }
    func setActive(_ id: String) { try? prompts.setActive(id); objectWillChange.send() }
    func updatePrompt(_ id: String, title: String, body: String) { try? prompts.update(id, title: title, body: body); objectWillChange.send() }
    func removePrompt(_ id: String) { try? prompts.remove(id); objectWillChange.send() }
}
```

Also create `Sources/STTBar/Config/DefaultPrompt.swift` holding the German default prompt as a multi-line Swift string literal (copy verbatim from `stt-postprocess.sh`'s `default_prompt`).

- [ ] **Step 2: HotkeyRecorder.swift (NSViewRepresentable)**

```swift
import SwiftUI
import Carbon.HIToolbox

/// A click-to-record field that captures the next key+modifier chord.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: Hotkey
    var onChange: () -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let b = RecorderButton(); b.onCapture = { hk in hotkey = hk; onChange() }; b.hotkey = hotkey; return b
    }
    func updateNSView(_ nsView: RecorderButton, context: Context) { nsView.hotkey = hotkey }
}

final class RecorderButton: NSButton {
    var onCapture: ((Hotkey) -> Void)?
    var hotkey: Hotkey = .fullDefault { didSet { title = hotkey.display } }
    private var recording = false

    override init(frame: NSRect) { super.init(frame: frame); bezelStyle = .rounded; setButtonType(.momentaryPushIn); target = self; action = #selector(begin) }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func begin() { recording = true; title = "Taste drücken…"; window?.makeFirstResponder(self) }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        var mods: UInt32 = 0
        if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.shift) { mods |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.option) { mods |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
        let hk = Hotkey(keyCode: UInt32(event.keyCode), carbonModifiers: mods)
        recording = false; hotkey = hk; onCapture?(hk)
    }
}
```

- [ ] **Step 3: SettingsView.swift (TabView)**

Implement a `TabView` with five tabs (Server, Prompts, Shortcuts, Anzeige, Allgemein) binding to `SettingsModel`. Server tab: `TextField`s for `whisperURL`, `whisperModel` (with a `Menu` of presets incl. `Systran/faster-whisper-large-v3-turbo`), `language`, `Toggle` postprocess, `lmStudioURL`, `llmModel`, provider `Picker`. Prompts tab: `List` of `model.prompts.prompts` with a selection bound to active + New/Duplicate/Delete + "Bearbeiten…" button calling an `openEditor` closure. Shortcuts tab: a row per `SttMode` with `mode.label` + `HotkeyRecorder`. Anzeige tab: a 3×3 grid of buttons (center disabled) setting `hudAnchor` + a `Toggle` for `hudBackground`. Allgemein tab: autostart toggle (writes LaunchAgent via `LaunchAgent.setEnabled`) + Hammerspoon note + a button opening Accessibility settings.

(Full SwiftUI body — each control is a standard `TextField`/`Toggle`/`Picker` bound to the matching `@Published` property; the anchor grid maps the 8 `HudAnchor` cases to the 8 non-center grid cells.)

- [ ] **Step 4: SettingsWindow.swift + PromptEditorWindow.swift (NSWindow hosts)**

```swift
import AppKit
import SwiftUI

final class SettingsWindow {
    private var window: NSWindow?
    private let model: SettingsModel
    init(installDir: URL, onHotkeysChanged: @escaping () -> Void) {
        model = SettingsModel(installDir: installDir); model.onHotkeysChanged = onHotkeysChanged
    }
    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model, openEditor: { [weak self] id in
                self?.openEditor(id)
            }))
            let w = NSWindow(contentViewController: host)
            w.title = "STTBar – Einstellungen"; w.styleMask = [.titled, .closable, .miniaturizable]
            w.setContentSize(NSSize(width: 520, height: 420)); window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center(); window?.makeKeyAndOrderFront(nil)
    }
    private func openEditor(_ id: String) {
        let editor = PromptEditorWindow(model: model, promptId: id); editor.show(); retainedEditor = editor
    }
    private var retainedEditor: PromptEditorWindow?
}
```

`PromptEditorWindow.swift`:
```swift
import AppKit
import SwiftUI

final class PromptEditorWindow {
    private var window: NSWindow?
    private let model: SettingsModel
    private let promptId: String?
    // Convenience init used by the menu ("Prompt bearbeiten…") -> active prompt.
    init(installDir: URL) { self.model = SettingsModel(installDir: installDir); self.promptId = nil }
    init(model: SettingsModel, promptId: String) { self.model = model; self.promptId = promptId }

    func show() {
        let id = promptId ?? model.prompts.activePrompt?.id ?? ""
        let title = model.prompts.prompts.first { $0.id == id }?.title ?? "Prompt"
        if window == nil {
            let host = NSHostingController(rootView: PromptEditorView(model: model, promptId: id))
            let w = NSWindow(contentViewController: host)
            w.title = "Prompt bearbeiten – \(title)"
            w.styleMask = [.titled, .closable, .resizable]
            w.setContentSize(NSSize(width: 600, height: 480)); window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
```

Add a `PromptEditorView` (SwiftUI) with a `TextEditor` bound to the prompt body, a title `TextField`, and Save/Schließen buttons calling `model.updatePrompt`.

- [ ] **Step 5: LaunchAgent.swift helper**

```swift
import Foundation

/// Writes/removes the login LaunchAgent that starts STTBar.app.
enum LaunchAgent {
    static let label = "de.projectmakers.sttbar"
    static var plistURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static func setEnabled(_ on: Bool, appPath: String) {
        if on {
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>Label</key><string>\(label)</string>
              <key>ProgramArguments</key><array><string>\(appPath)/Contents/MacOS/STTBar</string></array>
              <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
            </dict></plist>
            """
            try? plist.write(to: plistURL, atomically: true, encoding: .utf8)
        } else { try? FileManager.default.removeItem(at: plistURL) }
    }
}
```

- [ ] **Step 6: Build**

Run: `cd macos-app && swift build 2>&1 | tail -3 && swift test 2>&1 | tail -4`
Expected: build complete, tests pass.

- [ ] **Step 7: Commit**

```bash
git add macos-app/Sources/STTBar
git commit -m "feat(macos): SwiftUI settings, prompt editor, hotkey recorder"
```

---

## Task 9: build-app.sh (assemble .app bundle) + smoke run

**Files:**
- Create: `macos-app/build-app.sh`

- [ ] **Step 1: Write build-app.sh**

```bash
#!/usr/bin/env bash
# Builds STTBar and assembles a .app bundle. Usage: build-app.sh [dest-dir]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-$HOME/Applications}"
APP="$DEST/STTBar.app"

swift build -c release --package-path "$HERE"
BIN="$(swift build -c release --package-path "$HERE" --show-bin-path)/STTBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/STTBar"
cp "$HERE/Resources/Info.plist" "$APP/Contents/Info.plist"
echo "Built $APP"
```

- [ ] **Step 2: Build the bundle**

Run: `bash macos-app/build-app.sh "$PWD/macos-app/.build"`
Expected: `Built .../STTBar.app`.

- [ ] **Step 3: Smoke-launch (manual)**

Run: `STT_INSTALL_DIR="$HOME/.local/share/stt" open macos-app/.build/STTBar.app` (or run the binary directly). Verify a menu-bar mic icon appears and the menu opens. Quit via the menu.

- [ ] **Step 4: Commit**

```bash
chmod +x macos-app/build-app.sh
git add macos-app/build-app.sh
git commit -m "build(macos): assemble STTBar.app bundle"
```

---

## Task 10: install.sh integration + Hammerspoon stand-down

**Files:**
- Modify: `install.sh` (macOS branch around lines 312-360)

- [ ] **Step 1: Add an app-install path to the macOS branch**

After copying scripts, add (guarded by a `STT_USE_NATIVE_APP` prompt/flag, default yes when `swift` is present):

```bash
install_native_app() {
    command -v swift >/dev/null 2>&1 || { echo "swift not found; keeping Hammerspoon front-end."; return 1; }
    echo "Building STTBar.app…"
    STT_INSTALL_DIR="$INSTALL_DIR" bash "$SCRIPT_DIR/macos-app/build-app.sh" "$HOME/Applications"
    # LaunchAgent for login start
    local plist="$HOME/Library/LaunchAgents/de.projectmakers.sttbar.plist"
    mkdir -p "$(dirname "$plist")"
    cat > "$plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>de.projectmakers.sttbar</string>
  <key>ProgramArguments</key><array>
    <string>$HOME/Applications/STTBar.app/Contents/MacOS/STTBar</string>
  </array>
  <key>EnvironmentVariables</key><dict><key>STT_INSTALL_DIR</key><string>$INSTALL_DIR</string></dict>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
</dict></plist>
PL
    launchctl unload "$plist" 2>/dev/null || true
    launchctl load "$plist" 2>/dev/null || true
    echo "STTBar.app installed and started."
}
```

- [ ] **Step 2: Wire it in + stand Hammerspoon down**

In the macOS install flow, after `cp ... stt-global.sh`, call:

```bash
if install_native_app; then
    # Native app owns icon + hotkeys + HUD; remove the Hammerspoon STT block.
    unregister_hammerspoon_binding && echo "Disabled Hammerspoon STT block (native app active)."
else
    register_hammerspoon_binding || true
fi
```

- [ ] **Step 3: Verify install script syntax**

Run: `bash -n install.sh && echo OK`
Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat(macos): install STTBar.app + LaunchAgent, stand Hammerspoon down"
```

---

## Task 11: Docs + end-to-end verification

**Files:**
- Modify: `CLAUDE.md` (add a macOS native-app section), `.env.example` (note `STT_POSTPROCESS_PROMPT_FILE`)

- [ ] **Step 1: Document the app** — add a "macOS native app (STTBar)" section to `CLAUDE.md`: what it owns, where prompts live (`prompts.json` / `active-prompt.txt`), how to rebuild (`macos-app/build-app.sh`), and that it replaces Hammerspoon.

- [ ] **Step 2: Note the new env key** — add a commented `STT_POSTPROCESS_PROMPT_FILE=""` to `.env.example` explaining the app manages it.

- [ ] **Step 3: End-to-end manual verification (record outcomes):**
  - Trigger Full hotkey → mic icon + waveform HUD → speak → stop → whisper/llm spinner → text pasted.
  - Switch active prompt in Settings → next run reflects it (check `stt-postprocess.log`).
  - Move HUD across the 8 anchors + toggle gray background.
  - Rebind a hotkey → trigger via the new chord.
  - Edit whisper/LM-Studio URLs + models → confirm `.env` updated and used.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md .env.example
git commit -m "docs(macos): document STTBar native app + prompt-file env key"
```

---

## Self-Review Notes

- **Spec coverage:** menu icon (Task 6), settings window (Task 8), 8-anchor HUD + gray bg (Tasks 5/7/8), shortcut description + rebinding (Tasks 5/8), live prompt switching + multiple prompts + separate titled editor (Tasks 1/4/8), LLM id entry (Task 8), whisper + LM-Studio IPs (Task 8), whisper model setting (Task 8), Hammerspoon stand-down (Task 10). All covered.
- **Type consistency:** `SttMode`, `SttState`, `HudAnchor`, `Hotkey`, `EnvStore`, `PromptStore`, `AudioLevelReader`, `SettingsModel` used consistently across tasks.
- **Backend contract** matches Hammerspoon's (`STT_MODE`, `STT_NOTIFICATIONS=0`, `STT_PHASE_FILE`, `stt-global.sh`).
