# Bewegung und Übergänge

Regeln für alle Animationen in Familiar. Die Werte stehen zentral in `FamiliarMotion`
(`ios/Packages/FamiliarKit/Sources/FamiliarDesign/Tokens/FamiliarMotion.swift`) – in Views keine Einzelwerte.

## Grundsätze

1. **Eine Ursache, eine Animation.** Wechselt ein Bereich zwischen Platzhalter, Leerzustand, Fehler und Liste,
   steuert **ein** Zustandswert (z. B. `phase`) den Wechsel über `familiarContentSwap(value:)`. Mehrere
   `.animation`-Modifier auf verschiedenen Werten erzeugen Doppelbewegungen.
2. **Inhalte werden überblendet, nicht geschoben.** `FamiliarMotion.contentTransition` = reine Deckkraft,
   0,25 s, ohne Verzögerung.
3. **Federn über Dauer und Bounce**, nie `easeInOut` für etwas, das der Finger anstößt oder unterbricht.
   Layout: `standard` (0,4 s, ohne Überschwingen). Kleine Rückmeldung: `snappy` (0,3 s).
4. **Nichts über 0,5 s** als Reaktion auf eine Eingabe.
5. **Nie anzeigen, was falsch ist.** Der Zustand „geladen“ erst setzen, wenn alles da ist, was die Anzeige
   entscheidet (z. B. Verlauf vor „Alles erledigt“/„Noch keine Aufgaben“).
6. **Bewegung reduzieren:** nur kurze Überblendung, keine Positions- oder Größenänderung
   (`FamiliarMotion.animation(_, reduceMotion:)`).

## Tab-Leiste (`FloatingTabBar`)

Maße der Systemleiste ab iOS 26, im Simulator an einer echten `TabView` gemessen (Debug-Argument
`-FamiliarSystemTabBarReference`, iPhone 17, Pixel ÷ 3):

| Maß | Wert |
|---|---|
| Höhe der Pille / Plus-Knopf | 62 pt |
| Auswahlkapsel: Abstand zum Rand | rundum 4 pt (54 pt hoch) |
| Abstand zur Unterkante (mit Home-Indikator) | 21 pt (sonst 12 pt) |
| Seitenrand | 20 pt |
| Beschriftung | 10 pt halbfett, wächst bis „xLarge“ mit |
| Symbol | 23 pt |
| Luft am Listenende | 16 pt (`FloatingTabBar.listClearance`) |

Die Tastatur gehört dem Blatt, nicht der Tabs-Ansicht: `RootTabView` schließt sie aus der Safe Area aus
(`.ignoresSafeArea(.keyboard)`), sonst fährt die Leiste mit.

## Blätter mit Texteingabe

`endsEditingWhenDisappearing()` schließt die Tastatur, sobald ein Blatt zu verschwinden beginnt – auch beim
Wegziehen mit dem Finger. Sonst blieb sie nach dem Wegwischen rund 1,9 s über der Liste stehen.

## Start

Alles, was nicht voneinander abhängt, läuft gleichzeitig (`async let` mit `captured { … }`, siehe
`ConcurrentLoad.swift`): Profil ∥ Familien, Aufgaben ∥ Verlauf. Aufgaben werden schon nach der Anmeldung
geladen (`TaskStore.prefetch`), nicht erst, wenn die Startseite erscheint.

Messung mit `-FamiliarInMemoryLatency 1000` (jede Anfrage 1 s; Protokoll „NETZ …“ im Systemprotokoll):
vorher Profil → Familien → Aufgaben nacheinander (Aufgaben fertig nach 4,2 s, bei leerer Liste kämen
Verlauf und Serienlöschungen dazu), nachher alle Anfragen gleichzeitig (fertig nach 1,1 s).
