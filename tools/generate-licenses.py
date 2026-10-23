#!/usr/bin/env python3
"""Erzeugt ios/Familiar/Resources/Licenses.json – die Open-Source-Lizenzhinweise für die App.

Aufruf (im Projektordner, nach einem Xcode-Build, damit die Pakete ausgecheckt sind):
    python3 tools/generate-licenses.py <Pfad zu SourcePackages/checkouts>

Ohne Pfad wird der neueste DerivedData-Ordner von Familiar gesucht. Übernimmt LICENSE- und
NOTICE-Dateien jedes Pakets aus Package.resolved (Apache 2.0 verlangt die NOTICE-Datei, MIT den
Copyright-Hinweis) sowie die Schriftlizenz (SIL OFL) von Bricolage Grotesque.
Nach jedem Paket-Update erneut ausführen.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RESOLVED = ROOT / "ios" / "Packages" / "FamiliarKit" / "Package.resolved"
FONT_LICENSE = ROOT / "ios" / "Packages" / "FamiliarKit" / "Sources" / "FamiliarDesign" / "Resources" / "Fonts" / "BricolageGrotesque-OFL.txt"
OUTPUT = ROOT / "ios" / "Familiar" / "Resources" / "Licenses.json"


def find_checkouts() -> pathlib.Path:
    if len(sys.argv) > 1:
        return pathlib.Path(sys.argv[1])
    derived = pathlib.Path.home() / "Library" / "Developer" / "Xcode" / "DerivedData"
    candidates = sorted(derived.glob("Familiar-*/SourcePackages/checkouts"), key=lambda p: p.stat().st_mtime)
    if not candidates:
        sys.exit("Keine ausgecheckten Pakete gefunden – Pfad zu SourcePackages/checkouts angeben.")
    return candidates[-1]


def license_name(text: str) -> str:
    # Reihenfolge wichtig: Der OFL-Text enthält ebenfalls „Permission is hereby granted“.
    if "SIL OPEN FONT LICENSE" in text.upper():
        return "SIL Open Font License 1.1"
    if "Apache License" in text and "Version 2.0" in text:
        return "Apache License 2.0"
    if "Permission is hereby granted, free of charge" in text:
        return "MIT License"
    return "Lizenz"


def main() -> None:
    checkouts = find_checkouts()
    pins = json.loads(RESOLVED.read_text())["pins"]
    entries = []
    for pin in sorted(pins, key=lambda p: p["identity"]):
        url = pin["location"]
        folder = next((d for d in checkouts.iterdir()
                       if d.name.lower() == url.rstrip("/").removesuffix(".git").split("/")[-1].lower()), None)
        if folder is None:
            sys.exit(f"Paket {pin['identity']} nicht unter {checkouts} gefunden.")
        texts = []
        for pattern in ("LICENSE*", "LICENCE*", "NOTICE*"):
            for file in sorted(folder.glob(pattern)):
                if file.is_file():
                    texts.append(file.read_text(errors="replace").strip())
        if not texts:
            sys.exit(f"Keine Lizenzdatei in {folder}.")
        entries.append({
            "name": url.rstrip("/").removesuffix(".git").split("/")[-1],
            "version": pin["state"].get("version") or pin["state"].get("revision", "")[:7],
            "url": url.removesuffix(".git"),
            "license": license_name(texts[0]),
            "text": "\n\n".join(texts),
        })
    font = FONT_LICENSE.read_text(errors="replace").strip()
    entries.append({
        "name": "Bricolage Grotesque (Schrift)",
        "version": "",
        "url": "https://github.com/ateliertriay/bricolage",
        "license": license_name(font),
        "text": font,
    })
    OUTPUT.write_text(json.dumps(entries, ensure_ascii=False, indent=1) + "\n")
    print(f"{len(entries)} Einträge → {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
