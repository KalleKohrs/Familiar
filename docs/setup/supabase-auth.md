# Einrichtung: Supabase-Anmeldung (E-Mail-Code)

Familiar meldet per **6-stelligem Code aus der E-Mail** an (kein Passwort, kein Link). Supabase verschickt standardmäßig einen Link; damit ein Code in der E-Mail steht, muss die Vorlage die Variable `{{ .Token }}` enthalten (Supabase-Doku „Passwordless email logins“ → „With OTP“).

Projekt: `ldeouecoaqyfvubhrjei` (Dev). **Den Resend-API-Key nie in den Chat kopieren** – er gehört nur ins Supabase-Dashboard.

**Reihenfolge:** Zuerst ein eigener Mailserver (Abschnitt 0). Ohne ihn zeigt das Dashboard „Set up custom SMTP to edit templates“, die Vorlagen lassen sich nicht ändern, und Supabase schickt E-Mails nur an Adressen aus deinem Supabase-Team.

## 0. Eigener Mailserver mit Resend (Pflicht)

Resend ist ein Versanddienst für App-E-Mails. Der kostenlose Tarif reicht für Familiar (laut Resend: 3.000 E-Mails pro Monat, höchstens 100 pro Tag, 3 Domains). Du brauchst Zugriff auf die DNS-Einstellungen deiner Domain (beim Anbieter, bei dem du die Domain gekauft hast).

**Übergang ohne eigene Domain (nur zum Testen):** Ohne verifizierte Domain kann Resend über die Testadresse `onboarding@resend.dev` senden – laut Resend aber **nur an die E-Mail-Adresse deines Resend-Kontos**. Damit lässt sich die Anmeldung mit genau dieser Adresse testen, und die Vorlagen in Supabase werden bearbeitbar. Dafür Schritte a) und b) überspringen, in c) den Key ohne Domain-Beschränkung anlegen und in d) als Sender `onboarding@resend.dev` eintragen. Für andere Familienmitglieder braucht es danach die eigene Domain.

**Domain kaufen:** Am besten bei einem Anbieter mit fairem Verlängerungspreis und DNS-Verwaltung inklusive, z. B. INWX (`.de` laut Preisliste rund 6 € pro Jahr). Vorsicht bei Lockangeboten mit 1 € im ersten Jahr und deutlich höherem Preis ab dem zweiten Jahr. Die Domain dient später auch für Einladungslinks und die Datenschutzerklärung (Pflicht im App Store).

**a) Domain in Resend hinzufügen**

1. Konto anlegen auf [resend.com](https://resend.com) (kostenlos).
2. Im Dashboard **Domains** → **Add Domain**.
3. Als Domain eine **Subdomain** eintragen (Resend empfiehlt das), `mail.familiar-app.de`.
4. **Region:** die nächstgelegene wählen (Europa, falls angeboten).
5. Resend zeigt im Reiter **Records** mehrere DNS-Einträge (TXT sowie MX oder CNAME).

**b) DNS-Einträge bei deinem Domain-Anbieter eintragen**

1. Beim Domain-Anbieter die DNS-Verwaltung der Domain öffnen.
2. **Jeden** Eintrag aus dem Resend-Reiter „Records“ anlegen – Typ, Name/Host und Wert **exakt kopieren** (Resend: „These records must match exactly what Resend generated“).
   - **Name/Host:** Die meisten Anbieter (auch INWX) hängen `.familiar-app.de` automatisch an. Zeigt Resend z. B. `send.mail.familiar-app.de`, trägst du nur `send.mail` ein; aus `resend._domainkey.mail.familiar-app.de` wird `resend._domainkey.mail`. Sonst entsteht `….familiar-app.de.familiar-app.de` und die Prüfung schlägt fehl.
   - **MX-Eintrag:** die Priorität aus Resend übernehmen (eigenes Feld „Prio“).
3. Bei Cloudflare: für CNAME-Einträge den Proxy ausschalten (graue statt orange Wolke).
4. In Resend auf **Verify** klicken. Laut Resend klappt die Prüfung oft innerhalb von 15 Minuten, DNS-Änderungen können aber bis zu 72 Stunden brauchen.
5. Nach erfolgreicher Prüfung empfiehlt Resend zusätzlich einen DMARC-Eintrag (TXT, Name `_dmarc`); den vorgeschlagenen Wert aus Resend übernehmen. Das hilft, dass die Codes nicht im Spam landen.

**c) API-Key erstellen**

1. In Resend **API Keys** → **Create API Key**.
2. Name z. B. `Supabase Familiar`; Berechtigung **nur Senden** (Sending access), falls angeboten, und auf deine Domain beschränken.
3. Den Key **sofort kopieren** – Resend zeigt ihn danach nicht mehr an. Nur ins Supabase-Dashboard einfügen, nirgendwo sonst speichern.

**d) In Supabase eintragen**

1. [Authentication › Emails › SMTP Settings](https://supabase.com/dashboard/project/ldeouecoaqyfvubhrjei/auth/smtp) öffnen und **Enable custom SMTP** einschalten.
2. **Sender email:** `familiar@mail.familiar-app.de` (muss zur verifizierten Domain gehören).
3. **Sender name:** `Familiar`
4. **Host:** `smtp.resend.com` · **Port:** `465` · **Username:** `resend` · **Password:** der API-Key aus Schritt c.
5. **Save**.
6. Unter [Rate Limits](https://supabase.com/dashboard/project/ldeouecoaqyfvubhrjei/auth/rate-limits) steht danach ein E-Mail-Limit (Supabase setzt nach dem Umstellen 30 pro Stunde). Das reicht für den Anfang.


## 1. E-Mail-Vorlagen anpassen (Pflicht)

1. Öffne [Authentication › Email Templates](https://supabase.com/dashboard/project/ldeouecoaqyfvubhrjei/auth/templates).
2. Vorlage **„Magic link“** (bzw. „Magic link or OTP“) auswählen.
3. **Subject:** `Dein Anmeldecode für Familiar`
4. **Message body** komplett ersetzen durch:

   ```html
   <h2>Dein Anmeldecode</h2>
   <p>Gib diesen Code in der Familiar-App ein:</p>
   <p style="font-size: 28px; font-weight: bold; letter-spacing: 4px;">{{ .Token }}</p>
   <p>Der Code ist nur kurze Zeit gültig. Wenn du dich nicht anmelden wolltest, kannst du diese E-Mail ignorieren.</p>
   ```

5. **Save** klicken.
6. Dasselbe für die Vorlage **„Confirm sign up“** wiederholen (gleicher Text). Die Doku legt nicht eindeutig fest, welche der beiden Vorlagen Supabase bei der **ersten** Anmeldung einer neuen Adresse verschickt – mit beiden Vorlagen klappt es in jedem Fall.

## 2. Optional: Einstellungen prüfen

Unter [Authentication › Sign In / Providers › Email](https://supabase.com/dashboard/project/ldeouecoaqyfvubhrjei/auth/providers):

- **Email** ist aktiviert (Standard).
- **Email OTP Length**: auf **6** lassen. Die App akzeptiert 6–10 Ziffern, 6 ist am bequemsten.
- **Email OTP Expiration**: Standard lassen (höchstens 86400 Sekunden erlaubt).

## Anmeldung in der App testen

1. App im Simulator starten → deine E-Mail-Adresse eingeben → **Code senden**.
2. Code aus der E-Mail eingeben → **Anmelden**.
3. Name und Bild bestätigen → Familie erstellen oder mit Code beitreten.

Kommt keine E-Mail: Spam-Ordner prüfen; in Resend unter **Emails** nachsehen, ob sie verschickt wurde; nach 60 Sekunden „Neuen Code senden“. Steht in der E-Mail ein Link statt eines Codes, fehlt `{{ .Token }}` in der Vorlage (Abschnitt 1).

## Quellen

- [Passwordless email logins (Supabase)](https://supabase.com/docs/guides/auth/auth-email-passwordless)
- [Email Templates (Supabase)](https://supabase.com/docs/guides/auth/auth-email-templates)
- [Send emails with custom SMTP (Supabase)](https://supabase.com/docs/guides/auth/auth-smtp)
- [Send emails with Supabase SMTP (Resend)](https://resend.com/docs/send-with-supabase-smtp)
- [Add a domain (Resend)](https://resend.com/docs/add-a-domain)
- [Pricing (Resend)](https://resend.com/pricing)
- [403 error resend.dev domain (Resend)](https://resend.com/docs/knowledge-base/403-error-resend-dev-domain)
- [Preisliste (INWX)](https://www.inwx.de/de/domain/pricelist)
