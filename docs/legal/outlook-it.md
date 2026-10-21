# Familiar für Outlook freigeben – Informationen für IT-Abteilungen

Eine Person aus Ihrem Unternehmen möchte in der Familien-App **Familiar** ihre **eigenen** Outlook-Termine anzeigen. Weil Familiar von einer Privatperson entwickelt wird und daher kein bei Microsoft verifizierter Herausgeber ist, verlangen viele Unternehmen eine einmalige Freigabe durch die IT. Diese Seite erklärt, was Familiar tut, damit Sie das prüfen können.

## Was Familiar liest

| | |
|---|---|
| **Rechte (delegiert)** | `Calendars.ReadBasic`, `offline_access`, `openid`, `email` |
| **Bedeutung** | Nur die Kalender der jeweils angemeldeten Person. `Calendars.ReadBasic` ist das kleinste Kalender-Leserecht von Microsoft Graph: **ohne** Termin-Text (Body), Anhänge und Erweiterungen. |
| **Gespeichert** | Titel, Beginn und Ende, Ort, Organisator und Absage-Status von Terminen im Zeitraum 7 Tage zurück bis 120 Tage voraus – nur aus den Kalendern, die die Person auswählt. |
| **Sichtbar für** | Ausschließlich die Person selbst. Ihre Termine erscheinen **nicht** bei Familienmitgliedern. |
| **Schreibzugriff** | Keiner. Familiar ändert, erstellt oder löscht nichts in Outlook. |
| **Zugangsdaten** | Das Refresh-Token liegt verschlüsselt auf dem Server (Supabase Vault, EU-Region), nie auf dem Gerät. Die App authentifiziert sich bei Microsoft mit einem Zertifikat. |
| **Widerruf** | In Familiar unter Profil › Outlook › Trennen: Token und gespeicherte Termine werden gelöscht. Zusätzlich jederzeit über Ihre Unternehmensanwendungen in Microsoft Entra ID. |

## Freigabe erteilen

**Variante A – Freigabe-Link:** Die anfragende Person hat Ihnen aus der App einen Link geschickt (`https://login.microsoftonline.com/organizations/adminconsent?client_id=…`). Öffnen Sie ihn mit einem Konto mit der Rolle *Cloud Application Administrator*, *Application Administrator* oder *Global Administrator*, prüfen Sie die angezeigten Rechte und bestätigen Sie.

**Variante B – Entra Admin Center:** Sobald jemand aus Ihrem Unternehmen versucht hat, Familiar zu verbinden, finden Sie die App unter **Entra ID › Enterprise apps › All applications › Familiar**. Dort unter **Security › Permissions** auf **Grant admin consent** klicken.

**Zugriff einschränken (optional):** In der Enterprise App unter **Properties** „Assignment required“ aktivieren und unter **Users and groups** nur die Personen zuweisen, die Familiar nutzen dürfen.

Microsoft-Dokumentation: [Grant tenant-wide admin consent](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/grant-admin-consent) · [Configure the admin consent workflow](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-admin-consent-workflow)

## Kontakt

Fragen zur Freigabe: [kontakt@familiar-app.de]. Weitere Informationen: [Datenschutzerklärung](/datenschutz/).
