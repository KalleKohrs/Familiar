# ADR 0003: Lesen per RLS, Schreiben nur über geprüfte RPCs

- **Status:** angenommen (2026-10-20)
- **Kontext:** Viele Regeln betreffen mehrere Tabellen oder einzelne Spalten (nur zugewiesene Personen haken ab, der Ersteller darf direkt erledigen, letzter Admin, Serien und Vorkommen, Einladungs-Rate-Limit). Das lässt sich mit Tabellen-Policies allein nicht verlässlich ausdrücken.
- **Entscheidung:** `authenticated` darf exponierte Tabellen nur lesen (RLS). Alle Schreibvorgänge laufen über `security definer`-Funktionen mit `search_path = ''`, expliziten Rechteprüfungen und sprechenden Fehlern. Hilfsfunktionen liegen im nicht exponierten Schema `private`.
- **Konsequenzen:** Jede neue Schreiboperation braucht eine RPC samt Tests (Erfolg, verweigerter Zugriff, Grenzfälle). RLS-Tests simulieren Nutzer per `set local role authenticated` und `request.jwt.claims`.
