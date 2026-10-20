# ADR 0005: Push-Mitteilungen und Live Activities serverseitig über APNs

- **Status:** angenommen, mit Prüfvorbehalt (2026-10-20)
- **Kontext:** Live Activities sollen fünf Minuten vor Start auf allen Geräten der zugewiesenen Personen erscheinen, auch wenn die App nicht läuft; Push-Mitteilungen zu Zuweisung, Start, Erinnerung, Erledigung und Änderungen. Die Datenbank bleibt maßgeblich.
- **Entscheidung:** Outbox-Tabelle `notification_jobs` (idempotent über `dedupe_key`), per `pg_cron` minütlich an die Edge Function `push-dispatch` übergeben, die APNs mit Token-Authentifizierung (ES256-JWT) über HTTP/2 anspricht. Live Activities starten per Push-to-Start (`event: start`, `input-push-token: 1`); Updates und Ende per Activity-Token. Beim Öffnen gleicht die App lokal ab.
- **Grenzen laut Apple-Doku:** Eine Live Activity ist höchstens 8 Stunden aktiv und danach bis zu 4 Stunden auf dem Sperrbildschirm; statische und dynamische Daten zusammen höchstens 4 KB; Anzahl gleichzeitiger Activities systemabhängig; Zustellung nicht garantiert.
- **Prüfvorbehalt (Spike S2):** HTTP/2 aus der Supabase-Edge-Runtime ist nicht dokumentiert. Ausweichwege: `node:http2` in der Edge-Runtime; andernfalls ein separater Sender (eigene Entscheidung).
