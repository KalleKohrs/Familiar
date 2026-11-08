#!/usr/bin/env python3
"""Serie E: Texte aus A, Orange-Weiß-Design aus D, wechselnde Hintergründe (Rhythmus).
Aufruf (Repo-Wurzel):  python3 docs/app-store/v2/entwuerfe/quelle/serie.py <render-html-Programm>"""
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
h1 {{ position:absolute; left:48px; right:40px; top:96px; font-weight:700; letter-spacing:-0.025em; font-size:80px; line-height:1.0; z-index:3; }}
.shot {{ position:absolute; left:60px; width:540px; top:450px; display:block; border-radius:62px 62px 0 0; z-index:2; }}
.mark {{ position:absolute; left:48px; top:38px; font-weight:650; font-size:22px; z-index:3; }}
.mark i {{ display:inline-block; width:14px; height:14px; border-radius:4px; margin-right:10px; vertical-align:-1px; }}
"""
def page(name, css, body):
    (Q / f"{name}.html").write_text(f"<!doctype html><meta charset=utf-8><style>{BASE}{css}</style><body>{body}</body>")
    subprocess.run([RENDER, str(Q / f"{name}.html"), str(OUT / f"{name}.png"), "660", "1434"], check=True)

ORANGE = "background:radial-gradient(520px 420px at 15% 0%, rgba(255,255,255,.22), transparent 70%), linear-gradient(175deg,#F9954A 0%,#F27A2B 45%,#E8631A 100%); color:#fff;"
SHEET = "body::after{content:'';position:absolute;left:0;right:0;top:880px;bottom:0;background:#FFFAF4;border-radius:56px 56px 0 0;z-index:1;}"
DARKBG = "background:radial-gradient(620px 520px at 88% 6%, rgba(255,122,61,.30), transparent 70%), radial-gradient(720px 720px at 0% 100%, rgba(122,59,92,.55), transparent 70%), #1E1519; color:#F6EEE6;"
CREAM = "background:radial-gradient(600px 500px at 90% 0%, rgba(255,150,85,.55), transparent 70%), radial-gradient(660px 620px at 0% 100%, rgba(232,150,178,.55), transparent 70%), #F5ECE1; color:#2B1F25;"

WARMSHOT = ".shot{top:380px;box-shadow:0 0 0 1.5px rgba(43,31,37,.10),0 40px 90px rgba(120,60,30,.34)}"
CREAMCSS = f"body{{{CREAM}}} h1{{font-weight:620}} h1 em{{font-style:normal;color:#D45A12}} .mark{{color:#675850}} .mark i{{background:#F27A2B}} {WARMSHOT}"
ORANGECSS = f"body{{{ORANGE}}} h1 em{{font-style:normal;color:#2B141A}} .mark{{color:#fff}} .mark i{{background:#fff}} .shot{{top:380px;box-shadow:0 30px 80px rgba(120,50,10,.40)}}"
# 1 Orange + weiße Fläche, helles Gerät, zweifarbig
page("E1-serie", f"body{{{ORANGE}}} {SHEET} h1 em{{font-style:normal;color:#2B141A}} .mark{{color:#fff}} .mark i{{background:#fff}} .shot{{top:450px;box-shadow:0 30px 80px rgba(120,50,10,.38)}}",
 f'<div class=mark><i></i>Familiar</div><h1>Alles, was<br>ansteht.<br><em>Eine Liste.</em></h1><img class=shot src="{LIGHT}hell-aufgaben.png">')
# 2 Papier, DUNKLES Gerät, zweifarbig
page("E2-serie", CREAMCSS,
 f'<div class=mark><i></i>Familiar</div><h1>Jeder hakt<br><em>seinen Teil</em> ab.</h1><img class=shot src="{DARK}2-detail.png">')
# 3 Voll-Orange, helles Gerät, zweifarbig
page("E3-serie", ORANGECSS,
 f'<div class=mark><i></i>Familiar</div><h1>Der Monat<br><em>im Blick.</em></h1><img class=shot src="{LIGHT}hell-kalender.png">')
# 4 Papier, dunkles Gerät, einfarbig
page("E4-serie", CREAMCSS,
 f'<div class=mark><i></i>Familiar</div><h1>Gelöscht?<br>Zurückholen.</h1><img class=shot src="{DARK}6-verlauf.png">')
# 5 Orange + weiße Fläche, dunkles Gerät, einfarbig
page("E5-serie", f"body{{{ORANGE}}} {SHEET} .mark{{color:#fff}} .mark i{{background:#fff}} .shot{{top:380px;box-shadow:0 30px 80px rgba(120,50,10,.42)}}",
 f'<div class=mark><i></i>Familiar</div><h1>Jede Familie<br>ihre Regeln.</h1><img class=shot src="{DARK}5-familien.png">')
# 6 Papier, dunkles Gerät, einfarbig
page("E6-serie", CREAMCSS,
 f'<div class=mark><i></i>Familiar</div><h1>Wer macht’s?<br>Kurz zugewiesen.</h1><img class=shot src="{DARK}3-zuweisen.png">')
print("fertig")
