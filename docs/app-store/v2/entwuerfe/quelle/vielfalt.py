#!/usr/bin/env python3
"""Serie F: jedes Bild mit eigenem Layout (Handy rechts angeschnitten, Zoom ohne Handy, Poster, Kartenstapel,
Handy oben angeschnitten, Ausschnitte auf Orange, Abschluss). Alle Inhalte sind unveränderte Teile echter Aufnahmen.
Aufruf (Repo-Wurzel):  python3 docs/app-store/v2/entwuerfe/quelle/vielfalt.py <render-html-Programm>"""
import subprocess, sys, pathlib
Q = pathlib.Path(__file__).resolve().parent
OUT = Q.parent
RENDER = sys.argv[1]
FONT = "../../../../../ios/Packages/FamiliarKit/Sources/FamiliarDesign/Resources/Fonts/BricolageGrotesque.ttf"
ICON = "../../../../../ios/Familiar/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
DARK = "../../../screenshots/"
LIGHT = "../../../v2/rohmaterial/"
W = 1320  # Breite der Originalaufnahmen in Pixeln

BASE = f"""
@font-face {{ font-family:'Bricolage'; src:url('{FONT}'); font-weight:200 800; }}
* {{ box-sizing:border-box; margin:0; padding:0; }}
html, body {{ width:660px; height:1434px; overflow:hidden; }}
body {{ position:relative; font-family:'Bricolage',sans-serif; -webkit-font-smoothing:antialiased; }}
h1 {{ position:absolute; font-weight:700; letter-spacing:-0.025em; font-size:84px; line-height:1.0; z-index:5; }}
.sub {{ position:absolute; font-weight:450; font-size:25px; line-height:1.25; z-index:5; }}
.mark {{ position:absolute; left:48px; top:38px; font-weight:650; font-size:22px; z-index:6; }}
.mark i {{ display:inline-block; width:14px; height:14px; border-radius:4px; margin-right:10px; vertical-align:-1px; }}
.shot {{ position:absolute; display:block; z-index:2; }}
em {{ font-style:normal; }}
"""

def crop(src, sx, sy, sw, sh, x, y, w, r=34, shadow="0 30px 70px rgba(60,25,10,.35)", rr=None, z=3):
    sc = w / sw
    rad = rr if rr else f"{r}px"
    return (f'<div style="position:absolute;z-index:{z};left:{x}px;top:{y}px;width:{w}px;height:{sh*sc:.1f}px;overflow:hidden;'
            f'border-radius:{rad};box-shadow:{shadow}"><img src="{src}" style="position:absolute;left:{-sx*sc:.1f}px;top:{-sy*sc:.1f}px;width:{W*sc:.1f}px"></div>')

def page(name, css, body):
    (Q / f"{name}.html").write_text(f"<!doctype html><meta charset=utf-8><style>{BASE}{css}</style><body>{body}</body>")
    subprocess.run([RENDER, str(Q / f"{name}.html"), str(OUT / f"{name}.png"), "660", "1434"], check=True)

CREAM  = "background:radial-gradient(600px 500px at 90% 0%, rgba(255,150,85,.50), transparent 70%), radial-gradient(660px 620px at 0% 100%, rgba(232,150,178,.45), transparent 70%), #F5ECE1; color:#2B1F25;"
ORANGE = "background:radial-gradient(520px 420px at 15% 0%, rgba(255,255,255,.25), transparent 70%), linear-gradient(175deg,#F9954A 0%,#F27A2B 45%,#E8631A 100%); color:#fff;"
SONNE  = "background:radial-gradient(520px 420px at 100% 0%, rgba(255,255,255,.7), transparent 70%), linear-gradient(180deg,#FBE7A0 0%,#F7D774 100%); color:#2B1F25;"
SALBEI = "background:radial-gradient(520px 420px at 0% 0%, rgba(255,255,255,.6), transparent 70%), linear-gradient(180deg,#DCEFE0 0%,#BFE0C7 100%); color:#1F2A24;"
ROSE   = "background:radial-gradient(520px 420px at 100% 0%, rgba(255,255,255,.6), transparent 70%), linear-gradient(180deg,#FBDDE9 0%,#F4B6CE 100%); color:#2B1F25;"
MARK_D = ".mark{color:#2B1F25} .mark i{background:#F27A2B}"
MARK_W = ".mark{color:#fff} .mark i{background:#fff}"

# F1 · Handy rechts angeschnitten + vergrößerte Karte (Orange)
page("F1-vielfalt", f"body{{{ORANGE}}} {MARK_W} h1{{left:48px;top:96px;text-shadow:0 2px 24px rgba(160,60,5,.25)}} h1 em{{color:#2B141A}} "
  ".shot{border-radius:62px;box-shadow:0 30px 80px rgba(120,50,10,.42)}",
  f'<div class=mark><i></i>Familiar</div><h1>Wer macht was<br><em>und bis wann?</em></h1>'
  f'<img class=shot style="width:560px;left:150px;top:470px" src="{LIGHT}hell-aufgaben.png">'
  + crop(LIGHT+"hell-aufgaben.png", 45, 1060, 1230, 465, 24, 1010, 560, r=36, shadow="0 30px 70px rgba(110,40,5,.45)", z=4))

# F2 · Zoom ohne Handy: der Bildschirm im Großformat (Papier)
page("F2-vielfalt", f"body{{{CREAM}}} {MARK_D} h1{{left:48px;top:96px;font-weight:640}} h1 em{{color:#D45A12}}",
  '<div class=mark><i></i>Familiar</div><h1>Jeder hakt<br><em>seinen Teil</em> ab.</h1>'
  + crop(DARK+"2-detail.png", 0, 395, 1320, 2100, 0, 420, 660, rr="62px 62px 0 0", shadow="0 -6px 60px rgba(120,60,30,.28), 0 0 0 1.5px rgba(43,31,37,.10)"))

# F3 · Poster: Kalender-Ausschnitt oben, Schlagzeile unten (Sonne)
page("F3-vielfalt", f"body{{{SONNE}}} {MARK_D} h1{{left:48px;top:1030px}} h1 em{{color:#A84A0A}} .sub{{left:50px;top:1230px;color:#5A4A1E}}",
  '<div class=mark><i></i>Familiar</div>'
  + crop(LIGHT+"hell-kalender.png", 40, 550, 1240, 1900, 30, 90, 600, r=40, shadow="0 30px 70px rgba(120,90,10,.35)")
  + '<h1>Der Monat<br><em>im Blick.</em></h1><div class=sub>Aufgaben und Wiederholungen im Kalender.</div>')

# F4 · Kartenstapel aus dem Verlauf, kein Handy (Salbei)
cards = [(672,367,40,450),(1073,367,100,640),(1608,367,50,830),(2009,367,100,1020)]
stack = "".join(crop(DARK+"6-verlauf.png", 49, sy, 1222, sh, x, y, 530, rr="32px", shadow="0 22px 50px rgba(20,60,30,.38)", z=3+i) for i,(sy,sh,x,y) in enumerate(cards))
page("F4-vielfalt", f"body{{{SALBEI}}} {MARK_D} .mark i{{background:#2E9B5C}} h1{{left:48px;top:96px}} h1 em{{color:#1B7340}} .sub{{left:50px;top:1250px;color:#33503C;width:560px}}",
  '<div class=mark><i></i>Familiar</div><h1>Gelöscht?<br><em>Zurückholen.</em></h1>' + stack
  + '<div class=sub>Erledigtes und Gelöschtes bleibt 30 Tage im Verlauf.</div>')

# F5 · Handy oben angeschnitten, Schlagzeile unten (Rose)
page("F5-vielfalt", f"body{{{ROSE}}} {MARK_D} .mark{{top:auto;bottom:40px}} .mark i{{background:#E0508A}} h1{{left:48px;top:1010px}} h1 em{{color:#B02F68}} "
  ".shot{border-radius:0 0 62px 62px;box-shadow:0 30px 70px rgba(150,40,90,.35)}",
  '<div class=mark><i></i>Familiar</div>'
  f'<img class=shot style="width:540px;left:60px;top:-228px" src="{DARK}5-familien.png">'
  '<h1>Jede Familie<br><em>ihre Regeln.</em></h1>')

# F6 · Ausschnitte auf Orange, Schlagzeile in der Mitte
page("F6-vielfalt", f"body{{{ORANGE}}} {MARK_W} h1{{left:48px;top:390px;text-shadow:0 2px 24px rgba(160,60,5,.25)}} h1 em{{color:#2B141A}}",
  '<div class=mark><i></i>Familiar</div>'
  + crop(DARK+"3-zuweisen.png", 60, 510, 1200, 380, 50, 100, 560, rr="32px", shadow="0 26px 60px rgba(90,30,5,.45)")
  + '<h1>Wer macht’s?<br><em>Kurz<br>zugewiesen.</em></h1>'
  + crop(DARK+"3-zuweisen.png", 60, 2040, 1200, 765, 70, 840, 560, rr="32px", shadow="0 26px 60px rgba(90,30,5,.45)"))

# F7 · Abschluss: Zeichen, Versprechen, Ausschnitt der Liste (Papier)
page("F7-vielfalt", f"body{{{CREAM}}} h1{{left:0;right:0;text-align:center;top:480px;font-weight:640}} h1 em{{color:#D45A12}} .sub{{left:0;right:0;text-align:center;top:690px;color:#675850}}",
  f'<img style="position:absolute;left:215px;top:150px;width:230px;border-radius:52px;box-shadow:0 24px 60px rgba(150,60,10,.35)" src="{ICON}">'
  '<h1>Ohne Werbung.<br><em>Ohne Tracking.</em></h1><div class=sub>Kostenlos. Daten in der EU.</div>'
  + crop(LIGHT+"hell-aufgaben.png", 40, 1040, 1240, 1050, 50, 850, 560, rr="38px 38px 0 0", shadow="0 -6px 60px rgba(120,60,30,.28), 0 0 0 1.5px rgba(43,31,37,.08)"))
print("fertig")
