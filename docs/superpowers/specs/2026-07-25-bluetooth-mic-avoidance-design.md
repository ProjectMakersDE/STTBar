# Bluetooth-Mikrofon-Vermeidung im nativen Recorder

Datum: 2026-07-25

## Problem

Sind AirPods verbunden, macht macOS sie zum Standard-Eingabegerät. Jede Diktat-Aufnahme
öffnet dann das AirPods-Mikrofon, wodurch CoreAudio das Headset von A2DP in das
bidirektionale HFP-Profil kippt: Musikwiedergabe wird hörbar dumpf und die Lautstärke
springt. Das passiert auch dann, wenn in den STTBar-Einstellungen ausdrücklich
`MacBook Pro-Mikrofon` gewählt ist.

## Zwei getrennte Ursachen

Die Untersuchung förderte zwei unabhängige Fehler zutage. Der erste erklärt, warum
die Gerätewahl wirkungslos blieb; der zweite erklärt das hörbare Umschalten, das auch
nach dessen Behebung blieb.

## Ursache 1: die Gerätewahl wird nicht angewendet

Der Schutz existiert, wird aber nicht mehr ausgeführt.

- `stt-record.sh:96` (`resolve_audio_device`) weicht Bluetooth-Eingängen aus, gesteuert
  über `STT_MACOS_AVOID_BLUETOOTH_PROFILE_SWITCH`. Eingeführt in `092e014`.
- Seit dem App-Store-Umbau (`ed3f681`) verdrahtet `AppDelegate.swift:37` den
  `NativeBackend`. Die Aufnahme läuft über `AudioRecorder`, das Shell-Skript wird für
  Aufnahmen nicht mehr aufgerufen.
- `AudioRecorder.swift:42` nimmt über `engine.inputNode` auf. Das ist immer das
  System-Standard-Eingabegerät; weder `STT_AUDIO_DEVICE` noch der Bluetooth-Schalter
  werden gelesen.

Der Gerätepicker in den Einstellungen schreibt also in eine Env-Variable, die auf dem
aktiven Codepfad niemand mehr liest. Der Hinweistext `SettingsView.swift:52`
("Bluetooth-Headsets werden vermieden") beschreibt Verhalten, das es nicht mehr gibt.

## Ursache 2: AVAudioEngine reißt die Wiedergabe ab

Nach Behebung von Ursache 1 nahm die App nachweislich vom eingebauten Mikrofon auf —
und das Umschalten blieb trotzdem, ausschließlich beim Starten einer Aufnahme.

Eine `AVAudioEngine` besitzt immer auch einen Ausgangsknoten am **Standard-Ausgabe-
gerät**, selbst wenn nichts damit verbunden ist. Beim Start handelt sie diesen Strom
neu aus. Gemessen mit CoreAudio-Property-Listenern (Stichproben alle 200 ms übersehen
den Vorgang):

```
+160 ms  stopped  AirPods Pro [out]
+256 ms  STARTED  MacBook Pro-Mikrofon [in]
+357 ms  STARTED  AirPods Pro [out]
```

Rund 200 ms Unterbrechung der Wiedergabe, bei jedem Aufnahmestart, unabhängig vom
gewählten Mikrofon. Auf einem Bluetooth-Headset ist diese Neuaushandlung deutlich
hörbar. Das Stream-Format bleibt dabei unverändert bei 48 kHz stereo — eine Messung
über Formate oder Abtastraten zeigt den Fehler daher nicht.

Dieselbe Messung mit einer reinen Eingangs-AudioUnit meldet nur das Mikrofon und rührt
kein Wiedergabegerät an. Das erklärt auch, warum das Problem im alten Shell-Backend
nicht auftrat: `sox -t coreaudio` arbeitet genau so.

## Lösung

### `Core/Transcription/AudioRecorder.swift` (umgebaut)

Aufnahme läuft über eine bare AUHAL-Einheit (`kAudioUnitSubType_HALOutput`) mit
aktiviertem Eingangs- und deaktiviertem Ausgangsbus, gebunden an das aufgelöste Gerät
vor `AudioUnitInitialize`. Ohne Ausgangsseite gibt es nichts, was ein Wiedergabegerät
neu aushandeln könnte. Die Umrechnung auf 16 kHz mono bleibt bei `AVAudioConverter`,
also unverändert gegenüber dem erprobten Pfad; ausgetauscht wird allein die Geräte-
anbindung.

### `Core/AudioDevices.swift` (neu)

CoreAudio-Wrapper. Liefert für jeden Eingang `AudioDeviceID`, Name und Transporttyp
(`kAudioDevicePropertyTransportType`), dazu das aktuelle Standard-Eingabegerät. Nur
Geräte mit mindestens einem Eingangskanal zählen als Eingang.

### `Core/AudioInputResolver.swift` (neu)

Reine Entscheidungslogik über Wertetypen, ohne CoreAudio-Abhängigkeit und damit
vollständig unit-testbar. Regeln in dieser Reihenfolge:

1. Im Picker gewähltes Gerät verbunden → dieses Gerät, auch wenn es Bluetooth ist.
   Eine bewusste Auswahl schlägt den Schalter.
2. Gewähltes Gerät nicht verbunden → weiter mit Regel 3, statt still auf den
   Systemstandard zu fallen.
3. Automatik und Schalter aus → Systemstandard.
4. Automatik, Schalter an, Standard ist Bluetooth → erstes eingebautes Mikrofon, sonst
   erstes USB-Gerät, sonst erster Nicht-Bluetooth-Eingang. Gibt es keinen, bleibt es
   beim Systemstandard: eine Aufnahme in schlechter Qualität ist besser als keine.

### Einstellungen

Neuer Schalter "Bluetooth-Mikrofone vermeiden" im Abschnitt Audio-Eingang,
Standard an. Er schreibt denselben Key `STT_MACOS_AVOID_BLUETOOTH_PROFILE_SWITCH`, den
die Shell-Skripte bereits nutzen, damit beide Pfade derselben Regel folgen. Der
irreführende Hinweistext wird korrigiert.

Die Geräteliste des Pickers kommt künftig aus CoreAudio statt aus `AVCaptureDevice`.
Ein Namensabgleich zwischen zwei verschiedenen Quellen ist genau die Sorte stiller
Fehlschlag, die dieses Problem verursacht hat.

## Verifikation

- Unit-Tests für alle vier Resolver-Regeln, dazu vier für `InstallPaths`.
- Messung am realen Gerät mit CoreAudio-Property-Listenern auf
  `kAudioDevicePropertyDeviceIsRunningSomewhere` aller Geräte. Vor dem Umbau standen
  bei jedem Aufnahmestart `stopped`/`STARTED` auf dem Bluetooth-Ausgang im Protokoll,
  danach ausschließlich Ereignisse des gewählten Mikrofons.

## Messfallen

Zwei Signale sehen nach einem Beweis aus und sind keiner:

- **Die Nominalrate des Bluetooth-Geräts.** macOS führt AirPods als zwei Objekte
  gleichen Namens, ein Eingangs- und ein Ausgangsobjekt. Die Rate des Eingangsobjekts
  schwankt unabhängig vom Wiedergabeprofil. Aussagekräftig ist allein das Stream-Format
  im Ausgangs-Scope — und selbst das bleibt beim hier gefundenen Fehler unverändert.
- **Stichproben.** Die Wiedergabe setzt für rund 200 ms aus. Ein Polling-Intervall von
  200 ms übersieht das zuverlässig. Nur Listener sind hier belastbar.
