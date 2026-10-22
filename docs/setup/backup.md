# Datensicherung einrichten (Backblaze B2, kostenlos)

Stand 2026-10-22. Die Entscheidung und ihre Begründung stehen in [ADR 0009](../decisions/0009-backups.md). Grundlage ist die Backblaze-Doku: [Konto und Region](https://www.backblaze.com/docs/cloud-storage-data-regions), [Buckets](https://www.backblaze.com/docs/cloud-storage-create-and-manage-buckets), [Lebenszyklus-Regeln](https://www.backblaze.com/docs/cloud-storage-configure-and-manage-lifecycle-rules), [Anwendungsschlüssel](https://www.backblaze.com/docs/cloud-storage-create-and-manage-app-keys).

**Dauer:** etwa 25 Minuten.

**Wann:** Die Schritte 1–4 gehen sofort. Schritt 5 machst du zuerst im Dev-Projekt und wiederholst ihn später im Produktionsprojekt (Launch-Liste Punkt 2).

**Was ich schon erledigt habe:** Datenbank-Teil (Migration `0017_backup`), Sicherungs- und Wiederherstellungs-Function im Dev-Projekt, Schlüsselpaar.

**Was du am Ende hast:** Jede Nacht landet eine verschlüsselte Kopie aller Familien, Aufgaben, Konten und Bilder in Amsterdam. Backblaze kann sie nicht lesen. Nach 30 Tagen werden alte Stände automatisch gelöscht.

**Geheim** sind der private Sicherungsschlüssel, der Backblaze-`applicationKey` und der Resend-API-Schlüssel. Sie kommen **nie in den Chat**, sondern nur in den Passwort-Manager und ins Supabase-Dashboard. Sag mir nur, *dass* du einen Schritt erledigt hast.

## Schritt 1 – Backblaze-Konto in der EU

1. Öffne <https://www.backblaze.com/sign-up/cloud-storage>.
2. Gib E-Mail und Passwort ein (neues Passwort, im Passwort-Manager speichern).
3. **Wichtig:** Stell bei **Region** auf **EU Central** um. Die Region lässt sich später nicht mehr ändern. Ein Konto in der falschen Region müsstest du neu anlegen.
4. Konto anlegen. Eine Kreditkarte ist für die kostenlosen 10 GB nicht nötig. Fragt Backblaze trotzdem danach, brich hier ab und sag mir Bescheid.
5. Bestätige die E-Mail-Adresse. Schalte unter **Account › My Settings** die **Zwei-Faktor-Anmeldung** ein (Security).

## Schritt 2 – Bucket anlegen

1. Links unter **B2 Cloud Storage** auf **Buckets** → **Create a Bucket**.
2. **Bucket Unique Name:** `familiar-sicherung-` plus fünf beliebige Ziffern, z. B. `familiar-sicherung-48213` (der Name muss weltweit einmalig sein; er ist nicht geheim).
3. **Files in Bucket are:** **Private**.
4. **Default Encryption:** **Enable**, falls die Einstellung angezeigt wird.
5. **Object Lock:** **Disable**.
6. **Create a Bucket**.

## Schritt 3 – Automatisches Löschen nach 30 Tagen

1. In der Bucket-Liste beim neuen Bucket auf **Lifecycle Settings** → **Use custom lifecycle rules**.
2. Lege **zwei Regeln** an (über „Add rule“ o. Ä. eine zweite Zeile):

   | File Path | daysFromUploadingToHiding | daysFromHidingToDeleting |
   |---|---|---|
   | `db/` | `30` | `1` |
   | `images/` | *(leer lassen)* | `30` |

3. **Update Bucket**.

So bleiben 30 Tagesstände der Datenbank. Gelöschte oder ersetzte Bilder verschwinden nach 30 Tagen.

## Schritt 4 – Schreib-Schlüssel für Supabase

1. Links **Application Keys** → **Add a New Application Key**.
2. **Name of Key:** `familiar-sicherung-schreiben`.
3. **Allow Access to Bucket(s):** deinen Bucket aus Schritt 2 wählen (nicht „All“).
4. **Type of Access:** **Write Only**. Damit kann Supabase Sicherungen ablegen, aber nichts lesen und nichts endgültig löschen.
5. Die übrigen Felder leer lassen → **Create New Key**.
6. Backblaze zeigt jetzt `keyID` und `applicationKey`. **Der `applicationKey` erscheint nur dieses eine Mal.** Lass die Seite offen und mach direkt mit Schritt 5 weiter.

## Schritt 5 – Secrets in Supabase

1. Öffne <https://supabase.com/dashboard/project/ldeouecoaqyfvubhrjei/functions/secrets> (Supabase → dein Projekt → **Edge Functions** → **Secrets**). Später machst du das Gleiche im Produktionsprojekt.
2. Lege an (Name links, Wert rechts, **Save**):

   | Name | Wert |
   |---|---|
   | `B2_KEY_ID` | `keyID` aus Schritt 4 |
   | `B2_APPLICATION_KEY` | `applicationKey` aus Schritt 4 |

3. Erst danach die Backblaze-Seite schließen.

Für das Produktionsprojekt legst du in Schritt 4 einen zweiten Schlüssel an (`familiar-sicherung-prod`) und, wenn du magst, einen eigenen Bucket. Dev- und Produktionsdaten bleiben so getrennt.

## Schritt 6 – Warn-E-Mail (Resend)

1. Öffne <https://resend.com/api-keys> → **Create API Key**.
2. **Name:** `familiar-sicherung`. **Permission:** **Sending access**. **Domain:** `mail.familiar-app.de` (die Absender-Domain aus der Anmelde-Einrichtung) → **Add**.
3. Kopier den Schlüssel und lege ihn in Supabase (wie in Schritt 5) als Secret `RESEND_API_KEY` an. Auch er wird nur einmal angezeigt.

## Schritt 7 – Sicherungsschlüssel aufbewahren

Das Schlüsselpaar habe ich schon erzeugt. Der **öffentliche** Teil ist nicht geheim, er liegt in `supabase/backup-public.pem`. Den **privaten** Teil lege ich dir in die Zwischenablage, ohne ihn selbst anzuzeigen.

1. Leg im Passwort-Manager einen Eintrag **„Familiar Sicherungsschlüssel“** an, z. B. in der App **Passwörter** als neue sichere Notiz. Füge dort den Inhalt der Zwischenablage ein (⌘V).
2. **Zweite Kopie:** Füge den Schlüssel zusätzlich in eine Textdatei auf einem USB-Stick ein, den du an einem sicheren Ort aufbewahrst. Alternativ druckst du ihn aus.
3. Sag mir Bescheid. Ich lege dir dann den **öffentlichen** Schlüssel in die Zwischenablage. Den trägst du wie in Schritt 5 als Secret `BACKUP_PUBLIC_KEY` ein. Danach lösche ich den privaten Schlüssel vom Mac.

**Ohne den privaten Schlüssel kann niemand die Sicherungen öffnen, auch du und ich nicht.** Geht er verloren, sind alle bisherigen Sicherungen wertlos. Dann erzeugen wir einen neuen, und ab der nächsten Nacht gibt es wieder brauchbare Sicherungen.

## Schritt 8 – Erster Lauf und Probe-Wiederherstellung

1. Ich starte die Sicherung einmal von Hand und prüfe sie. Bei Backblaze siehst du danach unter **Buckets › Browse Files** die Ordner `db/` und `images/` mit Dateien auf `.fam`. Die sind verschlüsselt und lassen sich nicht öffnen – genau so soll es sein.
2. Für die Probe-Wiederherstellung legst du bei Backblaze einen zweiten Schlüssel an, wie in Schritt 4, aber mit **Name of Key** `familiar-sicherung-lesen` und **Type of Access** **Read Only**.
3. In Supabase (wie in Schritt 5) vorübergehend eintragen:

   | Name | Wert |
   |---|---|
   | `B2_READ_KEY_ID` | `keyID` des Lese-Schlüssels |
   | `B2_READ_APPLICATION_KEY` | `applicationKey` des Lese-Schlüssels |
   | `BACKUP_PRIVATE_KEY` | der private Schlüssel aus deinem Passwort-Manager |

4. Ich spiele die Sicherung zur Probe ein. Dabei ändert sich nichts an den Daten. Ich prüfe, ob alle Zeilen und Bilder stimmen.
5. Danach löschst du diese drei Secrets in Supabase wieder (Mülleimer neben dem Eintrag) und den Lese-Schlüssel bei Backblaze (**Application Keys** → **Delete**).

## Wenn eine Warn-E-Mail kommt

Betreff „Familiar: Datensicherung fehlgeschlagen“: Leite sie nicht weiter, sondern sag mir in einer neuen Sitzung Bescheid. Die Fehlermeldung steht in der E-Mail und enthält keine Familiendaten.
