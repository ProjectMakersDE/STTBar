# STTBar: App-Sprache (DE/EN), In-App-Updater & Allgemein-Politur

Datum: 2026-06-18
Status: Entwurf zur Review

## Ziel

Drei zusammenhängende, aber technisch unabhängige Erweiterungen der nativen
macOS-App `STTBar`, in **einem** Implementierungs-Durchlauf umgesetzt:

1. **App-Sprache Deutsch/English** — ein zur Laufzeit umschaltbarer Sprach-
   schalter, der gleichzeitig (a) die gesamte App-UI übersetzt, (b) den Whisper-
   Default (`STT_LANGUAGE`) auf `de`/`en` setzt und (c) den aktiven Prompt auf
   das passende eingebaute Preset (`Agent V4 (DE)` ↔ `Agent V4 (EN output)`)
   umstellt. Schnellzugriff in der Menüleiste **und** in den Einstellungen.
2. **„Allgemein"-Tab Politur** — ein „made with ❤ by ProjectMakers.de"-Footer
   (Herz-Icon, Link auf die Website), ein dauerhaft sichtbarer GitHub-Repo-Link
   und ein aufgeräumter Update-Bereich mit dauerhaft sichtbarem Release-Link.
3. **Echter In-App-Updater** — ein „Aktualisieren"-Button, der das neueste
   Release lädt (App-Bundle **und** Shell-Skripte), entpackt, einspielt und die
   App neu startet.

## Nicht-Ziele / Außerhalb des Scopes

- **Backend/Shell-Strings bleiben einsprachig (Englisch):** Notifications und
  Status-Events der Shell-Skripte werden **nicht** laufzeit-zweisprachig,
  sondern statisch auf **Englisch** umgestellt (siehe 1.6). Der Sprachschalter
  betrifft die laufzeit-umschaltbare Swift-UI.
- **Notarisierung / Apple-Developer-Signing:** Bleibt wie gehabt (self-signed
  / ad-hoc). Der Updater entfernt das Quarantäne-Attribut, statt auf
  Notarisierung zu setzen.

---

## Teil 1 — App-Sprache Deutsch/English

### 1.1 Lokalisierungs-Infrastruktur

Da `STTBar` ein SwiftPM-**Executable** ohne Standard-`.lproj`-Runtime-Switch ist
und die Sprache **zur Laufzeit** (ohne Neustart) wechseln soll, verwenden wir
einen schlanken eigenen Mechanismus statt String-Catalogs:

- **`AppLanguage`** (`enum AppLanguage: String { case de, en }`) — neuer Typ in
  `Config/`.
- **`Localization`** (neue Datei `Config/Localization.swift`):
  ```swift
  final class Localization: ObservableObject {
      static let shared = Localization()
      @Published var language: AppLanguage
  }
  ```
  Initialwert aus `AppSettings.appLanguage` (Default `.de` → Bestandsnutzer
  bleiben auf Deutsch).
- **Freie Funktion** `func L(_ de: String, _ en: String) -> String` — liefert je
  nach `Localization.shared.language` den passenden String. Kein Key-Management;
  Übersetzungen stehen direkt an der Aufrufstelle (`L("Einstellungen",
  "Settings")`). Gut wartbar und trivial laufzeit-umschaltbar.
- **Persistenz:** neues `AppSettings.appLanguage: AppLanguage` (UserDefaults-Key
  `appLanguage`, Default `.de`).

### 1.2 Laufzeit-Neurendern

- **SwiftUI-Views:** Jede Top-Level-View, die `L(...)` nutzt, hält
  `@ObservedObject private var loc = Localization.shared`. Ändert sich
  `language`, wird der Body neu ausgewertet und `L(...)` liefert die neuen
  Strings. Betroffen: `SettingsView` (+ alle privaten Sub-Tabs),
  `PromptEditorView`, `StatusWindow`-Content, `HudOverlay`.
- **AppKit-Menüleiste:** `MenuBarController` ist kein SwiftUI. `AppDelegate`
  abonniert `Localization.shared.$language` (Combine) und ruft bei Änderung
  `menu.rebuild()` (heutiges `buildMenu()` wird `internal`/aufrufbar gemacht)
  sowie Tooltip-Refresh.

### 1.3 Kopplung Sprache → Whisper + Prompt

Eine **einzige Einstiegsmethode** auf `SettingsModel`:

```swift
func setAppLanguage(_ lang: AppLanguage)
```

tut atomar:
1. `Localization.shared.language = lang` (löst UI/Menü-Refresh aus).
2. `AppSettings.shared.appLanguage = lang`.
3. `language = (lang == .de ? "de" : "en")` (Whisper-Feld) und schreibt
   `STT_LANGUAGE` in `.env`.
4. Aktiviert den passenden eingebauten Prompt: sucht in `prompts.prompts` nach
   Titel `DefaultPrompt.germanTitle` bzw. `DefaultPrompt.englishTitle`; falls
   gefunden → `setActive(id)` (aktualisiert `active-prompt.txt` +
   `STT_POSTPROCESS_PROMPT_FILE`). Falls der Nutzer das Preset gelöscht hat:
   no-op für den Prompt (Sprache + Whisper greifen trotzdem).
5. `env.save()`.

Das bestehende Freitext-Feld „Sprache" im Server-Tab bleibt als Experten-
Override erhalten. Der Schalter überschreibt es bewusst beim Umschalten.

### 1.4 String-Extraktion (UI-Übersetzung)

Alle nutzersichtbaren deutschen Swift-Strings werden auf `L("de", "en")`
umgestellt. Betroffene Dateien (grobe Stringzahl):

- `UI/SettingsView.swift` (~86) — alle Tab-Titel, Labels, Buttons, Hinweise.
- `Config/AppSettings.swift` — `SttMode.label` + `SttMode.detail` (DE/EN).
- `UI/MenuBarController.swift` (~16) — Menüeinträge, Tooltip-States.
- `UI/StatusWindow.swift` (~12).
- `UI/PromptEditorView.swift` (~11) + `UI/PromptEditorWindow.swift`.
- `UI/HudOverlay.swift`, `UI/SettingsWindow.swift`, `UI/HotkeyRecorder.swift`.
- `Config/SettingsModel.swift` — nutzersichtbare Meldungen
  (`saveMessage`, `validationMessage`, `updateMessage`-Texte etc.).
- `Core/HealthCenterModel.swift` — sofern nutzersichtbare deutsche Strings.

Übersetzungen werden fachlich sauber gewählt (z. B. „Einstellungen" →
„Settings", „Bedienungshilfen" → „Accessibility", „Wörterbuch" → „Vocabulary").

### 1.5 Shell-Skripte & README auf Englisch (statisch)

- **Shell-Notifications & Status-Events:** Alle nutzersichtbaren deutschen
  Strings in `stt-global-mac.sh`, `stt-global.sh`, `stt-record.sh`,
  `stt-transcribe.sh`, `stt-postprocess.sh` (Argumente von `stt_status_event`
  und `notify`-Texte, z. B. „Aufnahme wird gestoppt…") werden fest auf Englisch
  umgestellt („Recording is being stopped…"). Keine Laufzeit-Umschaltung.
- **Status-Event-Codes** (maschinenlesbare Schlüssel wie `whisper_failed`)
  bleiben unverändert — nur die Klartext-`message`/`detail` werden übersetzt.
- **Tests prüfen:** `tests/*.sh` auf Assertions gegen deutsche Strings prüfen
  und ggf. auf die englischen Texte anpassen.
- **README.md** wird auf Englisch umgeschrieben (Inhalt bleibt äquivalent).

### 1.6 UI des Schalters

- **Menüleiste:** Neuer Eintrag/Untermenü „Sprache / Language" mit zwei
  Optionen „Deutsch" und „English" (Häkchen am aktiven). Klick →
  `model.setAppLanguage(...)`. `AppDelegate` reicht eine
  `onSetLanguage`-Closure an `MenuBarController`.
- **Einstellungen → Allgemein:** Ein `Picker`/Segmented Control „Sprache /
  Language" oben in der Section „Start" oder einer neuen Section „Sprache".

---

## Teil 2 — „Allgemein"-Tab Politur

Alle Änderungen in `UI/SettingsView.swift` → `GeneralTab`.

### 2.1 ProjectMakers-Footer

Eine dezente Fußzeile am Ende des Formulars:

> made with ❤ by **ProjectMakers.de**

- Herz: SF-Symbol `heart.fill` in Rot (`.foregroundStyle(.red)`).
- „ProjectMakers.de" ist ein `Link` auf `https://projectmakers.de`.
- Umgesetzt als `HStack` mit `Text` + `Image(systemName:)` + `Link`.

### 2.2 GitHub-Repository-Link (dauerhaft sichtbar)

- In der „Version"-Section ein dauerhaft sichtbarer `Link` „GitHub-Repository"
  auf `https://github.com/\(repository)` (Repo aus `STTBAR_UPDATE_REPOSITORY`,
  Default `ProjectMakersDE/STTBar`).

### 2.3 Update-Bereich-Layout

- Dauerhaft sichtbarer Link „Releases öffnen" auf
  `https://github.com/\(repository)/releases` (vor jedem Check verfügbar).
- Aufgeräumte Darstellung der aktuellen Version + Update-Status (siehe Teil 3
  für die Zustände/Buttons).

---

## Teil 3 — In-App-Updater

### 3.1 Zustandsmodell

`SettingsModel` (oder neuer Typ `Core/Updater.swift`, an `SettingsModel`
gehängt) hält:

- `updateState`: `idle | checking | upToDate | available | downloading |
  installing | failed`
- `latestVersion: String?`, `releaseURL: URL?`
- `appAssetURL: URL?`, `scriptsAssetURL: URL?`, `appSha256: String?`
- `updateMessage: String?` (lokalisiert)

### 3.2 Check (Erweiterung des bestehenden `checkForUpdates()`)

- `GitHubRelease` wird um `assets: [{ name, browser_download_url }]` erweitert.
- Aus den Assets werden ermittelt: `STTBar.app.zip` (App),
  `stt-scripts.zip` (Skripte) und optional `STTBar.app.zip.sha256`.
- Bei `latest > current` → `updateState = .available`, Button „Aktualisieren"
  wird sichtbar.

### 3.3 Update-Ablauf („Aktualisieren")

Hintergrund-Queue, UI zeigt `downloading`/`installing`:

1. **Download** App-Zip + Skripte-Zip (+ optional `.sha256`) nach
   `~/Library/Caches/STTBar/update/`.
2. **Verifikation** (optional, empfohlen): SHA256 des App-Zips gegen das
   `.sha256`-Asset prüfen. Mismatch → `failed`.
3. **Entpacken** App-Zip via `ditto -x -k` in ein Staging-Verzeichnis.
4. **Quarantäne entfernen:** `xattr -dr com.apple.quarantine <staged-app>`.
5. **In-Place-Swap (laufende App, APFS-sicher):** installierte App
   (`Bundle.main.bundlePath`) → `…/STTBar.app.old` verschieben, dann
   `ditto <staged-app> <app-dest>`. Der laufende Prozess behält über offene
   Inodes seine alte Binary, bis er beendet wird.
6. **Skripte einspielen:** `stt-scripts.zip` ins Install-Dir
   (`InstallPaths.resolve()`) entpacken. **Nutzerdaten werden nicht
   überschrieben:** `.env`, `prompts.json`, `profiles.json`,
   `active-prompt.txt`, `stt-replacements.tsv` bleiben unangetastet.
   Nur Skripte (`stt-*.sh`, `stt.zsh`, `stt-global.sh`, `docker-compose.yml`,
   `.env.example`) werden ersetzt und `chmod +x` gesetzt.
7. **Relaunch:** Ein nach `/tmp` geschriebenes Helper-Shell-Skript wird
   **detached** gestartet; es wartet auf das Beenden der App-PID, räumt
   `STTBar.app.old` auf und startet die App (`open`) — sofern der LaunchAgent
   sie nicht via `KeepAlive` schon neu gestartet hat. Danach `NSApp.terminate`.

### 3.4 LaunchAgent-Interaktion (Risiko)

Der LaunchAgent `de.projectmakers.sttbar` läuft mit `KeepAlive=true`. Da der
Bundle-Swap **vor** `terminate` passiert (Schritt 5), startet `launchd` beim
Beenden bereits die **neue** Binary vom Originalpfad neu. Der Helper darf daher
nicht zusätzlich `open` aufrufen, wenn der Agent aktiv ist (sonst Doppelstart).
**Schutzmaßnahmen:**
- Helper prüft, ob der Prozess innerhalb ~5 s von selbst (launchd) wieder läuft;
  nur falls nicht, `open`.
- Zusätzlich ein leichtgewichtiger **Single-Instance-Guard** beim App-Start
  (z. B. über einen benannten Lock/`NSRunningApplication`-Check), als
  Sicherheitsnetz gegen Doppelstart.

### 3.5 Fehlerbehandlung

- Netzwerk-/HTTP-Fehler, fehlende Assets, SHA-Mismatch, Entpack-/Kopier-Fehler
  → `updateState = .failed` mit lokalisierter Meldung; **kein** Teil-Swap bleibt
  zurück (bei Fehler vor Schritt 5 ist nichts verändert; schlägt Schritt 6 fehl,
  bleibt die neue App, Skripte ggf. teilweise — Meldung weist auf manuelles
  `install.sh` hin).
- Backup `STTBar.app.old` wird erst nach erfolgreichem Relaunch entfernt.

### 3.6 CI: Skripte ins Release-Asset

- **`scripts/prepare-release.sh`** baut zusätzlich `dist/stt-scripts.zip` in
  **install-fertigem Layout** (d. h. `stt-global-mac.sh` ist darin bereits als
  `stt-global.sh` enthalten, damit der Updater nur entpacken + `chmod` muss).
  Inhalt: `stt.zsh`, `stt-runtime.sh`, `stt-record.sh`, `stt-transcribe.sh`,
  `stt-postprocess.sh`, `stt-global.sh` (= mac), `docker-compose.yml`,
  `.env.example`, `stt-replacements.tsv` (nur als Vorlage; der Updater spielt
  diese Datei nicht über eine vorhandene Nutzerdatei). Plus
  `dist/stt-scripts.zip.sha256`.
- **`.releaserc.json`** → `@semantic-release/github`-Assets um
  `dist/stt-scripts.zip` (+ `.sha256`) erweitern.

---

## Versionierung & Deploy

- Semantic-Release berechnet die Version aus Conventional Commits. Sprach-
  schalter + Updater sind Features → **Minor-Bump (voraussichtlich 1.1.0)**.
- **Commit + Push auf `master` ist freigegeben** (vom Nutzer ausdrücklich
  gewünscht). Push triggert die CI → Semantic-Release baut + veröffentlicht das
  Release inkl. der neuen Assets (`STTBar.app.zip`, `stt-scripts.zip`).
- **Lokale Installation durch Claude** (nach erfolgreichem Build):
  1. Laufende Instanz **sauber stoppen** — LaunchAgent entladen
     (`launchctl unload ~/Library/LaunchAgents/de.projectmakers.sttbar.plist`)
     und ggf. laufenden Prozess beenden.
  2. `bash install.sh` (baut die App neu, kopiert Skripte, registriert Agent).
  3. App **wieder starten** (LaunchAgent lädt sie via `RunAtLoad`/`KeepAlive`;
     sonst `open`).
- Updater-Test (durch Nutzer): erfordert ein neueres Release als das installierte
  (z. B. ein anschließender Patch-Commit), um „Aktualisieren" real auszulösen.

## Teststrategie

- **`swift test --package-path macos-app`** — neue Unit-Tests:
  - `L()` liefert je Sprache den korrekten String; `Localization` published.
  - `setAppLanguage` setzt Whisper-Sprache + aktiviert den richtigen Prompt
    (mit gemocktem/temporärem Install-Dir).
  - Release-Asset-Parsing (App-/Skript-/SHA-Asset aus JSON), Versionsvergleich
    (bestehende Logik) inkl. „Aktualisieren sichtbar"-Bedingung.
  - Helper-Skript-Generierung (Pfade korrekt gequotet, Nutzerdaten-Ausnahmen).
- **Shell-Tests:** `for t in tests/*.sh; do bash "$t"; done` +
  `bash -n` der geänderten Skripte; `bash -n scripts/prepare-release.sh`.
- **Build-Check:** `bash macos-app/build-app.sh /tmp/sttbar-build-check`.
- **Manuell (Nutzer):** Sprachumschaltung in Menüleiste + Einstellungen prüft
  UI-Übersetzung + Whisper-Sprache + aktiven Prompt; Footer-/GitHub-Links;
  vollständiger Update-Flow gegen ein Test-Release.
- Der Bundle-Swap/Relaunch ist nicht voll unit-testbar; er wird über isoliert
  getestete Bausteine (Asset-Parsing, Helper-Generierung) + manuellen End-to-
  End-Test abgesichert.

## Datei-Änderungsübersicht

**Neu:**
- `macos-app/Sources/STTBar/Config/Localization.swift` (`AppLanguage`,
  `Localization`, `L(_:_:)`).
- `macos-app/Sources/STTBar/Core/Updater.swift` (Download/Swap/Relaunch) — oder
  als Erweiterung in `SettingsModel`.
- Tests unter `macos-app/Tests/STTBarTests/`.

**Geändert:**
- `Config/AppSettings.swift` — `appLanguage`; `SttMode` Labels DE/EN.
- `Config/SettingsModel.swift` — `setAppLanguage`, Updater-State/Logik,
  lokalisierte Meldungen.
- `UI/SettingsView.swift` — komplette Lokalisierung; Sprach-Picker;
  ProjectMakers-Footer; GitHub-/Releases-Links; Update-Buttons/-Zustände.
- `UI/MenuBarController.swift` — Lokalisierung; Sprach-Untermenü;
  `rebuild()` aufrufbar.
- `AppDelegate.swift` — `Localization`-Subscription → Menü-Rebuild;
  `onSetLanguage`-Closure; Single-Instance-Guard.
- `UI/PromptEditorView.swift`, `UI/PromptEditorWindow.swift`,
  `UI/StatusWindow.swift`, `UI/HudOverlay.swift`, `UI/SettingsWindow.swift`,
  `UI/HotkeyRecorder.swift`, `Core/HealthCenterModel.swift` — Lokalisierung.
- `scripts/prepare-release.sh` — `stt-scripts.zip` (+ `.sha256`).
- `.releaserc.json` — neue Release-Assets.
- `stt-global-mac.sh`, `stt-global.sh`, `stt-record.sh`, `stt-transcribe.sh`,
  `stt-postprocess.sh` — nutzersichtbare Strings auf Englisch.
- `tests/*.sh` — Assertions an englische Strings anpassen, falls nötig.
- `README.md` — auf Englisch.
