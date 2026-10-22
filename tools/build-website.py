#!/usr/bin/env python3
"""Erzeugt die Textseiten von familiar-app.de aus docs/legal/*.md.

Aufruf (im Projektordner):  python3 tools/build-website.py
Unterstützt nur, was die Texte brauchen: Überschriften, Absätze, Listen, Tabellen, Zitate,
**fett**, `Code` und [Links](url). Entwurfs-Hinweise (Zitat-Absätze) und „(Entwurf)“ in
Überschriften erscheinen nicht auf der Website; übrige Platzhalter in eckigen Klammern werden
gelb markiert, damit nichts Unfertiges unbemerkt online geht.
"""
import html
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "docs" / "legal"
SITE = ROOT / "website"

PAGES = {
    "datenschutz.md": ("datenschutz", "Datenschutzerklärung"),
    "impressum.md": ("impressum", "Impressum"),
    "outlook-it.md": ("outlook-it", "Familiar für Outlook freigeben"),
    "support.md": ("support", "Hilfe"),
}


def inline(text: str) -> str:
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", r'<a href="\2">\1</a>', text)
    # Übrige [Platzhalter] hervorheben.
    text = re.sub(r"\[([^\]<>]+)\]", r'<mark>[\1]</mark>', text)
    return text


def render(markdown: str) -> str:
    out, paragraph, items, rows = [], [], [], []

    def flush():
        nonlocal paragraph, items, rows
        if paragraph:
            # Zeilenumbrüche bleiben erhalten (Anschriften); Fließtext steht je Absatz in einer Zeile.
            out.append(f"<p>{'<br>'.join(inline(line) for line in paragraph)}</p>")
        if items:
            out.append("<ul>" + "".join(f"<li>{inline(i)}</li>" for i in items) + "</ul>")
        if rows:
            header, *body = [r for r in rows if not (re.fullmatch(r"[\s|:-]+", r) and "-" in r)]
            cells = lambda r: [c.strip() for c in r.strip().strip("|").split("|")]
            head = "".join(f"<th>{inline(c)}</th>" for c in cells(header))
            trs = "".join("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in cells(r)) + "</tr>" for r in body)
            thead = f"<thead><tr>{head}</tr></thead>" if head.replace("<th></th>", "") else ""
            out.append(f'<div class="table"><table>{thead}<tbody>{trs}</tbody></table></div>')
        paragraph, items, rows = [], [], []

    for line in markdown.splitlines():
        stripped = line.strip()
        if not stripped:
            flush()
        elif stripped.startswith("#"):
            flush()
            level = len(stripped) - len(stripped.lstrip("#"))
            title = stripped[level:].strip().replace(" (Entwurf)", "")
            out.append(f"<h{level}>{inline(title)}</h{level}>")
        elif stripped.startswith(">"):
            # Entwurfs-Hinweise sind für die Arbeit im Repo, nicht für die Website.
            flush()
        elif stripped.startswith("|"):
            if paragraph or items:
                flush()
            rows.append(stripped)
        elif re.match(r"^([-*]|\d+\.)\s", stripped):
            if paragraph or rows:
                flush()
            items.append(re.sub(r"^([-*]|\d+\.)\s+", "", stripped))
        else:
            if items or rows:
                flush()
            paragraph.append(stripped)
    flush()
    return "\n".join(out)


def page(title: str, body: str) -> str:
    # Abschnitte bekommen Sprungmarken; ab drei Abschnitten gibt es ein Inhaltsverzeichnis.
    sections = []

    def anchor(match):
        text = re.sub(r"<[^>]+>", "", match.group(1))
        slug = re.sub(r"[^a-z0-9äöüß]+", "-", text.lower()).strip("-")
        sections.append((slug, match.group(1)))
        return f'<h2 id="{slug}">{match.group(1)}</h2>'

    body = re.sub(r"<h2>(.*?)</h2>", anchor, body)
    # Zweispaltige Tabellen ohne Kopfzeile (Begriff | Erklärung) stehen auf dem Handy untereinander.
    body = body.replace('<div class="table"><table><tbody>', '<div class="table stack"><table><tbody>')
    toc = ""
    if len(sections) >= 3:
        links = "".join(f'<li><a href="#{slug}">{text}</a></li>' for slug, text in sections)
        toc = f"""<details class="toc" id="toc">
      <summary>Auf dieser Seite</summary>
      <nav aria-label="Auf dieser Seite"><ol>{links}</ol></nav>
    </details>
    <script>if (matchMedia("(min-width: 960px)").matches) document.getElementById("toc").open = true;</script>
    """
    layout = "doc" if toc else "doc single"
    help_current = ' aria-current="page"' if title == "Hilfe" else ""
    return f"""<!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)} – Familiar</title>
  <meta name="theme-color" content="#1E1519">
  <link rel="icon" href="/assets/mark.svg" type="image/svg+xml">
  <link rel="preload" href="/assets/fonts/BricolageGrotesque.woff2" as="font" type="font/woff2" crossorigin>
  <link rel="stylesheet" href="/assets/site.css">
</head>
<body>
  <a class="skip" href="#inhalt">Zum Inhalt</a>
  <header class="site-header">
    <a class="brand" href="/"><img src="/assets/mark.svg" alt="" width="32" height="32">Familiar</a>
    <nav aria-label="Hauptnavigation"><a href="/support/"{help_current}>Hilfe</a><a href="/kontakt/">Kontakt</a></nav>
  </header>
  <div class="{layout}">
    {toc}<main id="inhalt" class="prose">
{body}
    </main>
  </div>
  <footer class="site-footer">
    <div class="wrap">
      <div>
        <a class="brand" href="/"><img src="/assets/mark.svg" alt="" width="28" height="28">Familiar</a>
        <p class="tagline">Aufgaben teilen, ruhig planen.</p>
      </div>
      <nav aria-label="Rechtliches"><a href="/support/">Hilfe</a><a href="/kontakt/">Kontakt</a><a href="/datenschutz/">Datenschutz</a><a href="/impressum/">Impressum</a></nav>
      <small>© 2026 Familiar</small>
    </div>
  </footer>
</body>
</html>
"""


def main() -> None:
    for source, (slug, title) in PAGES.items():
        target = SITE / slug / "index.html"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(page(title, render((SOURCE / source).read_text())))
        print("geschrieben:", target.relative_to(ROOT))


if __name__ == "__main__":
    main()
