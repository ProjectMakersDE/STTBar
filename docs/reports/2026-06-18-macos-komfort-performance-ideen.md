# STT macOS Komfort- und Performance-Report

Datum: 2026-06-18  
Scope: Analyse und Ideensammlung fuer die macOS-Nutzung von STT-SpeachToTerminal. Keine Umsetzung, keine Produktcode-Aenderung.

## Kurzfazit

Das Projekt ist auf dem Mac bereits deutlich weiter als ein reines Script-Tool: Es gibt mit `STTBar.app` eine native Menueleisten-App, globale Hotkeys, HUD, Prompt-Verwaltung, `.env`-Editor, LaunchAgent, stabile lokale Signierung und eine robuste Shell-Pipeline mit Clipboard-Fallback, LLM-Postprocessing, Ersatzwoerterbuch und Logging.

Der naechste grosse Qualitaetssprung liegt weniger in neuen Einzel-Features, sondern in Produktisierung: gefuehrtes Setup, Health-Checks, klare Fehlerursachen, kontrollierbare Aufnahmezustaende, Hotkey-Konfliktvermeidung, ein Vokabular-Editor und bessere Performance-Messung. Danach lohnt sich die schrittweise Verlagerung kritischer Mac-Funktionen aus Shell/AppleScript in die native App.

## Gepruefte Evidenz

- Repo-Struktur und zentrale Dateien gelesen: `install.sh`, `stt-global-mac.sh`, `stt-record.sh`, `stt-transcribe.sh`, `stt-postprocess.sh`, `stt.zsh`, `hammerspoon-stt.lua`, `macos-app/Sources/STTBar/*`, vorhandene Design-/Plan-Dokumente.
- Lokaler Installationsstand geprueft: `STTBar.app` liegt unter `/Applications/STTBar.app`, LaunchAgent `de.projectmakers.sttbar` ist geladen, `STTBar` lief zum Analysezeitpunkt.
- Zum Analysezeitpunkt lief ein `rec`-Prozess fuer `/tmp/stt-recording.wav`; ich habe ihn nicht beendet.
- Installierte Scripts sind mit dem Repo identisch: `stt-global.sh`, `stt-record.sh`, `stt-transcribe.sh`, `stt-postprocess.sh`, `hammerspoon-stt.lua`, `stt.zsh`. Nur `stt-replacements.tsv` unterscheidet sich, vermutlich als lokale persoenliche Wortliste.
- Lokale `stt-replacements.tsv`: Repo 6 Zeilen, installierte Kopie 17 Zeilen.
- Verifikation: `bash tests/test-postprocess-prompt-file.sh` bestanden.
- Verifikation: `swift test` in `macos-app/` bestanden, 13 Tests, 0 Fehler.
- Verifikation: `bash -n install.sh stt-global.sh stt-global-mac.sh stt-record.sh stt-transcribe.sh stt-postprocess.sh tests/test-postprocess-prompt-file.sh` ohne Syntaxfehler.
- `shellcheck` ist auf diesem Mac nicht installiert.

## Aktueller Stand

### Staerken

- Native Mac-App statt reiner Hammerspoon-Abhaengigkeit: Menueleisten-Icon, globale Hotkeys, Settings, Prompt-Editor und HUD sind bereits vorhanden.
- Der bewusste Shell-Backend-Vertrag ist einfach und stabil: App startet `stt-global.sh`, Shell kuemmert sich um Aufnahme, Whisper, Postprocessing und Paste.
- Drei Modi sind bereits vorgesehen: bereinigt, roh, Englisch.
- `.env` bleibt zentrale Konfiguration, und `EnvStore` versucht Kommentare und unbekannte Keys zu erhalten.
- `PromptStore` hat ein sinnvolles Live-Modell: Prompts in `prompts.json`, aktive Datei in `active-prompt.txt`, naechster Lauf verwendet den aktiven Prompt.
- Bluetooth-Profilwechsel wird auf macOS bereits vermieden, sofern kein explizites Audiogeraet gewaehlt ist.
- Postprocessing hat sinnvolle Fallbacks: Bei LLM-Fehlern bleibt der rohe Whisper-Text erhalten und Ersatzwoerter werden weiter angewendet.
- Postprocess-Logging speichert Metadaten ohne Rohtext. Das ist fuer Debugging nuetzlich und datenschutzfreundlich.
- `build-app.sh` signiert mit stabiler lokaler Identitaet, damit Accessibility-/Automation-Freigaben Rebuilds eher ueberleben.

### Hauptluecken

- Der Installer verlangt aktuell noch `Hammerspoon.app`, obwohl STTBar der bevorzugte native Frontend-Pfad ist. Das ist fuer eine echte Mac-App-Erfahrung widerspruechlich.
- Fehler werden im UI nur sehr grob sichtbar. Der Nutzer sieht meistens Icon/HUD/Notification, aber nicht die konkrete Ursache: Server offline, LM Studio Timeout, keine Mic-Berechtigung, leere Aufnahme, fehlende Automation, kaputter Pfad.
- Health-Checks fuer Whisper, LM Studio, `.env`, Prompt-Datei, Ersatzwoerterbuch, Permissions und LaunchAgent existieren nicht als zentrale In-App-Diagnose.
- Die Swift-App portiert nicht alle Resilienzdetails des Hammerspoon-Fallbacks. Insbesondere Start-Watchdog, Stale-Task-Reset und App-seitiges Logging sind im Swift-Pfad nur teilweise oder gar nicht vorhanden.
- `/tmp/stt-recording.pid`, `/tmp/stt-recording.wav` und `/tmp/stt-overlay-phase` sind globale Dateinamen. Das ist einfach, aber kollisions- und stale-state-anfaellig, besonders wenn Terminal-Widget und App parallel genutzt werden.
- Hotkey-Konflikte werden nicht sichtbar gemacht. Wenn Carbon die Registrierung ablehnt, gibt es keine klare Rueckmeldung im UI.
- Die Settings schreiben `.env` direkt bei jeder Texteingabe. Das ist bequem, aber riskant bei halb getippten URLs/Modellnamen und schwer rueckgaengig zu machen.
- Die HUD-Positionen sind inkonsistent: Das UI und die Specs sprechen von 8 Anchors, aber mehrere Anchors mappen im Code auf dieselbe Position. Der `edges`-Array in `DisplayTab` wirkt ungenutzt.
- `stt-transcribe.sh` hat ein festes `--max-time 30`, waehrend lange Diktate und lokale/remote Server deutlich variieren koennen.
- Doku und Installer-Ausgaben sind nicht voll synchron: ältere Dokumente beschreiben skhd, neuere STTBar; teils steht `~/Applications`, die Installation bevorzugt aber `/Applications`; die macOS-Usage-Ausgabe nennt weiterhin Hammerspoon-Autostart.

## Priorisierte Roadmap

### P1 - Setup-Assistent und Health Center

Ziel: Ein neuer Mac-Nutzer soll nach der Installation sofort sehen, ob alles einsatzbereit ist.

Ideen:

- In `STTBar` ein Fenster "Status & Diagnose" einbauen.
- Ampelstatus fuer:
  - STTBar laeuft.
  - LaunchAgent geladen und Pfad korrekt.
  - Scripts im Installationsordner vorhanden und ausfuehrbar.
  - `sox`/`rec`, `curl`, `jq` im PATH des LaunchAgent-Kontexts erreichbar.
  - Mikrofonberechtigung vorhanden.
  - Accessibility vorhanden.
  - Automation/System Events vorhanden oder native Paste-Alternative aktiv.
  - Whisper-URL erreichbar.
  - LM-Studio-URL erreichbar, falls Postprocessing aktiv ist.
  - Eingestelltes Whisper-Modell plausibel.
  - Eingestelltes LLM-Modell plausibel.
  - `active-prompt.txt` lesbar.
  - `stt-replacements.tsv` lesbar.
  - Kein stale PID / keine haengende Aufnahme.
- Buttons: "Whisper testen", "LM Studio testen", "Mikrofon-Test", "Testaufnahme 3 Sekunden", "Testtext in Zwischenablage legen", "Diagnosebericht kopieren".
- Diagnosebericht ohne Rohdiktate: Versionen, Pfade, Berechtigungen, letzte Fehlercodes, Laufzeiten, Dateigrössen, Modellnamen, aber keine aufgenommenen Inhalte.

Warum zuerst: Das spart bei jedem Mac-Problem Zeit und macht das Tool fuer Nicht-Entwickler benutzbar.

Akzeptanzkriterien:

- Nach einem frischen Install zeigt STTBar klar, welche Schritte noch fehlen.
- Bei kaputter Whisper-URL ist die Ursache vor der ersten Aufnahme sichtbar.
- Bei fehlender Paste-Berechtigung bleibt der Text in der Zwischenablage und das UI sagt exakt, was fehlt.

### P1 - Installer wirklich STTBar-first machen

Ziel: STTBar ist die primaere Mac-Erfahrung; Hammerspoon ist nur Fallback.

Ideen:

- `Hammerspoon.app` aus den Pflicht-Dependencies entfernen.
- Dependency-Check in Pflicht und Fallback trennen:
  - Pflicht fuer STTBar: Swift Toolchain oder vorgebautes App-Bundle, `sox`, `rec`, `curl`, `jq`.
  - Optional fuer Fallback: Hammerspoon.
- Installationsausgabe korrigieren: Wenn STTBar aktiv ist, keine Hammerspoon-Autostart-Zeile drucken.
- Doku konsolidieren: skhd-Dokumente als historische Designs markieren oder in einen Archiv-Ordner verschieben.
- `CLAUDE.md`, STTBar-Spec und `install.sh` auf denselben Installationsort bringen: entweder "bevorzugt `/Applications`, fallback `~/Applications`" oder konsequent per User.
- In der App ein "Fallback-Frontend" anzeigen: STTBar aktiv, Hammerspoon block entfernt, Hammerspoon-Fallback verfügbar/nicht verfügbar.

Warum wichtig: Der Installer ist die erste User Experience. Wenn dort Hammerspoon verlangt wird, obwohl die native App ihn ersetzen soll, wirkt das Tool unfertig.

### P1 - Fehlerursachen sichtbar machen

Ziel: Nicht nur "Error", sondern "warum" und "was jetzt".

Ideen:

- Neben `STT_PHASE_FILE` eine strukturierte Statusdatei schreiben, z. B. `stt-status.json`.
- Shell-Scripts melden Ereignisse:
  - `recording_started`
  - `recording_empty`
  - `whisper_request_started`
  - `whisper_unreachable`
  - `whisper_http_error`
  - `whisper_empty_text`
  - `postprocess_started`
  - `postprocess_timeout`
  - `postprocess_fallback`
  - `paste_failed_clipboard_ok`
  - `done`
- STTBar zeigt den letzten Fehler im Menue und Settings-Tab an.
- Menuepunkte:
  - "Letzten Fehler anzeigen"
  - "Letztes Transkript erneut einfuegen"
  - "Letztes Transkript kopieren"
  - "Logs oeffnen"
- Fehler-HUD nicht nur roter Punkt, sondern kurze native Notification mit eindeutiger Ursache.

Akzeptanzkriterien:

- Wenn LM Studio nicht erreichbar ist, steht dort "LLM nicht erreichbar, Rohtext/Ersatzwoerter verwendet" statt generischem Fehler.
- Wenn Accessibility fehlt, steht dort "Text liegt in Zwischenablage, Einfuegen per Cmd+V oder Accessibility aktivieren".
- Wenn `rec` sofort beendet, steht dort "Aufnahme konnte nicht gestartet werden, pruefe Mikrofon/sox".

### P1 - Aufnahme sicherer und kontrollierbarer machen

Ziel: Der Nutzer weiss immer, ob gerade aufgenommen wird, und kann eine haengende Aufnahme sauber kontrollieren.

Ideen:

- Menuepunkt "Aufnahme abbrechen" ohne Transkription.
- Menuepunkt "Aufnahme stoppen und transkribieren".
- Sichtbarer Timer im HUD oder Menue.
- Optionales Max-Dauer-Limit, z. B. 5, 10, 20 Minuten.
- Optional Push-to-talk-Modus statt Toggle-Modus.
- Stale-PID-Erkennung periodisch in STTBar, nicht erst beim naechsten Hotkey.
- Wenn `rec` laeuft, aber STTBar gerade keinen passenden State kennt: Warnung und "aufräumen"-Aktion anbieten.
- Namespaced Temp-Verzeichnis, z. B. `$TMPDIR/de.projectmakers.stt/recording.wav`, plus Lockfile.
- Terminal-Widget und STTBar sollten parallele Nutzung erkennen und freundlich blockieren.

Begruendung aus aktuellem Zustand: Zum Analysezeitpunkt lief ein `rec`-Prozess. Das kann korrekt sein, aber ohne UI-Kontrolle ist eine haengende Aufnahme schwer einzuschaetzen.

### P1 - Vokabular-/Ersatzwoerter-Editor

Ziel: Eigennamen, Projektnamen, Domains und Fachbegriffe sollen ohne Shell-Datei-Editieren pflegbar sein.

Ideen:

- Neuer Settings-Tab "Woerterbuch".
- Tabelle fuer `von -> nach`, aktiv/inaktiv, Kommentar, Kategorie.
- Vorschau: Rohtext eingeben, Ergebnis sehen.
- Validierung:
  - keine leeren linken Seiten.
  - Warnung bei sehr allgemeinen Begriffen.
  - Fallbeispiele fuer Wortgrenzen.
- Import/Export TSV.
- Backup vor Aenderungen.
- Projektprofile, z. B. "horizOn", "BodySeasons", "Allgemein".
- Anzeige, ob installierte Datei vom Repo-Template abweicht.

Warum wichtig: Die installierte Ersatzliste ist bereits lokal gewachsen. Das ist ein klarer Hinweis, dass diese Datei ein echtes Produktfeature ist, nicht nur Konfiguration.

### P1 - Hotkey-Konflikte und Modus-UX

Ziel: Die drei Modi sollen sich sicher anfuehlen und nicht still ausfallen.

Ideen:

- Beim Registrieren eines Hotkeys Rueckmeldung speichern: registriert, Konflikt, ungueltig.
- Konfliktanzeige direkt im Shortcuts-Tab.
- Duplikate zwischen Full/Raw/English verhindern.
- Systemnahe Kombinationen warnen, z. B. bekannte macOS-/Spotlight-/Input-Source-Shortcuts.
- "Zuruecksetzen auf Standard" pro Modus.
- Modus im Menue klar als aktueller Stopp-Modus erklaeren: Die Taste, mit der gestoppt wird, bestimmt die Ausgabe.
- Optional Modus-Schnellumschaltung im Menue: Default-Modus fuer naechsten Stopp.

Aktuelles Risiko: `RegisterEventHotKey` kann fehlschlagen; der Code ignoriert Fehlschlaege ausser, dass der Hotkey nicht in `idToMode` landet.

### P2 - Performance messbar machen

Ziel: Nicht raten, sondern wissen, wo Latenz entsteht.

Ideen:

- Lokale Metriken pro Lauf:
  - Aufnahme-Dauer.
  - WAV-Groesse.
  - Whisper-Request-Dauer.
  - Whisper-Textlaenge.
  - Postprocess-Dauer.
  - Output-Laenge.
  - Paste-Erfolg.
- In der Menueleiste: "Letzter Lauf: 2.8s Whisper, 4.1s LLM".
- In Settings: kleine Verlaufsliste der letzten 20 Laeufe ohne Rohtext.
- Schwellwerte:
  - Warnung bei LLM > 20s.
  - Warnung bei Whisper > 30s.
  - Empfehlung "Raw-Modus nutzen" bei langsamer LLM-Verbindung.
- `STT_TRANSCRIBE_TIMEOUT` konfigurierbar machen statt fixer 30 Sekunden.
- Automatische Timeout-Empfehlung aus Aufnahme-Dauer ableiten.

Warum wichtig: Die aktuellen Postprocess-Logs zeigen bereits Start/Success und Laengen. Diese Idee erweitert das auf die gesamte Pipeline.

### P2 - Schnellere Mac-Pipeline

Ziel: Weniger Prozess-Overhead und weniger AppleScript.

Optionen, konservativ bis ambitioniert:

1. Shell behalten, aber Events strukturierter machen.
   - Schnell umzusetzen.
   - Geringes Risiko.
   - Gute Zwischenstufe fuer Diagnose.

2. Paste nativ in STTBar ausfuehren.
   - Shell schreibt Text in eine Ergebnisdatei oder stdout.
   - App setzt NSPasteboard und sendet Paste per Accessibility/CGEvent.
   - Reduziert `osascript`/System Events-Abhaengigkeit.
   - Ermoeglicht bessere Fehlererkennung.

3. Audioaufnahme nativ mit `AVAudioEngine`.
   - Reduziert SoX/CoreAudio-Shell-Abhaengigkeit.
   - Bessere Live-Pegel und Mic-Auswahl.
   - Mehr App-Code, hoeheres Risiko.
   - Shell-Fallback sollte bleiben.

4. Transkription/Postprocessing per `URLSession`.
   - Kein `curl`/`jq` im Mac-App-Pfad.
   - Native Timeouts, bessere HTTP-Fehler, strukturierte Logs.
   - Shell-Pfad bleibt fuer Terminal/Linux.

Empfehlung: Erst Option 1 und 2, danach entscheiden, ob AVAudioEngine/URLSession den Mehrwert rechtfertigen.

### P2 - Server- und Modellprofile

Ziel: Nutzer wechseln nicht per `.env`, sondern per Profil.

Ideen:

- Profile fuer Whisper:
  - Lokal.
  - AI-Server.
  - Schneller Modus.
  - Qualitaetsmodus.
- Profile fuer Postprocessing:
  - Raw.
  - Qwen lokal.
  - OpenAI-kompatibel.
  - Englisch-Uebersetzung.
- Pro Profil: URL, Modell, Sprache, Timeout, Postprocess an/aus.
- "Profil testen" mit Health-Check.
- "Beim Fehler automatisch Raw-Fallback" als Option.
- Anzeige, welches Profil gerade aktiv ist.

Warum wichtig: Der aktuelle `.env`-Stand hat bereits viele Parameter. Profile machen das bedienbar und reduzieren Fehlkonfigurationen.

### P2 - Prompt-Workflow professionalisieren

Ziel: Prompts sind ein produktiver Bestandteil des Tools, nicht nur Textdateien.

Ideen:

- Prompt-Versionen mit Datum/Kommentar.
- "Prompt duplizieren und testen".
- Integrierte Testseite aus `stt-postprocess-eval.html` oder eine native Mini-Eval.
- Golden-Samples mit Bewertung:
  - Faktentreue.
  - Laengenveraenderung.
  - entfernte Floskeln.
  - korrekt erhaltene Dateinamen/URLs.
- Unterschiedsanzeige zwischen Rohtext und bereinigtem Text.
- Prompt v3 als auswählbares Profil, falls der aktive Default davon abweicht.
- Schutz gegen versehentlich leere aktive Prompts.

Begruendung: Es gibt bereits Eval-Berichte mit messbarer Qualitaet. Daraus kann ein nutzbarer Prompt-Qualitaetsworkflow werden.

### P2 - HUD und Menueleiste polieren

Ziel: Das Tool soll sich wie eine kleine native Mac-App anfuehlen.

Ideen:

- HUD-Timer und Phasenlabel optional anzeigen: "Aufnahme", "Whisper", "LLM".
- Live-HUD-Vorschau im Anzeige-Tab.
- Echte 8 eindeutige HUD-Positionen oder UI auf die tatsaechlichen Positionen reduzieren.
- HUD fuer mehrere Monitore: aktueller Bildschirm der aktiven App statt immer `NSScreen.main`.
- Menuebar-Icon mit Tooltip: aktueller Zustand, aktiver Modus, letzter Lauf.
- "Nicht stoeren"/Silent Mode.
- Optionaler Sound oder Haptic-artiger Systemton bei Start/Stop/Done.
- Anzeige bei sehr leiser Aufnahme: "Mikrofonpegel niedrig".

Aktueller konkreter Befund: Einige `HudAnchor`-Faelle liefern dieselben Koordinaten. Das sollte entweder korrigiert oder im UI vereinfacht werden.

### P2 - Verlauf und Datenschutzmodus

Ziel: Ergebnisse sind rettbar, aber Datenschutz bleibt kontrollierbar.

Ideen:

- Verlauf der letzten N Transkripte optional.
- Standard: aus oder nur "letztes Transkript" im Speicher.
- Wenn aktiviert: lokale Speicherung mit Auto-Loeschen nach X Stunden/Tagen.
- Sensitive Mode: keine Speicherung, keine Text-Notifications, nur Clipboard.
- "Letztes Transkript erneut einfuegen" auch ohne persistenten Verlauf.
- Export nur bewusst.

Warum wichtig: Das Tool diktiert potenziell sensible Inhalte. Komfort darf nicht unkontrolliert Rohtext speichern.

### P2 - Konfiguration sicherer machen

Ziel: `.env` bleibt lesbar, aber UI-Aenderungen werden kontrollierter.

Ideen:

- Settings mit "Anwenden" oder Debounce statt Speichern bei jedem Tastenanschlag.
- Vor dem Speichern validieren:
  - URL-Schema.
  - Modellname nicht leer.
  - Timeout numerisch.
  - Provider passend zur URL.
- Vor Aenderungen Backup der `.env`.
- Rueckgaengig machen fuer letzte Aenderung.
- Speichern sichtbar bestaetigen.
- Fehler beim Speichern nicht still verschlucken.
- Quotes/Escaping in `EnvStore` robuster machen.

Aktuelles Risiko: `SettingsModel` schreibt bei jedem `didSet`; `try?` verdeckt Schreibfehler.

### P3 - Distribution und Updates

Ziel: Installation und Aktualisierung sollen weniger Entwicklerwissen brauchen.

Ideen:

- Vorgebautes `STTBar.app` als Release-Artefakt.
- Optional DMG oder ZIP.
- `install.sh` nutzt vorgebautes Bundle, falls kein Swift Toolchain vorhanden ist.
- In-App-Version und "Nach Updates suchen".
- Sparkle-Update spaeter, wenn Distribution wichtiger wird.
- Signatur-/TCC-Hinweise in einem klaren Troubleshooting-Dokument.
- Migrationen fuer `prompts.json`, `.env` und `stt-replacements.tsv`.

Kurzfristig wichtiger als Auto-Update: Ein reproduzierbarer Build und klare "installierte Version entspricht Commit X"-Anzeige.

### P3 - Tests und QA ausbauen

Ziel: Mac-Regressionen frueher finden.

Ideen:

- Unit-Tests fuer:
  - `HotkeyManager`-nahe Validierung ohne Carbon-Registrierung.
  - `HudAnchor` eindeutige Positionen.
  - `LaunchAgent`-Plist-Erzeugung.
  - `SettingsModel` schreibt erwartete `.env`-Keys.
  - `.env`-Escaping.
- Shell-Tests fuer:
  - Raw-Modus wendet Ersatzwoerter an, ruft aber kein LLM.
  - `STT_TRANSCRIBE_TIMEOUT`.
  - Fehlerstatusdatei.
  - `/tmp`-Namespace/Locking.
- Manuelle Mac-QA-Checkliste:
  - Erstinstallation.
  - fehlende Accessibility.
  - fehlende Automation.
  - fehlendes Mikrofon.
  - Whisper offline.
  - LM Studio offline.
  - Hotkey-Konflikt.
  - Bluetooth-Headset aktiv.
  - externe USB-Mic.
  - zweiter Monitor.

## Konkrete Feature-Ideen als Backlog

1. In-App Health Center mit Ampeln und Diagnosebericht.
2. Installer STTBar-first, Hammerspoon nur optional.
3. Strukturierte Status-/Fehlerdatei zwischen Shell und App.
4. Menuepunkt "Aufnahme abbrechen".
5. Menuepunkt "Letztes Transkript erneut einfuegen".
6. Hotkey-Konflikte im Shortcuts-Tab anzeigen.
7. Vokabular-Editor fuer `stt-replacements.tsv`.
8. Profil-System fuer Whisper/LLM/Modi.
9. Konfigurierbarer Transcribe-Timeout.
10. Vollstaendige Laufzeitmetriken pro STT-Lauf.
11. HUD-Timer und optionales Phasenlabel.
12. Echte 8 eindeutige HUD-Positionen oder UI vereinfachen.
13. Multi-Monitor-HUD an aktiver App ausrichten.
14. Native Paste aus STTBar statt `osascript`.
15. App-seitiges Log ohne Rohtext.
16. Settings mit Validierung und Apply/Undo.
17. Prompt-Versionen und Mini-Eval im UI.
18. Datenschutzmodus fuer Verlauf/Notifications.
19. Namespaced Temp-/Lock-Verzeichnis statt globaler `/tmp/stt-*` Dateien.
20. Stale-Recording-Recovery mit periodischem Watchdog.
21. "Mikrofonpegel zu niedrig"-Warnung.
22. "Server vorwaermen" oder "Modell warm halten"-Option.
23. Automatischer Raw-Fallback bei langsamen/fehlerhaften LLMs.
24. Import/Export fuer Settings, Prompts und Vokabular.
25. Version/Commit-Anzeige fuer installierte App und Scripts.

## Empfohlene Reihenfolge

### Phase 1 - Alltagssicherheit

1. Installer STTBar-first korrigieren.
2. Fehlerstatus zwischen Shell und App strukturieren.
3. Health Center mit Permissions/Pfaden/Servern bauen.
4. Aufnahme abbrechen, stale Recording erkennen, letzter Text erneut einfuegen.
5. Hotkey-Konflikte sichtbar machen.

Ergebnis: Das Tool fuehlt sich stabil und beherrschbar an.

### Phase 2 - Nutzerkomfort

1. Vokabular-Editor.
2. Profile fuer Server/Modelle/Modi.
3. Settings validieren und sicher speichern.
4. HUD-Positionen korrigieren, Timer/Preview ergaenzen.
5. Doku/Installer-Ausgaben konsolidieren.

Ergebnis: Weniger `.env`-Editieren, weniger Unsicherheit, bessere Mac-App-Anmutung.

### Phase 3 - Performance

1. End-to-End-Metriken fuer Aufnahme, Whisper, LLM, Paste.
2. Timeout- und Fallback-Strategien anhand realer Daten einstellen.
3. Native Paste in STTBar.
4. Optional native HTTP-Requests per `URLSession`.
5. Erst danach ueber native Audioaufnahme nachdenken.

Ergebnis: Latenz wird sichtbar und gezielt reduzierbar.

### Phase 4 - Produktreife

1. Vorgebaute App/Release-Artefakte.
2. Versions-/Commit-Anzeige.
3. Migrationen fuer lokale Daten.
4. Datenschutz-/Verlaufsmodus.
5. Erweiterte Mac-QA.

Ergebnis: Das Projekt wird von einem starken lokalen Tool zu einer sauberen Mac-App.

## Nicht priorisieren

- Sofortige komplette Swift-Neuschreibung der gesamten Pipeline. Der Shell-Backend-Vertrag funktioniert und ist als Fallback wertvoll.
- Auto-Update vor Health Center und Diagnose. Updates helfen wenig, wenn Fehlerursachen weiter unsichtbar bleiben.
- Mehr Prompt-Komplexitaet ohne Eval/Preview. Prompts sind stark, aber nur, wenn Qualitaet messbar bleibt.
- Hammerspoon weiter ausbauen. Er sollte Fallback bleiben, nicht der Hauptpfad.

## Naechster sinnvoller Arbeitsschnitt

Der beste erste Umsetzungsschnitt waere ein kleiner, aber spuerbarer Mac-Stabilitaetsblock:

1. `check_deps_macos` so umbauen, dass Hammerspoon nur optional ist.
2. Installationsausgabe fuer STTBar korrigieren.
3. Strukturierte `stt-status.json` einfuehren.
4. STTBar-Menuepunkt "Letzten Fehler anzeigen" und "Aufnahme abbrechen".
5. Stale-Recording-Watchdog aus Hammerspoon in Swift nachziehen.

Das ist eng genug fuer einen sauberen PR, verbessert die reale Mac-Nutzung sofort und legt die Grundlage fuer Health Center, Performance-Metriken und bessere UI.
