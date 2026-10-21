# Outlook-Freigabe durch die IT (Firmenkonto)

Stand 2026-10-21, geprüft gegen [Grant tenant-wide admin consent](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/grant-admin-consent).

Deine Firma erlaubt Mitarbeitenden nicht, Apps ohne Microsoft-Herausgeberprüfung selbst freizugeben. Das ist eine verbreitete und sinnvolle Einstellung. Die IT muss Familiar einmal freigeben.

## Was du vorher brauchst

Die **Application (client) ID** von Familiar: <https://entra.microsoft.com> (mit deinem **privaten** Konto) → **Entra ID** → **App registrations** → **Familiar** → Seite **Overview**. Die ID ist kein Geheimnis.

## Mail an deine IT (zum Kopieren)

> **Betreff:** Bitte um Freigabe: Lesezugriff auf meinen Outlook-Kalender für die App „Familiar“
>
> Hallo,
>
> ich nutze privat die Familien-App „Familiar“ und möchte dort meine eigenen Outlook-Termine nur anzeigen lassen. Beim Verbinden erscheint „Genehmigung erforderlich“.
>
> - **App:** Familiar (Application/Client ID: `HIER-DIE-ID-EINFÜGEN`)
> - **Angefragte Rechte (delegiert):** `Calendars.ReadBasic`, `offline_access`, `openid`, `email`
> - `Calendars.ReadBasic` ist das kleinste Kalender-Leserecht von Microsoft Graph: nur die Kalender des angemeldeten Nutzers, **ohne** Termin-Text (Body), Anhänge und Erweiterungen. Die App schreibt nichts in Outlook und speichert nur Titel, Zeit, Ort und Organisator der Termine.
>
> **Freigabe-Link** (als Cloud Application Administrator o. Ä. öffnen und prüfen):
> `https://login.microsoftonline.com/organizations/adminconsent?client_id=HIER-DIE-ID-EINFÜGEN`
>
> Alternativ im Entra Admin Center: **Entra ID → Enterprise apps → All applications → Familiar → Security → Permissions → Grant admin consent**.
>
> Wenn ihr den Zugriff auf mich beschränken wollt: in der Enterprise App „Assignment required“ aktivieren und nur mich zuweisen.
>
> Vielen Dank!

## Danach

In Familiar: Profil → Outlook → **Mit Outlook verbinden** erneut tippen. Die Seite „Genehmigung erforderlich“ sollte dann nicht mehr erscheinen.

## Für andere Familien

Damit andere ohne IT-Freigabe auskommen, muss der Herausgeber bei Microsoft verifiziert sein („Publisher Verification“) – Punkt 3 der [Launch-Liste](../LAUNCH-TODO.md).
