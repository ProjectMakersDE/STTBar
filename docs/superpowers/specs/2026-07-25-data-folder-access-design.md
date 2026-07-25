# Zugang zu den Daten-Ordnern und Aufräumen temporärer Dateien

Datum: 2026-07-25

## Problem

Die App legt ihre Daten an drei Stellen im Sandbox-Container ab, und es gibt praktisch
keinen Weg, dort hineinzusehen. Der einzige vorhandene Einstieg ist der Menüleisten-Punkt
"Logs öffnen" (`MenuBarController.swift:100` → `AppDelegate.swift:162`). Der ruft
`activateFileViewerSelecting` auf drei einzelne Dateien auf, die in zwei verschiedenen
Ordnern liegen — Finder öffnet daraufhin zwei Fenster mit je einer Datei-Auswahl, statt
einen Ordner zum Stöbern. Im Einstellungsfenster fehlt jeder Datei-Zugang.

Dazu kommt: temporäre Dateien wachsen unbegrenzt. `events.jsonl` liegt bei 337 KB,
`sttbar.log` bei 340 KB, `recording.wav` belegt nach jeder Aufnahme rund 1 MB. Es gibt
keinen Weg, das aus der App heraus aufzuräumen.

Unter der App-Sandbox liegen die Ordner unter
`~/Library/Containers/de.projectmakers.sttbar/Data/…` — ein Pfad, den man von Hand
nicht findet. Siehe auch die Notiz zur Container-Konfiguration in `a5a76f2`.

## Ist-Zustand der Ordner

| Bereich | Pfad (relativ zum Container-`Data/`) | Inhalt |
|---|---|---|
| Konfiguration | `Library/Application Support/STTBar/` | `.env`, `prompts.json`, `active-prompt.txt`, `stt-replacements.tsv`, `transcript-history.json`, `.env.backup-*` |
| Laufzeit | `Library/Application Support/STTBar/runtime/` | `recording.wav`, `events.jsonl`, `metrics.jsonl`, `status.json`, `phase`, `last-transcript.txt`, `recording.pid`, `recording.lock` |
| Logs | `Library/Logs/STTBar/` | `sttbar.log` |

`runtime` ist ein Unterordner der Konfiguration. Aufgelöst wird die Konfiguration über
`InstallPaths.resolve()`, die Laufzeit über `RuntimePaths.directory`, das Log-Verzeichnis
über `AppLogger.logURL.deletingLastPathComponent()`.

## Lösung

Drei Teile: ein Ordner-Modell, eine Löschfunktion mit Positivliste, und zwei
Einstiegspunkte (Einstellungen + Menüleiste).

### Ordner-Modell (`Core/DataLocations.swift`, neu)

Ein `enum DataLocation: CaseIterable` mit den Fällen `config`, `runtime`, `logs`. Jeder
Fall liefert Titel und Kurzbeschreibung über `L()` (deutsch/englisch) sowie die URL aus
den oben genannten bestehenden Auflösern. Neue Pfad-Logik entsteht nicht — die drei
Auflöser bleiben die einzige Quelle der Wahrheit.

Dazu eine Größenberechnung: rekursive Summe der Dateigrößen per
`FileManager.enumerator`, ausgewertet über `URLResourceValues.fileSize`.

Die Größe von `config` klammert den `runtime`-Teilbaum aus. Ohne das zählt die UI die
Laufzeitdaten zweimal und die drei angezeigten Zahlen ergeben in Summe keinen Sinn.
Umgesetzt als Ausschluss-URL-Parameter der Größenfunktion, nicht als Sonderfall im
Enum — dadurch bleibt die Funktion für sich testbar.

Ein nicht existierender Ordner liefert Größe 0 statt eines Fehlers, und die
Größenberechnung selbst legt keine Ordner an. Eine Ausnahme bleibt bestehen:
`AppLogger.logURL` erzeugt das Log-Verzeichnis als Seiteneffekt beim Zugriff
(`AppLogger.swift:7`). Das ist vorhandenes Verhalten und wird hier nicht geändert.

### Löschfunktion (`Core/TempFileCleanup.swift`, neu)

Löscht ausschließlich diese Dateien:

- aus dem Laufzeit-Ordner: `recording.wav`, `events.jsonl`, `metrics.jsonl`,
  `status.json`, `phase`, `last-transcript.txt`
- aus dem Log-Ordner: `sttbar.log`

Unangetastet bleiben `.env`, `prompts.json`, `active-prompt.txt`,
`stt-replacements.tsv`, `transcript-history.json`, sämtliche `*.backup-*`-Dateien sowie
`recording.pid` und `recording.lock`.

Die explizite Positivliste ist die eigentliche Sicherheitseigenschaft. Es gibt kein
`removeItem` auf ein Verzeichnis und kein Muster-Matching: selbst wenn eine
Pfadauflösung einmal danebengreift, kann die Funktion keine Konfigurationsdatei
entfernen.

Signatur (sinngemäß):

```swift
enum TempFileCleanup {
    struct Result { let removedFiles: Int; let freedBytes: Int64 }
    static func removableURLs(runtime: URL, logs: URL) -> [URL]
    static func run(runtime: URL, logs: URL) -> Result
}
```

Ordner-URLs werden hereingereicht, nicht intern aufgelöst — nur so ist die Funktion
gegen ein Temp-Verzeichnis testbar. Eine fehlende Datei ist kein Fehler und zählt
nicht mit. Die freigegebene Byte-Zahl wird vor dem Löschen ermittelt.

Der Aufrufer schreibt nach dem Lauf eine `AppLogger`-Zeile mit Anzahl und Bytes. Da
`AppLogger` die Log-Datei bei Bedarf neu anlegt, ist das gelöschte Log sofort wieder da
— mit dem Aufräum-Eintrag als erster Zeile.

### Sperre während eines laufenden Durchgangs

Aufräumen ist nur erlaubt, wenn `runner.state == .idle`. Nicht nur während der Aufnahme:
auch in den Phasen Whisper und LLM liest der Backend noch `recording.wav`, und
`status.json`/`phase` werden fortlaufend geschrieben. Ist der Zustand nicht `.idle`,
ist der Button deaktiviert und darunter steht ein Hinweis, warum — kein stilles
Nichtstun.

### Bestätigung

Vor dem Löschen ein `NSAlert` mit Abbrechen/Löschen. Das Log ist die Beweislage bei
einer Fehlersuche; einmal nachfragen ist angemessen. Nach dem Lauf meldet die Sektion
das Ergebnis ("3 Dateien, 1,3 MB freigegeben") und berechnet die Größen neu.

### UI: Sektion "Dateien & Speicher" im Allgemein-Tab

Neue `Section` in `GeneralTab` (`SettingsView.swift`), platziert zwischen
"Import/Export" und "Version". Pro Ordner eine Zeile mit:

- Titel und einzeiliger Beschreibung des Inhalts
- Größe, formatiert über `ByteCountFormatter`
- Button "Im Finder öffnen" → `NSWorkspace.shared.open(url)`

`open` statt `activateFileViewerSelecting`: gewünscht ist der Blick *in* den Ordner,
nicht eine Datei-Auswahl im Elternordner.

Unter jeder Zeile steht der vollständige Pfad als kleine, markierbare Textzeile
(`.font(.caption)`, `.textSelection(.enabled)`). Bei einem Sandbox-Container ist der
Pfad die eigentlich nützliche Information.

Darunter der Aufräum-Bereich: Button "Temporäre Dateien löschen", darunter je nach
Zustand der Sperr-Hinweis oder die Ergebnismeldung des letzten Laufs.

Die Größen werden auf einer Hintergrund-Queue berechnet und beim Erscheinen des Tabs
(`.onAppear`) sowie nach dem Aufräumen aktualisiert. Die Ordner sind klein, aber die
Form soll beim Tab-Wechsel nicht blockieren.

Der Zustand der Sektion (Größen, Sperre, letzte Meldung) lebt in einem kleinen
`ObservableObject` und nicht in `SettingsModel` — `SettingsModel.swift` liegt bereits
bei 419 Zeilen und trägt die `.env`-Verwaltung.

### Menüleiste

`MenuBarController.onOpenLogs` wird zu `onOpenDataFolder: ((DataLocation) -> Void)?`.
Statt des Eintrags "Logs öffnen" ein Untermenü "Dateien" mit drei Einträgen
(Konfiguration, Laufzeit, Logs); jeder öffnet genau einen Finder-Ordner. Damit
verschwindet auch das Zwei-Fenster-Verhalten des bisherigen Eintrags.

`AppDelegate.openLogs()` wird durch `openDataFolder(_:)` ersetzt. Aufräumen gibt es
nur in den Einstellungen, nicht im Menü — eine löschende Aktion gehört nicht in ein
Menü, das man im Vorbeigehen bedient.

## Tests

Neue Testdateien in `macos-app/Tests/STTBarTests/`:

`DataLocationsTests`
- Größensumme über ein angelegtes Temp-Verzeichnis mit Dateien bekannter Größe
- Ausschluss-Parameter: die Summe klammert einen Unterordner korrekt aus
- Nicht existierender Ordner liefert 0 und keinen Fehler

`TempFileCleanupTests`
- Temp-Verzeichnis mit allen löschbaren Dateien *und* `.env`, `prompts.json`,
  `transcript-history.json`, `.env.backup-1`, `recording.pid`, `recording.lock`:
  nach dem Lauf sind genau die Löschbaren weg, alles andere unverändert
- `freedBytes` entspricht der Summe der gelöschten Dateien, `removedFiles` der Anzahl
- Lauf auf einem leeren Verzeichnis liefert 0/0 und wirft nicht

Der bestehende Lauf `swift test --package-path macos-app` bleibt die Abnahme.

## Bewusst nicht dabei

- Löschen von `*.backup-*`-Dateien und `transcript-history.json`. Für den Verlauf gibt
  es bereits "Verlauf jetzt löschen" im Datenschutz-Tab; eine zweite Stelle dafür wäre
  eine Doppelung mit abweichendem Verhalten.
- Wahl oder Verschieben des Speicherorts.
- Datei-Vorschau innerhalb der App. Der Finder ist der Betrachter.
- Automatische Rotation oder Größenbegrenzung von `events.jsonl` und `sttbar.log`. Das
  ist ein eigenes Thema; hier geht es um den manuellen Zugang.
