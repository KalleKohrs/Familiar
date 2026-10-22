# familiar-app.de

Statische Website für Familiar. Wird bei einem statischen Hoster veröffentlicht (z. B. Cloudflare Pages oder Netlify; `_redirects`/`_headers` sind für beide geschrieben).

| Pfad | Zweck |
|---|---|
| `/.well-known/apple-app-site-association` | Universal Links: `/join/*` öffnet die App ([Apple: Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains)). Muss per HTTPS, ohne Weiterleitung und als `application/json` ausgeliefert werden. Enthält Team-ID und Bundle-ID (keine Geheimnisse). |
| `/join/<code>` | Ausweichseite ohne installierte App: zeigt den Code und den Weg in den App Store. |
| `/datenschutz/`, `/impressum/`, `/support/`, `/outlook-it/` | Erzeugt aus `docs/legal/*.md` mit `python3 tools/build-website.py` – Texte nur dort ändern, dann neu erzeugen. Platzhalter `[…]` sind gelb markiert und müssen vor dem Veröffentlichen ersetzt sein. |
| `/` | Startseite. |
| `/app/` | Ziel aller „Laden im App Store“-Knöpfe. Vor dem Start die Seite „Bald im App Store“, danach Weiterleitung in den App Store per Zeile in `_redirects` (siehe `docs/LAUNCH-TODO.md`, Punkt 11). Abzeichen: offizielle Apple-Grafik `assets/app-store-badge.svg` (Apple Marketing Tools, Deutsch, unverändert). |

Schrift: Bricolage Grotesque (SIL Open Font License, `assets/fonts/`), selbst gehostet als WOFF2, reduziert auf lateinische Zeichen (erzeugt mit `fontTools.subset` aus der Schriftdatei der App) – keine externen Ressourcen, kein Tracking.

App-Bild auf der Startseite: `assets/app-aufgaben.jpg`, verkleinert aus `docs/app-store/screenshots/1-aufgaben.png` (Vorführdaten).
