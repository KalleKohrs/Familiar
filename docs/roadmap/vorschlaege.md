# Vorschläge für neue Funktionen (Stand 2026-11-11)

Ziel: mehr Nutzung, mehr Einladungen, mehr Bindung – ohne neue Kosten, ohne Tracking, ohne In-App-Käufe. Mindest-iOS 27, nur iPhone und Alter 16+ bleiben, wie entschieden. Geordnet nach **Wirkung im Verhältnis zum Aufwand**.

Grundlage: Was die App heute kann (Aufgaben, Reihum, Erinnern, Kalender, Verlauf, mehrere Familien, Widgets, Siri, Live Activities) und wo sie Nutzer verliert. Zwei Lücken fallen auf:

1. **Der erste Start ist leer.** Nach „Familie erstellen“ landet man in einer leeren Aufgabenliste. Einladen versteckt sich tief (Profil › Familien › Familie › Einladung). Eine Familien-App ohne zweites Mitglied ist wertlos – der Einladungsweg ist der wichtigste Wachstumshebel.
2. **Es gibt keinen Grund, die App ohne eigene Aufgabe zu öffnen.** Es fehlt ein wiederkehrender Moment (Tagesstart, Wochenplan) und eine kleine positive Rückmeldung unter den Familienmitgliedern.

Aufwand: **S** = wenige Tage, **M** = etwa eine Woche, **L** = mehrere Wochen. Alle Funktionen setzen die Regeln aus `AGENTS.md` voraus: zuerst RPC + SQL-Test, dann Repository, `InMemoryBackend`, dann Oberfläche; Barrierefreiheit, Texte auf Deutsch. Neue Migrationen beginnen bei `0021`; sie werden nicht ohne Abstimmung eingespielt.

---

## Übersicht

| # | Funktion | Wirkung | Aufwand | Backend | Datenschutz-Folgen |
|---|---|---|---|---|---|
| 1 | Einladen gleich beim Start | sehr hoch (Wachstum) | S | keins | keine |
| 2 | Vorlagen („Putzplan“, „Morgenroutine“ …) | hoch (erster Erfolg) | S–M | keins | keine |
| 3 | Tagesstart und Wochenübersicht | hoch (Bindung) | M | Migration + Funktion (oder rein lokal) | gering |
| 4 | „Danke“-Reaktion beim Erledigen | mittel–hoch (Bindung) | M | Migration + RPC | ja (neue Daten) |
| 5 | Checklisten in Aufgaben (z. B. Einkauf) | mittel–hoch | M–L | Migration + RPCs | ja (neue Daten) |
| 6 | Steuerelemente für Kontrollzentrum und Sperrbildschirm | mittel | S | keins | keine |
| 7 | Familien-Punkte / Sterne | unklar, Risiko | L | Migration + RPCs | ja, plus Altersfrage |
| 8 | Apple Watch | mittel | L | keins (aber eigene Anmeldung/Abgleich) | gering |

**Empfehlung: 1 + 2 zusammen** als „Guter Start“ (S–M, ohne Server-Arbeit, sofort wirksam), danach **3** als Bindungs-Funktion. 4 und 5 folgen, wenn der Inhaber mehr Tiefe im Alltag will.

---

## 1. Einladen gleich beim Start (S) – Empfehlung

**Nutzen:** Wer eine Familie anlegt, wird sofort gefragt: „Wen holst du dazu?“ – mit Teilen-Knopf (Nachricht, AirDrop, WhatsApp über das iOS-Teilen-Blatt). Dazu eine Einladungs-Karte im Leerzustand der Aufgabenliste, solange man allein in der Familie ist, und ein Knopf „Einladen“ im Familien-Kopf. Ablauf: Familie anlegen → erste Aufgabe (siehe 2) → zuweisen → einladen.
**Technik:** Einladungen gibt es schon (`create_invite`, Link `familiar-app.de/join/<Code>`, Ausweichseite für Leute ohne App). Neu ist nur die Oberfläche; `OnboardingFlow` bekommt einen Schritt „einladen“ (überspringbar). Der Einladungstext sollte den App-Store-Link enthalten (die Ausweichseite führt schon dorthin).
**Backend:** keins. **Datenschutz:** keine neuen Daten.
**Risiken:** Der Einladungscode ist 7 Tage gültig – im Onboarding nur erzeugen, wenn der Schritt wirklich genutzt wird (kein Code „auf Vorrat“). UI-Tests für das Onboarding (`OnboardingUITests`) müssen angepasst werden.

## 2. Vorlagen (S–M) – Empfehlung

**Nutzen:** Eine leere Liste schreckt ab. Vorlagen („Putzplan Woche“ mit reihum, „Morgenroutine“, „Müll“, „Wocheneinkauf“, „WG-Küchendienst“) legen mit zwei Tipps mehrere Aufgaben bzw. Serien an – der Nutzer wählt nur noch Personen und Uhrzeit. Auch aus dem Plus-Knopf („Aus Vorlage“) erreichbar.
**Technik:** Vorlagen fest in der App (`FamiliarCore`, mit Unit-Tests, deutsche Texte, später erweiterbar), erzeugt über die vorhandenen `createTask`/`createSeries` – also **keine Server-Änderung**. Eigene, selbst gespeicherte Vorlagen wären ein späterer Schritt (dann Tabelle).
**Backend:** keins. **Datenschutz:** keine neuen Daten.
**Risiken:** Mehrere Aufgaben auf einmal erzeugen viele Mitteilungen – die Aufgaben müssen als Sammelvorgang laufen oder die Personen erst nach der Vorlage zugewiesen werden (Entscheidung vor Umsetzung). Texte sollen für alle Familienformen passen (Familie, WG, Oma & Opa).

## 3. Tagesstart und Wochenübersicht (M)

**Nutzen:** Ein fester Anlass, die App zu öffnen. (a) **Wochenübersicht** in der App: „Diese Woche“ – wer macht was, nach Tagen und Personen, Reihum-Termine sichtbar; erreichbar aus dem Kalender. (b) Optionale **Tagesstart-Mitteilung** („Heute: 3 Aufgaben für dich“) zur selbst gewählten Uhrzeit, und optional ein Sonntagabend-Rückblick/-Ausblick.
**Technik:** Die Übersicht braucht keine Server-Änderung (alle Daten sind in der App). Die Mitteilung gibt es in zwei Wegen: **lokal** (Mitteilung wird auf dem Gerät geplant; Inhalt kann veraltet sein, wenn jemand anderes Aufgaben ändert – daher neutraler Text oder Neuberechnung bei jedem Laden) oder **vom Server** über die bestehende Warteschlange (`enqueue_notification`, Cron; mit Eintrag „Uhrzeit/Ein-Aus“ pro Person, z. B. Spalte am Profil). Server-Weg ist genauer, aber Migration + Deploy von `push-dispatch`.
**Backend:** nur beim Server-Weg: Migration (Einstellung je Person, Cron), Anpassung `push-dispatch`. **Datenschutz:** Server-Weg speichert eine Einstellung (Uhrzeit, an/aus) → Datenschutzerklärung und Verarbeitungsverzeichnis kurz ergänzen; lokaler Weg: keine Änderung.
**Risiken:** Zu viele Mitteilungen nerven (Standard: aus, Opt-in, Ruhezeit 21–7 Uhr wie beim Erinnern beachten). Der Server-Weg setzt voraus, dass Push-Mitteilungen im Betrieb zuverlässig ankommen (bitte vor Start bestätigen).

## 4. „Danke“-Reaktion beim Erledigen (M)

**Nutzen:** Kleine Anerkennung statt Nörgeln: Wer fertig ist, bekommt von der Familie ein „Danke 🧡“ (feste Auswahl, z. B. Herz, Daumen, Applaus – kein Freitext). Die Person sieht es in der Aufgabe/im Verlauf und bekommt eine Mitteilung („Lena sagt Danke für Müll rausbringen“). Fördert das Gefühl „es merkt jemand“ – ein starker Bindungsgrund bei Kindern und Jugendlichen ab 16.
**Technik:** Tabelle `task_reactions` (Aufgabe, Person, Art), RPC `react_to_task` (nur Mitglieder mit Sicht; nicht auf eigene Aufgabe; eine Reaktion je Person und Aufgabe), Mitteilung über die Warteschlange, Aufräumen im Austritts-Trigger, Aufnahme in Sicherung und Wiederherstellung, Realtime wie bei Aufgaben.
**Ausbau später (nicht empfohlen für jetzt):** echte **Kommentare** (Freitext). Das öffnet Fragen zu Moderation/Meldung (DSA-Formular gibt es), Benachrichtigungsflut und Verlauf; die ursprünglichen Vorgaben (`guide.txt`, Abschnitt 2) wollten „zunächst keine Kommentare“. Reaktionen sind der kleinere, sichere Schritt.
**Backend:** Migration + RPC + SQL-Test + Anpassung `push-dispatch` und Sicherung. **Datenschutz:** neue Daten (wer hat wem Danke gesagt) → Datenschutzerklärung (Abschnitt 3), Verarbeitungsverzeichnis, Löschfristen; `PrivacyInfo.xcprivacy`: voraussichtlich unverändert (bereits „Andere Nutzerinhalte“/Name?) – prüfen; App-Store-Fragebogen für Nutzerinhalte bleibt gleich.
**Risiken:** Reaktionen bei Serien (je Vorkommen), bei „Jede Person einzeln“ (auf wen?), Sichtbarkeit bei „nur Zugewiesene“.

## 5. Checklisten in Aufgaben (M–L)

**Nutzen:** „Einkaufen: Milch, Brot, Äpfel“ oder „Koffer packen“ – eine Aufgabe mit abhakbaren Unterpunkten. Deckt die **Einkaufsliste** als häufigsten Anwendungsfall ab, ohne einen zweiten Bereich in der App aufzubauen (eine eigene Einkaufsliste wäre L und würde die klare Aufgaben-Idee verwässern).
**Technik:** Tabelle `task_checklist_items` (Text, Reihenfolge, erledigt von wem/wann); RPCs zum Anlegen/Ändern/Abhaken; Verträge mit Serien (jedes Vorkommen bekommt eine **frische** Kopie der Liste), Verlauf/Wiederherstellen, Bearbeiten mit Versionsprüfung, Austritt, Sicherung, Realtime. Der Aufwand liegt fast ganz in diesen Berührungspunkten, nicht in der Oberfläche.
**Backend:** Migration + RPCs + SQL-Tests (inkl. Serien und Rückgängig). **Datenschutz:** neuer Text im Aufgabenumfeld (Inhalt wie Beschreibung) → Datenschutzerklärung und Verarbeitungsverzeichnis ergänzen.
**Risiken:** größtes Regelwerk aller Vorschläge (Serien, Reihum, Verlauf). Sollte nach 1–3 kommen.

## 6. Steuerelemente für Kontrollzentrum und Sperrbildschirm (S)

**Nutzen:** Zwei Steuerelemente (iOS-„Controls“): **„Neue Aufgabe“** (öffnet direkt den Editor) und **„Heute offen: n“** (zeigt Anzahl, öffnet die Liste) – im Kontrollzentrum und als Sperrbildschirm-Taste. Macht Familiar im Alltag „einen Handgriff entfernt“.
**Technik:** `ControlWidget` in der bestehenden Widget-Extension; liest den vorhandenen App-Group-Schnappschuss (`WidgetSync`), „Neue Aufgabe“ per App Intent mit `openAppWhenRun`. Kein Zugriff aufs Konto in der Extension, wie beim Heute-Widget (ADR 0010). **Nebenbei:** alternative App-Icons (Farbvarianten) wären auf gleichem Niveau (S), aber mit geringer Wirkung – nur wenn das Design ohnehin Varianten liefert.
**Backend:** keins. **Datenschutz:** keine neuen Daten; Titel bleiben `privacySensitive`.
**Risiken:** Intents liegen **nicht** in einem Swift-Paket (Stolperstein in `AGENTS.md`); Prüfung per Archive nötig.

## 7. Familien-Punkte / Sterne (L) – nur nach Entscheidung zur Altersfrage

**Nutzen:** Punkte für erledigte Aufgaben, Wochen-Ranking, kleine „Belohnung“ (nur als Zahl/Abzeichen, nichts Echtes, keine Käufe). Hohe Motivation, besonders bei Kindern.
**Warum nicht oben:** (a) **Alter:** Familiar richtet sich laut Nutzungsbedingungen und Datenschutzerklärung (Abschnitt 10) an Personen **ab 16**; jüngere nur mit Zustimmung der Eltern. Eine Funktion, die ausdrücklich auf „Kinder“ zielt, passt dazu schlecht und würde Altersfreigabe, App-Store-Beschreibung und möglicherweise den Rechtscheck berühren. (b) **Regeln:** Was gibt es bei Rückgängig, Reihum, „Jede Person einzeln“, Selbst-Abhaken durch Kinder (Mogeln)? Streit in der Familie ist ein reales Risiko. (c) **Aufwand:** Punktebuch-Tabelle, RPCs, Rückbuchungen, Austritt, Sicherung.
**Mögliche, kleinere Alternative:** die Reaktion aus Punkt 4 plus ein reiner **Wochenrückblick** („Diese Woche hat die Familie 23 Aufgaben erledigt“) in der Wochenübersicht (3) – ohne Rangliste und Punkte.
**Backend:** Migration + RPCs + Tests. **Datenschutz:** neue Daten, dazu Prüfung der Altersangaben.

## 8. Apple Watch (L)

**Nutzen:** „Heute“-Liste am Handgelenk, Abhaken per Tipp, Komplikation. Wirkt hochwertig, ist aber für die Grundnutzung nicht nötig.
**Technik:** neues Ziel (watchOS-App), Anmeldung/Datenabgleich vom iPhone (WatchConnectivity oder Schnappschuss wie beim Widget), eigene Store-Bilder und Tests, Abhaken über denselben Weg wie `CompleteTaskIntent`. Die Prüfung durch Apple und das Signieren (neue Bundle-ID und App Group) kommen dazu.
**Backend:** keins, wenn der Schnappschuss-Weg genügt. **Datenschutz:** gering (Daten liegen schon auf dem iPhone).
**Risiken:** viel neue Test- und Pflegefläche für eine kleine Zielgruppe; Mindest-Version und Simulator-Test aufwendig. Erst sinnvoll, wenn die Nutzung steigt.

---

## Bewusst nicht vorgeschlagen

- **Eigene Einkaufsliste als zweiter Bereich:** Checkliste (5) deckt den Fall ab.
- **Freitext-Kommentare:** später, wenn Reaktionen gut ankommen (siehe 4).
- **Alles mit Analyse, Werbung, Käufen oder Tracking:** widerspricht den Projektregeln (auch Wachstumsmessung – Einladungs-Erfolg lässt sich lokal an `use_count` des Codes ablesen, ohne neues Werkzeug).

## Entscheidung des Inhabers

Empfehlung: **1 + 2** (Guter Start), danach **3**. Welche Funktionen sollen gebaut werden? Offen für Phase 2 außerdem: bei 3 lokale oder Server-Mitteilung; bei 2 Aufgaben sofort oder erst nach Zuweisung anlegen.
