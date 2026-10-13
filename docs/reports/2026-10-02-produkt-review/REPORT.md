# STTBar Produkt und Release Review

Stand: 2. Oktober 2026. Für Daniel, vor dem ersten breiten Produktrelease.

**Meine Einschätzung: STTBar ist ein sinnvolles, klar fokussiertes Produkt.** Der Nutzen ist besonders für Menschen greifbar, die häufig längere Prompts an Coding-Agenten schreiben. Lokale Verarbeitung, eigene Server, kein Konto und ein geringer Einmalpreis passen gut zusammen. Der wichtigste nächste Schritt ist, die vorhandenen Datenschutzoptionen und Diktiermodi verlässlich zu machen. Dafür gibt es konkrete Fehler. Als nächstes größeres Feature empfehle ich vollständige Arbeitsprofile, die auf Wunsch zur aktiven App passen. Eine kleine Ergebnisansicht zum Korrigieren und Wiederholen würde zusätzlich viel Alltagsnutzen bringen.

In der nativen App wurde keine kritische Sicherheitslücke bestätigt. Ein wichtiger Datenschutzfehler in den Einstellungen sollte vor einem breiteren Launch behoben werden. Weitere bestätigte Fehler betreffen Aufbewahrung, Übersetzung, lokale Sprachauswahl und Einrichtung. Eine Sicherheitslücke niedriger Schwere betrifft ausschließlich die optionalen alten Shell-Werkzeuge.

## Prüfgrundlage und Grenzen

Geprüft wurde der aktuelle [GitHub Release v1.7.0](https://github.com/ProjectMakersDE/STTBar/releases/tag/v1.7.0), Quellstand `f09a5cedf6c0782aba74d57ab7c2d5fc42060aa8`. Der ursprüngliche lokale Checkout steht auf `develop`, Commit `e9fed7e`, Version 1.5.0. Die aktuelle Version wurde deshalb getrennt gelesen und gebaut. Alle Codeverweise unten beziehen sich auf 1.7.0.

Die [öffentliche Produktseite](https://projectmakers.de/apps/sttbar), das aktuelle README, die Datenschutzerklärung, Release- und Signierskripte, native Nutzerabläufe und die separate Shell-Laufzeit wurden einbezogen. Die vorhandenen Einstellungs-Screenshots wurden visuell angesehen. Das App-Store-Angebot zu 1,99 € und der bevorstehende erste echte Release sind Daniels Angaben. Die Website zeigt derzeit noch „Bald im Mac App Store“. Ein freigegebener Store-Eintrag oder App-Store-Connect-Status wurde nicht unabhängig geprüft.

Die Prüfung kombiniert Quellcodeanalyse, unabhängige Gegenprüfung und synthetische Reproduktionen. Es wurden keine echten Diktate, API-Keys, Mikrofone oder Zwischenablageinhalte verwendet. Die App wurde nicht installiert oder in fremde Programme tippen gelassen. Es wurde kein Produktcode geändert, kein Release ausgelöst und nichts veröffentlicht. Eine Messung von Erkennungsqualität und Latenz auf verschiedenen Macs sowie eine reale Bedienprüfung bleiben offen. Die Prüfung ist keine vollständige Sicherheitszertifizierung.

## Produkt und Positionierung

Der Kernablauf ist gut: Hotkey, sprechen, Hotkey, Text am Cursor. STTBar besitzt bereits sinnvolle Details wie Wörterersetzungen, mehrere Diktiermodi, eine Phasenanzeige, Bluetooth-Mikrofonvermeidung und flexible Endpunkte. Die native App verwendet eine eigene Swift-Pipeline. Die mitgelieferten Shell-Skripte sind nicht ihre Laufzeit.

„Diktieren überall auf dem Mac“ und lokale Erkennung allein unterscheiden das Produkt noch nicht ausreichend. Apple bietet bereits systemweites Diktieren und abhängig von Einstellungen lokale Verarbeitung. Superwhisper bietet unter anderem lokale Modelle, Modi und automatische Zuordnung zu Apps. Wispr Flow bewirbt sprachliche Bereinigung und ein persönliches Wörterbuch. Das sind Herstellerangaben, kein eigener Qualitätsvergleich. Quellen: [Apple Dictation](https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac), [Superwhisper Modi](https://superwhisper.com/docs/modes/modes), [Wispr Flow](https://wisprflow.ai/).

Die überzeugende Kombination bei STTBar ist aus meiner Sicht: **Diktieren für Coding-Agenten mit Kontrolle über Modelle und Daten, kostenloser GitHub-Distribution und sehr günstigem Store-Kauf.** Diese Positionierung passt besser zum vorhandenen Produkt als ein allgemeiner KI-Assistent. E-Mails und Notizen sind naheliegende zusätzliche Anwendungen, brauchen aber passende Bereinigungsprofile. Der aktuelle Agent-Prompt formt Sprache bewusst zu direkten Handlungsanweisungen. Für eine höfliche Kundenmail ist das nicht automatisch die richtige Bearbeitung.

Der Preis von 1,99 € ist aus Nutzersicht attraktiv. Ich würde GitHub und App Store als zwei Wege zum gleichen Produkt erklären: GitHub für kostenlose Nutzung, App Store für bequeme Installation und Updates sowie Unterstützung der Entwicklung. Ein geringerer Funktionsumfang für kostenlose Nutzer ist für diese Positionierung nicht nötig. Ob der Preis langfristig den Support trägt, lässt sich ohne Verkaufs- und Supportdaten nicht beurteilen.

Für optionale gehostete Whisper- oder LLM-Dienste sollte direkt bei der Einrichtung stehen, dass der jeweilige Anbieter zusätzliche Kosten verursachen kann. Ein lokales Whisper-Modell bedeutet zudem nur lokale **Transkription**. Ein aktivierter externer LLM-Endpunkt erhält weiterhin den Text. Die Oberfläche sollte den gesamten Weg anzeigen, etwa „Audio lokal, Text zu OpenRouter“.

## Fehler nach Priorität

P1 bedeutet vor dem breiteren Launch beheben. P2 bedeutet zeitnah beheben oder die Einschränkung sichtbar machen. P3 bedeutet kleine Korrektur oder nachrangige Verbesserung. Diese Produktprioritäten sind keine Sicherheits-Schweregrade.

| Priorität | Befund | Nutzerwirkung | Belegstatus |
|---|---|---|---|
| P1 | Sensitive Mode bleibt bei fehlgeschlagenem Anwenden unbemerkt inaktiv | Angekreuzter Datenschutzmodus stimmt nicht mit der tatsächlichen Verarbeitung überein | Quellcode, isolierte Reproduktion und Gegenprüfung |
| P2 | Vertrauliche Aufnahme bleibt nach Fehler oder leerem Ergebnis liegen | Audiodatei bleibt im App-Speicher | Fehlerfall dynamisch bestätigt, Leerfall im Code bestätigt |
| P2 | Verlauf läuft nicht automatisch ab | Alte Texte bleiben ohne weiteres normales Diktat gespeichert | Isolierte Reproduktion und Gegenprüfung |
| P2 | Englisch-Modus kann deutschen Text ausgeben, Fallback-Schalter wirkt nicht | Ein beworbener Modus und eine Einstellung verhalten sich anders als erwartet | Durchgängiger Codepfad bestätigt |
| P2 | Lokale Erkennung ignoriert eingestellte Sprache | Gewählte Sprache beeinflusst den lokalen Decoder nicht | App-Code und gepinnte WhisperKit-Abhängigkeit bestätigt |
| P2 | Einrichtung meldet Abschluss ohne ausreichende Bereitschaft | Nutzer kann mit fehlendem Modell oder Mikrofonrecht starten | Quellcode bestätigt |
| P2 | Export verliert lokale Quelle und Modell | Übertragung einer lokalen Einrichtung ist unvollständig | Export und Import im Code bestätigt |
| P2 prüfen | Dateizugriff für Import und Export fehlt in Sandbox-Rechten | Externe JSON-Dateien können je nach Sandbox-Verhalten scheitern | Fehlendes Recht statisch belegt, signierter Ablauf noch zu testen |

### Sensitive Mode muss wirksam und sichtbar sein

Die Checkbox bindet an einen Entwurf. „Anwenden“ validiert zunächst alle Einstellungen. Ein Fehler verhindert anschließend die Übernahme in `AppSettings`, aber der Datenschutz-Tab zeigt die Fehlermeldung nicht. Beispiel: Verlauf ist bereits eingeschaltet, Sensitive Mode ausgeschaltet. Bei „Auto-Löschen nach Stunden“ wird `24h` eingetragen, Sensitive Mode angekreuzt und Anwenden gedrückt. Der Haken bleibt gesetzt, der tatsächlich verwendete Sensitive Mode bleibt aus. Verlauf und Löschlogik richten sich weiter nach dem alten Wert.

Eine ungültige Whisper-URL verursacht denselben Fehler, auch wenn lokale Erkennung ausgewählt ist und dieses Serverfeld ausgeblendet wird. Das isolierte Prüfharness mit den unveränderten Validierungs- und Übernahmemethoden bestätigt `sensitive_draft=true`, aber `effective_sensitive=false`. Dateien, Schlüsselbund und Benutzerpräferenzen werden dabei durch Testobjekte ersetzt.

**Empfehlung:** Datenschutzoptionen unabhängig übernehmen oder unmittelbar wirksam machen. Nur Einstellungen des tatsächlich verwendeten Backends validieren. Jeder Tab muss Fehler und erfolgreichen Abschluss sichtbar anzeigen. Die angezeigte wirksame Einstellung darf nach einem fehlgeschlagenen Anwenden nicht dem Entwurf entsprechen.

Belege: [SettingsModel.swift](https://github.com/ProjectMakersDE/STTBar/blob/v1.7.0/macos-app/Sources/STTBar/Config/SettingsModel.swift#L119), Zeilen 120, 150 und 426. [PrivacyTab](https://github.com/ProjectMakersDE/STTBar/blob/v1.7.0/macos-app/Sources/STTBar/UI/SettingsView.swift#L399), Zeilen 406 bis 425. Reproduktion unter [verification/reproductions.json](verification/reproductions.json).

### Vertrauliche Audioaufnahmen auch im Fehlerfall entfernen

Die Aufnahme liegt als `recording.wav` auf der Platte. Sensitive Mode entfernt sie nach der Verarbeitung eines nicht leeren Ergebnisses. Der Fehlerpfad und ein leeres Ergebnis erreichen diese Löschung nicht. Ein synthetischer Transkriptionsfehler bestätigt: Zustand `error`, WAV weiterhin vorhanden. Die nächste Aufnahme, explizites Abbrechen oder manuelle Laufzeitbereinigung entfernen sie später. Ein gewöhnlicher Neustart besitzt dafür keine eigene Bereinigung.

Das ist keine nachgewiesene Datenübertragung an Dritte. Es ist eine unnötige Aufbewahrung vertraulicher Audiodaten. Die öffentliche Datenschutzerklärung verspricht ausdrücklich die Löschung der Textdatei nach dem Einfügen, nicht umfassend die Löschung fehlgeschlagener Aufnahmen. Ich würde das Verhalten trotzdem als Teil eines verlässlichen vertraulichen Modus korrigieren.

**Empfehlung:** Für jeden Lauf einen eigenen Dateipfad und den zu Beginn wirksamen Datenschutzmodus verwenden. Erfolg, leeres Ergebnis, Fehler und Abbruch müssen einen gemeinsamen Abschluss mit definierter Löschung haben. Eine verspätete Löschung des gemeinsamen Dateinamens könnte sonst eine neue Aufnahme treffen.

Belege: [SttRunner.swift](https://github.com/ProjectMakersDE/STTBar/blob/v1.7.0/macos-app/Sources/STTBar/Core/SttRunner.swift#L173), Zeilen 180 bis 189 und 209 bis 214. [NativeBackend.swift](https://github.com/ProjectMakersDE/STTBar/blob/v1.7.0/macos-app/Sources/STTBar/Core/Transcription/NativeBackend.swift#L49), Zeilen 55 bis 59 und 96 bis 97.

### Verlauf wirklich nach Zeit löschen

„Auto-Löschen nach Stunden“ wird nur ausgeführt, wenn ein neues gewöhnliches Transkript gespeichert wird. Beim Laden bleiben alte Einträge unverändert. Bei deaktiviertem Verlauf oder Sensitive Mode kehrt `add()` vor der Bereinigung zurück. Damit können abgelaufene Texte beliebig lange bestehen bleiben. Im Prüfharness blieb ein 48 Stunden alter Eintrag trotz einer Stunde Aufbewahrung nach dem Laden und einem vertraulichen Diktat vorhanden. Erst ein normales neues Diktat entfernte ihn.

**Empfehlung:** Beim Start, bei Änderungen der Aufbewahrungszeit und regelmäßig während der Laufzeit bereinigen und speichern. Für eine geschlossene App ehrlich erklären, dass abgelaufene Einträge beim nächsten Start entfernt werden. Eine Hintergrundkomponente nur für diese Löschung ist nicht erforderlich.

Beleg: [TranscriptHistoryStore.swift](https://github.com/ProjectMakersDE/STTBar/blob/v1.7.0/macos-app/Sources/STTBar/Core/TranscriptHistoryStore.swift#L14), Zeilen 19 bis 31 und 39 bis 47.

### Diktiermodi und Einstellungen konsistent machen

Im Englisch-Modus erfolgt die Übersetzung ausschließlich innerhalb der aktivierten LLM-Bereinigung. Ist sie ausgeschaltet, wird das Rohtranskript ausgegeben. Bei einem LLM-Fehler passiert derselbe Rückfall. Der allgemeine Rückfall ist dokumentiert und sinnvoll. Die Oberfläche sollte aber erkennen lassen, dass eine englische Ausgabe dann nicht verfügbar ist oder nicht erzeugt wurde.

Der Schalter „Raw fallback on LLM error“ wird gespeichert, kommt jedoch nicht in der nativen Transkriptionskonfiguration vor. Der native Fehlerpfad fällt immer auf Rohtext zurück. Ein deaktivierter Schalter hat deshalb keine Wirkung.

Bei lokaler Erkennung wird `config.language` nicht an WhisperKit übergeben. Die Bibliothek erhält keine `DecodingOptions`. Die gewählte Sprache steuert also nicht den lokalen Decoder. Daraus folgt ohne echte Audioprüfung nicht, dass jedes deutsche Diktat falsch oder englisch ausgegeben wird. Es ist aber ein klarer Verdrahtungsfehler.

**Empfehlung:** Englisch-Modus nur bei tatsächlich verfügbarer Übersetzung anbieten, fehlgeschlagene Übersetzung anzeigen und die Fallback-Einstellung einhalten. Die lokale Erkennung muss gewählte Sprache und bewusste automatische Spracherkennung korrekt an WhisperKit übergeben.

Belege: [NativeBackend.swift](https://github.com/ProjectMakersDE/STTBar/blob/v1.7.0/macos-app/Sources/STTBar/Core/Transcription/NativeBackend.swift#L70), Zeilen 70 bis 79. [Transcriber.swift](https://github.com/ProjectMakersDE/STTBar/blob/v1.7.0/macos-app/Sources/STTBar/Core/Transcription/Transcriber.swift#L30), Zeile 40. [WhisperKit 1.0.0 Optionen](https://github.com/argmaxinc/argmax-oss-swift/blob/v1.0.0/Sources/WhisperKit/Core/Configurations.swift).

### Erste Einrichtung an tatsächlicher Bereitschaft ausrichten

„Weiter“ ist nicht an vorhandenes Mikrofonrecht oder ein einsatzbereites lokales Modell gebunden. Der Abschluss setzt das Onboarding-Flag vor dem Anwenden der Einstellungen. Eine Prüfung auf irgendeine `.mlmodelc`-Komponente belegt außerdem nicht, dass gerade das gewählte Modell vollständig vorhanden ist. Bereitschaftsprüfungen beim Start und nach Fehlern können die Einrichtung erneut öffnen, wodurch kein dauerhafter Ausschluss entsteht. Trotzdem kann eine unbrauchbare Einrichtung zunächst als fertig erscheinen.

Der Testschritt ist bewusst optional. Ihn zwingend zu machen wäre eine Produktentscheidung, kein bereits festgelegtes Erfordernis. Sinnvoll wäre eine gut sichtbare Bereitschaftsanzeige und ein angebotener kurzer Test. Bedienungshilfen können mit erklärter manueller Zwischenablagefunktion optional bleiben.

**Empfehlung:** Erforderliches Mikrofonrecht, erfolgreiche Konfigurationsübernahme und vollständiges ausgewähltes Modell prüfen. Modellgröße, Fortschritt und Abbrechen des Downloads anzeigen. Abschluss erst nach erfolgreichem Speichern markieren.

Belege: [OnboardingView.swift](https://github.com/ProjectMakersDE/STTBar/blob/v1.7.0/macos-app/Sources/STTBar/UI/OnboardingView.swift#L47), Zeilen 47 bis 70. [OnboardingWindow.swift](https://github.com/ProjectMakersDE/STTBar/blob/v1.7.0/macos-app/Sources/STTBar/UI/OnboardingWindow.swift#L39), Zeilen 39 bis 43. [OnboardingReadiness.swift](https://github.com/ProjectMakersDE/STTBar/blob/v1.7.0/macos-app/Sources/STTBar/Onboarding/OnboardingReadiness.swift#L71).

### Import und Export als verlässlichen Wechsel auf einen anderen Mac behandeln

Der Export enthält `STT_SOURCE` und `STT_LOCAL_MODEL` nicht. Eine lokale Einrichtung stellt auf einem frischen Ziel deshalb weder die Quelle noch das Modell wieder her. API-Keys absichtlich auszunehmen ist dagegen richtig.

Zusätzlich fehlt im gemeinsamen Sandbox-Rechtesatz `com.apple.security.files.user-selected.read-write`, obwohl Open- und Save-Panel für externe Dateien verwendet werden. Das fehlende Recht ist in Quellcode und veröffentlichter App-Signatur prüfbar. Das genaue Scheitern des Dateidialogs oder des Dateizugriffs wurde hier nicht in einer laufenden signierten App reproduziert. Apple beschreibt die [Rechte für ausgewählte Dateien](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-write). Der Export ignoriert Schreibfehler und kann anschließend trotzdem „Exportiert“ anzeigen.

**Empfehlung:** Quelle und Modell mit exportieren, Einlesen und Schreiben mit sichtbaren Fehlern behandeln und einen Export auf dem Schreibtisch mit anschließendem Import in einer signierten Sandbox-App prüfen. Ein versioniertes Exportformat erleichtert spätere Erweiterungen.

Belege: [SettingsModel.swift](https://github.com/ProjectMakersDE/STTBar/blob/v1.7.0/macos-app/Sources/STTBar/Config/SettingsModel.swift#L290), Zeilen 290 bis 324 und 441 bis 459. [STTBar.entitlements](https://github.com/ProjectMakersDE/STTBar/blob/v1.7.0/macos-app/Resources/STTBar.entitlements#L6).

## Kleinere Korrekturen und offene Bedienprüfung

- **P3 Self-host-Vorgabe:** Einrichtung und Einstellungen verwenden `localhost:8000`, die mitgelieferte Compose-Datei veröffentlicht standardmäßig Host-Port `8082`. Die Vorgabe sollte zur mitgelieferten Anleitung passen. Andere eigene Server können selbstverständlich Port 8000 verwenden. Belege: `OnboardingView.swift:197`, `SettingsView.swift:91`, `docker-compose.yml:6`.
- **P3 Profil testen:** Der entsprechende Button ruft nur `applyEnvChanges()` auf den aktuellen Entwurf auf. Er testet weder einen Dienst noch das ausgewählte Profil. Umbenennen oder einen echten Test implementieren. Beleg: `SettingsView.swift:198`.
- **P3 Vertraulich kopieren:** „Letztes Transkript kopieren“ schreibt direkt in die Zwischenablage und umgeht die Markierung, die automatische vertrauliche Ausgaben vor kooperierenden Clipboard-Managern verbirgt. Beide Kopierwege sollten dieselbe Funktion verwenden. Ein echter Clipboard-Manager wurde nicht getestet. Belege: `AppDelegate.swift:157-160`, `NativePaste.swift:200-208`.
- **Einfügen prüfen:** Die Unicode-Stufe meldet Erfolg nach dem Absenden von Tastaturereignissen, ohne Einfügung zu bestätigen. Ein ungeeignetes oder nicht editierbares Ziel kann deshalb ein Ergebnis verschlucken. Das letzte Transkript ist immerhin über das Menü wieder erreichbar. Browser, TextEdit, Terminal und ein typischer Coding-Agent sollten Teil der realen Abnahme sein.
- **Clipboard-Sonderfälle prüfen:** Der seltene dritte Einfügeweg stellt nach 0,4 Sekunden nur alten Klartext wieder her und berücksichtigt zwischenzeitliches Kopieren nicht. UTF-16-Blöcke können ein Emoji teilen. Das sind belegte Implementierungsrisiken, aber in diesem Review keine beobachtete Textbeschädigung oder häufige Sicherheitslücke. Belege: `NativePaste.swift:149-165,187-193`.

## Features mit echtem Mehrwert

Die Aufwandseinschätzungen sind qualitative Schätzungen anhand der vorhandenen Architektur, keine Zusagen zu Entwicklungszeiten.

| Rang | Feature | Konkreter Nutzen | Geschätzter Aufwand |
|---|---|---|---|
| 1 | Vollständige Arbeitsprofile mit optionaler App-Zuordnung | Agentenprompt, Kundenmail und Notiz bekommen passende Form, Sprache und Wörterbuch ohne ständiges Umstellen | Mittel |
| 2 | Ergebnisansicht mit Wiederholen und Korrigieren | Ein misslungenes Diktat muss nicht erneut gesprochen werden | Mittel |
| 3 | Englische Ausgabe ohne zusätzliches LLM | Der Englisch-Hotkey funktioniert mit geeigneten lokalen Whisper-Modellen auch offline | Klein bis mittel, Qualität zu prüfen |
| 4 | Wortkorrekturen als Wörterbucheintrag vorschlagen | Wiederkehrende Namen und Fachbegriffe werden mit wenigen Klicks zuverlässiger | Mittel |
| 5 | Sichtbare Verarbeitungskette und verifizierte Offline-Bereitschaft | Nutzer versteht vor dem Diktat, was lokal bleibt und welcher Dienst Text erhält | Klein bis mittel |

### Arbeitsprofile als stärkstes nächstes Produktfeature

Heute existieren Profile und Prompts, aber ein Profil enthält unter anderem nicht die Transkriptionsquelle, das lokale Modell oder die Prompt-Identität. Ich würde daraus vollständige Arbeitsabläufe machen: „Coding-Agent“, „E-Mail“, „Notizen“ und „Wörtlich“. Ein Profil verbindet Prompt, Sprache, Modell oder Quelle, Ersetzungen und optional ein Tastenkürzel.

Optional kann STTBar anhand der aktiven App einen passenden Ablauf wählen. Dafür reicht zunächst die App-Kennung. Es muss kein Bildschirmtext gelesen oder automatisch an ein LLM geschickt werden. Die manuelle Auswahl bleibt sinnvoll. Beispiel: Im Coding-Agenten entsteht eine klare Aufgabenliste, im Mailprogramm eine höfliche Nachricht mit unverändertem Inhalt.

Der Nutzen ist gute Alltagstauglichkeit, nicht behauptete Marktneuheit. Superwhisper besitzt bereits App-Zuordnung und entsprechende Modi. STTBar kann diese Idee in einem schlanken, günstigen Produkt mit freier Serverwahl anbieten. Quelle: [Superwhisper Modi](https://superwhisper.com/docs/modes/modes).

### Ergebnisansicht als zweite große Verbesserung

Eine kleine Ansicht nach Fehlern oder auf Wunsch nach jedem Diktat könnte Rohtext und bereinigtes Ergebnis zeigen. Aktionen: kopieren, erneut bereinigen, anderes Profil wählen und bewusst einfügen. Bei einem Netzwerkfehler sollte die Wiederholung möglich sein, ohne alles neu einzusprechen.

Das vorhandene Menü für das letzte Transkript ist ein guter Anfang. Für erneute Bereinigung fehlen getrennt verwalteter Rohtext und Ergebnis. Sensitive Mode sollte Wiederherstellung nur im Arbeitsspeicher und mit kurzer Lebensdauer erlauben. Ein gewöhnlicher Verlauf darf weiterhin ausgeschaltet bleiben. Die Korrektur der Audioaufbewahrung hat Vorrang vor dem bewussten Speichern für Wiederholungen.

### Offline übersetzen und aus Korrekturen lernen

WhisperKit stellt bereits einen Übersetzungsauftrag bereit. Englische Ausgabe könnte damit unabhängig von der LLM-Bereinigung werden. Dafür braucht es ein geeignetes mehrsprachiges, übersetzungsfähiges Modell und einen Qualitätstest. Nicht jedes schnelle Modell eignet sich gleich gut. Quelle: [WhisperKit 1.0.0 Optionen](https://github.com/argmaxinc/argmax-oss-swift/blob/v1.0.0/Sources/WhisperKit/Core/Configurations.swift).

Beim Korrigieren eines Namens in der Ergebnisansicht könnte STTBar anbieten, die Änderung als Wörterersetzung zu übernehmen. Die vorhandene Ersetzungsliste ist dafür eine gute Grundlage. Korrekturen sollten ausdrücklich bestätigt werden. Automatisches Mitschneiden fremder Texte ist dafür nicht nötig.

Meeting-Aufnahme, mobile Begleiter oder umfangreiche Assistentenintegrationen würde ich derzeit nachrangig behandeln. Sie vergrößern Einrichtung, Datenschutzfläche und Supportaufwand, bevor der eigentliche Diktierablauf verlässlich genug ist.

## Website und Release Angebot

Die [Produktseite](https://projectmakers.de/apps/sttbar) erklärt den Ablauf und den Agenten-Anwendungsfall verständlich. Preis und kostenloser GitHub-Weg sind sichtbar. Folgende Anpassungen würde ich zum Launch vorsehen:

- Den Store-Button an den tatsächlichen Freigabestand anpassen. Derzeit steht dort noch „Bald im Mac App Store“. Sobald der Eintrag öffentlich ist, sollte der Button direkt dorthin führen.
- Das kostenlose GitHub-Angebot als fertigen App-Download gleichwertig sichtbar machen. Die Seite nennt teils den Quellcode, erwähnt aber später auch die fertige notarisierte Version. Ein direkter Link zum neuesten Release reduziert Unsicherheit bei weniger technischen Nutzern.
- Bei Offline-Betrieb den einmaligen Modelldownload erwähnen und lokale Erkennung von optionaler externer Bereinigung unterscheiden.
- Die Beispielrechnung für Zeitersparnis als Szenario belassen. Drei Sekunden für Transkription und Bereinigung sind eine dort ausdrücklich genannte Annahme, kein in diesem Review gemessener STTBar-Wert. Echte Messungen sollten später Modell, Mac und Diktatlänge nennen.
- Bereinigung als sprachliche Bearbeitung erklären. Der Satz, jeder Prompt werde geprüft, kann eine inhaltliche Prüfung nahelegen, die der Code nicht garantiert. Fakten, Zahlen, Negationen und technische Namen benötigen weiterhin Nutzerkontrolle.

Die Lizenz wird im aktuellen README ausdrücklich als source-available bezeichnet. „Kostenlos nutzbar, Quellcode verfügbar“ ist dafür eine passende Produktbeschreibung. Für das spätere GitHub-Update fehlt derzeit ein Hinweis innerhalb der App. Ein Menüpunkt zum Öffnen des neuesten Releases wäre eine kleine Verbesserung, ohne einen eigenen Installer einzuführen.

## Sicherheit und positive Muster

Positiv sind die App Sandbox, die native Verarbeitung ohne Shell-Ausführung, getrennte Signierpfade, ein verpflichtender Developer-ID-Pfad für GitHub-Releases und API-Keys im Schlüsselbund. Keys werden nach Host und explizitem Port zugeordnet und aus env, Profilen sowie Exporten herausgehalten. Verlauf ist optional. Die Laufzeitbereinigung arbeitet mit einer ausdrücklichen Dateiliste. In den untersuchten nativen Pfaden wurde kein Produkttracking gefunden.

**Bestätigte Sicherheitslücke LOW, nur optionale Shell-Werkzeuge:** Ein anderes lokales Benutzerkonto kann die noch nicht vorhandene gemeinsame Legacy-PID-Datei `/tmp/stt-recording.pid` anlegen. Wenn der Besitzer eines dort angegebenen Prozesses später die alten Shell-Werkzeuge verwendet, schicken sie SIGINT und TERM an diesen PID, ohne Eigentümer der Datei oder Recorder-Identität zu prüfen. Dadurch kann fremde Arbeit unterbrochen werden. Die aktuelle native App und App-Store-App rufen diese Skripte nicht auf. Das ist kein Blocker für deren Release. Globale Legacy-PID-Verarbeitung entfernen oder sicher an Benutzer und Recorder binden. Ablauf, Bedingungen und sichere Reproduktion stehen in [findings.json](findings.json) und [FINDINGS-DETAIL.md](FINDINGS-DETAIL.md).

**Härtung für Entwicklerwerkzeuge:** Der manuell gestartete, nicht mit der App ausgelieferte `stt-eval-proxy.py` dient Dateien aus dem Repository aus. Ein dediziertes Verzeichnis mit erlaubten öffentlichen Assets wäre sinnvoll. Sein Einsatz mit privaten Dateien oder von anderen lokalen Benutzern wurde hier nicht als eigener Exploit getestet.

Nicht als native Sicherheitslücken aufgenommen wurden frei gewählte lokale Server, unbelegte API-Key-Lecks durch Weiterleitungen, eine nur bei zusätzlicher manueller Verknüpfung mögliche Import-zu-Shell-Ausführung und ein über die ausgelieferte Oberfläche nicht erreichbarer Abbruch während des Einfügens. Weitere zielgerichtete Prüfläufe können zusätzliche Pfade abdecken.

## Verifikation und nächste Schritte

- Swift-Testpaket und App-Executable erfolgreich gebaut.
- **189 Swift-Tests ausgeführt, ein Test aufgrund der ausdrücklich isolierten Pfade übersprungen, keine Fehler.** Ausgeführt mit XCTest in einer zusätzlichen macOS-Sandbox, ohne Netzwerkzugriff und mit gesperrten Schreibzugriffen auf die echte Benutzer-Library. Kein Produkt-Setup installiert.
- **Alle neun vorhandenen Shell-Testskripte erfolgreich.** Ergebnisse unter [verification/shell-tests.json](verification/shell-tests.json).
- Datenschutzfehler mit isolierten Daten und unveränderten Quellmethoden reproduziert. Der zunächst vermutete Fehler beim Speichern einer neuen `.env` wurde auf diesem macOS widerlegt und deshalb verworfen. Ergebnisse unter [verification/reproductions.json](verification/reproductions.json), ausführbares Prüfharness unter [verification/run_checks.py](verification/run_checks.py).
- Veröffentlichte GitHub-App separat heruntergeladen. SHA256 stimmt mit dem veröffentlichten Wert überein. Signaturprüfung erfolgreich, Gatekeeper akzeptiert sie als „Notarized Developer ID“, angeheftetes Notarisierungsticket gültig. Die App ist arm64, Version 1.7.0, Build 22, Build-Commit `165d2ca`. Der anschließende Release-Commit `f09a5ce` ergänzt Changelog und Versionsmetadaten. Die signierten Rechte entsprechen dem untersuchten Rechtesatz. Ergebnisse unter [verification/release-verification.json](verification/release-verification.json).
- Sicherheitsdaten strukturell validiert und von einem anderen Prüfer gegen den Quellcode gegengeprüft.

**Empfohlene Reihenfolge:** Zuerst die tatsächlich wirksamen Datenschutzoptionen sichtbar und zuverlässig machen. Danach Aufnahme- und Verlaufslöschung, Englisch-Modus und lokale Sprachauswahl korrigieren. Anschließend Einrichtung sowie Import und Export mit der fertig signierten App auf einem frischen Benutzerkonto abnehmen. Dazu kurze deutsche und englische Diktate, Netzwerkfehler, fehlende Bedienungshilfen und echte Zielprogramme testen. Erst danach vollständige Arbeitsprofile und Ergebniswiederholung ausbauen.

Die vorhandene Testbasis und Release-Automation sind ein guter Ausgangspunkt. Für den breiteren Launch zählt jetzt vor allem, dass angezeigte Einstellungen und beworbene Modi exakt dem tatsächlichen Verhalten entsprechen.
