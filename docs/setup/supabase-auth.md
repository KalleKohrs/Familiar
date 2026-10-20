# Einrichtung: Supabase-Anmeldung (E-Mail-Code)

Familiar meldet per **6-stelligem Code aus der E-Mail** an (kein Passwort, kein Link). Supabase verschickt standardmäßig einen Link; damit ein Code in der E-Mail steht, muss die Vorlage die Variable `{{ .Token }}` enthalten (Supabase-Doku „Passwordless email logins“ → „With OTP“).

Projekt: `ldeouecoaqyfvubhrjei` (Dev). **Keine Werte aus diesem Dokument in den Chat kopieren** – es sind aber auch keine Geheimnisse nötig.

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

## 2. Test-Adresse prüfen (Pflicht für Tests)

Solange kein eigener Mailserver eingerichtet ist, verschickt Supabase E-Mails **nur an Adressen aus dem Team deiner Supabase-Organisation** und nur wenige pro Stunde (Supabase-Doku „Send emails with custom SMTP“). Für die ersten Tests:

1. Öffne [Organization › Team](https://supabase.com/dashboard/org/_/team).
2. Prüfe, dass die E-Mail-Adresse, mit der du dich in der App anmelden willst, dort steht (normalerweise die Adresse deines Supabase-Kontos).

Andere Familienmitglieder können sich erst anmelden, wenn ein eigener SMTP-Server hinterlegt ist (siehe Abschnitt 4).

## 3. Optional: Einstellungen prüfen

Unter [Authentication › Sign In / Providers › Email](https://supabase.com/dashboard/project/ldeouecoaqyfvubhrjei/auth/providers):

- **Email** ist aktiviert (Standard).
- **Email OTP Length**: auf **6** lassen. Die App akzeptiert 6–10 Ziffern, 6 ist am bequemsten.
- **Email OTP Expiration**: Standard lassen (höchstens 86400 Sekunden erlaubt).

## 4. Später: eigener Mailserver (vor dem Einladen der Familie)

Damit alle Familienmitglieder Codes bekommen, braucht das Projekt einen eigenen SMTP-Dienst (z. B. Resend, Postmark, Amazon SES). Die Zugangsdaten trägst du unter [Authentication › Emails › SMTP Settings](https://supabase.com/dashboard/project/ldeouecoaqyfvubhrjei/auth/smtp) ein – **nie im Chat**. Danach unter [Rate Limits](https://supabase.com/dashboard/project/ldeouecoaqyfvubhrjei/auth/rate-limits) das E-Mail-Limit passend erhöhen (Supabase setzt nach dem Umstellen zunächst 30 pro Stunde). Eine Schritt-für-Schritt-Anleitung erstelle ich, wenn es so weit ist.

## Anmeldung in der App testen

1. App im Simulator starten → E-Mail-Adresse aus Abschnitt 2 eingeben → **Code senden**.
2. Code aus der E-Mail eingeben → **Anmelden**.
3. Name und Bild bestätigen → Familie erstellen oder mit Code beitreten.

Kommt keine E-Mail: Spam-Ordner prüfen; nach 60 Sekunden „Neuen Code senden“. Steht in der E-Mail ein Link statt eines Codes, fehlt `{{ .Token }}` in der Vorlage (Abschnitt 1).

## Quellen

- [Passwordless email logins (Supabase)](https://supabase.com/docs/guides/auth/auth-email-passwordless)
- [Email Templates (Supabase)](https://supabase.com/docs/guides/auth/auth-email-templates)
- [Send emails with custom SMTP (Supabase)](https://supabase.com/docs/guides/auth/auth-smtp)
