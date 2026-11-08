#!/usr/bin/env python3
"""Finale App-Store-Bilder (iPhone 6,9", 1320 × 2868, PNG ohne Alpha).

Aufruf (Repo-Wurzel):
  swiftc -O docs/app-store/v2/tools/render-html.swift -o /tmp/render-html
  python3 docs/app-store/v2/quelle/store.py /tmp/render-html

Grundsätze
- Rohmaterial: docs/app-store/v2/rohmaterial/ (Simulator iPhone 18 Pro Max, Vorführdaten „showcase“, 9:41).
- Alle App-Inhalte sind unveränderte Ausschnitte echter Aufnahmen (Richtlinie 2.3.3).
- Bauteile werden exakt an ihrer eigenen Kante ausgeschnitten (gemessen mit tools/probe.swift), 2 px nach innen,
  mit der Rundung des Bauteils – nie mit App-Hintergrund drumherum („Rahmen im Rahmen“ vermeiden).
- Raster (CSS-Pixel, Seite 660 × 1434, Faktor 2): Rand 48, Spalte 564, Schlagzeile oben bei 104, Unterzeile 296 (einzeilig),
  Inhalt ab 400.
"""
import subprocess, sys, pathlib
Q = pathlib.Path(__file__).resolve().parent
OUT = Q.parent / "final"
RENDER = sys.argv[1]
FONT = "../../../../ios/Packages/FamiliarKit/Sources/FamiliarDesign/Resources/Fonts/BricolageGrotesque.ttf"
ICON = "../../../../ios/Familiar/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
RAW = "../rohmaterial/"
W = 1320                 # Breite der Aufnahmen (px)
M, COL = 48, 564         # Seitenrand, Spaltenbreite
DISPLAY_R = 165          # Eckenradius des iPhone-Displays in Aufnahme-Pixeln (55 pt × 3)

# ---- gemessene Bauteile: (x0, y0, x1, y1, radius) in Aufnahme-Pixeln ----
CARD_R = 72              # 24 pt × 3
L_ZIMMER   = (48, 1063, 1272, 1521, CARD_R)   # hell-aufgaben
L_GESCHENK = (48, 1560, 1272, 2018, CARD_R)
D_ZUGEW    = (48, 1127, 1272, 1685, CARD_R)   # dunkel-detail
D_BUTTON   = (48, 1746, 1272, 1896, 75)
L_REIHUM   = (60, 1715, 1260, 2315, CARD_R)   # hell-reihum-editor (neu aufgenommen, ganz sichtbar)
L_ZUGEW_ED = (60, 569, 1260, 1457, CARD_R)
PANEL_TOP, SHEET_CORNER_Y = 436, 2756           # Ausschnitt ab Lücke über „Zugewiesen“; darunter Blatt-Ecken
L_KAL      = (48, 562, 1272, 1827, CARD_R)    # hell-kalender
L_TAG      = (48, 2003, 1272, 2423, CARD_R)
L_BERGER   = (48, 456, 1272, 675, CARD_R)     # hell-familien
L_OMA      = (48, 712, 1272, 931, CARD_R)
L_MITGL    = (48, 668, 1272, 1347, CARD_R)    # hell-regeln
L_RECHTE   = (48, 1245, 1272, 2136, CARD_R)   # hell-regeln-unten (ganz sichtbar)
D_KOPF     = (14, 361, 1234, 920, CARD_R)     # dunkel-detail: Kopfbereich, Ränder = Innenabstand der Karte
D_VERLAUF  = [(48, y0, 1272, y1, CARD_R) for y0, y1 in [(707, 1073), (1108, 1474), (1643, 2009), (2044, 2410)]]
SHEET_TOP, SHEET_R = 186, 112                 # Blatt (Sheet) im Editor

BASE = f"""
@font-face {{ font-family:'Bricolage'; src:url('{FONT}'); font-weight:200 800; }}
* {{ box-sizing:border-box; margin:0; padding:0; }}
html, body {{ width:660px; height:1434px; overflow:hidden; }}
body {{ position:relative; font-family:'Bricolage',sans-serif; -webkit-font-smoothing:antialiased; }}
h1 {{ position:absolute; left:{M}px; right:{M}px; top:104px; font-weight:700; letter-spacing:-0.025em; font-size:84px; line-height:1.0; z-index:9; }}
em {{ font-style:normal; }}
.sub {{ position:absolute; left:{M+2}px; right:{M}px; top:296px; font-weight:480; font-size:26px; line-height:1.28; z-index:9; white-space:nowrap; }}
.mark {{ position:absolute; left:{M}px; top:40px; font-weight:650; font-size:22px; z-index:9; }}
.mark i {{ display:inline-block; width:14px; height:14px; border-radius:4px; margin-right:10px; vertical-align:-1px; }}
.el {{ position:absolute; overflow:hidden; }}
.el img {{ position:absolute; display:block; }}
.el .edge {{ position:absolute; inset:0; border-radius:inherit; pointer-events:none; }}
"""

SH_ORANGE = "0 26px 60px rgba(110,40,5,.36), 0 4px 14px rgba(110,40,5,.16)"
SH_LIGHT  = "0 26px 60px rgba(120,60,25,.20), 0 3px 12px rgba(120,60,25,.10)"
EDGE_LIGHT = "inset 0 0 0 1px rgba(255,255,255,.70)"
EDGE_DARK  = "inset 0 0 0 1px rgba(255,243,230,.10)"

def part(src, b, x, y, w, shadow, edge, z=3, inset=2):
    """Exakter Ausschnitt eines Bauteils b=(x0,y0,x1,y1,r) mit Breite w an Position (x, y)."""
    x0, y0, x1, y1, r = b
    sx, sy, sw, sh = x0 + inset, y0 + inset, (x1 - x0) - 2 * inset, (y1 - y0) - 2 * inset
    sc = w / sw
    return (f'<div class=el style="z-index:{z};left:{x:.2f}px;top:{y:.2f}px;width:{w:.2f}px;height:{sh*sc:.2f}px;'
            f'border-radius:{(r-inset)*sc:.2f}px;box-shadow:{shadow}">'
            f'<img src="{RAW}{src}" style="left:{-sx*sc:.2f}px;top:{-sy*sc:.2f}px;width:{W*sc:.2f}px">'
            f'<div class=edge style="box-shadow:{edge}"></div></div>')

def part_h(b, w, inset=2):
    x0, y0, x1, y1, r = b
    return ((y1 - y0) - 2 * inset) * w / ((x1 - x0) - 2 * inset)

def screen(src, x, y, w, shadow, edge, top=0, radius=DISPLAY_R, z=2):
    """Ganzer Bildschirm (ab Zeile `top`), oben gerundet, läuft unten aus dem Bild."""
    sc = w / W
    return (f'<div class=el style="z-index:{z};left:{x:.2f}px;top:{y:.2f}px;width:{w:.2f}px;height:{1434-y+10:.2f}px;'
            f'border-radius:{radius*sc:.2f}px {radius*sc:.2f}px 0 0;box-shadow:{shadow}">'
            f'<img src="{RAW}{src}" style="left:0;top:{-top*sc:.2f}px;width:{w:.2f}px">'
            f'<div class=edge style="box-shadow:{edge}"></div></div>')

def device(src, x, y, w, shadow, edge, z=2):
    """Ganzer Bildschirm, passt vollständig ins Bild: alle vier Ecken mit Display-Rundung."""
    sc = w / W; h = 2868 * sc; r = DISPLAY_R * sc
    return (f'<div class=el style="z-index:{z};left:{x:.2f}px;top:{y:.2f}px;width:{w:.2f}px;height:{h:.2f}px;'
            f'border-radius:{r:.2f}px;box-shadow:{shadow}">'
            f'<img src="{RAW}{src}" style="left:0;top:0;width:{w:.2f}px">'
            f'<div class=edge style="box-shadow:{edge}"></div></div>')

def lift(src, b, sx_page, sy_page, sc, k, shadow, edge, top=0, dy=0):
    """Bauteil, das aus dem Bildschirm vergrößert „abhebt“ – gleiche Mitte wie im Bildschirm."""
    x0, y0, x1, y1, r = b
    cx = sx_page + (x0 + x1) / 2 * sc
    cy = sy_page + ((y0 + y1) / 2 - top) * sc
    w = (x1 - x0 - 4) * sc * k
    h = part_h(b, w)
    return part(src, b, cx - w / 2, cy - h / 2 + dy, w, shadow, edge, z=5)

def page(name, css, body):
    (Q / f"{name}.html").write_text(f"<!doctype html><meta charset=utf-8><style>{BASE}{css}</style><body>{body}</body>")
    subprocess.run([RENDER, str(Q / f"{name}.html"), str(OUT / f"{name}.png"), "660", "1434"], check=True)

ORANGE   = "background:radial-gradient(540px 440px at 12% 0%, rgba(255,255,255,.24), transparent 70%), linear-gradient(175deg,#F9954A 0%,#F27A2B 46%,#E8631A 100%); color:#fff;"
PAPIER   = "background:radial-gradient(620px 520px at 92% 0%, rgba(255,150,85,.42), transparent 70%), radial-gradient(680px 620px at 0% 100%, rgba(242,190,140,.50), transparent 70%), #F5ECE1; color:#2B1F25;"
APRIKOSE = "background:radial-gradient(560px 460px at 100% 0%, rgba(255,255,255,.65), transparent 70%), linear-gradient(180deg,#FDE6D2 0%,#F9C79C 100%); color:#2B1F25;"
ON_ORANGE = ".mark{color:#fff} .mark i{background:#fff} h1{text-shadow:0 2px 24px rgba(150,55,5,.20)} h1 em{color:#2B141A;text-shadow:none} .sub{color:rgba(255,255,255,.95)}"
ON_LIGHT  = ".mark{color:#6A564B} .mark i{background:#F27A2B} h1{font-weight:660} h1 em{color:#C9530F} .sub{color:#5E4C43}"
MARK = '<div class=mark><i></i>Familiar</div>'
Y0 = 400

# 01 · Handy mittig, eine Karte hebt sich vergrößert heraus (Orange)
sc = COL / W
page("01-wer-macht-was", f"body{{{ORANGE}}} {ON_ORANGE}",
     f'{MARK}<h1>Wer macht was<br><em>und bis wann?</em></h1><div class=sub>Alle Aufgaben der Familie an einem Ort.</div>'
     + screen("hell-aufgaben.png", M, Y0, COL, SH_ORANGE, EDGE_LIGHT)
     + lift("hell-aufgaben.png", L_ZIMMER, M, Y0, sc, 1.10, "0 34px 70px rgba(110,40,5,.42), 0 6px 16px rgba(110,40,5,.18)", EDGE_LIGHT))

# 02 · Drei Bauteile untereinander, Unterzeile unten (Papier, dunkle App)
h_kopf = part_h(D_KOPF, COL); h_zug = part_h(D_ZUGEW, COL); h_btn = part_h(D_BUTTON, COL)
y_k = Y0 + 16; y_z = y_k + h_kopf + 24; y_b = y_z + h_zug + 24
page("02-jeder-sein-teil", f"body{{{PAPIER}}} {ON_LIGHT} .sub{{top:{y_b + h_btn + 60:.1f}px}}",
     f'{MARK}<h1>Jeder hakt<br><em>seinen Teil</em> ab.</h1>'
     + part("dunkel-detail.png", D_KOPF, M, y_k, COL, "0 26px 60px rgba(60,25,10,.34), 0 3px 12px rgba(60,25,10,.14)", EDGE_DARK)
     + part("dunkel-detail.png", D_ZUGEW, M, y_z, COL, "0 30px 66px rgba(60,25,10,.38), 0 4px 14px rgba(60,25,10,.16)", EDGE_DARK, z=4)
     + part("dunkel-detail.png", D_BUTTON, M, y_b, COL, "0 20px 46px rgba(170,70,10,.32), 0 3px 10px rgba(170,70,10,.14)", "inset 0 0 0 1px rgba(255,255,255,.18)", z=4)
     + '<div class=sub>„Erinnern“ für alle, die noch offen sind.</div>')

# 03 · Ausschnitt des Editors als Bildschirm-Fläche, läuft unten aus (Aprikose)
s3 = COL / W
y3 = max(Y0 + 70, 1434 - (SHEET_CORNER_Y - 20 - PANEL_TOP) * s3)
page("03-reihum", f"body{{{APRIKOSE}}} {ON_LIGHT}",
     f'{MARK}<h1>Mal Paul,<br><em>mal Mia.</em></h1><div class=sub>Reihum verteilt Aufgaben von selbst.</div>'
     + screen("hell-reihum-editor.png", M, y3, COL, SH_LIGHT, EDGE_LIGHT, top=PANEL_TOP, radius=DISPLAY_R))

# 04 · Poster: Kalender oben, Schlagzeile unten, Zeichen unten (Orange)
w4 = COL; x4 = M
h_kal = part_h(L_KAL, w4); h_tag = part_h(L_TAG, w4)
page("04-kalender", f"body{{{ORANGE}}} {ON_ORANGE} h1{{top:1016px}} .sub{{top:1208px}} .mark{{top:auto;bottom:46px}}",
     part("hell-kalender.png", L_KAL, x4, 104, w4, SH_ORANGE, EDGE_LIGHT)
     + part("hell-kalender.png", L_TAG, x4, 104 + h_kal + 24, w4, SH_ORANGE, EDGE_LIGHT)
     + '<h1>Der Monat<br>im Blick.</h1><div class=sub>Aufgaben und Wiederholungen im Kalender.</div>' + MARK)

# 05 · Familien oben, Rechte darunter, Schlagzeile darunter – Block senkrecht mittig (Papier)
h_fam = part_h(L_BERGER, COL); h_re = part_h(L_RECHTE, COL)
block5 = h_fam + 16 + h_fam + 32 + h_re + 72 + 168 + 24 + 66
t5 = max(110, (1434 - block5) / 2 + 20)
y_ber = t5; y_oma = y_ber + h_fam + 16; y_re = y_oma + h_fam + 32; y_h = y_re + h_re + 72
page("05-familien", f"body{{{PAPIER}}} {ON_LIGHT} h1{{top:{y_h:.1f}px}} .sub{{top:{y_h + 192:.1f}px;white-space:normal}}",
     MARK
     + part("hell-familien.png", L_BERGER, M, y_ber, COL, SH_LIGHT, EDGE_LIGHT)
     + part("hell-familien.png", L_OMA, M, y_oma, COL, SH_LIGHT, EDGE_LIGHT)
     + part("hell-regeln-unten.png", L_RECHTE, M, y_re, COL, SH_LIGHT, EDGE_LIGHT)
     + '<h1>Familie, WG,<br>Oma &amp; Opa.</h1><div class=sub>Mehrere Familien in einer App –<br>jede mit eigenen Regeln.</div>')

# 06 · Verlauf als Kartenstapel; die gelöschte Aufgabe vorn und etwas größer; Unterzeile unten (Orange)
w6 = 540; x6 = (660 - w6) / 2; h6 = part_h(D_VERLAUF[0], w6); gap6 = 24
k6 = COL / w6
ys = [Y0 + 16 + i * (h6 + gap6) for i in range(4)]
stack = "".join(part("dunkel-verlauf.png", b, x6, y, w6, SH_ORANGE, EDGE_DARK, z=3) for b, y in zip(D_VERLAUF[1:], ys[1:]))
stack += part("dunkel-verlauf.png", D_VERLAUF[0], M, ys[0] - h6 * (k6 - 1) / 2, COL,
              "0 34px 70px rgba(90,25,5,.50), 0 6px 16px rgba(90,25,5,.22)", EDGE_DARK, z=5)
page("06-verlauf", f"body{{{ORANGE}}} {ON_ORANGE} .sub{{top:{ys[3] + h6 + 60:.1f}px}}",
     f'{MARK}<h1>Gelöscht?<br>Zurückholen.</h1>{stack}<div class=sub style="white-space:normal">Erledigtes und Gelöschtes bleibt<br>30 Tage im Verlauf.</div>')

# 07 · Abschluss: App-Icon, Versprechen, zwei echte Karten (Papier) – vertikal mittig
h7 = part_h(L_ZIMMER, COL); h7b = part_h(L_GESCHENK, COL)
block = 200 + 56 + 168 + 22 + 33 + 64 + h7 + 20 + h7b
t = (1434 - block) / 2
page("07-ohne-werbung", f"body{{{PAPIER}}} {ON_LIGHT} h1{{left:0;right:0;text-align:center;top:{t+256:.1f}px}} "
     f".sub{{left:0;right:0;text-align:center;top:{t+446:.1f}px}}",
     f'<img style="position:absolute;left:230px;top:{t:.1f}px;width:200px;border-radius:44.7px;'
     f'box-shadow:0 24px 56px rgba(150,60,10,.32), 0 4px 12px rgba(150,60,10,.14)" src="{ICON}">'
     '<h1>Ohne Werbung.<br>Ohne Tracking.</h1><div class=sub>Kostenlos. Daten in der EU.</div>'
     + part("hell-aufgaben.png", L_ZIMMER, M, t + 543, COL, SH_LIGHT, EDGE_LIGHT)
     + part("hell-aufgaben.png", L_GESCHENK, M, t + 543 + h7 + 20, COL, SH_LIGHT, EDGE_LIGHT))
print("fertig")
