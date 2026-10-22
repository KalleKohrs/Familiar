# ADR 0009: Nächtliche Datensicherung ohne Kosten

- **Status:** vorgeschlagen (2026-10-22), wartet auf Zustimmung und das Backblaze-Konto des Nutzers. Ersetzt den Entwurf vom 2026-10-21 (GitHub Actions), siehe „Verworfen“.
- **Kontext:** Familiar läuft auch in Produktion im Supabase-Free-Tarif (Entscheidung 2026-10-21: nur kostenlose Dienste). Free enthält keine automatischen Sicherungen (Supabase-Doku „Database Backups“: tägliche Backups und PITR erst ab Pro). Gesichert werden müssen die Datenbank (Familien, Aufgaben, Zuweisungen, Profile, Anmelde-Konten) und die Bilder aus den privaten Buckets `task-images` und `avatars`. Die Sicherung muss außerhalb von Supabase liegen, damit sie einen Projektverlust übersteht. Sie darf die Familiendaten weder dem Speicheranbieter noch einem weiteren Dienst offenlegen.

## Rahmen (offizielle Doku, Stand 2026-10-22)

| Quelle | Wert |
|---|---|
| Supabase Free | 500 MB Datenbank, 1 GB Dateien, **5 GB ungecachter Traffic pro Monat für alle Dienste zusammen** (Datenbank, Storage, Edge Functions); zwei aktive Projekte |
| Supabase Edge Functions (Free) | 150 s Laufzeit, **2 s CPU-Zeit pro Aufruf** (Warten auf Netz zählt nicht), 256 MB Speicher, Secrets bis 48 KiB |
| Backblaze B2 | **10 GB dauerhaft kostenlos**, Anmeldung laut Backblaze ohne Kreditkarte; Region **EU Central (Amsterdam)** wird beim Anlegen des Kontos gewählt und ist danach fest; Lebenszyklus-Regeln löschen alte Versionen automatisch; DPA mit EU-Standardvertragsklauseln |
| Cloudflare R2 | 10 GB kostenlos, EU-Jurisdiktion möglich, aber zum Aktivieren muss ein Zahlungsmittel hinterlegt werden |
| GitHub Free (private Repos) | 2.000 Actions-Minuten pro Monat, **500 MB** für Artefakte und Packages zusammen; für private Konten **kein Auftragsverarbeitungsvertrag** (der GitHub-DPA gilt für Organisations-/Enterprise-Kunden) |

## Verworfen

| Weg | Grund |
|---|---|
| **GitHub Actions + `supabase db dump`** (Entwurf vom 2026-10-21; Supabase-Doku „Automated backups using GitHub Actions“) | Datenschutz: Die Daten liegen während des Laufs **unverschlüsselt auf GitHub-Rechnern** (USA). Für ein privates GitHub-Konto gibt es keinen Auftragsverarbeitungsvertrag. Grenzen: Jede Nacht alle Bilder neu laden kostet bei vollem Speicher (1 GB) 30 GB Traffic pro Monat statt erlaubter 5 GB. 30 Bilder-Artefakte sprengen die 500 MB. Verschlüsselte Sicherungen als Git-Commits bleiben für immer in der Historie, sodass gelöschte Familiendaten nie verschwinden. |
| **Cloudflare R2** | Verlangt ein Zahlungsmittel; sonst gleichwertig zu B2. |
| **Nur ein privates Git-Repository** | Wie oben: keine Löschfrist und keine Auftragsverarbeitung. |

## Entscheidung

**Die Sicherung läuft innerhalb von Supabase und landet verschlüsselt bei Backblaze B2 in der EU (Amsterdam).** Familiendaten verlassen Supabase nur verschlüsselt. Den Schlüssel zum Öffnen hat nur der Inhaber.

1. **Auslöser:** `pg_cron` ruft jede Nacht um 02:30 UTC `private.start_backup()` auf. Die Funktion folgt dem bestehenden Muster aus `0008_history_purge.sql`: Sie erzeugt ein Einmal-Token in `private.cron_tokens` und ruft per `pg_net` die Edge Function `backup` auf.
2. **Datenbank:** Die Function öffnet über die eingebaute Variable `SUPABASE_DB_URL` eine direkte Verbindung und liest in **einer** Transaktion (`repeatable read, read only`, also ein einheitlicher Stand) jede Tabelle als JSON:
   - `public.*`
   - `auth.users` und `auth.identities`, damit Anmeldungen samt Apple/Google erhalten bleiben
   - `supabase_migrations.schema_migrations`: Die Sicherung enthält damit auch das komplette Schema, also alle Migrationen mit ihrem SQL.

   Nicht gesichert werden Sitzungen (Nutzer melden sich nach einer Wiederherstellung neu an), Einmal-Tokens, der Outlook-Cache (`external_events`) und Outlook-Zugangstokens. Die Tokens liegen im Vault und gelten nur im alten Projekt; Outlook wird nach einer Wiederherstellung neu verbunden.
3. **Verschlüsselung (in der Function, WebCrypto):**
   - Das Ergebnis wird mit gzip gepackt.
   - Danach wird es mit **AES-256-GCM** verschlüsselt. Dieses Verfahren erkennt auch jede Veränderung der Datei. Für jede Datei gibt es einen eigenen Zufallsschlüssel.
   - Dieser Zufallsschlüssel wird mit dem **öffentlichen RSA-4096-Schlüssel** (OAEP/SHA-256) verschlüsselt.

   Den öffentlichen Schlüssel kennt die Function. Der **private Schlüssel** liegt nur im Passwort-Manager des Inhabers, nie bei Supabase, Backblaze oder im Chat. Weder Supabase noch Backblaze noch ein Angreifer mit den Backblaze-Zugangsdaten können die Sicherung lesen.
4. **Bilder (inkrementell):** Die Tabelle `private.backup_objects` merkt sich, welche Datei mit welchem Stand (ETag) schon gesichert ist. Jede Nacht passiert Folgendes:
   - Neue und geänderte Dateien (z. B. ein neues Profilbild) werden geladen, einzeln verschlüsselt und hochgeladen.
   - Dateien, die es in Supabase nicht mehr gibt, werden bei B2 **verborgen**.

   So fließt jedes Bild nur einmal und nicht jede Nacht alle. Gibt es mehr Bilder, als in einen Aufruf passen, ruft sich die Function bis zu 20-mal selbst erneut auf.
5. **Ablage und Löschfristen in B2:** Der Bucket ist privat und zusätzlich serverseitig verschlüsselt (SSE-B2). Dort liegen:
   - `db/JJJJ-MM-TT.fam`: Lebenszyklus-Regel „nach 30 Tagen verbergen, 1 Tag später löschen“.
   - `images/<bucket>/<pfad>.fam`: Verborgene und ersetzte Versionen werden nach 30 Tagen gelöscht.

   Gelöschte Familiendaten verschwinden damit spätestens nach rund 31 Tagen auch aus der Sicherung. Das steht so in der Datenschutzerklärung.
6. **Zugangsschlüssel für B2:** Der Anwendungsschlüssel in Supabase darf nur **schreiben** (Zugriffsart „Write Only“, nur dieser Bucket). Er kann nichts lesen und nichts endgültig löschen. Wird er gestohlen, bleiben die vorhandenen Sicherungen trotzdem erhalten und unlesbar. Zum Wiederherstellen legt der Inhaber dann einen eigenen Lese-Schlüssel an.
7. **Schutz vor Löschwellen:** Zeigt Supabase plötzlich weniger als die Hälfte der bisher gesicherten Bilder oder gar keine Familien, verbirgt die Function nichts. Sie bricht ab und meldet einen Fehler. Ein Unfall wird so nicht in die Sicherung übernommen.
8. **Benachrichtigung:** Schlägt die Sicherung fehl oder fehlt seit 48 Stunden eine erfolgreiche Sicherung, schickt Familiar über die **Resend-API** (Resend wird schon für Anmelde-Codes genutzt, also kein neuer Dienst) eine E-Mail an info@familiar-app.de. Den Stand jeder Nacht (Zeit, Größe, Anzahl Bilder, Fehler) schreibt die Function in `private.backup_runs`.
9. **Secrets** (nur im Supabase-Dashboard, nie im Chat):
   - `B2_KEY_ID` und `B2_APPLICATION_KEY` (Write Only)
   - `B2_BUCKET_NAME` (die Bucket-ID liefert die B2-Anmeldung selbst, weil der Schlüssel auf diesen einen Bucket beschränkt ist)
   - `BACKUP_PUBLIC_KEY` (öffentlich, darf auch im Repository liegen)
   - `RESEND_API_KEY` (nur Senden)

   Zum Wiederherstellen kommen vorübergehend `BACKUP_PRIVATE_KEY` und ein Lese-Schlüssel für B2 hinzu.

## Grenzen

- Gesichert wird einmal pro Nacht. Im schlimmsten Fall gehen die Änderungen eines Tages verloren. Es gibt 30 Tagesstände.
- Die Datenbank wird jede Nacht vollständig in den Speicher der Function gelesen. Das geht bis etwa 50 MB Nutzdaten (heute weit unter 1 MB). `private.backup_runs` protokolliert die Größe. Ab 25 MB warnt die E-Mail, dann wird auf tabellenweise Teildateien umgestellt.
- Platz bei B2: höchstens etwa 1 GB Bilder (Supabase-Grenze) plus 30 × gepackte Datenbank. Das bleibt deutlich unter 10 GB.
- Traffic: Die Datenbank geht gepackt jede Nacht einmal hinaus (heute < 1 MB), Bilder nur einmal. Das macht nur einen kleinen Teil der 5 GB aus.
- Ohne den privaten Schlüssel ist keine Wiederherstellung möglich. Er muss deshalb im Passwort-Manager **und** auf einem Ausdruck oder USB-Stick an einem sicheren Ort liegen.
- Läuft das Supabase-Projekt nicht mehr, entstehen keine neuen Sicherungen. Die vorhandenen bleiben aber 30 Tage bei B2 liegen. Die Warn-E-Mail kommt in diesem Fall nicht, weil sie vom selben Projekt verschickt wird. Ein Totalausfall fällt aber sofort an der App auf.
- Der Quellcode ist nicht Teil dieser Sicherung (siehe Launch-Liste: GitHub, privat). Das Schema steckt trotzdem in jeder Sicherung (`schema_migrations`).
- Nicht wiederhergestellt werden Anmelde-Sitzungen (neu anmelden), Outlook-Verbindungen (neu verbinden) und Push-Geräte (melden sich beim nächsten App-Start neu an).

## Wiederherstellung

Ich führe die Wiederherstellung mit dem Inhaber durch. Es braucht dafür keine Programme auf dem Mac, alles läuft im Supabase-Dashboard und in einer Edge Function.

1. Neues Supabase-Projekt (EU Frankfurt) anlegen oder das bestehende nutzen.
2. Bei Backblaze einen **Lese-Schlüssel** („Read Only“, nur dieser Bucket) anlegen. Im neuen Projekt diese Secrets setzen: `BACKUP_PRIVATE_KEY` (aus dem Passwort-Manager), `B2_READ_KEY_ID`, `B2_READ_APPLICATION_KEY`, `B2_BUCKET_NAME`.
3. Edge Function `backup-restore` deployen und mit dem gewünschten Datum aufrufen. Sie
   - lädt `db/<datum>.fam`, prüft und entschlüsselt die Datei,
   - spielt in einem leeren Projekt zuerst die gesicherten Migrationen ein, sonst die aus dem Repository,
   - lädt dann alle Tabellen in **einer** Transaktion (`session_replication_role = replica`, damit die Reihenfolge der Fremdschlüssel keine Rolle spielt),
   - stellt danach die Bilder in Etappen in die Buckets zurück.
4. Danach die übrigen Edge Functions deployen und ihre Secrets setzen (Liste in `docs/setup/`). URL und Schlüssel in der App bleiben gleich, wenn dasselbe Projekt genutzt wird. Bei einem neuen Projekt braucht es ein App-Update mit der neuen Projekt-URL.
5. `BACKUP_PRIVATE_KEY` und den Lese-Schlüssel wieder löschen.

**Probe-Wiederherstellung:** einmal nach dem Bau und dann jährlich. Dabei wird die Sicherung des Dev-Projekts in ein leeres Supabase-Projekt eingespielt, solange der zweite Projekt-Platz noch frei ist, also vor dem Anlegen des Produktionsprojekts. Danach werden Zeilenzahlen und Bilder verglichen. Jede Nacht prüft B2 jede hochgeladene Datei gegen die mitgeschickte SHA-1-Prüfsumme. Jede Datei trägt außerdem das GCM-Prüfzeichen, sodass eine beschädigte Sicherung beim Wiederherstellen sofort erkannt wird.
