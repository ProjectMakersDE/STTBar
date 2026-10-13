# STTBar Architektur und Prüfgrundlage

Stand 2. Oktober 2026. Aktueller GitHub Release v1.7.0, Commit f09a5ce. Ausgangscheckout develop e9fed7e entspricht v1.5.0. Analyse des aktuellen Releases im isolierten Checkout. Keine vorherigen Security-Audit-Runs unter dem Standardpfad gefunden.

STTBar ist eine native macOS-Menüleisten-App für Endnutzer. AppKit hält Menü, Fenster und globale Hotkeys. SwiftUI stellt Einrichtung, Einstellungen und HUD dar. SwiftPM setzt macOS 14 voraus, der vorkompilierte Release ist arm64. WhisperKit 1.0.0 ist die lokale Erkennung. Der App Store und die direkte GitHub-Distribution haben getrennte Signierpfade. Semantic Release veröffentlicht von master.

## Datenfluss

AppDelegate erstellt immer NativeBackend. SttRunner steuert Aufnahme, Transkription, optionale Bereinigung und Einfügen. AudioRecorder schreibt recording.wav im Runtime-Verzeichnis. LocalTranscriber lädt WhisperKit-Modelle oder RemoteTranscriber sendet die WAV an den vom Nutzer konfigurierten Whisper-Endpunkt. LLMClient sendet optional den Text an einen konfigurierten OpenAI-kompatiblen Dienst. ReplacementStore korrigiert Begriffe. NativePaste versucht AXSelectedText, Unicode-CGEvents, dann Clipboard und Command V. TranscriptHistoryStore speichert optional Verlauf. AppLogger und StatusStore speichern Betriebsdaten. Die mitgelieferten Shell- und Python-Werkzeuge sind getrennte Legacy- oder Entwicklungsoberflächen, die native App startet sie nicht.

## Vertrauensgrenzen

Der Nutzer kontrolliert Server-URLs, Modelle, Prompts, Ersetzungen und importierte JSON-Konfiguration. Audiodaten und Serverantworten sind Eingaben. Die App hat App Sandbox, ausgehenden Netzwerkzugriff und Mikrofonrecht. Bedienungshilfen werden über TCC gewährt. Sie läuft ohne root. Es gibt kein Konto und keine Mehrbenutzer-API. Die aktive fremde Anwendung und systemweite Zwischenablage sind Ausgaben außerhalb des App-Containers. Vom Nutzer gewählte Dienste sind beabsichtigte Empfänger. Es ist kein SSRF-Fehler, dass der Nutzer lokale Server aufrufen kann.

API-Keys werden in Security Generic Password Items gespeichert. ApiKeyStore leitet den Account aus Host und explizitem Port ab. Keys sind nicht Teil von env, Profilen und Exporten. WhisperClient und LLMClient setzen Bearer-Header. Shell-Eingaben stammen aus eigener Konfiguration und CLI. Der optionale Entwicklungsproxy bindet standardmäßig localhost und hat eigene Datei- und HTTP-Oberflächen. Er ist kein Bestandteil der normalen App-Laufzeit.

## Einstiege und Sinks

- AppDelegate.swift, SttRunner.swift und RecordingToggle.swift: Hotkeys, Menüaktionen, Abbruch, Zustandsmaschine.
- Core/Transcription/NativeBackend.swift, AudioRecorder.swift, Transcriber.swift, WhisperClient.swift und LLMClient.swift: Audio, Antworten, Netzwerk, lokale Modelle, Fallback.
- Config/ApiKeyStore.swift, EnvStore.swift, SettingsModel.swift, ProfileStore.swift, PromptStore.swift und ReplacementStore.swift: Schlüsselbund, JSON-Import und Export, Datei- und Texteingaben.
- Core/NativePaste.swift: Accessibility, synthetische Tastaturereignisse, systemweite Zwischenablage.
- Core/RuntimePaths.swift, TranscriptHistoryStore.swift, TempFileCleanup.swift, LineJournal.swift und StatusStore.swift: persistierte Daten, Aufbewahrung und Löschung.
- install.sh, macos-app/build-app.sh, macos-app/build-appstore.sh und scripts/prepare-release.sh: Installation, Signierung und Paketbau.
- stt-runtime.sh, stt-record.sh, stt-transcribe.sh, stt-postprocess.sh, stt-global-mac.sh, stt-eval-proxy.py: separate Shell- und Entwicklungsoberflächen.

Swift-Pfade liegen unter macos-app/Sources/STTBar. Tests liegen unter macos-app/Tests/STTBarTests und tests.

## Vergleich

Apple Dictation, Superwhisper und Wispr Flow sind die relevante Produktgruppe. Apple dokumentiert Diktieren an Texteingabestellen und abhängig von Einstellungen lokale Verarbeitung. Superwhisper dokumentiert Offline-Modus, Wörterbuch, frei konfigurierte Modi und Zuordnung zu Apps. Daraus folgt keine Sicherheitsgarantie für diese Produkte. STTBar muss insbesondere die eigenen Zusagen zu vertraulichem Modus, Abbruch und API-Key-Zielen erfüllen. Vergleichsquellen und Produktbewertung stehen im Hauptreport.
