# Einrichtung: Apple Developer Program

Schritt-für-Schritt-Anleitung für alles, was Familiar bei Apple braucht. Grundlage sind die offiziellen Apple-Account-Hilfeseiten (Links unten). **Gib keine dieser Werte oder Dateien in den Chat ein.** Team-ID und Bundle-ID sind keine Geheimnisse, gehören aber in deine lokale Datei `ios/Config/Local.xcconfig`. Der APNs-Schlüssel (`.p8`) ist ein Geheimnis und kommt ausschließlich in die Supabase-Edge-Function-Secrets.

Du brauchst die Rolle **Account Holder** oder **Admin** im Developer-Team.

## 0. Kostenloses Konto oder bezahlte Mitgliedschaft?

**Certificates, Identifiers & Profiles** (Abschnitte 3 und 4) gibt es nur mit der bezahlten **Apple Developer Program**-Mitgliedschaft (99 USD pro Jahr, in Landeswährung; laut Apple-Hilfe „Enrollment“). Mit einem kostenlosen Konto erscheint dort „Access Unavailable“.

Laut Apple-Tabelle „Supported capabilities (iOS)“ für Familiar relevant:

| Capability | Kostenloses Konto | Developer Program |
|---|---|---|
| Push Notifications (Mitteilungen, Live-Activity-Pushes) | nein | ja |
| Sign in with Apple | nein | ja |
| Associated Domains (Einladungslinks) | nein | ja |
| App Groups | ja | ja |

Ohne Mitgliedschaft geht: Entwicklung und Tests im **Simulator**, E-Mail-Anmeldung, lokale Live Activities. Mit kostenlosem Konto kann Xcode die App zusätzlich auf dein eigenes iPhone laden (laut Apple: höchstens 3 Geräte und 3 Apps, Profile laufen nach 7 Tagen ab), aber ohne die drei Capabilities oben.

**Empfehlung:** Mitgliedschaft abschließen, bevor Sign in with Apple, Push und Einladungslinks umgesetzt werden. Anmeldung als Einzelperson unter [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll/); den rechtlichen Namen exakt angeben und mit eigener Kreditkarte zahlen, sonst verzögert sich die Freischaltung. Danach mit Abschnitt 3 weitermachen.

## 1. Team-ID nachsehen

1. Auf [developer.apple.com/account](https://developer.apple.com/account) anmelden.
2. In der Seitenleiste **Membership details** öffnen.
3. Die **Team ID** (10 Zeichen, z. B. `ABCDE12345`) notieren.

Alternativ in Xcode: **Xcode › Settings › Accounts**, Team auswählen.

## 2. Bundle-ID festlegen und lokal eintragen

Wähle eine eindeutige Bundle-ID in Reverse-DNS-Form, z. B. `de.deinname.familiar`. Die Live-Activity-Extension bekommt automatisch die Endung `.LiveActivity`.

1. `ios/Config/Local.example.xcconfig` kopieren nach `ios/Config/Local.xcconfig`.
2. Eintragen:
   ```
   FAMILIAR_DEVELOPMENT_TEAM = ABCDE12345
   FAMILIAR_BUNDLE_ID = de.deinname.familiar
   ```
3. `Local.xcconfig` wird nicht eingecheckt (`.gitignore`).

## 3. App-ID registrieren und Capabilities aktivieren

Laut Apple-Hilfe „Register an App ID“:

1. In **Certificates, Identifiers & Profiles** in der Seitenleiste **Identifiers** wählen, dann oben links auf **+** klicken.
2. **App IDs** auswählen → **Continue**.
3. Den vorausgewählten Typ (App) bestätigen → **Continue**.
4. **Description**: z. B. „Familiar“.
5. **Explicit** wählen und die Bundle-ID aus Schritt 2 eintragen (muss exakt mit Xcode übereinstimmen).
6. Unter **Capabilities** aktivieren:
   - **Push Notifications** (Mitteilungen und Live Activities)
   - **Sign in with Apple**
   - **Associated Domains** (Einladungslinks über deine Domain)
7. **Continue** → Angaben prüfen → **Register**.

Hinweis: Die in der App-ID aktivierten Capabilities sind eine Erlaubnisliste. Zusätzlich werden sie im Xcode-Target eingetragen; das übernehme ich in den jeweiligen Phasen (Entitlements-Datei), Xcode synchronisiert die Provisioning-Profile dann automatisch.

## 4. APNs-Schlüssel (.p8) erstellen – erst in Phase 7 nötig

Laut Apple-Hilfe „Create a private key to access a service“:

1. In **Certificates, Identifiers & Profiles** **Keys** wählen, oben links **+**.
2. **Key Name**: z. B. „Familiar APNs Sandbox“.
3. Haken bei **Apple Push Notification service (APNs)** → **Continue**.
4. Neben „Apple Push Notification service“ auf **Configure** klicken:
   - **Environment**: zunächst **Sandbox** (Entwicklung). Für den Release später einen zweiten Schlüssel für **Production** (Apple empfiehlt getrennte, umgebungsspezifische Schlüssel).
   - **Key type**: **Team Scoped** (für alle Apps des Teams) ist am einfachsten.
5. Konfiguration prüfen → **Confirm**.
6. **Download** klicken. **Achtung:** Der Schlüssel kann nur ein einziges Mal heruntergeladen werden. Die `.p8`-Datei sicher aufbewahren (nicht im Projektordner, nicht in iCloud-Desktop).
7. **Done**.
8. **Key ID** nachsehen: **Keys** → Schlüssel auswählen → die Kennung steht unter dem Namen.

### In Supabase hinterlegen (nicht im Chat!)

Supabase-Dashboard → Projekt → **Edge Functions › Secrets** → folgende Secrets anlegen:

| Name | Wert |
|---|---|
| `APNS_KEY_P8` | gesamter Inhalt der `.p8`-Datei (inkl. `-----BEGIN PRIVATE KEY-----`-Zeilen) |
| `APNS_KEY_ID` | Key ID aus Schritt 8 |
| `APNS_TEAM_ID` | Team-ID aus Abschnitt 1 |
| `APNS_TOPIC` | deine Bundle-ID |
| `APNS_ENVIRONMENT` | `sandbox` (später `production`) |

Danach mir nur Bescheid geben, *dass* die Secrets angelegt sind – nie die Werte.

## Quellen

- [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios)
- [Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment/)
- [Compare memberships](https://developer.apple.com/support/compare-memberships/)
- [Register an App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id)
- [Create a private key to access a service](https://developer.apple.com/help/account/keys/create-a-private-key)
- [Get a key identifier](https://developer.apple.com/help/account/keys/get-a-key-identifier)
- [Establishing a token-based connection to APNs](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns)
