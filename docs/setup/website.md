# Website familiar-app.de veröffentlichen (Netlify)

Stand 2026-10-21, geprüft gegen die Netlify-Doku ([Deploys](https://docs.netlify.com/deploy/create-deploys/), [Externe DNS](https://docs.netlify.com/manage/domains/configure-domains/configure-external-dns/)). Dauer: etwa 20 Minuten plus Wartezeit für DNS (bis zu 24 h).

**Warum Netlify:** kostenlos für eine kleine Seite, Hochladen per Drag-and-drop, HTTPS automatisch, und die Domain bleibt bei INWX. E-Mail (MX) und die Resend-Einträge für den Mailversand bleiben unberührt.

**Stand:** Alle Angaben sind ausgefüllt (Impressum, Datenschutz). Rechtlich prüfen lassen ist trotzdem empfehlenswert.

## Schritt 1 – Netlify-Konto

1. <https://app.netlify.com/signup> öffnen und ein Konto anlegen (z. B. mit E-Mail).
2. Fragen nach Team/Projekt kannst du überspringen bzw. mit Standardwerten bestätigen.

## Schritt 2 – Website hochladen

1. Im Finder den Ordner `Familiar/website` öffnen (er enthält `index.html`, `assets`, `datenschutz` …).
2. Auf <https://app.netlify.com/drop> den **ganzen Ordner `website`** in das Feld ziehen.
3. Netlify zeigt nach ein paar Sekunden eine Adresse wie `https://irgendwas-12345.netlify.app` – öffnen und prüfen, ob die Startseite erscheint.
4. **Site configuration** → **Change site name** → `familiar-app` (falls frei) → **Save**.

Später aktualisieren: Seite in Netlify öffnen → **Deploys** → den Ordner `website` erneut in das Feld unten ziehen.

## Schritt 2b – Kontaktformular einschalten

1. In der Seite: **Forms** (bzw. **Project configuration › Forms**) → **Enable form detection**.
2. Den Ordner `website` noch einmal unter **Deploys** hineinziehen (Formulare werden erst ab dem nächsten Hochladen erkannt).
3. **Forms › Form notifications › Add notification › Email notification** → `info@familiar-app.de`, Formular `kontakt` → **Save**. Nachrichten kommen dann per Mail; alle Einsendungen stehen außerdem unter **Forms**.

## Schritt 3 – Domain verbinden

1. In Netlify: **Domain management** → **Add a domain** → `familiar-app.de` eingeben → **Verify** → **Add domain**.
2. Netlify fügt `www.familiar-app.de` automatisch hinzu und zeigt „Awaiting External DNS“.

## Schritt 4 – DNS bei INWX

1. Bei INWX anmelden → **Domains** → `familiar-app.de` → **DNS** (Nameserver-Einträge).
2. **Nichts löschen**, was mit `MX`, `TXT`, `send.mail`, `resend._domainkey` o. Ä. zu tun hat – das ist E-Mail.
3. Gibt es bereits einen **A-Eintrag** ohne Namen (bzw. `@`), z. B. eine Parkseite: diesen **ändern** statt einen zweiten anzulegen. Ebenso einen vorhandenen `www`-Eintrag.
4. Einträge (Name leer bzw. `@` steht für die Domain selbst):

   | Typ | Name | Wert |
   |---|---|---|
   | A | *(leer)* | `75.2.60.5` |
   | CNAME | `www` | deine Netlify-Adresse aus Schritt 2, z. B. `familiar-app.netlify.app` |

5. Speichern. Netlify prüft das selbst; nach einiger Zeit (Minuten bis 24 h) steht dort „Netlify DNS verified“ und das HTTPS-Zertifikat wird automatisch ausgestellt.

## Schritt 5 – Prüfen

Schreib mir, wenn die Seite unter `https://familiar-app.de` erscheint – ich prüfe dann Einladungslinks (`/join/…`), die Apple-Datei und alle Seiten.
