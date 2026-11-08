#!/usr/bin/env python3
"""Erzeugt die HTML-Entwürfe (4 Richtungen × 2 Bilder) und rendert sie als PNG (1320 × 2868).
Aufruf (Repo-Wurzel):  python3 docs/app-store/v2/entwuerfe/quelle/bauen.py <render-html-Programm>
Das Programm entsteht aus docs/app-store/v2/tools/render-html.swift (swiftc -O ... -o /tmp/render-html).
Layout: Seite 660 × 1434 CSS-Pixel, wird mit Faktor 2 gerendert."""
import subprocess, sys, pathlib
Q = pathlib.Path(__file__).resolve().parent
OUT = Q.parent
RENDER = sys.argv[1]
FONT = "../../../../../ios/Packages/FamiliarKit/Sources/FamiliarDesign/Resources/Fonts/BricolageGrotesque.ttf"
DARK = "../../../screenshots/"
LIGHT = "../../../v2/rohmaterial/"

BASE = f"""
@font-face {{ font-family:'Bricolage'; src:url('{FONT}'); font-weight:200 800; }}
* {{ box-sizing:border-box; margin:0; padding:0; }}
html, body {{ width:660px; height:1434px; overflow:hidden; }}
body {{ position:relative; font-family:'Bricolage',sans-serif; -webkit-font-smoothing:antialiased; }}
h1 {{ position:absolute; left:48px; right:48px; top:96px; font-weight:700; letter-spacing:-0.025em; font-size:80px; line-height:1.0; }}
.sub {{ position:absolute; left:50px; font-weight:450; font-size:25px; line-height:1.25; }}
.shot {{ position:absolute; left:60px; width:540px; display:block; border-radius:62px 62px 0 0; }}
.mark {{ position:absolute; left:48px; top:38px; font-weight:650; font-size:22px; }}
.mark i {{ display:inline-block; width:14px; height:14px; border-radius:4px; margin-right:10px; vertical-align:-1px; }}
"""

def page(name, css, body):
    (Q / f"{name}.html").write_text(f"<!doctype html><meta charset=utf-8><style>{BASE}{css}</style><body>{body}</body>")
    subprocess.run([RENDER, str(Q / f"{name}.html"), str(OUT / f"{name}.png"), "660", "1434"], check=True)

# ---------- A · Nacht ----------
A = """
body { background: radial-gradient(620px 520px at 88% 6%, rgba(255,122,61,.30), transparent 70%),
  radial-gradient(720px 720px at 0% 100%, rgba(122,59,92,.55), transparent 70%), #1E1519; color:#F6EEE6; }
h1 em { font-style:normal; color:#FF8C42; }
.sub { top:322px; color:#BFB2A5; }
.shot { top:420px; box-shadow:0 0 0 1.5px rgba(255,243,230,.16), 0 -10px 120px rgba(255,122,61,.20), 0 40px 100px rgba(0,0,0,.6); }
.mark { color:#BFB2A5; } .mark i { background:#FF8C42; }
"""
page("A1-nacht", A + ".sub{top:350px} .shot{top:450px}", f"""<div class=mark><i></i>Familiar</div>
<h1>Alles, was<br>ansteht.<br><em>Eine Liste.</em></h1>
<div class=sub>Die Aufgaben deiner Familie an einem Ort.</div>
<img class=shot src="{DARK}1-aufgaben.png">""")
page("A2-nacht", A, f"""<div class=mark><i></i>Familiar</div>
<h1>Jeder hakt<br><em>seinen Teil</em> ab.</h1>
<div class=sub>Eine Aufgabe, mehrere Personen.</div>
<img class=shot src="{DARK}2-detail.png">""")

# ---------- B · Papier ----------
B = """
body { background: radial-gradient(600px 500px at 90% 0%, rgba(255,150,85,.55), transparent 70%),
  radial-gradient(660px 620px at 0% 100%, rgba(232,150,178,.55), transparent 70%), #F5ECE1; color:#2B1F25; }
h1 { font-weight:620; }
h1 u { text-decoration:none; background:linear-gradient(transparent 64%, rgba(242,122,43,.40) 64%, rgba(242,122,43,.40) 92%, transparent 92%); }
.sub { top:322px; color:#675850; }
.shot { top:420px; box-shadow:0 0 0 1.5px rgba(43,31,37,.08), 0 40px 90px rgba(120,60,30,.30); }
.mark { color:#675850; } .mark i { background:#F27A2B; }
"""
page("B1-papier", B, f"""<div class=mark><i></i>Familiar</div>
<h1>Wer macht was<br><u>und bis wann?</u></h1>
<div class=sub>Person, Termin und Familie auf einen Blick.</div>
<img class=shot src="{LIGHT}hell-aufgaben.png">""")
page("B2-papier", B, f"""<div class=mark><i></i>Familiar</div>
<h1>Der Monat<br><u>im Blick.</u></h1>
<div class=sub>Aufgaben und Wiederholungen im Kalender.</div>
<img class=shot src="{LIGHT}hell-kalender.png">""")

# ---------- C · Mutig ----------
C = """
body { background:linear-gradient(170deg,#FF9A55 0%,#F27A2B 55%,#E8631A 100%); color:#2B141A; }
h1 { font-size:108px; line-height:.92; font-weight:800; letter-spacing:-0.04em; top:84px; }
h1 span { color:#FFF4E8; }
.shot { top:440px; box-shadow:0 40px 100px rgba(60,20,5,.45); }
.mark { color:#2B141A; } .mark i { background:#2B141A; }
.sticker { position:absolute; left:100px; width:500px; border-radius:30px; box-shadow:0 30px 70px rgba(60,20,5,.45); background-repeat:no-repeat; background-size:500px auto; }
"""
page("C1-mutig", C, f"""<div class=mark><i></i>Familiar</div>
<h1>Wer macht<br>was?</h1>
<img class=shot src="{DARK}1-aufgaben.png">""")
page("C2-mutig", C, f"""<div class=mark><i></i>Familiar</div>
<h1 style="font-size:92px">Gelöscht?<br><span>Zurückholen.</span></h1>
<img class=shot style="top:440px" src="{DARK}6-verlauf.png">""")

# ---------- D · Orange & Weiß ----------
D = """
body { background:radial-gradient(520px 420px at 15% 0%, rgba(255,255,255,.22), transparent 70%), linear-gradient(175deg,#F9954A 0%,#F27A2B 45%,#E8631A 100%); color:#FFFFFF; }
h1 { text-shadow:0 2px 24px rgba(160,60,5,.25); }
.sub { top:322px; color:rgba(255,255,255,.92); z-index:3; font-weight:500; }
.shot { top:440px; z-index:2; box-shadow:0 0 0 1.5px rgba(43,31,37,.08), 0 30px 80px rgba(120,50,10,.38); }
.mark { color:#fff; z-index:3; } .mark i { background:#fff; }
"""
page("D1-orange-weiss", D, f"""<div class=mark><i></i>Familiar</div>
<h1>Wer macht was<br>und bis wann?</h1>
<div class=sub>Person, Termin und Familie auf einen Blick.</div>
<img class=shot src="{LIGHT}hell-aufgaben.png">""")
page("D2-orange-weiss", D, f"""<div class=mark><i></i>Familiar</div>
<h1>Der Monat<br>im Blick.</h1>
<div class=sub>Aufgaben und Wiederholungen im Kalender.</div>
<img class=shot src="{LIGHT}hell-kalender.png">""")
print("fertig")
