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

## Schritt 5 – Client Secret erstellen (geheim!)

1. Links unter **Manage** → **Certificates & secrets** → Reiter **Client secrets** → **New client secret**.
2. **Description:** `Supabase Familiar`
3. **Expires:** **180 days (6 months)**. (Microsoft empfiehlt weniger als 12 Monate; ich erinnere dich vor Ablauf an die Erneuerung.)
4. **Add** klicken.
5. In der Tabelle erscheint eine Zeile. **Kopiere den Wert in der Spalte „Value“** (nicht „Secret ID“!).
   ⚠️ Der Wert wird nur jetzt angezeigt – nach dem Verlassen der Seite nie wieder.

## Schritt 6 – Werte in Supabase hinterlegen (nicht in den Chat)

1. Öffne <https://supabase.com/dashboard/project/ldeouecoaqyfvubhrjei/functions/secrets>
   (Supabase → dein Projekt → **Edge Functions** → **Secrets**).
2. Zwei Einträge anlegen (**Add new secret**):

   | Name | Wert |
   |---|---|
   | `MS_CLIENT_ID` | die **Application (client) ID** aus Schritt 2 |
   | `MS_CLIENT_SECRET` | der **Value** aus Schritt 5 |

3. **Save**.
4. Schreib mir im Chat nur: **„Microsoft fertig“**.

---

## Hinweis zu deinem Firmenkonto

Wenn du später in Familiar „Outlook verbinden“ tippst und dich mit dem **Firmenkonto** anmeldest, zeigt Microsoft eine Zustimmungsseite („Familiar möchte deinen Kalender lesen“).

- Viele Firmen erlauben das direkt – dann bist du fertig.
- Microsoft empfiehlt Firmen aber, Zustimmungen nur für **verifizierte Herausgeber** zuzulassen. Ist das bei deiner Firma eingestellt, erscheint **„Genehmigung erforderlich“ / „Need admin approval“**. Dann muss deine IT einmal zustimmen (meist über einen Button „Genehmigung anfordern“ direkt auf dieser Seite). Familiar verlangt nur das kleinste Leserecht – das kannst du der IT so sagen.

## Erneuern (alle 6 Monate)

Das Client Secret läuft ab. Vor Ablauf: Schritt 5 wiederholen und `MS_CLIENT_SECRET` in Supabase ersetzen. Für die Veröffentlichung im App Store empfiehlt Microsoft ein Zertifikat statt eines Secrets – das stellen wir vor dem Release um.

## Quellen

- [Register an app in Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app)
- [Add a redirect URI](https://learn.microsoft.com/en-us/entra/identity-platform/how-to-add-redirect-uri)
- [Add and manage app credentials](https://learn.microsoft.com/en-us/entra/identity-platform/how-to-add-credentials)
- [List calendarView – Berechtigungen](https://learn.microsoft.com/en-us/graph/api/calendar-list-calendarview?view=graph-rest-1.0)
- [Configure how users consent to applications](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-user-consent)
- [Azure Free Account FAQ](https://azure-int.microsoft.com/en-us/free/free-account-faq)
