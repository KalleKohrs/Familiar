# ADR 0001: Supabase als Backend

- **Status:** angenommen (2026-10-20)
- **Kontext:** Kein bestehendes Backend. Anforderungen: passwortlose E-Mail-, Apple- und Google-Anmeldung; Postgres mit strenger Zugriffskontrolle pro Familie und Nutzer; geschützte Bildablage; zeitnahe Aktualisierung; geplante Jobs (Vorkommen, Erinnerungen, Push, Outlook-Sync); sichere Secret-Verwaltung.
- **Entscheidung:** Supabase (Postgres + RLS, Auth, Storage, Realtime, Edge Functions, `pg_cron`/`pg_net`, Vault). Projekt `ldeouecoaqyfvubhrjei` ist die Dev-Umgebung; vor dem Release wird ein separates Produktionsprojekt angelegt.
- **Konsequenzen:** Nur der Publishable-Key gelangt in die App; Server-Code nutzt Secret-Keys aus der Function-Umgebung. Legacy-`anon`/`service_role`-Keys werden nicht verwendet (laut Supabase-Doku laufen sie Ende 2026 aus). Migrationen werden versioniert unter `supabase/migrations/` abgelegt und über das Supabase-MCP angewendet, da lokal keine CLI installiert ist.
