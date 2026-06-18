# STT Post-Processing — Faktentreue-Auswertung

**Datum:** 2026-06-17
**Modell:** `qwen/qwen3.6-35b-a3b` · temperature `0.2` · reasoning `off`
**Prompt:** v3 (`stt-postprocess-prompt-v3.md`, „Oberstes Gesetz")
**Context-Budget:** 8192 Token — eingehalten (Prompt ~2.6k + Input ~0.9–1.1k + Ausgabe ~0.4–0.6k ≈ < 4.3k pro Lauf)
**Durchführung:** 5 Szenarien über die Testseite gegen den live laufenden LM-Studio-Endpoint, Laufzeit 4,6–9,0 s je Szenario (~98 tok/s).

## Ergebnis

| # | Szenario | Faktentreue (auto) | Bewertung | Kernbefund |
|---|----------|:--:|:--:|------------|
| 1 | Stripe-Feature Demo → Live portieren | 9/9 | **9** | Demo erhalten, Richtung korrekt, alle Config-Unterschiede getrennt; kleine Detail-Auslassung |
| 2 | Reporting/Export: Vorlage vs. Ziele | 13/13 | **10** | Fehlerfrei |
| 3 | Microservice-Architektur (4 Services) | 10/10 | **8** | Fakten top, aber einleitendes Lob nicht entfernt |
| 4 | Export-Rechte (Selbstkorrektur/Scope) | 9/9 | **8** | Fakten top, aber einleitendes Lob nicht entfernt |
| 5 | Migration + Logging + Rate-Limit | 10/10 | **10** | Fehlerfrei |

**Schnitt: 9,0 / 10.** Faktentreue insgesamt sehr hoch — Rollen, Referenzen, Scope-Qualifizierer, exakte Bezeichner/Dateinamen, „nicht verschmelzen" und bewusste Tradeoffs wurden korrekt erhalten.

## Wichtig: der ursprüngliche Fehler trat NICHT mehr auf

Im kritischen Szenario 1 (genau dein Praxisfall) hat das Modell die **Demo-Umgebung vollständig erhalten**, die Richtung Demo → Live korrekt abgebildet, die Demo als „unangetastet" markiert und die beiden Umgebungen **nicht** verschmolzen. Die drei Unterschiede (Live-Key aus dem Vault, Webhook-URL ohne `demo`-Prefix, Sendgrid statt Mailtrap) blieben sauber getrennt.

→ Falls dein früherer Fehlerfall (Demo komplett rausgestrichen) auftrat, lag das vermutlich an einem **anderen/kleineren Modell oder einem älteren Prompt**. Empfehlung: denselben Input gegen das damals genutzte Modell gegentesten, um das zu bestätigen.

## Einziges wiederkehrendes Problem (für die Prompt-Anpassung)

**Lob/Meta über frühere Arbeit wird nur dann entfernt, wenn es ein reines Kompliment ist.**

- Zuverlässig entfernt (Kompliment-Floskel): „erste Sahne", „du machst das top", „großes Lob" → S1, S2, S5 starten direkt mit der Anweisung. ✓
- **Nicht** entfernt, wenn das Lob als *sachliche Status-Aussage* formuliert ist:
  - S3 behielt: „Die Migration auf Docker lief letzte Woche absolut reibungslos."
  - S4 behielt: „Das Error-Handling von letztes Mal war vorbildlich und sehr robust."
  Das Modell liest diese Sätze als Inhalt (klingt wie ein Statusbericht) statt als wegzuwerfendes Geplauder.
- Nebenbefund: Fluch-Betonung teils beibehalten — S3 behielt „Verdammt wichtig:".

### Konkrete Prompt-Empfehlung

Regel 1 um eine explizite Klausel ergänzen, z. B.:

> Lob, Dank und Status-Bemerkungen über *frühere oder andere* Arbeit entfallen vollständig — **auch wenn sie als sachliche Aussage formuliert sind** („X lief reibungslos", „Y war robust", „Z hat super funktioniert", „das hat mich drei Tage gekostet"). Sie sind nicht Teil der jetzt umzusetzenden Anweisung. Nur Aussagen über den **aktuell** zu bearbeitenden Sachverhalt bleiben erhalten.

Und für die Flüche:

> Verstärker-Flüche („verdammt", „krass", „mega") sind Hülle und entfallen; das betonte Sachwort bleibt („verdammt wichtig" → „wichtig").

### Detail zu Szenario 1 (warum 9 statt 10)

Die Beschreibung des bestehenden, zu portierenden Stands wurde leicht gerafft: **„Signaturprüfung mit dem Webhook-Secret"** und **„Bestellung auf ‚bezahlt' setzen"** fehlen im Output. Inhaltlich unkritisch (der Auftrag „Stand 1:1 portieren" bleibt klar), aber streng nach Regel 5 (nichts weglassen) eine kleine Auslassung. Falls solche Internas erhalten bleiben sollen, Regel 5 für „Beschreibung des bestehenden Stands" schärfen.

---

## Anhang — vollständige Modell-Outputs

### Szenario 1 (Rating 9)
```
Portiere den funktionierenden Stand aus der Demo-Umgebung in die Live-Umgebung (Produktion). Die Demo-Umgebung bleibt unverändert und darf nicht bearbeitet oder gelöscht werden.

Die Unterschiede zwischen Demo und Live sind:

1. API Keys: In der Demo läuft alles mit dem Stripe Test Key `sk_test_...`. In der Live-Umgebung muss der Live Key `sk_live_...` aus dem Vault unter `secret/stripe/live` zur Laufzeit bezogen werden. Nichts hardcoden.
2. Webhook URL: In der Demo ist der Endpunkt unter `/api/demo/webhook` registriert. In der Live-Umgebung muss er unter `/api/webhook` (ohne das "demo"-Prefix) laufen.
3. Bestätigungs-E-Mail: In der Demo geht die E-Mail an ein Mailtrap-Postfach. In der Live-Umgebung muss sie über den echten Sendgrid-Versand rausgehen.

Die Idempotenz-Logik und das Dekrementieren des Lagerbestands bleiben in beiden Umgebungen identisch und dürfen nicht geändert werden.

Die Retry-Logik mit Exponential Backoff für fehlgeschlagene Webhooks, die bisher nur in der Demo getestet wurde, muss zwingend auch in die Live-Umgebung übernommen werden, da Live-Webhooks erfahrungsgemäß öfter verzögert oder doppelt eintreffen.

Zusammenfassung: Portiere den funktionierenden Demo-Stand nach Live mit Live-Key aus dem Vault, Live-Webhook-URL ohne Demo-Prefix, echtem Sendgrid-Versand und der Retry-Logik. Die Demo-Umgebung bleibt komplett unangetastet.
```

### Szenario 2 (Rating 10)
```
Als Nächstes baue die User Card für das gesamte Reporting-Modul aus. Die User Card ist das Design-Vorbild; sie bleibt unverändert und dient nur als Referenz.

Die Product Card, die Order Card und die Invoice Card sollen exakt das Layout der User Card übernehmen (Icon links, Werte rechts). Dies gilt an zwei Stellen:
1. Im Dashboard-Grid, wo die Karten in einem Raster nebeneinander liegen.
2. In der neuen Export-Vorschau, wo die Karten untereinander in einer Liste gerendert werden.

Achte darauf, dass der Hover-Effekt mit dem Schatten nur im Dashboard-Grid aktiv ist. In der Export-Vorschau darf er nicht erscheinen, da er beim Scrollen flackert und billig wirkt.

Die Invoice Card hat als einzige ein Status-Badge oben rechts (bezahlt, offen, überfällig in Ampelfarben). Dieses Badge muss in jeder Ansicht erhalten bleiben.

Für den Export verwende keine PDF, sondern eine XLSX-Datei (Excel), da dies für die Buchhaltung praktischer ist.

Die Funktion, die den Export anstößt, heißt `buildExportSheet` und befindet sich in der Datei `export.service.ts`.

Es reicht aus, wenn der Export zunächst nur die aktuell sichtbaren Spalten exportiert; den kompletten Datensatz erweitern wir später.

Nutze Throttling beim Klick auf den Export-Button, um zu verhindern, dass bei einem Doppelklick zwei Exporte gleichzeitig starten.
```

### Szenario 3 (Rating 8 — Lob „Migration auf Docker lief reibungslos" nicht entfernt)
```
Die Migration auf Docker lief letzte Woche absolut reibungslos. Wir ziehen das Backend jetzt komplett auf Microservices. Ich beschreibe die vier Services einzeln, damit nichts verloren geht:

1. Der Auth-Service macht Login, Registrierung, Passwort-Reset und stellt die JWT-Access-Tokens aus. Er hält die Refresh-Tokens in einem Redis vor mit einer TTL von sieben Tagen.
2. Der User-Service verwaltet die Profil-Daten (Name, Adresse, Avatar) und die Benachrichtigungs-Einstellungen. Er hört auf ein User-Created-Event vom Auth-Service und legt dann automatisch ein leeres Profil an.
3. Der Billing-Service erzeugt die Rechnungen, verwaltet die Abos und macht die komplette Stripe-Anbindung. Für die Rechnungs-Adresse fragt er den User-Service ab.
4. Der Notification-Service verschickt E-Mails und Push-Nachrichten. Er lauscht auf Events von allen drei anderen Services (Auth, User und Billing feuern ihm Events).

Verdammt wichtig: Die Kommunikation läuft grundsätzlich asynchron über RabbitMQ. Die einzige Ausnahme ist der Billing-Service, der den User-Service synchron per HTTP aufruft, weil er die Rechnungs-Adresse im Moment der Rechnungs-Erstellung sofort braucht und nicht auf ein Event warten kann.

Jeder Service hat strikt seine eigene Datenbank. Die teilen sich niemals eine Datenbank. Database-per-Service ist hier Gesetz. Der Auth-Service ist als einziger von außen über das API-Gateway erreichbar. Die anderen drei hängen im internen Netz und sind von draußen nicht ansprechbar.

Falls RabbitMQ mal nicht erreichbar ist, sollen die Events in einer Outbox-Tabelle zwischengespeichert und später erneut verschickt werden. Nicht einfach verloren gehen. Das ist mir extrem wichtig.
```

### Szenario 4 (Rating 8 — Lob „Error-Handling war vorbildlich" nicht entfernt)
```
Zugriffsrechte für den neuen Datenexport. Das Error-Handling von letztes Mal war vorbildlich und sehr robust.

Zunächst dachte ich an ein komplettes Rollen- und Rechtesystem mit Rollen wie Admin, Editor, Viewer und feingranularen Permissions. Das ist jedoch für den Moment völlig überzogen. Lass das.

Es reicht, wenn ausschließlich die Admin-Rolle auf den Export-Endpunkt zugreifen darf. Alle anderen Rollen erhalten einen 403 Forbidden.

Die Funktion, die diesen Check macht, heißt nicht `checkPermission`, sondern `hasAdminAccess`. Sie liegt in der Datei `auth.guard.ts`.

Welche Rollen exportieren dürfen, steht nicht in der Datenbank, sondern in der `.env` unter dem Schlüssel `export_allowed_roles`.

Vermische das nicht mit der normalen Authentifizierung. Der Admin-Check ist eine zusätzliche Schicht, die erst läuft, nachdem sich der User ganz normal über das JWT eingeloggt hat. Also zuerst der normale Auth-Guard und dann obendrauf dieser Admin-Check speziell nur für den Export.

Benutze für die Prüfung Memoization, damit die `.env` nicht bei jedem Request neu geparst wird.
```

### Szenario 5 (Rating 10)
```
Es geht um drei Dinge, die strikt auseinandergehalten werden müssen, damit sie nicht vermischt werden:

1. Die Datenmigration, die die alten Bestell-Datensätze aus dem alten Schema in das neue normalisierte Schema überführt. Das gehört ausschließlich in den Order-Service.
2. Das Audit-Logging, also dass bei jeder Zahlung der komplette Request inklusive Betrag und Payment-Method-ID mitgeschrieben wird. Das gehört in den Payment-Service, nicht in den Order-Service.
3. Das neue Rate-Limiting für die öffentliche API. Das gehört ins API-Gateway.

Das sind drei verschiedene Baustellen in drei verschiedenen Komponenten; wirf sie nicht in einen Topf.

Zur Migration: Falls die Migration mittendrin abbricht oder fehlschlägt, muss sie komplett zurückrollen. Also strikt alles oder nichts. Ein halb migrierter Zustand mit teils altem, teils neuem Schema wäre eine absolute Katastrophe.

Zur Datenbank für das neue Schema: Wir nehmen ganz bewusst PostgreSQL, obwohl MongoDB eigentlich flexibler für die verschachtelten Positionen wäre. Wir brauchen die ACID-Transaktionen und die Fremdschlüssel-Beziehungen, deshalb ist es PostgreSQL. Das ist final entschieden.

Zum Audit-Logging im Payment-Service: Das darf die eigentliche Zahlungsverarbeitung niemals verlangsamen. Deshalb muss es asynchron über eine Queue rausgeschrieben werden, nicht synchron im Request, der die Zahlung abwickelt. Sonst wird der Checkout langsam.
```
