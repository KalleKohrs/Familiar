# familiar-app.de

Statische Website für Familiar. Wird bei einem statischen Hoster veröffentlicht (z. B. Cloudflare Pages oder Netlify; `_redirects`/`_headers` sind für beide geschrieben).

| Pfad | Zweck |
|---|---|
| `/.well-known/apple-app-site-association` | Universal Links: `/join/*` öffnet die App ([Apple: Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains)). Muss per HTTPS, ohne Weiterleitung und als `application/json` ausgeliefert werden. Enthält Team-ID und Bundle-ID (keine Geheimnisse). |
| `/join/<code>` | Ausweichseite ohne installierte App: zeigt den Code und den Weg in den App Store. |
| `/datenschutz`, `/impressum`, `/support` | folgen aus `docs/legal/` (Launch-Liste Punkt 6). |
