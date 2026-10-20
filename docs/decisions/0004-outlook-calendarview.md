# ADR 0004: Outlook-Sync über calendarView mit Calendars.ReadBasic

- **Status:** angenommen, mit Prüfvorbehalt (2026-10-20)
- **Kontext:** Nutzer wählen selbst, welche Outlook-Kalender einbezogen werden. Minimal nötige Microsoft-Berechtigungen; Tokens dürfen nicht unsicher im Client liegen; Änderungen und Absagen sollen beim nächsten Sync ankommen.
- **Entscheidung:** Vertraulicher Client (Entra, Web-Plattform) mit Auth-Code-Flow + PKCE; Redirect auf eine Edge Function; Refresh-Token nur im Supabase Vault. Scopes `Calendars.ReadBasic offline_access openid email`. Sync per `GET /me/calendars/{id}/calendarView` über ein Zeitfenster (−7 bis +120 Tage) mit vollständigem Abgleich (Upsert + Entfernen fehlender Termine).
- **Begründung:** Laut Microsoft-Graph-Doku ist `Calendars.ReadBasic` die geringste Berechtigung für `calendarView` und das Auflisten der Kalender (auch für private Microsoft-Konten). Die Delta-Abfrage (`event: delta`) gilt in v1.0 nur für den Primärkalender und verlangt `Calendars.Read`.
- **Prüfvorbehalt (Spike S3):** Mit einem realen Testtermin wird geprüft, ob Organisator und Teilnehmer mit `Calendars.ReadBasic` vollständig geliefert werden. Falls nicht: Wechsel auf `Calendars.Read` (weiterhin nur lesend), dokumentiert in diesem ADR. Bekannte Grenze: Bei `hideAttendees = true` ist keine Teilnehmerprüfung möglich; solche Termine werden vom Filter ausgeschlossen.
