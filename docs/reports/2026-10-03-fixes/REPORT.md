# STTBar: Korrekturen für Release und App Review

Stand: 3. Oktober 2026. Grundlage: bestätigte Befunde aus dem
[Produktreview vom 2. Oktober](../2026-10-02-produkt-review/REPORT.md) und Apples
Ablehnung von 1.7.0 (22).

Die bestätigten Fehler wurden im Quellcode korrigiert. China mainland wurde mit
Daniels ausdrücklicher Auswahl in App Store Connect ausgeschlossen. Die übrigen
174 Regionen bleiben ausgewählt. Nach Speichern und erneutem Laden zeigt die
Verfügbarkeitsseite weiterhin 174 Regionen. Ein neuer Build und seine
Wiedereinreichung sind abgeschlossen: **1.7.0 (23) wartet auf Apples Prüfung**.
Eine Freigabe durch Apple ist damit noch nicht erfolgt.

## Umgesetzte Korrekturen

| Bereich | Verhalten nach der Korrektur | Prüfung |
|---|---|---|
| Sensitive Mode | Datenschutz lässt sich unabhängig von Server-Entwürfen anwenden. Fehlgeschlagene Übernahme zeigt Fehler, wirksamen Zustand und noch nicht angewendete Änderungen. | Isolierte SettingsModel-Tests mit ungültigen Server-/Datenschutzwerten und simulierten Dateifehlern. |
| Audio | Jeder Lauf besitzt eine UUID-WAV. Erfolg, leeres Ergebnis, Start-/Transkriptionsfehler und Abbruch löschen diese Datei. Später Abschluss eines alten Laufs kann keine neue Aufnahme löschen oder einfügen. | Synthetische Recorder-/ASR-/LLM-Tests einschließlich verspäteter Completion nach Abbruch. |
| Datenschutz während eines Laufs | Sensitive Mode beim Start bleibt für Ergebnis, Verlauf und manuelles Kopieren wirksam. Aktivieren vor dem Einfügen wird zusätzlich berücksichtigt. | Privacy-Snapshot-, Runner- und Clipboard-Tests; AppDelegate-Hooks unabhängig geprüft. |
| Neustart | Verwaiste native UUID-Aufnahmen werden vor dem Recorder-Start entfernt. Im normalen App-Verzeichnis wird auch die alte `recording.wav` entfernt; ein benutzerdefinierter Runtime-Pfad behält den Legacy-Dateinamen zum Schutz möglicher Shell-Recorder. | Cleanup-Tests mit Konfigurationsdateien, Unterordnern, Symlinks und Legacy-Datei. |
| Verlauf | Abgelaufene Texte werden beim Laden, nach Änderungen der Datenschutzoptionen und regelmäßig während der Laufzeit entfernt. Deaktivierter Verlauf und Sensitive Mode verhindern diese Bereinigung nicht. | Tests mit injizierter Uhr, eigenen Preferences und Dateien. |
| Bereinigung | Der Raw-Fallback-Schalter wird von der nativen Pipeline eingehalten. Ohne Fallback wird ein LLM-Fehler gemeldet. | Pipeline-Tests mit absichtlich fehlschlagendem LLM. |
| Englisch-Modus | Fehlende oder fehlgeschlagene Übersetzung erzeugt einen verständlichen Fehler; unübersetzter Rohtext wird nicht als Englisch-Ergebnis eingefügt. | Tests für deaktivierten LLM und Übersetzungsfehler. |
| Lokale Sprache | Gewählte Sprache und bewusste Auto-Erkennung werden an WhisperKit-DecodingOptions übergeben. | Deutsche Sprache, Auto, leerer Wert und Groß-/Kleinschreibung geprüft. |
| Lokale Einrichtung | Mikrofon, gewählte Quelle, erforderliche Cache-Komponenten und erfolgreiches Speichern werden vor Weiter/Abschluss geprüft. Bedienungshilfen und Testdiktat bleiben optional. | Onboarding-Gates und Abschlussflag bei Speichern-Fehler/revokiertem Mikrofonrecht geprüft. |
| Lokaler Cache | Einrichtung, Download und Transkription verwenden dieselbe automatische oder explizite Modellkennung. Download lädt tatsächlich CoreML und Tokenizer. Ein vorhandener ausgewählter Cache wird direkt als `modelFolder` geöffnet. | Gegen gepinnte WhisperKit-Quellen geprüft; synthetische Cache- und Konfigurationstests. |
| Import/Export | Quelle, lokales Modell und Datenschutzwerte werden mit exportiert. Versionlose alte Exporte bleiben lesbar. Unbekannte Schlüssel/Versionen und Dateioperationen melden Fehler. Ein fehlgeschlagener Import stellt vorhandene Dateien wieder her. API-Keys bleiben ausgeschlossen. | Roundtrip, ältere Formate, unbekannte Schlüssel, kaputte JSON-Dateien und Schreibfehler getestet. |
| Dateiauswahl | Signierte Sandbox-Rechte enthalten `com.apple.security.files.user-selected.read-write` für Open-/Save-Panel. | Plist und erzeugte signierte App prüfen; reale Dateidialog-Abnahme bleibt separat. |
| Zwischenablage | Gemeinsamer Copy-Helfer markiert vertrauliche Inhalte. Clipboard-Fallback erhält mehrere Inhalte und Datenformate und überschreibt keine zwischenzeitliche neue Kopie. UTF-16-Blöcke teilen keine Surrogatpaare. | In-Memory-Clipboard und Unicode-Tests, ohne echte Zwischenablage. |
| Kleinere UI-Fehler | Selfhost-Vorgabe nutzt Compose-Port 8082 und den passenden README-Link. Irreführendes „Profil testen“ wurde entfernt. | Quellcode und Build. |
| Optionale Shell-Tools | Kein gemeinsamer Legacy-PID unter `/tmp`, keine globale Recorder-Suche. Private Runtime prüft Benutzer und Verzeichnis. Signale erreichen nur den verifizierten Recorder dieses Laufs. `status` liest ausschließlich, damit es keine parallel startende Aufnahme beschädigt. | Untrusted-/fremde-PID-, Runtime-, Startfenster-, Force-Start- und Cleanup-Regressionsprüfungen. |
| Eval-Proxy | Statische Dateien kommen aus einem separaten Asset-Verzeichnis. Hidden Files, unerlaubte Pfade, Traversal und Symlinks werden abgewiesen; fremde Origins/Hosts werden abgewiesen. | Vier synthetische lokale HTTP-Tests, kein realer Upstream. |

Zusätzlich zum ursprünglichen Report wurde der Offline-Neustartpfad korrigiert:
WhisperKit kontaktierte mit der früheren Konfiguration erneut die Modellablage,
auch wenn Gewichte bereits vorhanden waren. Der Einrichtungsdialog lud außerdem
mit `load: nil` noch keinen vollständigen Tokenizer. Beide Pfade wurden gegen die
gepinnten Library-Quellen geprüft und zusammen korrigiert. Distil-Kurznamen
werden für Cache und Download in dieselbe kanonische Kennung überführt.

## Verifikation

- Vollständiger Swift-App- und Testbuild erfolgreich.
- **229 Swift-Tests, ein wegen isolierter Pfade übersprungen, null Fehler.**
  Ausgeführt mit XCTest in zusätzlicher macOS-Sandbox, gesperrtem Netzwerk und
  gesperrtem Zugriff auf den echten Schlüsselbund sowie Schreibsperre für die
  echte Benutzer-Library. Eigene Runtime-, Installations- und Preferences-Pfade.
  [Ergebnis](verification/native-tests.json), [Log](verification/native-tests.log).
- **Alle elf Shell-Testskripte erfolgreich**, einschließlich der neuen Runtime-
  und Proxy-Tests. Nach der unabhängigen Race-Prüfung wurde die Recorder-Suite
  zusätzlich mit einem deterministischen Startfenster-Test erneut ausgeführt.
  [Ergebnisse](verification/shell-tests.json).
- Unabhängige Prüfungen der Root-Integration und der finalen Shell-/Onboarding-
  Pfade durchgeführt. Die dabei gefundene Status-/PID-Race ist korrigiert.
- App-Store-Paket **1.7.0 (23)** erfolgreich gebaut. App-Signatur, Installer-
  Signatur, eingebettetes Profil und signierte Sandbox-Rechte geprüft. Paket und
  Quell-Diff sind mit SHA-256 dokumentiert; der Original-Checkout enthält denselben
  getesteten Quellstand. [Paketprüfung](verification/appstore-package.json),
  [Quellnachweis](verification/source-provenance.json).
- Der zunächst im Review vermutete, später widerlegte First-Save-Fehler wurde
  nicht als Fehler behandelt. Neue Produktfeatures aus dem Report sind nicht
  Teil dieser Korrekturen.

Native Tests wiederholen:

```bash
swift build --build-tests --package-path macos-app
python3 docs/reports/2026-10-03-fixes/verification/run-native-tests.py
```

## Apple

App `6817328154`, abgelehnte Submission
`24906f41-5b19-4c82-b3fe-796de5c3a88d`, Version 1.7.0 (22). Verfügbarkeit vorher
175 Regionen; nach bestätigtem Ausschluss von China mainland und erneutem Laden
174 Regionen. Die Variante deaktiviert keine Funktionen außerhalb dieses
Storefronts und benötigt dort keine kosmetische Entfernung der Provider-Namen.
Die Entscheidung folgt der von Apple ausdrücklich angebotenen Alternative.

Die bestehende Prüfanleitung wurde um den bestätigten China-Ausschluss und die
Zuordnung zu Build 23 ergänzt. Nach Speichern und erneutem Laden war der gesamte
Text unverändert vorhanden. Automatische Veröffentlichung nach Apples Freigabe
bleibt gemäß Daniels ausdrücklicher Upload-/Einreichungsfreigabe eingestellt.

Transporter hat **1.7.0 (23) am 3. Oktober um 03:22 Uhr** erfolgreich ausgeliefert.
App Store Connect bestätigte den empfangenen Build mit „Verarbeitung läuft“.
[Uploadnachweis](verification/transporter-build23-delivered.png).

Nach abgeschlossener Verarbeitung wurde Build 23 in der Version 1.7.0 ausgewählt,
gespeichert und die bestehende Submission erneut zur App-Prüfung übermittelt.
App Store Connect bestätigte für Submission und App-Version **„Warten auf Prüfung“**
mit **1.7.0 (23)**. Es wurde keine separate Nachricht an Apple gesendet.
[Einreichungsnachweis](verification/appstore-build23-waiting-review.png),
[gespeicherte Review Notes](verification/appstore-review-notes.txt),
[gelesener Prüfungsstatus](verification/appstore-submission-state.txt).

Das angewendete Vorgehen und die Review Notes stehen unter
[App Store Review](../../app-store-review.md). Erfolgreicher Upload,
Serververarbeitung und Wiedereinreichung bedeuten keine bereits erfolgte
Apple-Freigabe.

## Noch erforderliche reale Abnahme

Die Cache-Prüfung bestätigt vorhandene Modellkomponenten und eine passende
Tokenizer-Struktur; sie prüft nicht jede Gewichtsdatei kryptografisch. Das Laden
über den Modellmanager prüft tatsächliches CoreML-/Tokenizer-Laden. Absichtlich
beschädigte oder inkompatible Caches können weiterhin Library-Ladefehler oder
Library-FatalErrors auslösen. Die UI benennt deshalb vorhandene Komponenten,
ohne eine umfassende Integritätsprüfung zu behaupten.

Es wurden keine echten Diktate aufgenommen, keine realen API-Keys verwendet,
keine Transkripte in andere Programme eingefügt und keine App installiert.
Vor breitem Vertrieb sind Import/Export im signierten Sandbox-Dateidialog sowie
kurze deutsche/englische Diktate, Offline-Neustart, Netzwerkfehler und Einfügen in
TextEdit, Browser, Terminal und Coding-Agent auf einem frischen Benutzerkonto
abzunehmen. Insbesondere das bestätigte Einfügen im realen Zielprogramm lässt
sich aus dem erfolgreichen Absenden von Unicode-Tastaturereignissen nicht
ableiten.

Quellversionen und Changelog wurden nicht manuell erhöht. Die Änderungen liegen
uncommitted im Original-Checkout auf `develop`. Keine Entwicklungs-Commits,
Pushes oder GitHub-Releases wurden erzeugt.
