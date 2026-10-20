# ADR 0002: iOS 27 als Mindestversion, native TabView mit hervorgehobenem Plus-Tab

- **Status:** iOS 27 als Mindestversion gilt weiter; der Teil zur Navigation ist **ersetzt durch [ADR 0006](0006-custom-glass-tab-bar.md)** (2026-10-20)
- **Kontext:** Der Guide verlangt eine schwebende Pillen-Tab-Bar mit drei Bereichen und einem separaten, runden Plus-Button rechts daneben, gestalterisch Teil desselben Systems. Native Materialien sind zu bevorzugen.
- **Entscheidung:** Deployment Target iOS 27.0 (Entscheidung des Nutzers). Hauptnavigation als SwiftUI-`TabView` mit drei Tabs und einem Tab mit `TabRole.prominent` (neu in iOS 27; laut Apple-Doku hervorgehoben und abgesetzt dargestellt). Die Auswahl des Plus-Tabs wird über eine eigene Selection-Binding abgefangen (`TabSelectionRouter`): Statt den Tab zu wechseln, öffnet sich das Sheet „Neue Aufgabe“, der aktive Bereich bleibt.
- **Prüfung:** Spike S1 – UI-Test `PlusTabUITests` und Sichtprüfung im Simulator.
- **Fallback:** Verhält sich der Plus-Tab nicht wie erwartet, eigene Leiste aus `GlassEffectContainer` + `glassEffect(.regular.interactive())`.

## Ergebnis Spike S1 (2026-10-20)

Im Simulator (iPhone 17, iOS 27.0) geprüft: Der Tab mit `.prominent` erscheint als separater runder Glas-Button rechts neben der Pillen-Tab-Bar. Antippen öffnet das Sheet „Neue Aufgabe“; nach „Abbrechen“ bleibt der zuvor aktive Bereich ausgewählt. Der Ansatz wird beibehalten.

Offen (Design): Der Plus-Tab ist neutral (weißes Symbol auf Glas); in der Design-Referenz ist der Plus-Button orange. Ob und wie ein `.prominent`-Tab eingefärbt werden kann, wird in der Apple-Doku geprüft, bevor eine Lösung umgesetzt wird. Der automatisierte UI-Test `PlusTabUITests` läuft, sobald wieder genug Speicherplatz frei ist.
