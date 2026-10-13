# STTBar 1.8.0 bei Apple eingereicht

Am 14.10.2026 um 01:32 Uhr (Europe/Berlin) wurde Version **1.8.0 (24)**
zur App-Prüfung eingereicht. App Store Connect bestätigte nach erneutem Laden
für die Übermittlung und die App-Version **Warten auf Prüfung**.
Die automatische Veröffentlichung nach Apples Freigabe bleibt eingestellt.
Apples Freigabe steht noch aus.

[Übermittlung in App Store Connect](https://appstoreconnect.apple.com/apps/6817328154/distribution/reviewsubmissions/details/d2b2886f-3f21-4dbc-afd5-7039a403c902)

## Paket und Herkunft

- Unveränderter Release-Quellstand `v1.8.0`, Commit
  `4fadcefc39af901b860b9967c619a943d43961c9`. Tag, `origin/master` und
  `origin/develop` zeigten bei der Prüfung auf diesen Commit.
- App-Store-Variante mit `APPSTORE` und Buildnummer 24 gebaut.
  Versionsdatei im fertigen Paket bestätigt `commit=4fadcef`, ohne `dirty`.
- App mit Apple Distribution und Installer mit dem Mac-Installer-Zertifikat
  signiert. App-Signatur, Installer-Signatur und Sandbox-Berechtigungen geprüft.
- SHA-256 des Pakets:
  `44de06b172c420d32b2caf8c4d3eaf62010bdeb205053e29f098f7a0331a019f`.
- Transporter bestätigte die Auslieferung am 14.10.2026 um 01:28 Uhr.
  App Store Connect zeigte anschließend die abgeschlossene Verarbeitung und
  Build 24 als bereit zur Übermittlung.
- Apple-Build-ID: `b79c6914-83c3-4118-af36-c46370f19fa5`.
- Übermittlungskennung: `d2b2886f-3f21-4dbc-afd5-7039a403c902`.

Das signierte Paket ist zusätzlich unter
`dist-appstore/1.8.0-build24/STTBar.pkg` im Hauptcheckout erhalten.
Die Kopie wurde mit dem ausgelieferten Paket per SHA-256 verglichen.

## Store-Eintrag

Deutsche und englische Beschreibungen und Änderungsnotizen nennen Parakeet,
das Vorladen lokaler Modelle und die einmalige Modellvorbereitung.
Die Prüfhinweise wurden auf den neuen lokalen Standard und Build 24 angepasst.
Die gespeicherten Metadaten wurden nach erneuter Navigation geprüft.
Die vorhandenen Screenshots wurden übernommen.

174 Länder und Regionen bleiben verfügbar. Festlandchina ist weiterhin das
einzige ausgeschlossene Land. Preise und Verfügbarkeit wurden nicht geändert.

## Nachweise und Prüfung

- [Status nach erneutem Laden](submission-readback.txt)
- [Screenshot der Übermittlung](waiting-for-review.jpg)
- [Paketprüfung](package-verification.json)
- [Buildprotokoll](build.log)
- [Englische Metadaten](metadata-en.txt), [deutsche Metadaten](metadata-de.txt)
- [Prüfhinweise](review-notes.txt), [Verfügbarkeit](availability.txt)
- [Bereinigung der Build-Caches](cleanup-preflight.json)

Der App-Store-Build war erfolgreich. Er meldete eine bestehende Swift-Warnung
zu einer nicht als Sendable markierten Capture in NativeBackend.swift.
Es wurden keine App-Quellen geändert und keine zusätzlichen Funktionstests
ausgeführt. Der vorhandene CI-Lauf für den zugrunde liegenden Quellstand
[38481885164](https://github.com/ProjectMakersDE/STTBar/actions/runs/38481885164)
und der [Release-Lauf 38481904321](https://github.com/ProjectMakersDE/STTBar/actions/runs/38481904321)
wurden mit Ergebnis success geprüft.

Die drei temporären SwiftPM-Checkouts waren unverändert und entsprachen den
im Release versionierten Package.resolved-Revisionen. Ihre Remote-Referenzen
wurden geprüft. Die regenerierbaren Build-Caches wurden entfernt, ohne sie zu
kopieren. Dabei wurden 1.249.849.344 Byte freigegeben. Der eigene Worktree wird
nach Commit, Push und Prüfung des Remote-Stands über die Codex-App archiviert.

Kanban: TASK-1067.
