## Was der Skill nicht kann: fragen, nicht improvisieren

**Improvisieren** heißt: ein Weg, den es als Werkzeug der App nicht gibt — ein
Umweg über andere Werkzeuge, eine Folge von Schritten, die niemand gemessen
hat. Das ist teuer, weil jeder Versuch mit seiner Ausgabe im Gesprächskontext
liegen bleibt, und es schreibt ohne Rückleseprobe in echte Kurse. Besser: die
Lücke melden, damit sie **einmal sauber** in die App eingebaut wird und danach
billig ist.

**Die App bemerkt eine Lücke oft selbst** und bricht ab, bevor etwas an Moodle
geht:

| Meldung der App | bedeutet |
|---|---|
| „Typ … kann die App nicht anlegen" / „Ändern geht bisher für …" | der Aktivitäts- oder Fragetyp ist nicht gemessen |
| „Nicht importiert, nichts hochgeladen: … nicht anlegbar" | ein Fragetyp im XML, dessen Format nicht erhoben ist |
| „Gesperrt: … steht nicht auf der Positivliste" | ein Weg, den kein Werkzeug vorsieht |
| „Das Kursformat dieses Kurses kennt die Aktion … nicht" | das Kursformat (ein Plugin) kann es nicht — keine Lücke der App |

**Fehlt nur eine Angabe**, ist das keine Lücke: Nimmt ein Werkzeug eine Nummer, die der Auftrag nicht enthält (ein Link auf eine Unterseite statt auf die Aktivität, kein Kurs genannt), frag danach, bevor du anfängst, und sag, wo der Nutzer sie findet. Ersetze sie nicht durch eine Annahme und arbeite nicht ohne sie los.

**Bemerkst du sie vorher** — der Auftrag verlangt etwas, wofür es kein
Werkzeug gibt, etwa „sortiere die Wikiseiten alphabetisch", „bewerte nach
Kriterium X" —, dann **anhalten und fragen**:

> (a) Sie erledigen es in der Moodle-Oberfläche; ich sage Ihnen genau, wo und wie.
> (b) Wir lassen es; der Lückenbefund unten geht zum Nachrüsten an die App.

| Lage | Verhalten |
|---|---|
| **lesen**, und der Auftrag baut darauf auf | anhalten und fragen, bevor du irgendetwas anderes tust — ein Ergebnis ohne die Quelle, die der Nutzer genannt hat, ist wertlos und sieht trotzdem fertig aus |
| **lesen**, und das Fehlende ist nebensächlich | weitermachen, gleich zu Beginn sagen, was fehlt; die Lücke trotzdem melden |
| **schreiben** ohne Werkzeug | anhalten, (a) oder (b) fragen, auf die Antwort warten |
| **löschen** oder sonst Unumkehrbares ohne Werkzeug | nur (b) — ohne Rückleseprobe weiß niemand, was wirklich weg ist |

**Der Lückenbefund steht immer am Ende der Antwort**, egal wie der Nutzer
entschieden hat — unverändert, als Codeblock. Er wird im Projekt moocp
eingefügt und sagt dort, was nachzurüsten ist:

```
LÜCKENBEFUND
Zum Nachrüsten: diesen Block unverändert im Projekt moocp einfügen.

Skill:      @@NAME@@
Art:        Typ nicht unterstützt | Typ unterstützt, Funktion fehlt | Weg nicht freigegeben
Typ:        <Aktivitäts- oder Fragetyp>
Gefordert:  <was gebraucht wurde, in einem Satz>
Anlass:     „<der Auftrag in Worten des Nutzers, ohne Personennamen>"
Meldung:    <wörtliche Meldung der App, falls eine kam>
```

`Anlass` ist der Auftrag in den Worten des Nutzers — **ohne Personennamen**
und ohne Inhalte, die jemandem zuzuordnen wären.

**Keine Lücke** ist:

- was dieser Skill beschreibt, auch wenn ein Schritt bei der Lehrkraft liegt;
- was an der Datenschutz-Sperre scheitert — das ist Absicht, dafür gibt es den
  Datenschutzbefund;
- Kursrahmen-Aktionen an Aktivitäten fremder Typen: verbergen, verschieben, duplizieren, löschen. Sie sind typunabhängig und gehen mit `sichtbarkeit_setzen`, `verschieben`, `duplizieren` und `loeschen`. Eine **Fragensammlung** ist die Ausnahme: Sie steht nicht in der Kursstruktur, deshalb geht nur `loeschen`. Verbergen, verschieben und duplizieren sind dort echte Lücken.

**Die Sperre nicht umgehen.** Kein anderes Werkzeug zweckentfremden, keine
Adresse umschreiben, bis sie durchrutscht. Das täte dasselbe, nur ohne dass
es jemand merkt — und genau dafür gibt es den Befund.
