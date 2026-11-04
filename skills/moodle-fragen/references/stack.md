# STACK: berechnete Fragen mit Rückmeldebaum

## Warum STACK hier eine Sonderrolle hat

STACK gehört **nicht** zum Moodle-Kern. Trotzdem legt die App STACK-Fragen an.
Der Grund ist kein Geschmacksurteil:

**STACK hat eine eingebaute Selbstprüfung.** Zu einer STACK-Frage gehören
Testfälle, die im XML mitgeliefert werden, und STACK sagt maschinenlesbar, ob
sie bestanden sind. Bei den meisten anderen Typen muss man dem selbst
geschriebenen XML glauben. Hier kann man nachmessen — und deshalb ist das
Anlegen verantwortbar.

Die Umkehrung gilt genauso: **Eine STACK-Frage ohne bestandene Testfälle ist
nicht mehr wert als geratenes XML.** `stack_xml` verweigert eine Frage ohne
Testfälle.

## Voraussetzung: Maxima muss laufen

STACK rechnet über das Computeralgebrasystem **Maxima** auf dem Server. Läuft
das nicht, lässt sich die Frage zwar importieren, sie rendert aber nicht und
bewertet nicht. Prüfen kostet einen Aufruf:

```
stack_cas(sammlung, frage, ausdruck: "Ergebnis {@x@}", variablen: "x : 3.5*2;")
```

Gerechnet wird, was in `{@…@}` steht. Kommt `7.0` zurück, ist alles in
Ordnung. Bleibt `3.5*2` unausgewertet stehen, ist entweder die
Auto-Vereinfachung aus (`vereinfachen: false`) oder das CAS antwortet nicht.

**Der Notizblock braucht eine STACK-Frage.** STACK öffnet ihn Lehrkräften nur über eine Frage, die sie bearbeiten dürfen; `frage` ist deshalb irgendeine STACK-Frage der Sammlung aus `fragen_lesen`. Welche, ist gleich: Sie wird weder gelesen noch geändert, gerechnet wird nur mit `variablen`. Gibt es in der Sammlung noch keine, entfällt Schritt 1 für die erste Frage – dann prüfen ihre Testfälle die Rechnung, und ab da ist der Notizblock über sie erreichbar.

## Der Arbeitsablauf

Fünf Schritte, und keiner davon ist optional:

1. **Rechnung im CAS prüfen** — `stack_cas`. Erst wenn die Maxima-Ausdrücke
   das Erwartete liefern, lohnt es sich, eine Frage zu bauen.
2. **Frage beschreiben und bauen** — `stack_xml(sammlung, fragen, datei)`.
3. **Importieren** — `fragen_importieren(sammlung, kategorie, datei)`. Die
   Testfälle laufen danach automatisch; das Ergebnis steht in der Antwort.
4. **Varianten einsetzen**, wenn die Aufgabenvariablen `rand()` benutzen —
   `stack_varianten(sammlung, frage, anzahl: 5)`.
5. **Aufgabenhinweise der Varianten ansehen** — `stack_varianten(sammlung,
   frage)` ohne Anzahl. Zufallszahlen erzeugen gern Brüche wie `7/2`, die im
   Unterricht unschön sind.

## Die Beschreibung für `stack_xml`

`stack_xml` nimmt eine knappe Beschreibung je Frage und setzt daraus das
vollständige XML — die rund 30 Anzeigeelemente, die Vorgaben je Eingabefeld,
das spezifische Feedback (`[[feedback:prt1]]` je Baum), die Antworthinweise
nach dem Muster `prt1-1-T`/`prt1-1-F`, die Gewichtung der Bäume zu gleichen
Teilen und die STACK-Version der Instanz.

```json
{
  "name": "Ohmsches Gesetz und Leistung",
  "idnummer": "et-ohm-leistung-01",
  "punkte": 2,
  "variablen": "I : (rand(9)+1)/2;\nR : 10*(rand(9)+2);\nU : I*R;\nP : U*I;\nPfalsch : U*R;",
  "hinweis": "U={@U@} V, R={@R@} Ohm, I={@I@} A, P={@P@} W",
  "fragetext": "<p>An einem Widerstand \\(R = {@R@}\\,\\Omega\\) liegt die Spannung \\(U = {@U@}\\,\\mathrm{V}\\).</p><p><strong>a)</strong> Wie groß ist der Strom? \\(I =\\) [[input:ans1]] A [[validation:ans1]]</p><p><strong>b)</strong> Welche Leistung wird umgesetzt? \\(P =\\) [[input:ans2]] W [[validation:ans2]]</p>",
  "allgemeinesFeedback": "<p>\\(I = U/R = {@I@}\\) A, \\(P = U \\cdot I = {@P@}\\) W</p>",
  "eingaben": [
    { "name": "ans1", "typ": "numerical", "tans": "I", "boxsize": 10, "options": "allowempty" },
    { "name": "ans2", "typ": "numerical", "tans": "P", "boxsize": 10, "options": "allowempty" }
  ],
  "prts": [
    { "name": "prt1", "knoten": [
      { "nr": 1, "beschreibung": "a) bearbeitet?", "test": "AlgEquiv", "sans": "ans1", "tans": "EMPTYANSWER", "leise": true,
        "wahr": { "punkte": 0, "abzug": 0, "feedback": "<p>a) wurde nicht bearbeitet – 0 Punkte.</p>" },
        "falsch": { "weiter": 2 } },
      { "nr": 2, "beschreibung": "Strom richtig?", "test": "NumRelative", "sans": "ans1", "tans": "I", "optionen": "0.001",
        "falsch": { "feedback": "<p>Nutze den Zusammenhang zwischen U, R und I.</p>" } } ] },
    { "name": "prt2", "knoten": [
      { "nr": 1, "beschreibung": "b) bearbeitet?", "test": "AlgEquiv", "sans": "ans2", "tans": "EMPTYANSWER", "leise": true,
        "wahr": { "punkte": 0, "abzug": 0, "feedback": "<p>b) wurde nicht bearbeitet – 0 Punkte.</p>" },
        "falsch": { "weiter": 2 } },
      { "nr": 2, "beschreibung": "Leistung genau richtig?", "test": "NumRelative", "sans": "ans2", "tans": "P", "optionen": "0.001",
        "falsch": { "weiter": 3 } },
      { "nr": 3, "beschreibung": "U mal R statt U mal I", "test": "NumRelative", "sans": "ans2", "tans": "Pfalsch", "optionen": "0.001",
        "wahr": { "punkte": 0.25, "feedback": "<p>Hier wurde \\(U \\cdot R\\) gerechnet. Die Leistung ist \\(P = U \\cdot I\\).</p>" },
        "falsch": { "weiter": 4 } },
      { "nr": 4, "beschreibung": "Zahlenwert richtig, aber in kW", "test": "NumRelative", "sans": "1000*ans2", "tans": "P", "optionen": "0.001",
        "wahr": { "punkte": 0.5, "feedback": "<p>Der Zahlenwert passt, aber die Einheit: gefragt war W, nicht kW.</p>" },
        "falsch": { "feedback": "<p>Rechne die Leistung aus Spannung und Strom.</p>" } } ] }
  ],
  "tests": [
    { "beschreibung": "Alles richtig", "eingaben": { "ans1": "I", "ans2": "P" },
      "erwartet": { "prt1": { "punkte": 1, "hinweis": "prt1-2-T" }, "prt2": { "punkte": 1, "hinweis": "prt2-2-T" } } },
    { "beschreibung": "Leistung als U mal R", "eingaben": { "ans1": "I", "ans2": "Pfalsch" },
      "erwartet": { "prt1": { "punkte": 1, "hinweis": "prt1-2-T" }, "prt2": { "punkte": 0.25, "abzug": 0.1, "hinweis": "prt2-3-T" } } },
    { "beschreibung": "Leistung in kW statt W", "eingaben": { "ans1": "I", "ans2": "P/1000" },
      "erwartet": { "prt1": { "punkte": 1, "hinweis": "prt1-2-T" }, "prt2": { "punkte": 0.5, "abzug": 0.1, "hinweis": "prt2-4-T" } } },
    { "beschreibung": "Beides falsch", "eingaben": { "ans1": "0", "ans2": "0" },
      "erwartet": { "prt1": { "punkte": 0, "abzug": 0.1, "hinweis": "prt1-2-F" }, "prt2": { "punkte": 0, "abzug": 0.1, "hinweis": "prt2-4-F" } } },
    { "beschreibung": "Nur a) bearbeitet", "eingaben": { "ans1": "I", "ans2": "" },
      "erwartet": { "prt1": { "punkte": 1, "hinweis": "prt1-2-T" }, "prt2": { "punkte": 0, "abzug": 0, "hinweis": "prt2-1-T" } } }
  ]
}
```

| Angabe | Bedeutung | Vorgabe |
|---|---|---|
| `name`, `fragetext` | Pflicht | — |
| `idnummer` | Sachnummer — überlebt jede Änderung | leer |
| `punkte` | Punkte der Frage | 1 |
| `strafe` | Abzug je falschem Versuch | 0.1 |
| `variablen` | Aufgabenvariablen (Maxima) | — |
| `hinweis` | Aufgabenhinweis — unterscheidet die Varianten; bei `rand()` Pflicht und mit allen gewürfelten Werten | — |
| `beschreibung` | interne Beschreibung der Frage | — |
| `allgemeinesFeedback`, `spezifischesFeedback` | Rückmeldungen | spezifisch: `[[feedback:…]]` je Baum |
| `anzeige` | einzelne Anzeigeoptionen überschreiben (`decimals`, `multiplicationsign` …) | Komma, Malpunkt |
| `eingaben[]` | `name`, `typ`, `tans`, dazu jede Eingabe-Option (`boxsize`, `forbidfloat`, `options` …); `gebunden: true` für eine Eingabe, die nur die Lage in einer Zeichnung hält (`jsxgraph.md`) | — |
| `prts[]` | `name`, `knoten`, `wert?` (Anteil), `vereinfachen?`, `feedbackvariablen?` | gleiche Anteile |
| `knoten[]` | `nr`, `test`, `sans`, `tans`, `optionen`, `beschreibung`, `leise`, `wahr`, `falsch` | Test `AlgEquiv` |
| `wahr` / `falsch` | `punkte`, `weiter`, `hinweis`, `feedback`, `abzug` (Abzug bei diesem Ausgang, etwa 0 für „nicht bearbeitet") | wahr 1, falsch 0, Ende, Abzug wie `strafe` |
| `tests[]` | `beschreibung`, `eingaben {}`, `erwartet {prt: {punkte, abzug, hinweis}}` | — |
| `zeichnungen[]` | `name` einer SVG in `dateien\` | — |

## Aufgabenvariablen

Maxima-Code, Anweisungen mit `;` getrennt. Zuweisung ist `:`, nicht `=`.

```
I : (rand(9)+1)/2;      /* 0,5 · 1,0 · … · 4,5 */
R : 10*(rand(9)+2);     /* 20 … 100 */
U : I*R;
```

**Zufallszahlen so wählen, dass schöne Ergebnisse entstehen.** `rand(n)`
liefert eine ganze Zahl von 0 bis n−1. Der klassische Fehler ist, Ausgangswerte
zu würfeln und das Ergebnis rechnen zu lassen: Aus `U : 10*(rand(8)+16)` und
`R : 10*(rand(9)+2)` wird `I = 23/7` — korrekt, aber im Unterricht
unbrauchbar. **Umgekehrt vorgehen:** die Werte würfeln, die glatt sein sollen,
und den Rest daraus ausrechnen.

**Ganzzahlig konstruieren, erst für die Anzeige teilen.** Wer Dezimalzahlen braucht, würfelt ganze Zahlen in der kleinsten Stelle – Zehntel, Cent – und teilt erst am Ende durch 10 oder 100. Maxima rechnet ganze Zahlen und Brüche exakt; eine Kommazahl, die früh entsteht, trägt Rundungsfehler in jeden weiteren Schritt. Das Ergebnis wird zuerst festgelegt und die Aufgabe daraus gebaut, so geht eine Division immer auf:

```
d  : 2+rand(8);                                  /* Divisor 2 … 9 */
q0 : 2+rand(39);                                 /* Quotient in Zehnteln */
q  : if is(mod(d*q0,10)=0) then q0+1 else q0;    /* kein glatter Dividend */
a  : d*q/10;                                     /* Dividend, etwa 36/5 */
ta : q/10;                                       /* Quotient, etwa 12/5 */
```

`a` und `ta` bleiben Brüche; im Text steht `{@dispdp(a,1)@}`, das zeigt 7,2 (siehe „Fragetext").

**Randfälle ausschließen statt neu würfeln.** Manche Würfe ergeben eine Aufgabe, die keine ist: Bei `d = 5` und geradem `q0` geht der Dividend glatt auf – eine Kommaaufgabe ohne Komma. Statt neu zu würfeln (eine Schleife mit `rand()` kostet Rechenzeit auf dem Server und endet nicht sicher) verschiebt die dritte Zeile um 1. Das genügt immer: `d*(q0+1)` unterscheidet sich von `d*q0` um `d`, und weil `d` zwischen 2 und 9 liegt, können nicht beide durch 10 teilbar sein. Ohne diese Zeile wären 64 der 312 möglichen Würfe trivial, mit ihr keiner (gemessen 09.10.2026).

**Alle Würfe durchrechnen, wo es überschaubar viele sind.** Ein Randfall in jedem fünften Wurf entgeht fünf eingesetzten Varianten in etwa einem Drittel der Fälle. `stack_cas` rechnet stattdessen alle durch: jedes `rand()` durch eine Laufvariable ersetzen und die schlechten Fälle zählen.

```
kor : flatten(makelist(makelist(if is(mod(d*q0,10)=0) then d*(q0+1) else d*q0, q0, 2, 40), d, 2, 9));
schlecht : length(sublist(kor, lambda([x], is(mod(x,10)=0))));
```

Mit dem Ausdruck `{@schlecht@} von {@length(kor)@}` kommt `0 von 312` zurück.

**Eine Auswahl, eine Zufallszahl.** In `if is(rand(2)=0) then a elseif is(rand(2)=0) then b else c` würfelt jede Stufe für sich: `a` kommt in der Hälfte der Varianten, `b` und `c` je in einem Viertel – daran ändert sich nichts, wenn die beiden Zahlen vorher gewürfelt werden. Eine Auswahl aus mehreren Fällen würfelt deshalb eine einzige Zahl: `rand([a, b, c])` wählt gleich verteilt aus der Liste (gemessen 09.10.2026), ebenso `w : rand(3);` mit `if is(w = 0) then … elseif is(w = 1) then … else …`. Soll die Auswahl gewichtet sein, dann ausdrücklich über Schwellen: `w : rand(10);` und dann `if w < 4 then … elseif w < 7 then … else …`.

Ob das alles gelungen ist, sieht man an den eingesetzten Varianten (Schritt 5).

## Fragetext

| Platzhalter | Bedeutung |
|---|---|
| `[[input:ans1]]` | Hier erscheint das Eingabefeld. **Ohne diesen Platzhalter kein Feld.** |
| `[[validation:ans1]]` | Rückmeldung „so habe ich Ihre Eingabe verstanden". **Zu jeder Eingabe, auch zu `dropdown`, `radio` und `checkbox`** — dort stellt `stack_xml` die Anzeige ab, der Platzhalter zeigt also nichts. |
| `{@ausdruck@}` | Wert aus den Aufgabenvariablen, gesetzt und formatiert |
| `[[feedback:prt1]]` | Rückmeldung eines Baums — steht im spezifischen Feedback |

`stack_xml` bricht ab, wenn zu einer Eingabe der `[[input:…]]`-Platzhalter fehlt. Das ist der häufigste Anfängerfehler und fiele sonst erst in der Vorschau auf. Ebenso beim `[[validation:…]]`-Platzhalter: Ohne ihn importiert Moodle die Frage zwar, aber das Bearbeitungsformular lehnt jede spätere Änderung ab.

Formeln in LaTeX: `\(…\)` inline, `\[…\]` abgesetzt. In JSON den Backslash
verdoppeln.

**Feste Nachkommastellen.** `{@x@}` zeigt eine Zahl so kurz wie möglich, 1,5 statt 1,50, und einen Bruch als Bruch. Für Geldbeträge und überall, wo die Stellenzahl etwas sagt, steht `{@dispdp(x,2)@}` im Text: Es zeigt 1,50 und 2,00, mit Komma wie der übrige Text, auch wenn `x` ein Bruch ist (gemessen 09.10.2026). `dispdp` ist nur Anzeige – gerechnet und gewertet wird mit `x` selbst.

Eine Zeichnung aus den Aufgabenvariablen oder zum Ziehen steht als Block `[[jsxgraph]]` im Fragetext. Wann sie sich lohnt, wie sie gebaut und bewertet wird und was die App dabei abweist: `jsxgraph.md`.

## Eingabetypen

Auf der Zielinstanz durchgemessen sind `numerical`, `units`, `algebraic`,
`string`, `dropdown` und `radio`; `stack_xml` nimmt außerdem `checkbox`,
`matrix`, `boolean`, `equiv`, `textarea` und `notes` an, nicht nachgeprüft.

| Typ | Wofür | Musterantwort (`tans`) |
|---|---|---|
| `numerical` | reine Zahl | `P` |
| `algebraic` | Term mit Variablen | `3*(x-1)^2` |
| `units` | **Zahl mit Einheit** — für Technik der wichtigste | `ta1` mit `ta1 : stackunits_make(R*ohm);` |
| `string` | Fachbegriff als Text | `"Kurzschluss"` |
| `dropdown` | Auswahlliste | `[["Reihenschaltung",true],["Parallelschaltung",false]]` |
| `radio` | dasselbe als Optionsfelder | wie `dropdown` |
| `checkbox` | Mehrfachauswahl | wie `dropdown`, mehrere `true` |

**`forbidfloat` steht auf `0`.** Der STACK-Standard ist `1` und weist
ausgerechnet die Dezimalzahl zurück, die man im Berufsschulunterricht
erwartet. Wer eine exakte Bruchangabe erzwingen will, setzt es je Eingabe
wieder auf `1`.

### Einheiten

Einheiten sind der Grund, warum STACK für Elektrotechnik interessant ist: `47`
und `47 Ω` und `0,047 kΩ` lassen sich unterscheiden und getrennt bewerten.
Einheitennamen sind Maxima-Bezeichner: `ohm`, `V`, `A`, `W`, `Hz`, `s`, `m`,
mit SI-Vorsätzen (`kohm`, `mA`). Das Ω-Zeichen entsteht bei der Anzeige, nicht
in der Eingabe: Getippt wird `ohm`, ein eingetipptes `kΩ` weist STACK als
„verbotene Variable" ab (gemessen 08.10.2026).

**Zerlegen einer Einheitenangabe** — gemessen, weil geraten falsch war:

```
n : first(args(stackunits_make(ans1)));    /* Zahlenwert  */
e : second(args(stackunits_make(ans1)));   /* Einheit     */
```

Die naheliegenden Namen `stackunits_num()` und `stackunits_units()` gibt es
**nicht**. Wer sie benutzt, bekommt keinen Fehler, sondern einen
unausgewerteten Ausdruck — und der Antworttest scheitert dann aus scheinbar
unerklärlichem Grund. Im Zweifel `stack_cas` fragen.

## Einheit und Genauigkeit

Die Regel steht im SKILL.md („Zahlenergebnisse: Einheit und Genauigkeit stehen im Text"): Der Text sagt, in welcher Einheit und wie genau, und der Knoten prüft genau das. Hier die Muster dazu, gemessen am 08.10.2026 mit \(I = 10\,\mathrm{V} / 150\,\Omega = 66{,}666\ldots\,\mathrm{mA}\).

**Einheit hinter dem Feld – die Vorgabe.** Eingabe `numerical`, die Einheit steht im Fragetext nach dem Platzhalter: `<p>\(I =\) [[input:ans1]] mA [[validation:ans1]]</p>`. Wer in der falschen Größenordnung antwortet, bekommt einen eigenen Knoten: `NumRelative` mit `sans: "1000*ans1"` gegen den Wert in mA erkennt die Antwort in A (0,0667) und gibt Teilpunkte mit dem Satz „Der Wert passt zur Einheit A – gefragt war mA."

**Komma an der falschen Stelle ist derselbe Fehler.** Bei Dezimalaufgaben stimmen oft die Ziffern und nur die Zehnerpotenz nicht: 0,72 oder 72 statt 7,2. Das fängt dasselbe Muster ab, je Richtung ein Knoten mit `NumRelative` gegen die Musterantwort, `sans: "10*ans1"` für ein Komma zu weit links und `sans: "ans1/10"` für eines zu weit rechts, mit der Rückmeldung „Die Ziffern stimmen, aber das Komma steht an der falschen Stelle." Ein Fehler um zwei Stellen (`100*ans1`) bekommt einen eigenen Knoten, wo er in der Aufgabe naheliegt, etwa beim Umrechnen von Flächeneinheiten. Testfälle: je Knoten der verschobene Wert (`ta/10`, `10*ta`).

**Einheit eingeben lassen – nur, wenn sie selbst geprüft wird.** Eingabe `units`, Musterantwort aus `stackunits_make(…)`, Knoten `UnitsRelative`: Er rechnet Vorsätze um. Gemessen: `66.7*mA` und `0.0667*A` sind beide richtig, `66.7*A` ist falsch (Vorsatz vergessen), `66.7*mV` passt nicht (`ATUnits_incompatible_units`). `UnitsStrictRelative` verlangt dagegen genau die Einheit der Musterantwort – nur, wenn der Text diese Einheit ausdrücklich verlangt („in mA"), sonst wird richtiges Umrechnen bestraft. Die Testfälle enthalten mindestens eine Antwort mit anderem Vorsatz als die Musterantwort.

Getippt wird, wie man es schreibt: `stack_xml` setzt bei `units` die Eingabeoption `insertstars` auf `4`, Sterne für Leerzeichen und für implizite Multiplikation. Gemessen: `66,7 mA`, `66,7mA` und `0,0667 A` werden angenommen und richtig gewertet; mit der STACK-Vorgabe `0` wären die ersten beiden ungültig, und Lernende müssten `66,7*mA` tippen.

**Nur Einheiten, die auf der Tastatur stehen.** Ω und µ stehen dort nicht, und wer sie eintippen soll, sucht sie. STACK nimmt sie auch nicht an: `kΩ` ist ungültig, `kohm` richtig (gemessen). Bei solchen Einheiten steht die Einheit deshalb fest hinter dem Feld. Soll sie doch eingegeben werden, nennt der Text die Schreibweise wörtlich („Ω als ohm, kΩ als kohm") – und die Übungsfrage vorher übt genau das.

**Runden.** Die Toleranz ist eine halbe Einheit der letzten verlangten Stelle:

| Der Text verlangt | Knoten | `optionen` | Was zählt (gemessen) |
|---|---|---|---|
| zwei Nachkommastellen, feste Einheit | `NumAbsolute` | `0.005` | 66,67 und genauer (66,6667) voll |
| drei geltende Ziffern | `NumRelative` | `0.005` | 66,7 und genauer voll |
| drei geltende Ziffern, und das Runden ist Lernziel | `NumSigFigs`, **leise** | `3` | nur 66,7; 66,67 und 66,6667 meldet STACK als falsche Stellenzahl (`ATNumSigFigs_WrongDigits`) |

Zu grob gerundet (66,7 bei verlangten zwei Nachkommastellen) fällt durch die enge Toleranz; ein weiterer Knoten mit `NumRelative` und `0.01` erkennt es und gibt Teilpunkte mit „Richtig gerechnet, aber nicht auf zwei Nachkommastellen gerundet." Ebenso nach `NumSigFigs`: ein Knoten mit `NumRelative` `0.005` für „richtig, aber anders gerundet". Der Knoten mit `NumSigFigs` ist dann **leise**: Sonst zeigt STACK zusätzlich „Ihre Antwort hat die falsche Anzahl an Dezimalstellen" – doppelt, und bei geltenden Ziffern auch noch falsch benannt (gemessen 08.10.2026). Ob genauer als verlangt voll zählt oder Teilpunkte bekommt, ist eine Entscheidung der Lehrkraft; der Vorschlag im Plan ist „voll", außer das Runden selbst ist Lernziel.

**Testfälle:** der richtig gerundete Wert, ein genauerer, ein zu grober und – bei fester Einheit – der Wert in der falschen Größenordnung. Testeingaben stehen in Maxima-Schreibweise mit Punkt (`66.67`); was Lernende mit Komma tippen (`66,67`), deutet die Anzeigeoption `decimals`, die `stack_xml` auf Komma stellt (gemessen 08.10.2026).

## Brüche: gekürzt oder wie abgezählt

Eine Eingabe `algebraic` mit `forbidfloat: 1` nimmt Brüche und keine Dezimalzahl. Ob gekürzt werden muss, sagt der Text, und der Baum prüft es in zwei Knoten: erst den Wert, dann die Form. Gemessen am 09.10.2026 mit 2 von 6 Teilen:

| Der Text verlangt | Knoten 1 (Wert) | Knoten 2 (Form) | Was zählt |
|---|---|---|---|
| vollständig gekürzt | `AlgEquiv` gegen `ta` | `LowestTerms` gegen `ta` | `1/3` voll; `2/6` ist wertgleich, aber nicht gekürzt (`ATLowestTerms_entries`) |
| den Bruch, wie abgezählt | `AlgEquiv` gegen `z/n` | `EqualComAss` gegen `z/n`, der Baum mit `vereinfachen: false` | `2/6` voll; `1/3` ist wertgleich, aber gekürzt |

Im zweiten Fall rechnet der Baum ohne Vereinfachung, sonst wird aus `z/n` mit `z : 2; n : 6;` schon `1/3`, und die ungekürzte Form ist nicht mehr zu prüfen. Knoten 2 sagt im falschen Zweig, was an der Form nicht stimmt („Der Wert stimmt, aber der Bruch ist nicht vollständig gekürzt."); ob das Teilpunkte gibt oder keine, entscheidet die Lehrkraft. Testfälle: die verlangte Form, die andere Form, ein falscher Wert.

## Rückmeldebäume (PRT)

Ein Baum ist eine Kette von Knoten. Jeder Knoten führt **einen** Antworttest
aus und verzweigt nach wahr und falsch: Punkte vergeben und aufhören
(`weiter` weglassen oder `-1`), oder weiter zu einem anderen Knoten
(`weiter: 2` heißt „Knoten 2").

### Knoten werden gezählt — an mehreren Stellen verschieden

Das ist die unangenehmste Falle des ganzen Fragetyps, auf der Instanz
gemessen:

| Wo | Erster Knoten | Zweiter Knoten |
|---|---|---|
| Beschriftung im Formular | „Knoten 1" | „Knoten 2" |
| Antwortnotiz | `prt1-1-T` | `prt1-2-T` |
| Formularfeld-Index | `prt1answertest[0]` | `prt1answertest[1]` |
| XML `<node><name>` | `0` | `1` |
| Auswahlwert bei `truenextnode` | `0` | `1` (`-1` = Ende) |

**Die Beschreibung benutzt durchgehend die sichtbare Nummer**, also die aus der
Formularbeschriftung und den Antwortnotizen: `nr: 1` ist „Knoten 1",
`weiter: 2` heißt „weiter zu Knoten 2". `stack_xml` rechnet an einer einzigen
Stelle um. Eine `0` wird **abgewiesen** statt stillschweigend umgedeutet — eine
falsch getroffene Verzweigung fiele sonst erst auf, wenn die Frage falsch
bewertet.

Genau daraus entsteht der didaktische Wert: Man kann **typische Fehler gezielt
abfangen** und mit passender Rückmeldung teilweise bewerten, statt nur richtig
und falsch zu kennen.

```
Knoten 1: Ergebnis genau richtig?
  ja   -> 1,0  Ende
  nein -> Knoten 2
Knoten 2: der bekannte Formelfehler?
  ja   -> 0,25 "Du hast U mal R gerechnet"   Ende
  nein -> Knoten 3
Knoten 3: Zahlenwert richtig, Einheit falsch?
  ja   -> 0,5  "Zahlenwert passt, Einheit prüfen"   Ende
  nein -> 0    "Rechne P aus U und I"
```

**Reihenfolge ist Bewertung.** Der erste zutreffende Test entscheidet.
Deshalb oben das Strengste, unten das Nachsichtigste.

**Antworthinweise** (`prt2-1-T`, `prt2-2-F` …) benennen den durchlaufenen
Pfad. Der Testlauf zeigt ihn vollständig an — `prt2-1-F | prt2-2-F | prt2-3-T`
heißt: an Knoten 1 und 2 vorbei, an Knoten 3 getroffen. Beim Nachbessern ist
das die wichtigste Spalte, weil sie zeigt, **wo** der Baum anders abgebogen ist
als gedacht.

`leise: true` an einem Knoten unterdrückt dessen Standardrückmeldung. Sinnvoll
bei Zwischenknoten, die nur verzweigen.

## Teile ohne Antwort: ausdrücklich 0 Punkte

STACK wertet einen Rückmeldebaum nur aus, wenn seine Eingaben ausgefüllt sind. Ein Teil, den jemand leer lässt, bekommt deshalb weder Punkte noch Rückmeldung, auch kein „falsch" (gemessen 08.10.2026). In einer Frage mit mehreren Teilen sieht dann niemand, dass ein Teil fehlt – die Punkte fehlen einfach, ohne dass die Rückmeldung es sagt.

Darum gilt bei mehreren Teilen (mehreren Bäumen): Jede Eingabe bekommt `"options": "allowempty"`, und jeder Baum prüft als Knoten 1, ob seine Eingabe leer ist – `AlgEquiv` gegen `EMPTYANSWER`, **leise**; wahr: 0 Punkte, **Abzug 0**, Rückmeldung „b) wurde nicht bearbeitet – 0 Punkte."; falsch: weiter zu Knoten 2. Leise, weil `AlgEquiv` bei einer Liste gegen `EMPTYANSWER` sonst den Lernenden bei jeder Antwort meldet, sie sei kein Ausdruck (gemessen 08.10.2026); `stack_xml` setzt einen Knoten gegen `EMPTYANSWER` deshalb immer leise. Moodle zeigt dazu wie bei jedem bewerteten Teil die Bewertung. Das Beispiel oben ist so gebaut.

Der Abzug ist 0, weil STACK mit `allowempty` ein leeres Feld auch dann bewertet, wenn jemand nur die Seite wechselt (STACK-Dokumentation). Wer weiterblättert, um später zurückzukommen, soll dafür nichts verlieren.

`stack_xml` bricht ab, wenn eine Eingabe leer bleiben darf und ein Baum, der sie benutzt, keinen solchen Knoten hat: Ohne ihn rechnet der Baum mit dem leeren Wert, und `ans2[1]` wird zu einem Fehler in Maxima statt zu „falsch". Leer ist nicht bei jedem Typ `EMPTYANSWER`, sondern bei `string` `""`, bei `checkbox` `[]`, bei `textarea` und `equiv` `[EMPTYANSWER]` (STACK-Dokumentation; gemessen sind `numerical` und `algebraic`). Benutzt ein Baum zwei Eingaben, prüft er beide, bevor er rechnet.

Dazu gehört ein Testfall, in dem ein Teil leer bleibt: die Eingabe als `""`, erwartet 0 Punkte, Abzug 0 und der Hinweis des ersten Knotens (`prt2-1-T`).

Eine Frage mit nur einem Teil braucht das nicht: Bleibt sie leer, zeigt Moodle sie als nicht beantwortet.

## Antworttests

| Test | Prüft | `optionen` |
|---|---|---|
| `AlgEquiv` | algebraische Gleichwertigkeit — der Standard | — |
| `NumRelative` | Zahl mit relativer Toleranz | `0.001` |
| `NumAbsolute` | Zahl mit absoluter Toleranz | `0.5` |
| `NumSigFigs` | Zahl auf n geltende Ziffern | `3` |
| `UnitsStrictRelative` | Zahl **und** Einheit, Einheit genau so | `0.01` |
| `UnitsRelative` | Zahl und Einheit, umgerechnete Einheiten erlaubt | `0.01` |
| `String` | Zeichenkette, exakt | — |
| `StringSloppy` | Zeichenkette, Groß-/Kleinschreibung und Leerzeichen egal | — |
| `EqualComAss` | gleich bis auf Kommutativität und Assoziativität | — |
| `LowestTerms` | Brüche vollständig gekürzt („Brüche: gekürzt oder wie abgezählt") | — |
| `SameType` | nur die Bauart der Antwort (Menge, Liste, Gleichung …) | — |

Die Einheitentests liefern eigene Hinweise mit — `ATUnits_incompatible_units`,
`ATUnits_correct_numerical`. Für ein reines „Einheit falsch, Zahl richtig" muss
man deshalb nicht zwingend einen zweiten Knoten bauen; für eine **eigene
Punktzahl** dagegen schon.

## Testfälle

- Die Werte sind **Maxima-Ausdrücke**, keine Zeichenketten des Nutzers. `I`,
  `P/1000`, `Pfalsch` beziehen sich auf die Aufgabenvariablen. Texte gehören in
  Anführungszeichen: `"\"Kurzschluss\""`.
- `punkte` ist der Anteil **dieses** Baums (0 bis 1), nicht die Punktzahl der
  Frage.
- `abzug` ist `0` bei voller Punktzahl und sonst der Wert aus `strafe`
  (Vorgabe 0,1).
- `hinweis` ist der erwartete Antworthinweis. Er ist die eigentliche Prüfung:
  Punkte können zufällig stimmen, der Pfad durch den Baum nicht.
- **Bei einer Auswahlliste (`dropdown`, `radio`, `checkbox`) muss die Testeingabe eine der Optionen sein, wie sie in `tans` dasteht.** STACK setzt die Aufgabenvariablen zwar ein, vereinfacht aber nicht: Zur Option `4` kommt `3+1` als `3+1` an und zählt nicht als Option, der Testfall prüft dann nichts. Soll der Wert aus einer Rechnung kommen, gehört er als Variable in die Aufgabenvariablen (`kn : kb+1;`) und steht dann in den Optionen **und** im Testfall; `stack_testen` meldet sonst „Eingabe … nicht übernommen".

**Mindestens drei Fälle**: alles richtig, der eingeplante typische Fehler,
alles falsch. Ohne den mittleren ist der Zweig für den typischen Fehler
ungeprüft.

Später erneut laufen lassen: `stack_testen(sammlung, frage, seed?)`.

## Varianten einsetzen

Bei `rand()` in den Aufgabenvariablen prüft ein Testlauf nur **eine**
Variante. Erst das Einsetzen rechnet weitere durch und lässt die Testfälle
darauf laufen. STACK unterscheidet Varianten am Aufgabenhinweis: Nennt er
nicht jeden gewürfelten Wert, gelten verschiedene Würfe als dieselbe
Variante, und es kommt keine neue dazu. Scheitert ein Testfall an einer
Variante, hört das Einsetzen dort auf.

```
stack_varianten(sammlung, frage, anzahl: 5)    -- nach Freigabe
stack_varianten(sammlung, frage)               -- was eingesetzt ist
stack_varianten(sammlung, frage, seed: 61853556)  -- genau diese Variante
```

Danach die Aufgabenhinweise ansehen. Im Testlauf des Beispiels oben kamen
`I = 1 A` und `I = 4 A` heraus, aber auch `I = 7/2 A` mit `P = 1225/2 W` —
rechnerisch richtig, für eine Klassenarbeit unbrauchbar. **Das sieht man nur
hier**, und es ist der Hauptgrund, warum dieser Schritt nicht optional ist.

## Gemessene Fallstricke

- **Die Versionsangabe.** `stackversion` muss die aktuelle Version der
  Instanz tragen, sonst markiert STACK die Frage dauerhaft als
  nachbesserungsbedürftig. `stack_xml` liest sie aus der Instanz.
- **Auto-Vereinfachung im CAS-Notizblock.** Ohne sie wertet Maxima nichts
  aus, und man hält die stehengebliebene Formel für ein defektes CAS.
  `stack_cas` schaltet sie ein, sofern nicht `vereinfachen: false`.
- **`stackunits_num` / `stackunits_units` gibt es nicht** — siehe oben.
- **Die Anteile der Bäume summieren sich auf 1.** `wert` ist der Anteil, nicht
  die Punktzahl. Ohne Angabe wird gleichmäßig verteilt; bei ungleicher
  Gewichtung müssen die Werte zusammen 1 ergeben.

## Was die App bei STACK nicht tut

- **Struktur einer vorhandenen Frage ändern** — ein zusätzlicher Knoten, ein
  zusätzliches Eingabefeld, ein weiterer Testfall. Inhalte vorhandener Knoten
  und Eingaben lassen sich ändern (siehe unten), die Struktur nicht.
- **Einen vorhandenen Testfall ändern oder löschen.** Er steht auf einer eigenen Seite, die die App nicht aufruft; in Moodle gehen beide Wege, unter den Ergebnissen jedes Testfalls auf der Seite mit den Fragetests. Über die App bleibt nur, die Frage neu anzulegen — deshalb die Testfälle vor dem Import genau nehmen.
- **„Antworten analysieren" öffnen.** Diese Seite wertet **echte Abgaben** aus
  und ist gesperrt. Testlauf, Varianten und CAS-Notizblock arbeiten nur mit der
  Frage selbst und sind offen.

## Eine vorhandene Frage ändern

Der Import legt immer neu an — geändert wird über das Bearbeitungsformular:

1. `fragen_lesen(sammlung, idnummer: "et-ohm-leistung-01")` — die aktuelle
   questionid
2. `frage_lesen(sammlung, frage)` — `frage-<id>/` mit den Textfeldern als
   `<feld>.html` und allen rund 150 Feldern in `einstellungen.json`
   (Aufgabenvariablen, Musterantworten, Knoten)
3. Textfelder bearbeiten, Einstellungen als Parameter an
   `aendern(ordner, einstellungen)`
4. `stack_testen` auf der **neuen** questionid

Die Feldnamen sind die des Formulars, nicht die der Beschreibung: Die
Musterantwort heißt `ans1modelans`, ein Knoten wird über den
**0-basierten** Formularindex angesprochen (`prt2truescore[0]` ist Knoten 1).
Lies sie aus `einstellungen.json`, statt sie zu raten.

Drei Punkte, die dabei zählen:

- **Es entsteht eine neue Version mit neuer questionid.** Testfälle,
  Rückmeldebäume und eingesetzte Varianten überstehen die Änderung —
  nachgemessen.
- **Tests ziehen „Immer die neueste" Version.** Die Änderung wirkt sofort in
  jedem Test, der die Frage benutzt.
- **Danach die Testfälle laufen lassen.** Eine geänderte Aufgabenvariable kann
  jeden Zweig des Baums verschieben, und die Testfälle sagen als Einzige, ob es
  noch stimmt.

## XML von Hand

Nur nötig, wenn `stack_xml` etwas nicht abdeckt. Dann den Weg gehen, der bei
jedem Fragetyp gilt: **eine Frage dieser Art von Hand anlegen lassen,
`frage_lesen`, Muster in `frage.xml` ablesen.** Die Elementreihenfolge ist die
des Exports: `name`, `questiontext`, `generalfeedback`, `defaultgrade`,
`penalty`, `hidden`, `idnumber`, `stackversion`, `questionvariables`,
`specificfeedback`, `questionnote`, `questiondescription`, die
Anzeigeoptionen, dann `input`, `prt`, `qtest`.
