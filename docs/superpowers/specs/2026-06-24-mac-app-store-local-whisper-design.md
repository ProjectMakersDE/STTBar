# STTBar → Mac App Store mit eingebautem lokalem Whisper

**Datum:** 2026-06-24
**Status:** Design abgenommen, bereit für Implementierungsplan

## Ziel

STTBar als bezahlte App (Einmalkauf **3,99 €**) im **Mac App Store** veröffentlichen
und dabei drei Transkriptions-Quellen anbieten: entfernter Server (wie heute),
selbst gehosteter Server (Anleitung → localhost) und ein **eingebautes lokales
Whisper** (WhisperKit/CoreML), das komplett offline läuft. Ein Erst-Start-Wizard
führt durch Berechtigungen und Einrichtung.

## Kernproblem (warum das kein Schalter ist)

Die heutige App ist eine **Developer-ID-App außerhalb des Stores**, läuft
**nicht** in der Sandbox und treibt ein **Shell-Backend** über `/bin/bash` an
(`SttRunner.swift:92` startet `stt-record.sh`/`stt-transcribe.sh`/
`stt-postprocess.sh`). Zusätzlich schreibt sie einen LaunchAgent
(`LaunchAgent.swift`) und hat einen eigenen Updater (`UpdateInstaller.swift`).

Der Mac App Store erzwingt die **App-Sandbox**. In der Sandbox sind verboten:
fremde Prozesse/Shell starten, Schreiben nach `~/Library/LaunchAgents`, Zugriff
auf `~/.local/share/stt` und beliebige `/tmp`-Pfade, sowie ein eigener
Self-Updater. Daher muss das gesamte Shell-Backend **nativ in Swift** nachgebaut
werden. Das ist die Hauptarbeit dieses Vorhabens.

## Abgenommene Entscheidungen

| Thema | Entscheidung |
|---|---|
| Vertrieb | Mac App Store, Einmalkauf 3,99 €, **kein StoreKit-Code** (reine Preisstufe) |
| Lokale Engine | **WhisperKit** (CoreML, MIT-Lizenz), Modelle on-demand von Hugging Face |
| Transkriptions-Quellen | 3 Modi: Server-URL · Selbst-hosten (Anleitung→localhost) · Eingebaut-lokal |
| Modell-Download | erscheint nur bei Auswahl „Eingebaut/lokal"; Größen-Dropdown + RAM-Empfehlung |
| LLM-Cleanup | bleibt optional, nativ via `URLSession`; Ollama/LM-Studio nur als externe Links |
| Text-Einfügen | **gestaffelt**: AX-API direkt → Unicode-Tippen → Clipboard+Cmd+V (mit Sichern/Wiederherstellen) |
| Onboarding | Erst-Start-Wizard, 6 Schritte |
| Min-Anforderung | Vorschlag macOS 14+, Apple Silicon empfohlen; Intel via Server/Self-host + kleine lokale Modelle |

## Lizenz-Lage (verifiziert)

- **WhisperKit** (Argmax Open-Source SDK, v1.0.0 seit Mai 2026): **MIT** → kommerzielle Nutzung erlaubt.
- **OpenAI Whisper** Code + Gewichte (inkl. `large-v3`, `large-v3-turbo`): **MIT** → in verkauften Produkten erlaubt.
- **whisper.cpp**: **MIT**.
- Einzige Pflicht: Lizenz-/Copyright-Hinweise in einem „Acknowledgements"-Bereich der App beilegen.

## Ziel-Architektur

Vollständig native, sandboxed Swift-App. Pipeline-Schritte ersetzen die Shell:

- **Aufnahme**: `AVAudioEngine`/`AVAudioRecorder` statt `stt-record.sh` (sox/ffmpeg). WAV/PCM in den Sandbox-Container.
- **Transkription (remote/self-host)**: `URLSession`-Multipart-POST an Whisper-kompatiblen Endpunkt statt `curl`.
- **Transkription (lokal)**: WhisperKit in-process; Modellverwaltung + Offline-Inferenz.
- **LLM-Cleanup**: `URLSession`-POST statt `stt-postprocess.sh` (optional).
- **Einfügen**: gestaffelte Strategie (siehe unten).
- **Laufzeitdateien**: aus `/tmp`/`~/.local/share/stt` in den Sandbox-Container (`~/Library/Containers/de.projectmakers.sttbar/Data/…`); `RuntimePaths.swift` umstellen.
- **Autostart**: LaunchAgent-Plist raus → `SMAppService` („Bei Anmeldung öffnen").
- **Self-Updater**: `UpdateInstaller.swift` entfernen (Updates macht der App Store).
- **Entitlements**: `com.apple.security.app-sandbox` an; `com.apple.security.network.client` dazu; Mikrofon (`device.audio-input`) + `automation.apple-events` bleiben.

## Arbeitspakete

### A. Sandbox-/App-Store-Umbau (Fundament)
- [ ] `app-sandbox` + `network.client` in `STTBar.entitlements` ergänzen, Mikro/Apple-Events behalten.
- [ ] Alle Shell-Aufrufe aus `SttRunner.swift` entfernen; Prozess-Spawning streichen.
- [ ] `RuntimePaths.swift` auf Container-Pfade umstellen (kein `/tmp`, kein `~/.local/share/stt`).
- [ ] `LaunchAgent.swift` durch `SMAppService`-Login-Item ersetzen.
- [ ] `UpdateInstaller.swift` + zugehörige UI entfernen.
- [ ] `Info.plist`: `LSUIElement`, `LSMinimumSystemVersion`, `ITSAppUsesNonExemptEncryption=false`, Usage-Strings (`NSMicrophoneUsageDescription`, `NSAppleEventsUsageDescription`).

### B. Native Aufnahme (ersetzt stt-record.sh)
- [ ] Mikrofon-Aufnahme via `AVAudioEngine`/`AVAudioRecorder` in den Container.
- [ ] Pegelmessung für die HUD-Waveform aus dem nativen Audiograph speisen (heute `AudioLevelReader`).
- [ ] Start/Stop/Cancel-Logik aus `RecordingToggle`/`SttRunner` beibehalten, nur nativ angebunden.

### C. Native Transkription (ersetzt stt-transcribe.sh)
- [ ] Mode „Server-URL" + „Self-host": Multipart-`URLSession`-Upload an Whisper-Endpunkt; URL/API-Key aus Settings (`EnvStore`/`AppSettings`).
- [ ] Mode „Lokal": WhisperKit als SwiftPM-Abhängigkeit einbinden; in-process Transkription.
- [ ] Modell-Download-Manager: Download von Hugging Face in den Container, Fortschritts-UI, Abbruch/Resume, Speicherort-Verwaltung.
- [ ] Modellgrößen-Dropdown (z.B. tiny / base / small / medium / large-v3-turbo) + freie Auswahl.
- [ ] RAM-Empfehlung via `ProcessInfo.processInfo.physicalMemory` (welche Größe ist sinnvoll).
- [ ] „Acknowledgements"-Ansicht mit MIT-Lizenztexten (WhisperKit + Whisper-Modelle).

### D. Natives Einfügen (gestaffelt, ersetzt Clipboard-only)
- [ ] **Stufe 1 — AX direkt**: fokussiertes Element via `AXUIElementCopyAttributeValue(kAXFocusedUIElementAttribute)`, Text via `kAXSelectedTextAttribute`/`kAXValueAttribute` setzen. Keine Zwischenablage.
- [ ] **Stufe 2 — Tippen**: Unicode-Events via `CGEventKeyboardSetUnicodeString` posten, falls Stufe 1 nicht greift. Keine Zwischenablage.
- [ ] **Stufe 3 — Clipboard-Fallback**: vorherigen `NSPasteboard`-Inhalt sichern → Cmd+V → alten Inhalt wiederherstellen.
- [ ] Bestehenden `NativePaste.swift` auf diese Staffelung umbauen; alle Wege nutzen dieselbe Accessibility-Berechtigung.

### E. LLM-Cleanup (ersetzt stt-postprocess.sh)
- [ ] Optionaler nativer `URLSession`-Call an konfigurierbaren LLM-Endpunkt; Prompt aus `PromptStore`/`active-prompt`.
- [ ] In Settings/Wizard nur **Links** zu Ollama / LM Studio (kein Bundling).

### F. Erst-Start-Wizard (neue UI, 6 Schritte)
- [ ] 1) Willkommen · 2) Mikrofon erlauben · 3) Accessibility erlauben (mit „Systemeinstellungen öffnen") · 4) Transkriptions-Quelle wählen (bei „lokal" optional Modell laden) · 5) Hotkey festlegen · 6) Fertig.
- [ ] Erkennung „Wizard schon durchlaufen?" (Settings-Flag); Wieder-Aufrufbarkeit aus Menü.

### G. Settings-UI
- [ ] Transkriptions-Quelle als 3-Modi-Auswahl; Modell-Dropdown + Download-Button nur bei „lokal".
- [ ] „Selbst hosten"-Button öffnet Schritt-für-Schritt-Anleitung (whisper.cpp-Server / faster-whisper / MLX-Server) und füllt URL-Feld mit `http://localhost:…`.
- [ ] Update-bezogene UI entfernen.

### H. Build-Pipeline / Signierung
- [ ] App-Store-Build: signiert mit **Apple Distribution** + Provisioning-Profil, Hardened Runtime + Sandbox.
- [ ] Auslieferungs-Artefakt als signiertes `.pkg` (Apple-Distribution-Installer) statt `.zip`.
- [ ] Upload via **Transporter**/Xcode Organizer/`xcrun altool`.
- [ ] Prüfen, ob ein dünnes Xcode-Projekt / `xcodebuild archive`-Wrapper um das SwiftPM-Target nötig ist (App-Store-Upload erwartet i.d.R. `.xcarchive`).
- [ ] Semantic-Release-Flow anpassen (heute baut er `STTBar.app.zip` für GitHub-Release; App-Store-Builds laufen getrennt).

### I. App Store Connect / Geschäftliches (kein Code)
- [ ] App-ID + Apple-Distribution-Zertifikat & Provisioning anlegen.
- [ ] App-Store-Connect-Eintrag: Bundle-ID, Kategorie, **Preisstufe 3,99 €**.
- [ ] **Datenschutz-Nutritionlabel** ausfüllen (Mikrofon-Nutzung; Offenlegung, dass im Server-Modus Audio an einen Endpunkt geht; lokaler Modus: keine Datenübertragung).
- [ ] **Datenschutzrichtlinie-URL** (Pflicht) bereitstellen.
- [ ] Export-Compliance bestätigen (`ITSAppUsesNonExemptEncryption=false`).
- [ ] **Screenshots** (z.B. 2560×1600), Beschreibung, Keywords, Support-URL.
- [ ] **Review-Notes**: Begründung der Accessibility-Nutzung (Auto-Einfügen ins fokussierte Feld) + Testanweisung für den Reviewer.

## Risiken & offene Punkte

1. **Accessibility-Auto-Einfügen ist das größte Genehmigungsrisiko.** Synthese von Tastatureingaben / AX-Schreibzugriff auf fremde Apps wird im Review geprüft. Absicherung: Clipboard-Fallback bleibt immer funktionsfähig; klare Review-Begründung; Funktion ist Kern des Nutzens (Diktat einfügen).
2. **Build-Pipeline-Umstellung** von SwiftPM/Developer-ID/`.zip` auf App-Store-`.pkg`/Apple-Distribution kann einen Xcode-Wrapper erfordern.
3. **Intel-Leistung**: CoreML läuft auf Intel, aber langsam bei großen Modellen. Erwartungshaltung in den Store-Texten managen; Intel praktisch über Server/Self-host + kleine lokale Modelle.
4. **Bestandskunden** der Developer-ID-Version migrieren **nicht** automatisch (andere Signatur/Distribution). Falls beide Tracks parallel laufen sollen, ist das ein eigenes Folgethema (in diesem Vorhaben nicht enthalten).
5. **Modell-Download-Größe**: `large-v3-turbo` (CoreML) ~1,5 GB. Erst-Nutzung braucht Internet + Speicherplatz; UX mit Fortschritt und klarer Größenangabe.

## Empfohlene Reihenfolge (Phasen)

1. **Phase 1 — Sandbox-Fundament**: Paket A. App startet sandboxed, ohne Shell, ohne LaunchAgent/Updater. (Hier kippt am meisten; früh validieren.)
2. **Phase 2 — Native Pipeline**: Pakete B + C-remote + E. Server-Modus läuft vollständig nativ.
3. **Phase 3 — Lokales Whisper**: Paket C-lokal (WhisperKit, Modellverwaltung).
4. **Phase 4 — Einfügen & Wizard**: Pakete D + F + G.
5. **Phase 5 — Auslieferung**: Pakete H + I, App-Review.

## Nicht im Scope (YAGNI)

- Kein StoreKit/In-App-Kauf (reiner Einmalkauf über Preisstufe).
- Kein Bundling von LLMs oder LLM-Servern (nur Links).
- Keine parallele Developer-ID-Direktversion (separates Folgethema, falls gewünscht).
- Kein gebündeltes Whisper-Modell in der App (on-demand-Download bevorzugt).
