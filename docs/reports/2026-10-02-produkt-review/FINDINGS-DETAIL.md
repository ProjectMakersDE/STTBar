# STTBar Sicherheitsnachweise

Geprüfter Stand: v1.7.0, f09a5ce, 2. Oktober 2026.

Es wurde keine bestätigte Sicherheitslücke der Stufe MEDIUM oder höher festgestellt. Die bestätigten Datenschutzfehler der nativen App sind im Produktreport beschrieben. Sie belegen keine fremde Datenabfrage oder Privilegienübernahme.

## Lokale Prozessunterbrechung in den optionalen Shell Werkzeugen

LOW. Der vollständige Ablauf und die Bedingungen stehen in [findings.json](findings.json). `stt-record.sh:15` setzt den gemeinsamen Legacy-Pfad `/tmp/stt-recording.pid`. `cancel_recording:255` ruft `force_clear_recordings` auf. Die Schleife ab Zeile 227 liest die Datei, prüft ab Zeile 231 nur `kill -0` und schickt an diesen PID SIGINT sowie später TERM. Dateieigentümer und Recorder-Identität werden nicht geprüft.

Ein anderes lokales Benutzerkonto kann eine noch nicht vorhandene, lesbare Datei mit dem PID eines fremden Prozesses anlegen. Verwendet der Besitzer des Prozesses anschließend die alten Shell-Werkzeuge, signalisiert sein Skript diesen Prozess mit seinen Rechten. Das kann Arbeit unterbrechen. Die aktuelle native App und die App-Store-App starten diese Skripte nicht.

Die Reproduktion unter [verification/run_checks.py](verification/run_checks.py) verwendet unveränderte Skriptkopien ohne `.env`, eigene Dateipfade und einen abgefangenen `kill`-Aufruf. Der positive synthetische PID `424242` erreichte SIGINT und TERM. Es wurden keine echten Prozesse signalisiert. Ergebnis: [verification/reproductions.json](verification/reproductions.json).

Apple Dictation, Superwhisper und Wispr Flow sind der Produktvergleich. Eine eigene Legacy-PID-Migration dieser Programme wurde nicht untersucht. Daraus wird keine vergleichende Sicherheitsbehauptung abgeleitet.
