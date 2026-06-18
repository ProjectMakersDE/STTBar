# STT Post-Processing — Faktentreue-Auswertung (Lauf 2: Selbstkorrekturen)

**Datum:** 2026-06-17
**Modell:** `qwen/qwen3.6-35b-a3b` · temperature `0.2` · reasoning `off`
**Prompt:** v3-Variante mit **expliziter Selbstkorrektur-Regel** (Regel 2 „Selbstkorrekturen — zentral!")
**Context-Budget:** 8192 Token — eingehalten (Prompt ~1.160 + Input 48–501 + Ausgabe ≈ < 1.700 gesamt pro Lauf, Reserve immer ~6.500)
**Fokus:** verwirrende, gesprochene Inputs mit absichtlichen Selbstkorrekturen (Dev→Live, Dateinamen, Zahlen, Richtung). Prüfkriterium: bleibt der **richtige (finale) Wert** erhalten, und wird der falsche idealerweise entfernt.

## Ergebnis

| # | Szenario | Länge | Korrektur(en) | Fakten (auto) | Bewertung |
|---|----------|-------|---------------|:---:|:---:|
| 1 | Deployment-Pipeline | lang | Dev→**Live**, deploy.yml→**release.yml**, Node 18→**20** | 10/10 | **10** |
| 2 | DB-Migration | mittel | Staging→**Produktion** | 6/6 | **10** |
| 3 | Caching | lang | memcached→**Redis** (Doppel-Flip), 15→**10 Min**, „nur Live"→**Dev zuerst** | 7/7 | **10** |
| 4 | Datumslib | kurz | moment.js→**day.js** | 2/2 | **10** |
| 5 | Config-Sync | mittel | Richtung prod→dev → **dev→prod** | 5/5 | **10** |
| 6 | Benachrichtigungen | lang | Monolith→**Service**, „erst Live"→**Dev zuerst**, Dateiname→**order_confirmation.html** | 10/10 | **10** |
| 7 | Login-Check | kurz | validateUser→**verifyUser**, user.service.ts→**auth.service.ts** | 2/2 | **9** |
| 8 | Rate-Limit | kurz | 100→**60** req/min | 4/4 | **10** |
| 9 | Suche | lang | Elasticsearch→**Postgres**, „jeder Buchstabe"→**Debounce 300ms** | 10/10 | **8** |
| 10 | Reconciliation | lang | **Demo→Live** (kritisch) | 9/9 | **10** |

**Schnitt: 9,7 / 10.**

## Kernbefund

**Alle Selbstkorrekturen wurden korrekt aufgelöst.** In jedem einzelnen Szenario blieb der **richtige (zuletzt genannte) Wert** erhalten; in keinem Fall wurde der korrigierte/gültige Wert gelöscht oder mit dem verworfenen vertauscht. In den meisten Fällen wurde der falsche Wert sogar sauber entfernt oder explizit als verworfen markiert:

- „über den GitHub Actions Workflow **release.yml** (nicht deploy.yml)" (S1)
- „Wir bleiben bei **Redis**; Memcached war der alte, verworfene Vorschlag" (S3) — trotz des doppelten „andersrum"-Flips
- „von der **Dev**-Config in die **Prod**-Config" (S5) — Richtungswechsel korrekt
- „heißt **order_confirmation.html** (mit Unterstrich)" (S6)
- „Die Methode heißt **verifyUser** (nicht validateUser) und liegt in **auth.service.ts** (nicht user.service.ts)" (S7)
- **S10 (dein ursprünglicher Fehlerfall):** „Der Job soll in der **Live-Umgebung** mit echten Stripe-Live-Daten gebaut und getestet werden, **nicht in der Demo-Umgebung**." → Der alte Fehler (Demo komplett rausgestrichen / Richtung vertauscht) tritt **nicht** mehr auf.

**Empfehlung:** Die explizite Selbstkorrektur-Regel in den produktiven Prompt übernehmen — sie liefert genau das gewünschte Verhalten.

## Die zwei einzigen (unkritischen) Schwächen

1. **S9 (Bewertung 8):** Alle Fakten korrekt, aber das Modell hat das gesprochene Hin-und-Her *verbatim* behalten statt es zu glätten: „… die reicht. Doch okay, wir bleiben bei PostgreSQL …" und „… Vorschläge zeigt. **Nein, Moment**, nicht nach jedem Buchstaben …". Kein Faktenfehler — der finale Wert ist eindeutig da — aber unsauber. Tritt auf, wenn die Korrektur in mehreren Etappen mit Zwischen-„doch/ne/Moment" erfolgt.
2. **S7 (Bewertung 9):** harmloses Meta „Das verwechsle ich immer" wurde beibehalten.

Beides ist laut deiner Vorgabe akzeptabel (Hauptsache der richtige Wert bleibt). Wer es strenger will: in Regel 2 ergänzen, dass bei *eindeutiger* mehrstufiger Korrektur nur der finale Wert genannt wird und die Zwischenschritte („doch", „ne", „Moment", „ich dachte erst") entfallen.

---

## Anhang — vollständige Modell-Outputs

### S1 (10)
```
Der Service soll auf die Live-Umgebung (Produktion) deployed werden; der Dev-Stand ist bereits durch. Das Deployment läuft über den GitHub Actions Workflow release.yml (nicht deploy.yml). Der Workflow umfasst drei Stages: Build, Test und Deploy. Der Deploy-Schritt soll nur im Branch main ausgeführt werden; bei Feature Branches nur Build und Test. Die Secrets für die Live-Umgebung (Stripe Live Key, Datenbank-Passwort) kommen aus den GitHub Environment Secrets unter dem Environment "production", nicht aus den normalen Repo Secrets. Nach dem Deployment soll der Health Check den Endpunkt /health anpingen; bei keinem 200er innerhalb von 30 Sekunden erfolgt ein automatischer Rollback auf die vorherige Version. Bei Erfolg wird eine Nachricht in den Slack Channel #deployments gepostet, bei Fehler in #alerts. Die Node-Version im Workflow muss auf 20 stehen.
```

### S2 (10)
```
Die Migration, die die User-Tabelle umbaut und die neue Spalte Last Login hinzufügt, soll direkt auf der Produktionsdatenbank laufen, weil die Staging-Datenbank diese Woche nicht mehr angefasst wird und die Daten dort veraltet sind. Ziehe vorher ein Backup. Die Migration muss in einer Transaktion laufen, damit bei Fehlern alles zurückgerollt wird. Fahre die Migration nur im Wartungsfenster, nicht während die User online sind.
```

### S3 (10)
```
Das Caching-Thema ist verwirrend. Wir wollen die Produktdetailseiten cachen, weil die Datenbank unter Last leidet. Wir bleiben bei Redis; Memcached war der alte, verworfene Vorschlag. Der Redis läuft auf dem Cache-Server unter Port 6379 (Standard). Die Produktdetailseiten werden für 10 Minuten gecacht (TTL), da sich die Preise öfter ändern als bei 15 Minuten. Wenn ein Produkt im Backend geändert wird, muss nur der Cache für genau dieses Produkt invalidiert werden, nicht der gesamte Cache. Das Cachen erfolgt zuerst in der Dev-Umgebung zum Testen und anschließend in der Live-Umgebung. Der Cache soll einen Fallback haben: Falls Redis nicht erreichbar ist, soll die Seite direkt aus der Datenbank laden, ohne abzustürzen.
```

### S4 (10)
```
Nimm Day.js für die Datumsformatierung im Dashboard. Moment.js ist deprecated und zu groß.
```

### S5 (10)
```
Kopiere die Datenbank-Pool-Einstellungen von der Dev-Config in die Prod-Config. Die Dev-Umgebung enthält die getesteten neuen Pool-Werte, die Prod-Umgebung noch die alten. Kopiere nur die Pool-Einstellungen (Pool-Size und Timeout), nicht die gesamte Konfiguration. Überschreibe weder die Credentials noch die URLs.
```

### S6 (10)
```
Erstelle ein Benachrichtigungssystem für Bestellungen. Wenn eine Bestellung eingeht, soll der Kunde eine Bestätigungs-E-Mail erhalten und im internen System eine Benachrichtigung für das Fulfillment-Team aufpoppen. Das gehört in den Notification Service, nicht in den Monolithen. Der Monolith schickt nur ein Event raus und der Notification Service hört darauf.

Das Ganze soll zuerst in der Dev-Umgebung getestet werden, nicht in Live. Teste mit einem Test-Postfach und schalte es erst auf Live, wenn es sauber durchläuft.

Die E-Mail-Vorlage liegt als Template im Ordner `templates/emails` und heißt `order_confirmation.html` (mit Unterstrich). Die E-Mail muss in der Sprache des Kunden ausgehen. Die Templates liegen in Deutsch und Englisch vor; die Sprache steht im Kundenprofil unter dem Feld `locale`.

Die interne Benachrichtigung für das Fulfillment-Team läuft über WebSockets, damit sie in Echtzeit aufpoppt, ohne dass die Seite neu geladen werden muss. Falls der Mail-Versand fehlschlägt, soll das in eine Retry-Queue gehen. Nach drei Fehlversuchen muss ein Mensch informiert werden, also ein Alert ans Support-Team, nicht einfach still verschluckt werden.
```

### S7 (9 — „Das verwechsle ich immer" beibehalten)
```
Die Validierung beim Login: Die Methode heißt verifyUser (nicht validateUser) und liegt in auth.service.ts (nicht in user.service.ts). Das verwechsle ich immer.
```

### S8 (10)
```
Stelle das Rate Limiting für die öffentliche API ein. Es sollen 60 Requests pro Minute pro IP gelten. Wer darüber geht, erhält einen 429, und der Zähler resettet sich jede Minute.
```

### S9 (8 — gesprochenes Hin-und-Her nicht geglättet)
```
Das Suchfeature für den Produktkatalog wird interessant. Wir wollen eine Volltextsuche. Ich dachte erst, wir machen das mit Elasticsearch, aber das ist überdimensioniert für unsere Datenmenge. Wir nehmen erstmal die PostgreSQL-Volltextsuche, die reicht. Doch okay, wir bleiben bei PostgreSQL Full Text Search; Elasticsearch heben wir uns für später auf, wenn die Datenmenge wächst. Also jetzt PostgreSQL. Die Suche soll über den Produktnamen, die Beschreibung und die Tags gehen, aber nicht über interne Felder wie die Einkaufspreise. Das darf nicht durchsuchbar sein. Die Ergebnisse sollen nach Relevanz sortiert werden und, wenn zwei gleich relevant sind, nach Verkaufszahl absteigend. Die Suche soll auch tippfehler tolerant sein, also Fuzzy Matching ein bisschen, aber nicht zu aggressiv, sonst kommt Müll. Und ein Autocomplete soll es geben, das Vorschläge zeigt. Nein, Moment, nicht nach jedem getippten Buchstaben, das feuert zu viele Requests, sondern mit einem Debounce von sagen wir 300 Millisekunden. Die Suche selbst bauen wir als eigenen Endpunkt /api/search, der einen Query-Parameter q nimmt. Und ganz wichtig: Das soll erstmal nur auf der Dev-Umgebung laufen, zum Ausprobieren. Auf Live kommt das erst, wenn die QA das abgenommen hat. Also auf keinen Fall direkt auf Live schalten. Achso, und die Suche ist öffentlich; da braucht man kein Login. Die Produktdaten sind eh public.
```

### S10 (10 — kritischer Demo→Live-Fall, korrekt)
```
Der letzte Schritt betrifft die Zahlungsabstimmung (Reconciliation). Das Problem besteht darin, dass Zahlungen bei Stripe durchgehen, im eigenen System aber nicht als bezahlt markiert werden, weil Webhooks verloren gehen.

Es wird ein Abgleich-Job benötigt, der einmal täglich läuft. Der Job zieht sich von Stripe alle erfolgreichen Zahlungen der letzten 24 Stunden und gleicht sie mit den Bestellungen ab.

- Wenn eine Bestellung im eigenen System noch auf „offen" steht, bei Stripe aber bereits bezahlt ist, wird der Status nachgesetzt.
- Wenn im eigenen System etwas als bezahlt steht, bei Stripe aber storniert wurde, wird dies zur manuellen Prüfung geflaggt. Eine automatische Stornierung erfolgt nicht, da dies zu heikel ist.

Der Job soll in der Live-Umgebung mit echten Stripe-Live-Daten gebaut und getestet werden, nicht in der Demo-Umgebung.

Der Job darf unter keinen Umständen doppelte Buchungen erzeugen. Bevor er einen Status nachsetzt, muss er prüfen, ob nicht bereits ein anderer Prozess dies tut.

Der Job läuft nachts um drei Uhr. Er erzeugt einen Report über die Anzahl der gefundenen Diskrepanzen und der automatisch korrigierten Einträge. Der Report wird per E-Mail an die Buchhaltung gesendet.

Wenn der Job mehr als 50 Diskrepanzen findet, soll er nicht automatisch korrigieren, sondern stoppen und Alarm schlagen, da dies auf ein größeres Problem hindeutet.
```
