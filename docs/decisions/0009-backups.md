# ADR 0009: Nächtliche Datensicherung ohne Kosten

- **Status:** angenommen (2026-10-22), gebaut (Migration `0017_backup`, Edge Functions `backup` und `backup-restore`); der erste echte Lauf wartet auf das Backblaze-Konto des Nutzers. Ersetzt den Entwurf vom 2026-10-21 (GitHub Actions), siehe „Verworfen“.
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

   Gelöschte Familiendaten verschwinden damit spätestens nach rund 31 Tagen auch aus der Sicherung. Das steht so in der Datenschutzerklärung. Wegen Object Lock (Punkt 6) lässt sich eine Version vor Ablauf der 30 Tage auch auf Wunsch nicht früher löschen. Das ist mit der angegebenen Frist vereinbar.
6. **Zugangsschlüssel und Löschschutz in B2:** Der Anwendungsschlüssel in Supabase ist auf diesen einen Bucket beschränkt und kann nichts lesen. Die Zugriffsart „Write Only“ der Backblaze-Oberfläche enthält aber auch `deleteFiles` und das Ändern der Lebenszyklus-Regeln (geprüft am 2026-10-22 mit dem Selbsttest). Gegen Löschen schützt deshalb **Object Lock** auf dem Bucket: Als Standard gilt eine Aufbewahrung von 30 Tagen. Jede hochgeladene Version ist dann 30 Tage lang für niemanden löschbar oder überschreibbar, auch nicht mit gestohlenem Schlüssel. Zum Wiederherstellen legt der Inhaber einen eigenen Lese-Schlüssel an.
7. **Schutz vor Löschwellen:** Zeigt Supabase plötzlich weniger als die Hälfte der bisher gesicherten Bilder oder gar keine Familien, verbirgt die Function nichts. Sie bricht ab und meldet einen Fehler. Ein Unfall wird so nicht in die Sicherung übernommen.
8. **Benachrichtigung:** Schlägt die Sicherung fehl oder fehlt seit 48 Stunden eine erfolgreiche Sicherung, schickt Familiar über die **Resend-API** (Resend wird schon für Anmelde-Codes genutzt, also kein neuer Dienst) eine E-Mail an info@familiar-app.de. Den Stand jeder Nacht (Zeit, Größe, Anzahl Bilder, Fehler) schreibt die Function in `private.backup_runs`.
9. **Secrets** (nur im Supabase-Dashboard, nie im Chat):
   - `B2_KEY_ID` und `B2_APPLICATION_KEY` (Write Only, auf den einen Bucket beschränkt; Bucket-ID und -Name liefert die B2-Anmeldung selbst)
   - `BACKUP_PUBLIC_KEY` (öffentlich, liegt auch als `supabase/backup-public.pem` im Repository)
   - `RESEND_API_KEY` (nur Senden)

   Zum Wiederherstellen kommen vorübergehend `BACKUP_PRIVATE_KEY`, `B2_READ_KEY_ID` und `B2_READ_APPLICATION_KEY` hinzu.

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

Ich führe die Wiederherstellung mit dem Inhaber durch. Auf dem Mac braucht es dafür keine Programme: Alles läuft im Supabase-Dashboard und in der Edge Function `backup-restore`. Das Ergebnis steht jeweils in `private.restore_runs`.

1. **Ziel vorbereiten:**
   - **Leeres Projekt** (Projekt verloren): neues Supabase-Projekt in der EU (Irland, eu-west-1 wie bisher) anlegen. Migrationen aus dem Repository einspielen, Edge Functions deployen, `functions_base_url` anpassen, wie bei jedem neuen Projekt.
   - **Bestehendes Projekt** (Daten kaputt): Es wird überschrieben, siehe Schritt 3.
2. **Secrets setzen** (nur für die Dauer der Wiederherstellung):
   - Bei Backblaze einen **Lese-Schlüssel** anlegen („Read Only“, nur dieser Bucket).
   - Im Zielprojekt eintragen: `BACKUP_PRIVATE_KEY` (aus dem Passwort-Manager), `B2_READ_KEY_ID`, `B2_READ_APPLICATION_KEY`.
3. **Im SQL-Editor starten:**
   - `select private.start_restore('probe', 'JJJJ-MM-TT');` ist eine **Probe**. Sie spielt alles in einer Transaktion ein, zählt jede Tabelle, macht alles rückgängig (ROLLBACK) und vergleicht Stichproben-Bilder mit den Originalen. Dabei ändert sich nichts.
   - `select private.start_restore('restore', 'JJJJ-MM-TT');` stellt in einem **leeren** Projekt wieder her.
   - Ein **nicht leeres** Projekt wird nur mit `'ÜBERSCHREIBEN'` als drittem Argument überschrieben. Dann werden zuerst alle Konten und alle Tabellen in `public` geleert.
   - Die Datenbank wird in **einer** Transaktion eingespielt: Tabellen in Fremdschlüssel-Reihenfolge, App-Trigger in `public` währenddessen aus, Einfügen als Upsert über den Primärschlüssel (der Trigger `on_auth_user_created` legt beim Einfügen in `auth.users` schon Profile an). Danach werden die Sequenzen nachgezogen. `session_replication_role = replica` ist auf Supabase der Rolle `postgres` nicht erlaubt (geprüft 2026-10-22).
   - Anschließend schreibt die Function alle Bilder in Etappen zurück.
4. **Danach:**
   - Bei einem neuen Projekt braucht es ein App-Update mit der neuen Projekt-URL.
   - Outlook muss neu verbunden werden.
   - `BACKUP_PRIVATE_KEY` und den Lese-Schlüssel wieder löschen.

Das Schema kommt aus dem Repository (`supabase/migrations/`, Quellcode-Sicherung auf GitHub, siehe Launch-Liste). Jede Sicherung enthält zusätzlich `supabase_migrations.schema_migrations` mit dem SQL aller Migrationen, als Rückfallebene, falls das Repository verloren geht.

## Tests (Stand 2026-10-22, Dev-Projekt)

- Migration `0017_backup` eingespielt. `backup_export` liefert alle 15 Tabellen in einem Snapshot (90 KB, davon das meiste Migrations-SQL). `backup_image_plan` erkennt das vorhandene Profilbild.
- Selbsttest in der echten Edge-Runtime (`select private.start_backup('selftest')`): Ver- und Entschlüsselung inklusive gzip stimmen überein, eine veränderte Datei wird abgelehnt.
- `backup-restore`: Token, direkte Datenbankverbindung und Bericht funktionieren. Ohne Schlüssel bricht die Function sauber mit Meldung ab.
- Erster echter Lauf am 2026-10-22 (Lauf 1): Datenbank 90 KB, verschlüsselt 20 KB als `db/2026-10-22.fam`, 1 Profilbild, Dauer 7 s. Die B2-Anmeldung schlug zunächst fehl, weil beim Einfügen Leerzeichen mitkamen; die Function entfernt sie jetzt selbst.
- Object Lock (30 Tage Standard-Aufbewahrung) am 2026-10-22 auf dem Dev-Bucket eingeschaltet.
- **Probe-Wiederherstellung am 2026-10-22 bestanden** (Lauf 4 in `private.restore_runs`): Entschlüsselt wurde mit dem privaten Schlüssel aus dem Passwort-Manager des Inhabers, eingetragen als Secret. Alle 14 Tabellen (inkl. `auth.users`, `auth.identities`) wurden vollständig eingespielt, keine Abweichung. Danach ROLLBACK, die Daten sind unverändert und alle Trigger wieder aktiv. Das Profilbild aus B2 ist bitgleich mit dem Original. Zwei Fehler wurden dabei gefunden und behoben: `replica` nicht erlaubt (siehe oben), und postgres.js hat das Dokument bei `$1::jsonb` doppelt kodiert (jetzt `::text::jsonb`, und eine leere Tabellenliste gilt als Fehler).
- **Offen:** Die vollständige Wiederherstellung in ein leeres Projekt (`restore`) wird einmal vor dem Start geübt, direkt nach dem Anlegen des Produktionsprojekts und bevor dort echte Daten liegen.
