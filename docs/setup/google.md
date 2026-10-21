# „Mit Google anmelden“ einrichten

Stand 2026-10-21, geprüft gegen die Supabase-Doku [Login with Google](https://supabase.com/docs/guides/auth/social-login/auth-google) (Abschnitt Swift) und Googles [Get started with Google Sign-In for iOS](https://developers.google.com/identity/sign-in/ios/start-integrating). Dauer: etwa 20 Minuten.

**Geheim ist nur das Client Secret** (Schritt 4) – es kommt ausschließlich ins Supabase-Dashboard. Die beiden **Client IDs** sind keine Geheimnisse; die schickst du mir in den Chat.

## Schritt 1 – Projekt anlegen

1. <https://console.cloud.google.com> öffnen und mit deinem Google-Konto anmelden.
2. Oben links auf die Projektauswahl → **Neues Projekt** → Name `Familiar` → **Erstellen**. Danach sicherstellen, dass oben **Familiar** ausgewählt ist.

## Schritt 2 – Google Auth Platform einrichten

1. <https://console.cloud.google.com/auth/overview> öffnen → **Get started** (bzw. **Jetzt starten**).
2. **App-Informationen:** App-Name `Familiar`, Nutzersupport-E-Mail: deine Adresse → **Weiter**.
3. **Zielgruppe:** **Extern** → **Weiter**.
4. **Kontaktdaten:** `info@familiar-app.de` → **Weiter** → Richtlinie bestätigen → **Erstellen**.
5. Links **Branding:**
   - Startseite der App: `https://familiar-app.de`
   - Link zur Datenschutzerklärung: `https://familiar-app.de/datenschutz/`
   - Autorisierte Domains: `familiar-app.de` hinzufügen
   - **Kein Logo hochladen** (ein Logo löst eine Prüfung durch Google aus, die Tage dauert) → **Speichern**.
6. Links **Datenzugriff** → **Bereiche hinzufügen oder entfernen** → `openid`, `.../auth/userinfo.email`, `.../auth/userinfo.profile` anhaken → **Aktualisieren** → **Speichern**.
7. Links **Zielgruppe** → bei Veröffentlichungsstatus **App veröffentlichen** → bestätigen. (Mit diesen Basis-Bereichen ist keine Google-Prüfung nötig; ohne Veröffentlichung könnten sich nur eingetragene Testnutzer anmelden.)

## Schritt 3 – iOS-Client

1. Links **Clients** → **Client erstellen**.
2. Anwendungstyp **iOS**, Name `Familiar iOS`, Bundle-ID: `de.kohrs.familiar` (App-Store-ID und Team-ID leer lassen – kommen nach dem 3.12.).
3. **Erstellen** → die **Client-ID** (endet auf `.apps.googleusercontent.com`) **kopieren und mir schicken**.

## Schritt 4 – Web-Client (für Supabase)

1. Wieder **Client erstellen** → Anwendungstyp **Webanwendung**, Name `Familiar Supabase`.
2. **Autorisierte Weiterleitungs-URIs** → **URI hinzufügen**: `https://ldeouecoaqyfvubhrjei.supabase.co/auth/v1/callback`
3. **Erstellen**. Es erscheinen **Client-ID** und **Clientschlüssel** (Client Secret).
   - Die **Client-ID mir schicken**.
   - Den **Clientschlüssel nicht** in den Chat – den brauchst du gleich in Schritt 5.

## Schritt 5 – Supabase

1. [Authentication › Sign In / Providers](https://supabase.com/dashboard/project/ldeouecoaqyfvubhrjei/auth/providers) → **Google** öffnen → **Enable Sign in with Google** einschalten.
2. **Client IDs:** zuerst die **Web**-Client-ID, dann Komma, dann die **iOS**-Client-ID (ohne Leerzeichen).
3. **Client Secret (for OAuth):** der Clientschlüssel aus Schritt 4.
4. **Skip nonce checks:** **aus** lassen (Familiar schickt eine Nonce mit).
5. **Save**.

Schreib mir danach „Google fertig“ und die zwei Client-IDs.
