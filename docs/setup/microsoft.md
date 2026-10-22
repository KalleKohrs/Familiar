# Outlook verbinden: Microsoft einrichten (Phase 8)

Stand 2026-10-21, geprüft gegen die offizielle Microsoft-Doku (Links unten). Dauer: etwa 20 Minuten.

**Ziel:** Familiar darf deine Outlook-Termine **nur lesen** (Recht `Calendars.ReadBasic`). Familiar schreibt nie in deinen Kalender und erzeugt aus Terminen keine Aufgaben.

**Wichtig:** Geheime Werte (das „Client Secret“) kommen **nie in den Chat** – nur direkt ins Supabase-Dashboard.

---

## Schritt 1 – Kostenloses Azure-Konto anlegen (eigenes „Verzeichnis“)

Für die App-Registrierung brauchst du ein eigenes Microsoft-Entra-Verzeichnis. Das bekommst du automatisch mit einem kostenlosen Azure-Konto.

1. Öffne <https://azure.microsoft.com/free>.
2. Melde dich mit einem **privaten** Microsoft-Konto an (z. B. outlook.com / hotmail / ein neu angelegtes) – **nicht** mit deinem Firmenkonto. So gehört die App-Registrierung dir und nicht deiner Firma.
3. Microsoft fragt Telefonnummer und eine **Kredit- oder Debitkarte** ab. Das dient nur der Identitätsprüfung; es wird höchstens kurz ein kleiner Betrag (ca. 1 $) reserviert und wieder freigegeben. Der kostenlose Tarif reicht – wir nutzen keine kostenpflichtigen Dienste.
4. Nach der Anmeldung hast du ein Verzeichnis namens **„Default Directory“**.

## Schritt 2 – App registrieren

1. Öffne <https://entra.microsoft.com> und melde dich mit demselben privaten Konto an.
2. Falls oben rechts mehrere Verzeichnisse angeboten werden: über das **Zahnrad-Symbol (Settings)** zu **Default Directory** wechseln.
3. Links: **Entra ID** → **App registrations** → oben **New registration**.
4. **Name:** `Familiar`
5. **Supported account types:** im Auswahlfeld **„Any Entra ID Tenant + Personal Microsoft accounts“** wählen.
   (So funktionieren später Firmen- **und** private Outlook-Konten.)
6. **Register** klicken.
7. Es öffnet sich die Seite **Overview**. Dort steht die **Application (client) ID** – die brauchst du in Schritt 6. (Sie ist kein Geheimnis.)

## Schritt 3 – Rücksprung-Adresse (Redirect URI) eintragen

1. In deiner App links unter **Manage** → **Authentication**.
2. Reiter **Redirect URI configuration** → **Add Redirect URI**.
3. Kachel **Web** wählen.
4. Bei **Redirect URI** genau eintragen:

   ```
   https://ldeouecoaqyfvubhrjei.supabase.co/functions/v1/outlook-oauth-callback
   ```

5. **Front-channel logout URL** leer lassen → **Configure**.

## Schritt 4 – Leserecht für den Kalender hinzufügen

1. Links unter **Manage** → **API permissions**.
2. **Add a permission** → **Microsoft Graph** → **Delegated permissions**.
3. In das Suchfeld nacheinander eingeben und jeweils das Häkchen setzen:
   - `Calendars.ReadBasic`
   - `offline_access`
   - `openid`
   - `email`
4. **Add permissions** klicken.
5. **Nicht** auf „Grant admin consent“ klicken – das betrifft nur dein eigenes Verzeichnis und ist nicht nötig.

## Schritt 5 – Zertifikat erzeugen und hochladen

Die App meldet sich bei Microsoft mit einem Zertifikat an, nicht mit einem Client Secret (Microsoft-Empfehlung für den Produktivbetrieb). Das Schlüsselpaar erzeuge ich im Terminal:

```bash
openssl req -x509 -newkey rsa:2048 -nodes -keyout familiar-ms.key -out familiar-ms.cer -days 730 -subj "/CN=Familiar Outlook"
```

- `familiar-ms.cer` (öffentlich) lädst du in Entra hoch: **Certificates & secrets** → Reiter **Certificates** → **Upload certificate** → Beschreibung `Supabase Familiar` → **Add**.
- `familiar-ms.key` (geheim) kommt nur in die Supabase-Secrets (Schritt 6) und wird danach vom Mac gelöscht.

## Schritt 6 – Werte in Supabase hinterlegen (nicht in den Chat)

1. Öffne <https://supabase.com/dashboard/project/ldeouecoaqyfvubhrjei/functions/secrets>
   (Supabase → dein Projekt → **Edge Functions** → **Secrets**).
2. Einträge anlegen (**Add new secret**):

   | Name | Wert |
   |---|---|
   | `MS_CLIENT_ID` | die **Application (client) ID** aus Schritt 2 |
   | `MS_CERT_PRIVATE_KEY` | der komplette Inhalt von `familiar-ms.key` (inkl. `-----BEGIN PRIVATE KEY-----`) |
   | `MS_CERT_THUMBPRINT` | Base64url-SHA-256 des Zertifikats – erzeuge ich mit `openssl x509 -in familiar-ms.cer -outform DER \| openssl dgst -sha256 -binary \| base64 \| tr '+/' '-_' \| tr -d '='` (kein Geheimnis) |

3. **Save**.

Ein Client Secret (`MS_CLIENT_SECRET`) wird nicht mehr verwendet; der Code kennt seit 2026-10-22 nur noch das Zertifikat.

---

## Hinweis zu deinem Firmenkonto

Wenn du später in Familiar „Outlook verbinden“ tippst und dich mit dem **Firmenkonto** anmeldest, zeigt Microsoft eine Zustimmungsseite („Familiar möchte deinen Kalender lesen“).

- Viele Firmen erlauben das direkt – dann bist du fertig.
- Microsoft empfiehlt Firmen aber, Zustimmungen nur für **verifizierte Herausgeber** zuzulassen. Ist das bei deiner Firma eingestellt, erscheint **„Genehmigung erforderlich“ / „Need admin approval“**. Dann muss deine IT einmal zustimmen (meist über einen Button „Genehmigung anfordern“ direkt auf dieser Seite). Familiar verlangt nur das kleinste Leserecht – das kannst du der IT so sagen.

## Erneuern (vor Ablauf des Zertifikats)

Das Ablaufdatum steht in Entra unter **Certificates & secrets** → **Certificates** („Expires“). Rechtzeitig vorher Schritt 5 und 6 wiederholen: neues Zertifikat **zusätzlich** hochladen, dann `MS_CERT_PRIVATE_KEY` und `MS_CERT_THUMBPRINT` in Supabase ersetzen, erst danach das alte Zertifikat in Entra löschen – so gibt es keine Unterbrechung.

## Quellen

- [Register an app in Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app)
- [Add a redirect URI](https://learn.microsoft.com/en-us/entra/identity-platform/how-to-add-redirect-uri)
- [Add and manage app credentials](https://learn.microsoft.com/en-us/entra/identity-platform/how-to-add-credentials)
- [Microsoft identity platform certificate credentials](https://learn.microsoft.com/en-us/entra/identity-platform/certificate-credentials)
- [List calendarView – Berechtigungen](https://learn.microsoft.com/en-us/graph/api/calendar-list-calendarview?view=graph-rest-1.0)
- [Configure how users consent to applications](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-user-consent)
- [Azure Free Account FAQ](https://azure-int.microsoft.com/en-us/free/free-account-faq)
