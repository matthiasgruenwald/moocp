# Fragetypen und ihr Moodle-XML

## Warum XML und nicht das Formular

Jeder Fragetyp bringt ein eigenes Bearbeitungsformular mit — Multiple Choice hat
allein 109 Felder, andere mehr. Für siebzehn Kerntypen wären das siebzehn
Feldstudien, und jede Moodle-Version kann sie verschieben.

Moodle-XML ist dagegen **ein** Format für alle Typen, es ist stabil, es legt
beliebig viele Fragen in einem Durchgang an, und es ist genau das Format, das
Moodle selbst exportiert. Damit ist der Kreis geschlossen: Was du liest, kannst
du zurückschreiben.

Kennst du das XML eines Typs nicht: **eine Frage dieses Typs von Hand anlegen
lassen, mit `frage_lesen` holen, Muster in `frage.xml` ablesen.** Das ist
zuverlässiger als jedes Raten.

## Gerüst

```xml
<?xml version="1.0" encoding="UTF-8"?>
<quiz>
  <question type="…"> … </question>
  <question type="…"> … </question>
</quiz>
```

Felder, die fast jede Frage hat:

```xml
<name><text>Kurzer Fragename</text></name>
<questiontext format="html"><text><![CDATA[<p>Der Fragetext.</p>]]></text></questiontext>
<generalfeedback format="html"><text></text></generalfeedback>
<defaultgrade>2.0000000</defaultgrade>
<penalty>0.3333333</penalty>
<hidden>0</hidden>
```

Regeln, die man einhalten muss:

- **HTML immer in `<![CDATA[…]]>`.** Sonst zerlegt der erste `<`-Winkel das XML.
- **`<idnumber>` vergeben.** Ein sprechender Schlüssel wie
  `et-reihenschaltung-01`, direkt nach `<hidden>`. Er ist die einzige Kennung,
  die eine Änderung überlebt — die `questionid` nicht. Ohne ihn ist die Frage
  in der nächsten Sitzung nur über ihren Namen wiederzufinden. **Innerhalb
  einer Kategorie muss er eindeutig sein**, sonst scheitert der Import.
- `defaultgrade` ist die Punktvorgabe der Frage. Sie wird beim Einfügen in einen
  Test zum Startwert, lebt danach aber unabhängig weiter.
- `fraction` an einer Antwort ist der **Prozentanteil** (`100`, `50`, `0`,
  auch `-25`). Bei genau einer richtigen Antwort muss eine `100` dabei sein.
- Umlaute sind erlaubt, solange die Datei wirklich UTF-8 ist. Schreib das XML
  deshalb mit dem Datei-Werkzeug, nicht per Heredoc in der Shell: Der kostet hier
  gemessen eine Ebene Backslash-Maskierung, und dass er an deutschem Text
  scheitert, ist gemeldet. Ersatzschreibweisen wie „Uebertragung“ sind kein
  Ausweg — sie stehen hinterher so in der Frage.

## Der Nachweis nach dem Import

Moodle liest ein XML oft vollständig ein und scheitert erst beim Schreiben in die
Datenbank. Die Meldung **„11 Fragen werden aus der Datei importiert" ist deshalb
kein Beleg** — sie beschreibt, was gelesen wurde, nicht was ankam. Genau so ist
der `ordering`-Fehler unten aufgefallen: gemeldet 11, angekommen 10.

`fragen_importieren` zählt darum die Fragen der Zielkategorie vorher und
nachher und nennt die tatsächlich angelegten mit questionid. Weicht die Zahl
ab, nicht weitermachen, sondern die Meldung lesen und dem Nutzer berichten.

---

# Die Kerntypen

Legende: **geprüft** = auf der Zielinstanz importiert und wieder ausgelesen.

## Multiple Choice (`multichoice`) — geprüft

`single` entscheidet alles: `true` = eine richtige Antwort (Radiobuttons),
`false` = mehrere (Kästchen). Bei `false` müssen sich die positiven Anteile auf
100 summieren, und falsche Antworten bekommen negative Werte, damit Ankreuzen
aller Optionen nichts bringt.

```xml
<question type="multichoice">
  <name><text>Netzspannung</text></name>
  <questiontext format="html"><text><![CDATA[<p>Welche Spannung liegt zwischen Außenleiter und Neutralleiter?</p>]]></text></questiontext>
  <generalfeedback format="html"><text><![CDATA[<p>230 V ist der Effektivwert.</p>]]></text></generalfeedback>
  <defaultgrade>2.0000000</defaultgrade>
  <penalty>0.3333333</penalty>
  <hidden>0</hidden>
  <single>true</single>
  <shuffleanswers>true</shuffleanswers>
  <answernumbering>abc</answernumbering>
  <correctfeedback format="html"><text>Richtig.</text></correctfeedback>
  <partiallycorrectfeedback format="html"><text>Teilweise richtig.</text></partiallycorrectfeedback>
  <incorrectfeedback format="html"><text>Leider falsch.</text></incorrectfeedback>
  <answer fraction="100" format="html"><text>230 V</text>
    <feedback format="html"><text>Richtig.</text></feedback></answer>
  <answer fraction="0" format="html"><text>400 V</text>
    <feedback format="html"><text>Das ist die Außenleiterspannung.</text></feedback></answer>
  <answer fraction="0" format="html"><text>24 V</text>
    <feedback format="html"><text>Das ist Schutzkleinspannung.</text></feedback></answer>
</question>
```

`answernumbering`: `abc`, `ABCD`, `123`, `iii`, `IIII` oder `none`.

## Wahr/Falsch (`truefalse`) — geprüft

Genau zwei Antworten, deren Text wörtlich `true` und `false` lauten muss — nicht
„wahr"/„falsch", auch auf deutscher Oberfläche nicht. `penalty` steht hier
üblicherweise auf `1`.

```xml
<question type="truefalse">
  <name><text>FI und Kurzschluss</text></name>
  <questiontext format="html"><text><![CDATA[<p>Ein Fehlerstromschutzschalter schützt auch vor Kurzschluss.</p>]]></text></questiontext>
  <generalfeedback format="html"><text></text></generalfeedback>
  <defaultgrade>1.0000000</defaultgrade>
  <penalty>1.0000000</penalty>
  <hidden>0</hidden>
  <answer fraction="0" format="moodle_auto_format"><text>true</text>
    <feedback format="html"><text>Nein, dafür ist der Leitungsschutzschalter zuständig.</text></feedback></answer>
  <answer fraction="100" format="moodle_auto_format"><text>false</text>
    <feedback format="html"><text>Richtig.</text></feedback></answer>
</question>
```

## Kurzantwort (`shortanswer`) — geprüft

Freitexteingabe mit Textvergleich. Mehrere Antworten für zulässige Schreibweisen
anlegen; `*` ist Platzhalter. `usecase` = `1` beachtet Groß- und Kleinschreibung.

Der häufigste Entwurfsfehler: zu enge Antwortlisten. Wer nach einer Einheit
fragt, muss „Ohm", „ohm" und „Ω" zulassen — sonst bewertet Moodle richtige
Antworten als falsch.

```xml
<question type="shortanswer">
  <name><text>Einheit Widerstand</text></name>
  <questiontext format="html"><text><![CDATA[<p>Welche Einheit hat der elektrische Widerstand?</p>]]></text></questiontext>
  <generalfeedback format="html"><text></text></generalfeedback>
  <defaultgrade>1.0000000</defaultgrade>
  <penalty>0.3333333</penalty>
  <hidden>0</hidden>
  <usecase>0</usecase>
  <answer fraction="100" format="moodle_auto_format"><text>Ohm</text>
    <feedback format="html"><text>Richtig.</text></feedback></answer>
  <answer fraction="100" format="moodle_auto_format"><text>Ω</text>
    <feedback format="html"><text>Richtig.</text></feedback></answer>
</question>
```

## Numerisch (`numerical`) — geprüft

Wie Kurzantwort, aber mit Zahlenvergleich und **Toleranz**. Ohne `<tolerance>`
wird auf den exakten Wert geprüft — bei gerundeten Ergebnissen praktisch immer
falsch. Dezimaltrenner im XML ist der **Punkt**.

`showunits`: `3` = keine Einheit verlangt, `0` = Einheit muss mit eingegeben
werden.

Einheit und Rundung nach der Regel im SKILL.md („Zahlenergebnisse"): `showunits` `3`, die Einheit steht im Fragetext („Welcher Strom fließt in mA?"), und der Text sagt, wie gerundet wird. `<tolerance>` ist hier absolut – eine halbe Einheit der letzten verlangten Stelle, bei zwei Nachkommastellen `0.005`. Geltende Ziffern lassen sich mit einer absoluten Toleranz nur für einen festen Wert ausdrücken; variieren die Zahlen, nimm `calculatedsimple` mit relativer Toleranz oder STACK. Einheiten mit Vorsätzen eingeben zu lassen ist hier nicht vorgesehen – dafür STACK (`stack.md`, „Einheit und Genauigkeit").

```xml
<question type="numerical">
  <name><text>Strom berechnen</text></name>
  <questiontext format="html"><text><![CDATA[<p>Ein Widerstand von 100 Ω liegt an 230 V. Welcher Strom fließt in A?</p>]]></text></questiontext>
  <generalfeedback format="html"><text><![CDATA[<p>I = U / R</p>]]></text></generalfeedback>
  <defaultgrade>2.0000000</defaultgrade>
  <penalty>0.3333333</penalty>
  <hidden>0</hidden>
  <answer fraction="100" format="moodle_auto_format"><text>2.3</text>
    <feedback format="html"><text>Richtig.</text></feedback>
    <tolerance>0.05</tolerance></answer>
  <unitgradingtype>0</unitgradingtype>
  <unitpenalty>0.1000000</unitpenalty>
  <showunits>3</showunits>
  <unitsleft>0</unitsleft>
</question>
```

## Welche Zuordnung?

Bevor du eines der drei folgenden Muster nimmst: **Darf dieselbe Antwort mehrfach
vorkommen?** Bei `match` und `ddmatch` darf sie das immer, bei `ddwtos` nie —
außer du erlaubst es je Element. Der Normalfall im Unterricht ist 1:1, und dafür
ist `ddwtos` der Typ, auch wenn „Drag-and-Drop-Zuordnung" anders klingt.

| 1:1, jedes Element genau einmal | `ddwtos` |
|---|---|
| Mehrfachverwendung gewollt, oder HTML auf der Antwortseite | `ddmatch` |
| Mehrfachverwendung gewollt, Auswahlliste statt Ziehen | `match` |

Die Entscheidungstabelle mit Begründung steht in SKILL.md unter „Zuordnung:
erst die Regel, dann der Typ".

## Zuordnung (`match`, im Export `matching`) — geprüft

Paare aus Frage und Antwort. Mindestens **zwei** vollständige Paare, und Moodle
verlangt insgesamt mindestens drei Antworten. Ein `<subquestion>` mit **leerem**
`<text>` liefert einen zusätzlichen Distraktor in der Auswahlliste, ohne dass
danach gefragt wird — ein nützlicher Kniff gegen das Ausschlussverfahren.

```xml
<question type="matching">
  <name><text>Größen und Einheiten</text></name>
  <questiontext format="html"><text><![CDATA[<p>Ordnen Sie Größe und Einheit zu.</p>]]></text></questiontext>
  <generalfeedback format="html"><text></text></generalfeedback>
  <defaultgrade>3.0000000</defaultgrade>
  <penalty>0.3333333</penalty>
  <hidden>0</hidden>
  <shuffleanswers>true</shuffleanswers>
  <correctfeedback format="html"><text>Richtig.</text></correctfeedback>
  <partiallycorrectfeedback format="html"><text>Teilweise richtig.</text></partiallycorrectfeedback>
  <incorrectfeedback format="html"><text>Falsch.</text></incorrectfeedback>
  <subquestion format="html"><text>Spannung</text><answer><text>Volt</text></answer></subquestion>
  <subquestion format="html"><text>Stromstärke</text><answer><text>Ampere</text></answer></subquestion>
  <subquestion format="html"><text>Widerstand</text><answer><text>Ohm</text></answer></subquestion>
  <subquestion format="html"><text></text><answer><text>Watt</text></answer></subquestion>
</question>
```

## Freitext (`essay`) — geprüft

Wird **nicht automatisch bewertet**. `penalty` ist hier `0`. `graderinfo` ist der
Erwartungshorizont — er ist nur für Lehrkräfte sichtbar und der richtige Ort für
Bewertungshinweise.

```xml
<question type="essay">
  <name><text>Schutzleiter TN-S</text></name>
  <questiontext format="html"><text><![CDATA[<p>Erläutern Sie die Funktion des Schutzleiters in einem TN-S-Netz.</p>]]></text></questiontext>
  <generalfeedback format="html"><text></text></generalfeedback>
  <defaultgrade>5.0000000</defaultgrade>
  <penalty>0.0000000</penalty>
  <hidden>0</hidden>
  <responseformat>editor</responseformat>
  <responserequired>1</responserequired>
  <responsefieldlines>10</responsefieldlines>
  <attachments>0</attachments>
  <attachmentsrequired>0</attachmentsrequired>
  <graderinfo format="html"><text><![CDATA[<p>Erwartungshorizont: Potentialausgleich, Abschaltbedingung, Trennung von N und PE.</p>]]></text></graderinfo>
  <responsetemplate format="html"><text></text></responsetemplate>
</question>
```

`responseformat`: `editor`, `editorfilepicker`, `plain`, `monospaced`,
`noinline` (kein Online-Text). `attachments`: `0` keine, `-1` unbegrenzt, sonst
die Höchstzahl.

### `noinline` ohne Dateianhang: ein Zustand, den nur der Import baut

`noinline` zusammen mit `attachments 0` heißt: **kein Textfeld und keine
Dateiauswahl** — der Lernende sieht nur den Fragetext und kann nichts eingeben.
Als Platzhalter für einen Aufgabenteil, der auf Papier bearbeitet wird, ist das
gewollt. Man muss aber wissen, was man sich damit einhandelt.

| Zustand | Import | Formular speichert | Was der Lernende sieht |
|---|---|---|---|
| `noinline` + `attachments 0` | ja | **nein** | nur den Fragetext, kein Eingabefeld |
| `noinline` + `attachments 1` | ja | ja | nur die Dateiauswahl |
| `editor` + `attachments 0` | ja | ja | Textfeld |

**Der Import prüft nicht, das Formular schon.** Wer eine so importierte Frage
später über ihr Bearbeitungsformular anfassen will — und sei es nur, um einen
Tippfehler im Fragetext zu berichtigen —, kommt nicht am Speichern vorbei:

> Wenn 'Kein Textfeld' ausgewählt wurde oder Antworten optional sind, muss
> mindestens ein Dateianhang zugelassen werden.

Gemessen, und in **beide** Richtungen: Man kommt weder mit `attachments 0`
heraus noch später wieder dorthin zurück.

**Die Frage ist trotzdem nicht schreibgeschützt.** Die Meldung nennt die
Bedingung, und die lässt sich erfüllen — im selben Speichervorgang
`attachments` auf `1` (oder `-1`) setzen, dann geht die Änderung durch und es
entsteht wie üblich eine neue Version. Der Preis ist, dass die Frage danach
eine Dateiabgabe anbietet.

Drei Wege, je nachdem was gemeint ist:

| Ziel | Weg |
|---|---|
| Papierteil, Punkte im Test, keine Abgabe | `noinline` + `attachments 0` **per Import**, und Änderungen ebenfalls per Import — nicht über das Formular |
| Papierteil, Foto der Lösung erlaubt | `noinline` + `attachments 1`. Pflegbar wie jede andere Frage. |
| Nur ein Hinweis, keine Punkte | gar keine `essay`-Frage, sondern `description` |

Sag dem Nutzer, welchen der drei Fälle du annimmst, bevor du eine solche Frage
anlegst.

## Beschreibung (`description`) — geprüft

Keine Frage, sondern ein Textblock im Test — für Vorbemerkungen, Anlagen,
Situationsbeschreibungen. `defaultgrade` ist `0`.

```xml
<question type="description">
  <name><text>Hinweis zu Anlage 1</text></name>
  <questiontext format="html"><text><![CDATA[<p>Die folgenden Aufgaben beziehen sich auf den Schaltplan in Anlage 1.</p>]]></text></questiontext>
  <generalfeedback format="html"><text></text></generalfeedback>
  <defaultgrade>0.0000000</defaultgrade>
  <penalty>0.0000000</penalty>
  <hidden>0</hidden>
</question>
```

## Lückentext / Cloze (`multianswer`, im Export `cloze`) — geprüft

Der mächtigste Typ und der einzige, dessen Inhalt **im Fragetext selbst** steckt.
Kein `defaultgrade` — die Punkte ergeben sich aus den eingebetteten Teilfragen.

Syntax einer Lücke: `{Gewicht:TYP:Antworten}`

`=` markiert die richtige Antwort, `~` trennt Alternativen, `%50%` gibt
Teilpunkte, `%-50%` zieht ab, und nach dem Doppelpunkt bei `NUMERICAL` steht die
Toleranz.

```
{1:SHORTANSWER:=R*I~%50%I*R}
{1:MULTICHOICE:=Volt~Ampere~Ohm}
{2:NUMERICAL:=2.3:0.05}
```

### Die dreizehn Lückenarten

Alle unten sind einzeln angelegt, importiert und in der Vorschau angesehen
worden. Das Gewicht vorn (`{1:` , `{2:`) ist bei allen frei wählbar.

| Typ | Kurzform | Was der Lernende sieht |
|---|---|---|
| `SHORTANSWER` | `SA`, `MW` | Eingabefeld, Groß-/Kleinschreibung **egal** |
| `SHORTANSWER_C` | `MWC` | Eingabefeld, Groß-/Kleinschreibung **zählt** |
| `NUMERICAL` | `NM` | Eingabefeld für eine Zahl, mit Toleranz |
| `MULTICHOICE` | `MC` | Aufklappliste |
| `MULTICHOICE_V` | `MCV` | Radioknöpfe **untereinander** |
| `MULTICHOICE_H` | `MCH` | Radioknöpfe **nebeneinander** |
| `MULTICHOICE_S` | `MCS` | Aufklappliste, Reihenfolge gemischt |
| `MULTICHOICE_VS` | `MCVS` | untereinander, gemischt |
| `MULTICHOICE_HS` | `MCHS` | nebeneinander, gemischt |
| `MULTIRESPONSE` | `MR` | Ankreuzkästchen untereinander |
| `MULTIRESPONSE_H` | `MRH` | Ankreuzkästchen nebeneinander |
| `MULTIRESPONSE_S` | `MRS` | untereinander, gemischt |
| `MULTIRESPONSE_HS` | `MRHS` | nebeneinander, gemischt |

Die Kurzform `SAC` ist nicht mitgemessen; für Groß-/Kleinschreibung sind
`SHORTANSWER_C` und `MWC` belegt. **Schreib die Langform** — sie ist eindeutig
und beim Wiederlesen verständlich.

**Das `_S` mischt wirklich.** Gemessen: dreimal dieselbe geschriebene Reihenfolge
`Volt~Ampere~Ohm`, dreimal eine andere Anzeige. Ohne `_S` steht sie so, wie sie
geschrieben ist. Wer mischen will, braucht also nicht die Antworten umzustellen.

**Mehrfachauswahl bewertet über mehrere `=`.** `{2:MULTIRESPONSE:=Kupfer~=Silber~%-50%Glas}`
mit beiden Richtigen angekreuzt gab die volle Punktzahl. Der negative Anteil auf
der falschen Antwort ist das Gegenmittel gegen Alleskreuzen.

### Der Fallstrick, der die ganze Frage kostet

**Eine einzige unbrauchbare Lücke verwirft die komplette Einreichung.** Gemessen
mit `{1:NM:=2.3:0.05}` und der Eingabe `2.3`:

> Die Einreichung ist ungültig und wurde ohne Bewertung verworfen.

Nicht die eine Lücke — die ganze Frage, alle sechs Lücken, ohne Punkte. Mit
`2,3` waren es dann 4 von 6 Punkten. Mit deutscher Oberfläche (gemessen auf
der Testinstanz) gilt für Zahlen also das **Komma**. Wenn du eine `NUMERICAL`-Lücke schreibst, sag dem Nutzer, dass
seine Lerngruppe das Komma benutzen muss, oder nimm `SHORTANSWER`.

### Das XML

```xml
<question type="cloze">
  <name><text>Ohmsches Gesetz</text></name>
  <questiontext format="html"><text><![CDATA[<p>Das Ohmsche Gesetz lautet U = {1:SHORTANSWER:=R*I~%50%I*R} und die Einheit der Spannung ist {1:MULTICHOICE_H:=Volt~Ampere~Ohm}.</p>]]></text></questiontext>
  <generalfeedback format="html"><text></text></generalfeedback>
  <penalty>0.3333333</penalty>
  <hidden>0</hidden>
  <idnumber>et-ohm-cloze-01</idnumber>
</question>
```

Weil die Punkte aus dem Text kommen, nennt `fragen_lesen` hier keine Punkte.
Das ist richtig so — nicht als Fehler melden.

**Eine Cloze-Frage verbraucht mehrere Fragenummern**: eine für die Frage selbst
und je eine für jede Lücke. Gemessen: Die Elternfrage bekam 14043, die drei
Lücken 14044 bis 14046, die nächste Frage erst 14047. Wer `questionid`-Werte
vergleicht, darf sich davon nicht irritieren lassen — sichtbar in der Sammlung
ist nur die Elternfrage.

## Lückentextauswahl (`gapselect`) — geprüft

Lücken im Text als `[[1]]`, `[[2]]`. Die `<selectoption>`-Elemente liefern in
ihrer Reihenfolge die Antworten: Die erste gehört zu `[[1]]`, die zweite zu
`[[2]]`. Weitere sind Distraktoren. `group` fasst Optionen zusammen, die
gegeneinander austauschbar angeboten werden. Lücken in Programmcode: unten
„Lücken im Code" – nie in `<code>`.

```xml
<question type="gapselect">
  <name><text>Schutzorgane</text></name>
  <questiontext format="html"><text><![CDATA[<p>Der [[1]] begrenzt den Strom, der [[2]] schützt vor Fehlerströmen.</p>]]></text></questiontext>
  <generalfeedback format="html"><text></text></generalfeedback>
  <defaultgrade>2.0000000</defaultgrade>
  <penalty>0.3333333</penalty>
  <hidden>0</hidden>
  <shuffleanswers>0</shuffleanswers>
  <correctfeedback format="html"><text>Richtig.</text></correctfeedback>
  <partiallycorrectfeedback format="html"><text>Teilweise richtig.</text></partiallycorrectfeedback>
  <incorrectfeedback format="html"><text>Falsch.</text></incorrectfeedback>
  <selectoption><text>Leitungsschutzschalter</text><group>1</group></selectoption>
  <selectoption><text>FI-Schalter</text><group>1</group></selectoption>
  <selectoption><text>Trenntrafo</text><group>1</group></selectoption>
</question>
```

## Drag&drop auf Text (`ddwtos`) — geprüft

**Der Typ für die 1:1-Zuordnung.** Wie `gapselect`, nur zieht man die Begriffe
statt sie auszuwählen. Identischer Aufbau, nur heißt das Element `<dragbox>`
statt `<selectoption>`. Dass die Lücken im Fließtext stehen, hindert nicht an
einer Zuordnung „Begriff links, Lücke rechts" — der Fragetext ist HTML, und
Lücken in Tabellenzellen sind gemessen (11.09.2026):

```html
<table class="table table-bordered">
  <thead><tr><th>Stoff</th><th>Klasse</th></tr></thead>
  <tbody>
    <tr><td>Kupfer</td><td>[[1]]</td></tr>
    <tr><td>Glas</td><td>[[2]]</td></tr>
    <tr><td>Silizium</td><td>[[3]]</td></tr>
  </tbody>
</table>
```

Dazu drei `<dragbox>` (Leiter, Nichtleiter, Halbleiter, alle `<group>1</group>`).
Die Vorschau zeigt die Tabelle mit drei Ablagezonen rechts; ein abgelegtes
Element ist aus dem Vorrat verschwunden. Das ist die 1:1-Zuordnung in der Optik,
die man von `ddmatch` kennt — ohne dessen Mehrfachverwendung.

```xml
<question type="ddwtos">
  <name><text>Leistungsformel</text></name>
  <questiontext format="html"><text><![CDATA[<p>Die Leistung berechnet sich aus [[1]] mal [[2]].</p>]]></text></questiontext>
  <generalfeedback format="html"><text></text></generalfeedback>
  <defaultgrade>2.0000000</defaultgrade>
  <penalty>0.3333333</penalty>
  <hidden>0</hidden>
  <shuffleanswers>0</shuffleanswers>
  <correctfeedback format="html"><text>Richtig.</text></correctfeedback>
  <partiallycorrectfeedback format="html"><text>Teilweise richtig.</text></partiallycorrectfeedback>
  <incorrectfeedback format="html"><text>Falsch.</text></incorrectfeedback>
  <dragbox><text>Spannung</text><group>1</group></dragbox>
  <dragbox><text>Strom</text><group>1</group></dragbox>
  <dragbox><text>Widerstand</text><group>1</group></dragbox>
</question>
```

**Jedes Ziehelement wird verbraucht.** Wer es in eine Lücke zieht, nimmt es aus
dem Vorrat; für eine zweite Lücke steht es nicht mehr bereit. Soll es mehrfach
verwendbar sein, gehört in die `<dragbox>` das leere Element `<infinite/>`.
Genau darin unterscheidet sich der Typ von `ddmatch`, wo **jedes** Element
unbegrenzt ist und sich daran nichts ändern lässt — Einzelheiten dort.

## Berechnet (`calculated`, `calculatedsimple`, `calculatedmulti`) — geprüft

Formelfragen mit Platzhaltern `{a}`, `{b}`, deren Werte aus **Datensätzen**
stammen. Für jede Variable braucht es eine `<dataset_definition>` mit
Wertebereich und den erzeugten `<dataset_item>`-Werten.

`calculatedsimple` hat private Datensätze (`<status>private</status>`),
`calculated` kann sie zwischen Fragen teilen, `calculatedmulti` bietet
berechnete Werte als Multiple Choice an.

```xml
<question type="calculatedsimple">
  <name><text>Strom aus U und R</text></name>
  <questiontext format="html"><text><![CDATA[<p>Ein Widerstand von {R} Ω liegt an {U} V. Welcher Strom fließt in A?</p>]]></text></questiontext>
  <defaultgrade>2.0000000</defaultgrade>
  <penalty>0.3333333</penalty>
  <hidden>0</hidden>
  <synchronize>0</synchronize>
  <single>0</single>
  <answernumbering>abc</answernumbering>
  <answer fraction="100" format="moodle_auto_format">
    <text>{U}/{R}</text>
    <tolerance>0.01</tolerance>
    <tolerancetype>1</tolerancetype>
    <correctanswerformat>2</correctanswerformat>
    <correctanswerlength>3</correctanswerlength>
    <feedback format="html"><text>Richtig.</text></feedback>
  </answer>
  <unitgradingtype>0</unitgradingtype>
  <unitpenalty>0.1000000</unitpenalty>
  <showunits>3</showunits>
  <unitsleft>0</unitsleft>
  <dataset_definitions>
    <dataset_definition>
      <status><text>private</text></status>
      <name><text>R</text></name>
      <type>calculatedsimple</type>
      <distribution><text>uniform</text></distribution>
      <minimum><text>10</text></minimum>
      <maximum><text>100</text></maximum>
      <decimals><text>0</text></decimals>
      <itemcount>3</itemcount>
      <dataset_items>
        <dataset_item><number>1</number><value>10</value></dataset_item>
        <dataset_item><number>2</number><value>50</value></dataset_item>
        <dataset_item><number>3</number><value>100</value></dataset_item>
      </dataset_items>
      <number_of_items>3</number_of_items>
    </dataset_definition>
  </dataset_definitions>
</question>
```

Durchgespielt: importiert, in der Vorschau geöffnet, beantwortet. Moodle setzte
R=10 und U=12 ein und wertete die Eingabe `1.2` als „Richtig, 2,00 von 2,00" mit
der Rückmeldung „Die richtige Antwort ist: 1,20".

Toleranz und Anzeige folgen der Rundung, die der Text verlangt (SKILL.md, „Zahlenergebnisse"): `<tolerancetype>1</tolerancetype>` ist relativ, `0.005` deckt drei geltende Ziffern; `<correctanswerformat>2</correctanswerformat>` mit `<correctanswerlength>3</correctanswerlength>` zeigt die richtige Antwort ebenso auf drei geltende Ziffern. Verlangt der Text Nachkommastellen, steht `correctanswerformat` auf `1` und `correctanswerlength` auf deren Zahl. Das Beispiel oben zeigt nur das XML; eine neue Frage nennt die Rundung im Text und setzt Toleranz und Anzeige danach.

### Der Fallstrick bei `calculatedmulti`

Bei `calculated` ist die Antwort eine **Rechenvorschrift zum Prüfen** — sie wird
nie angezeigt. Bei `calculatedmulti` ist sie eine **Antwortmöglichkeit, die
Lernende lesen**, und muss deshalb ausgerechnet werden. Dafür braucht sie die
`{=…}`-Schreibweise:

```xml
<answer fraction="100" format="moodle_auto_format"><text>{={U}*{I}}</text>
  <tolerance>0.01</tolerance><tolerancetype>1</tolerancetype>
  <correctanswerformat>1</correctanswerformat><correctanswerlength>2</correctanswerlength>
  <feedback format="html"><text>Richtig.</text></feedback></answer>
```

Schreibt man nur `{U}*{I}`, importiert Moodle die Frage anstandslos und die
Bewertung stimmt sogar — aber in der Auswahl steht dann wörtlich „24*6,0" statt
„144,00". Beides nachgemessen: ohne `{=…}` zeigte die Vorschau `a. 230/16,0` und
`b. 230*16,0`, mit `{=…}` dann `a. 48,00` und `b. 12,00`.

Das fällt bei einer Kontrolle des XML nicht auf und in der Klausur sofort — also
bei `calculatedmulti` immer in die Vorschau schauen.

## Zufällige Zuordnung (`randomsamatch`) — geprüft

Baut eine Zuordnungsfrage aus vorhandenen **Kurzantwort**-Fragen einer
Kategorie. Braucht also erst genügend `shortanswer`-Fragen.

```xml
<question type="randomsamatch">
  <name><text>Zufällige Zuordnung Einheiten</text></name>
  <questiontext format="html"><text><![CDATA[<p>Ordnen Sie zu.</p>]]></text></questiontext>
  <defaultgrade>4.0000000</defaultgrade>
  <penalty>0.3333333</penalty>
  <hidden>0</hidden>
  <choose>4</choose>
  <subcats>0</subcats>
</question>
```

`choose` ist die Zahl der gezogenen Paare, `subcats` schaltet Unterkategorien
hinzu. Die Frage bedient sich **zur Laufzeit** aus der Kategorie — sie muss also
in derselben Kategorie liegen wie die Kurzantwort-Fragen, und dort müssen
mindestens `choose` Stück vorhanden sein.

Geprüft mit drei `shortanswer`-Fragen (Volt / Ampere / Watt): Die Vorschau baute
daraus drei Zuordnungszeilen mit gemeinsamer Auswahlliste.

---

# Bilder in Fragen

Bilder werden **im XML mitgeliefert**, nicht verlinkt. Zwei Teile gehören
zusammen:

1. Im HTML verweist `src` auf den Platzhalter `@@PLUGINFILE@@/<dateiname>`.
2. Direkt hinter dem `<text>` steht ein `<file>`-Element mit demselben Namen und
   dem Inhalt als Base64.

```xml
<questiontext format="html">
  <text><![CDATA[<p>Welches Bauteil zeigt das Bild?</p>
    <p><img src="@@PLUGINFILE@@/bauteil.png" alt="Bauteil" class="img-fluid"></p>]]></text>
  <file name="bauteil.png" path="/" encoding="base64">iVBORw0KGgo…</file>
</questiontext>
```

Das `<file>`-Element muss **innerhalb** von `<questiontext>` stehen, als
Geschwister von `<text>` — nicht darin und nicht daneben. Beim Import legt Moodle
die Datei im Dateibereich der Frage ab und ersetzt den Platzhalter durch eine
echte `pluginfile.php`-Adresse.

Geprüft mit einem erzeugten PNG: Nach dem Import zeigte die Vorschau
`src="…/pluginfile.php/…/bauteil.png"` und das Bild war geladen.

Dasselbe funktioniert in `generalfeedback`, `answer` und `feedback` — überall
dort, wo Moodle einen Dateibereich führt.

**Woher das Base64 kommt:** Am einfachsten lässt du es den Browser erzeugen —
ein Bild in ein Canvas zeichnen und `toDataURL('image/png')` nehmen, oder eine
bereits in Moodle liegende Datei abrufen und umwandeln. Gib den Base64-Text
nicht in der Antwort aus; er ist lang und der Sicherheitsfilter des
Browser-Werkzeugs verwirft die Antwort dann unter Umständen komplett.

## Anordnung (`ordering`) — geprüft

Seit Moodle 4.5 ein Kerntyp: Elemente in die richtige Reihenfolge bringen. Die
Reihenfolge ergibt sich aus der **Dokumentreihenfolge** der `<answer>`-Elemente.
Was in `fraction` steht, ist dafür gleichgültig — nachgemessen mit `0` bei allen
und mit der Rangzahl `1, 2, 3, 4`; beides ergab dieselbe Frage. Moodle selbst
schreibt beim Export die Rangzahl hinein.

**Zwei Fallstricke, und der zweite ist der gefährlichere.**

**Erstens: `<shownumcorrect/>` ist Pflicht.** Fehlt es, bricht der Import mit
„Fehler beim Schreiben der Datenbank" ab, und über das Formular endet das
Speichern in `get_in_or_equal() does not accept empty arrays`. Der Fehler nennt
die Ursache nicht, und es sieht nach einem kaputten Plugin aus — ist es aber
nicht. Isoliert nachgemessen: mit `<shownumcorrect/>` und ohne Feedback-Block
läuft der Import; ohne scheitert er, auch mit vollständigem Feedback-Block. Das
leere Element genügt; Moodle selbst exportiert `<shownumcorrect>1</shownumcorrect>`.

**Zweitens: Die fünf Auswahlfelder wollen NAMEN, keine Zahlen.** Das ist der
Fallstrick, der nichts meldet. Schreibt man dort die Zahl aus dem Formular —
`<selecttype>0</selecttype>` —, importiert Moodle **klaglos** und speichert
etwas anderes:

| geschrieben | gespeichert | Folge |
|---|---|---|
| `<selecttype>0</selecttype>` | `1` — „zufällige Teilmenge" | Die Vorschau zeigt **2 von 4** Elementen |
| `<gradingtype>0</gradingtype>` | `1` — „relativ zum nächsten Element" | andere Bewertung als gewollt |

Kein Fehler, kein `.alert-danger`, die Kategoriezählung stimmt. Auffallen kann
es nur, wer die Vorschau zählt. Mit den Namen stimmt alles auf Anhieb —
gemessen an denselben vier Elementen: 4 statt 2, `selecttype` und `gradingtype`
wie geschrieben.

| Element | Namen (gemessen) |
|---|---|
| `layouttype` | `VERTICAL` · `HORIZONTAL` |
| `selecttype` | `ALL` · `RANDOM` · `CONTIGUOUS` |
| `gradingtype` | `ABSOLUTE_POSITION` · `ALL_OR_NOTHING` · `RELATIVE_TO_CORRECT` |
| `showgrading` | `SHOW` · `HIDE` |
| `numberingstyle` | `none` · `abc` · `ABCD` · `123` · `iii` · `IIII` |
| `selectcount` | eine **Zahl** — nur wirksam bei `RANDOM` und `CONTIGUOUS` |

`selecttype`, `layouttype` und `showgrading` sind damit vollständig.
`gradingtype` kennt neun Werte; die übrigen sechs sind nicht erhoben. Brauchst
du einen davon: eine Frage von Hand damit anlegen, exportieren, den Namen
ablesen — so sind auch diese drei entstanden.

**Die Regel dahinter, für jeden Fragetyp:** Wenn ein Auswahlfeld im Formular
Zahlen als `value` hat, heißt das nicht, dass im XML Zahlen stehen. Was im XML
steht, sagt der Export.

```xml
<question type="ordering">
  <name><text>Fünf Sicherheitsregeln</text></name>
  <questiontext format="html"><text><![CDATA[<p>Bringen Sie die Schritte in die richtige Reihenfolge.</p>]]></text></questiontext>
  <generalfeedback format="html"><text></text></generalfeedback>
  <defaultgrade>5.0000000</defaultgrade>
  <penalty>0.3333333</penalty>
  <hidden>0</hidden>
  <layouttype>VERTICAL</layouttype>
  <selecttype>ALL</selecttype>
  <selectcount>2</selectcount>
  <gradingtype>ABSOLUTE_POSITION</gradingtype>
  <showgrading>SHOW</showgrading>
  <numberingstyle>none</numberingstyle>
  <correctfeedback format="html"><text>Richtig.</text></correctfeedback>
  <partiallycorrectfeedback format="html"><text>Teilweise richtig.</text></partiallycorrectfeedback>
  <incorrectfeedback format="html"><text>Falsch.</text></incorrectfeedback>
  <shownumcorrect/>
  <answer fraction="0" format="html"><text>Freischalten</text><feedback format="html"><text></text></feedback></answer>
  <answer fraction="0" format="html"><text>Gegen Wiedereinschalten sichern</text><feedback format="html"><text></text></feedback></answer>
  <answer fraction="0" format="html"><text>Spannungsfreiheit feststellen</text><feedback format="html"><text></text></feedback></answer>
  <answer fraction="0" format="html"><text>Erden und kurzschließen</text><feedback format="html"><text></text></feedback></answer>
  <answer fraction="0" format="html"><text>Benachbarte Teile abdecken</text><feedback format="html"><text></text></feedback></answer>
</question>
```

## Drag&drop auf Bild / Markierungen (`ddimageortext`, `ddmarker`) — nur lesen

Brauchen eine Hintergrundgrafik und pixelgenaue Koordinaten der Ablagezonen. Das
Bild müsste als Base64 ins XML, und die Koordinaten lassen sich ohne Blick auf
das Bild nicht sinnvoll setzen.

Die App legt beide nicht an; `fragen_importieren` bricht vorher ab. Dem Nutzer
anbieten, die Frage in Moodle anzulegen und den Text hinterher zuzuliefern.

---

---

# HTML in Fragen

Fragetext, Feedback, allgemeines Feedback und Erwartungshorizont sind HTML, und für sie gelten dieselben Regeln wie für alles in Moodle: **`references/html.md`**. Dazu kommen Besonderheiten, die es nur bei Fragen gibt.

## Wo HTML nicht hingehört

**Antwortoptionen von `gapselect` und `ddwtos`.** Die `<selectoption>`- und
`<dragbox>`-Texte rendert Moodle in Auswahlfelder und Ziehkacheln. HTML darin
wird entweder als Text angezeigt oder still verschluckt — beides falsch. Nur
Klartext:

```xml
<selectoption><text>Leitungsschutzschalter</text><group>1</group></selectoption>
```

**Alles innerhalb der `{…}`-Klammern einer Cloze-Frage.** Die Syntax
`{1:SHORTANSWER:=R*I}` wird vom Cloze-Parser gelesen, nicht vom HTML-Renderer.
Ein `<strong>` darin zerlegt die Frage. HTML gehört ausschließlich in den Text
*um* die Klammern:

```html
<p>Das Ohmsche Gesetz lautet <strong>U =</strong> {1:SHORTANSWER:=R*I}.</p>
```

Dasselbe gilt sinngemäß für die kurzen Antworttexte von `shortanswer`,
`numerical` und `truefalse` — dort wird verglichen, nicht gerendert.

## Lücken im Code

Code ohne Lücken steht in Fragen wie überall als `<pre class="language-…"><code>…</code></pre>` (`references/html.md`, „Code"). **Steht eine Lücke von `gapselect` oder `ddwtos` im Code, kommt der Code in ein `<pre>` ohne `<code>` und ohne Klasse:**

```html
<pre>function summe(a, b) {
  [[1]] a + b;
}</pre>
```

Gemessen am 29.10.2026 in der Vorschau, mit Code-Highlighter an:

- In einem `<code>` mit Sprachklasse, auch `language-none`, wird die Lücke zu Text („Leer 1 Frage 1 return…"). Die Frage ist dann nicht lösbar, und zwar bei `gapselect` wie bei `ddwtos`.
- In einem `<code>` ohne Klasse und in `<code>`-Zeilen eines Absatzes bleibt die Lücke nur dann heil, wenn nirgends auf der Seite eine Sprachklasse steht. Steht eine in derselben Frage oder in einer anderen Frage auf derselben Testseite, geht die Lücke ebenfalls kaputt.
- In `<pre>` ohne `<code>` blieb die Lücke in jedem Fall ein Auswahlfeld.

Eine Frage, die in der Einzelvorschau heil aussieht, kann also im Test kaputt sein, sobald eine andere Frage Code mit Sprachklasse zeigt. Darum ist nur `<pre>` ohne `<code>` sicher. Lücken einer Cloze-Frage im Code sind nicht gemessen; dort dieselbe Form nehmen und in der Vorschau nachsehen.

## Was unkritisch ist

Fragetext, `generalfeedback`, das `feedback` je Antwort, `graderinfo` und
`responsetemplate` sind vollwertige HTML-Felder. Dort sind Absätze, Listen,
Tabellen und Bilder richtig aufgehoben.

## Formeln in Fragen

In allen HTML-Feldern setzt MathJax Formeln wie auf jeder Seite, nach den
Regeln in `references/html.md`, „Formeln". Gemessen am 01.10.2026 in der
Vorschau: im Fragetext und in den Antworten von `multichoice`, auf beiden
Seiten von `ddmatch` (auch auf den Ziehkärtchen), im Text um eine Cloze-Lücke.
Vier Stellen brauchen mehr:

- **Berechnete Fragen (`calculated`, `calculatedsimple`, `calculatedmulti`).**
  Moodle ersetzt jedes `{Name}` durch den Wert des Platzhalters, auch mitten in
  einer Formel. Gemessen: Aus `\(I = \frac{U}{R}\)` wurde „I = ½10", weil
  `\frac{U}{R}` zu `\frac1210` geworden war. LaTeX-Klammern um einen einzelnen
  Buchstaben, der auch Platzhalter ist, bekommen deshalb Leerzeichen:
  `\frac{ U }{ R }` bleibt der Bruch aus den Formelzeichen. Den Wert selbst
  setzt man mit doppelten Klammern ein: `\(I = \frac{{U}\,\mathrm{V}}{{R}\,\Omega}\)`
  zeigt „12 V / 10 Ω" (beides gemessen).
- **Cloze.** Innerhalb einer Lücke beendet jedes `}` die Lücke. In einer
  Formel als Antwort werden deshalb die schließenden Klammern maskiert, die
  öffnenden nicht: `{1:MULTICHOICE_V:=\(\frac{U\}{R\}\)~\(U \cdot R\)}`.
  Wer auch `\{` schreibt, bekommt statt der Formel „Extra close brace or
  missing open brace" (beides gemessen). Formeln als Antwort nur mit
  Radioknöpfen (`MULTICHOICE_V`, `MULTICHOICE_H`): Eine Aufklappliste
  (`MULTICHOICE`, `MULTICHOICE_S`) ist ein `<select>`, und in dessen
  `<option>` kann MathJax nichts setzen.
- **`gapfill`.** Mit `[]` als Lückenzeichen wird eine abgesetzte Formel
  `\[ … \]` zur Lücke. Gemessen: „ P = U \cdot I \" stand als Antwort zur
  Auswahl, vor der Lücke ein einzelner Backslash. Eine Formel im Text mit
  `\( … \)` verträgt `[]` (gemessen), aber sobald Formeln in der Frage stehen,
  ist `@@` sicherer: Es kollidiert mit nichts in LaTeX; `{}` scheidet aus.
  Steht `@@`, darf sonst kein `@` im Text stehen, denn jedes `@` beginnt oder
  beendet eine Lücke. Die App bricht den Import einer `gapfill`-Frage mit `[]`
  und `\[` ab.
- **Antworten, die verglichen statt angezeigt werden** — `shortanswer`,
  `numerical`, `truefalse`, die Lücken von `gapfill` und die Auswahltexte von
  `gapselect` und `ddwtos` — nehmen keine Formeln auf, aus demselben Grund wie
  kein HTML (oben). Die Formel steht dann im Fragetext, und die Antwort ist
  ein Wort oder eine Zahl.

# Drei Zusatztypen mit gemessenem XML

`ddmatch`, `mtf` und `gapfill` sind **keine** Kerntypen, werden hier aber
angelegt. Der Grund ist derselbe wie bei den Kerntypen: Das XML ist gemessen,
nicht geraten. Für jeden der drei wurde am 08.09.2026 im Testkurs eine Frage
von Hand angelegt, exportiert, das Muster daraus selbst neu geschrieben, wieder
importiert, erneut exportiert und verglichen — und die Vorschau angesehen.
Danach wurden alle Proben gelöscht.

Genau das ist auch der Weg, wenn ein vierter Zusatztyp dazukommen soll. Ein
Detail dabei, das eine Frage gekostet hat: **Nach dem Klick auf den
Speicherknopf nicht sofort weiternavigieren.** Der Klick stösst den POST nur an;
wer im selben Atemzug die nächste Seite lädt, bricht ihn ab, und die Frage
entsteht nie — ohne Fehlermeldung. Erst den Seitenwechsel abwarten.

## Drag-and-Drop-Zuordnung (`ddmatch`) — geprüft

**Nicht für 1:1.** Jede Antwort ist hier unbegrenzt oft verwendbar, ohne
Schalter — für eine Zuordnung, in der jedes Element genau einmal passt, ist
`ddwtos` der Typ (siehe „Welche Zuordnung?" oben).

Wie `match`, mit einem Unterschied: Die Antwort steht als eigenes Element
**innerhalb** der `<subquestion>` und ist **HTML**, nicht Text. Deshalb lohnt
sich der Typ überhaupt — man kann Formeln, Hervorhebungen und Bilder auf beiden
Seiten der Zuordnung benutzen.

```xml
<question type="ddmatch">
  <name><text>Größen und Einheiten</text></name>
  <questiontext format="html"><text><![CDATA[<p>Ordne jeder Größe ihre Einheit zu.</p>]]></text></questiontext>
  <generalfeedback format="html"><text></text></generalfeedback>
  <defaultgrade>3.0000000</defaultgrade>
  <penalty>0.3333333</penalty>
  <hidden>0</hidden>
  <idnumber>et-einheiten-01</idnumber>
  <shuffleanswers>true</shuffleanswers>
  <correctfeedback format="html"><text><![CDATA[<p>Die Antwort ist richtig.</p>]]></text></correctfeedback>
  <partiallycorrectfeedback format="html"><text><![CDATA[<p>Die Antwort ist teilweise richtig.</p>]]></text></partiallycorrectfeedback>
  <incorrectfeedback format="html"><text><![CDATA[<p>Die Antwort ist falsch.</p>]]></text></incorrectfeedback>
  <shownumcorrect/>
  <subquestion format="html">
    <text><![CDATA[<p>Spannung <em>U</em></p>]]></text>
    <answer format="html"><text><![CDATA[<p>Volt (V)</p>]]></text></answer>
  </subquestion>
  <subquestion format="html">
    <text><![CDATA[<p>Stromstärke <em>I</em></p>]]></text>
    <answer format="html"><text><![CDATA[<p>Ampere (A)</p>]]></text></answer>
  </subquestion>
  <subquestion format="html">
    <text><![CDATA[<p>Widerstand <em>R</em></p>]]></text>
    <answer format="html"><text><![CDATA[<p>Ohm</p>]]></text></answer>
  </subquestion>
</question>
```

- **Mindestens drei Paare.** Wie bei `match`: Die nicht gewählten Antworten sind
  die Ablenker, mit zwei Paaren gibt es keine.
- **Die drei Sammelrückmeldungen legt der Import nicht selbst an.** Lässt man
  sie weg, importiert Moodle klaglos, und die Frage bleibt stumm. Gemessen: Der
  Export der so entstandenen Frage zeigt leere Elemente, keine Vorgabetexte.
- Ein leeres `<subquestion>` mit gefülltem `<answer>` ist eine reine Ablenker-
  antwort — dasselbe Verhalten wie bei `match`.

### Jedes Merkmal bleibt im Vorrat

Wer ein Merkmal in eine Zielzone zieht, hat es **nicht verbraucht**: Es steht
weiterhin im Vorrat und lässt sich in eine zweite und dritte Zone ziehen. Das
ist kein Fehler und **kein Schalter im Formular**, sondern fest eingebaut. Der
Renderer gibt jedem Ziehelement die Klasse `draghome infinite`, und die
Ziehlogik klont alles, was `infinite` heißt: Beim Ziehen aus dem Vorrat bleibt
eine frische Kopie zurück. Im Bearbeitungsformular danach zu suchen, lohnt
nicht — es gibt dort kein Feld dafür.

Nachgemessen in der Vorschau (09.09.2026, Testkurs): dasselbe Merkmal in alle
drei Zielzonen gezogen, danach immer noch im Vorrat. **Das Prüfen nimmt das
klaglos an** — „Teilweise richtig, Sie haben 1 richtig ausgewählt", 1,00 von
3,00. Es gibt keine Warnung, weder für den Lernenden noch beim Auswerten.
Wer eine echte 1:1-Zuordnung braucht, merkt es also erst an den Punkten.

Der Grund liegt in der Herkunft: `ddmatch` bildet `match` nach, und dort dürfen
mehrere Zeilen dieselbe Antwort haben. Ohne Mehrfachverwendung wären solche
Zuordnungen gar nicht darstellbar.

| Wenn gewollt ist … | dann … |
|---|---|
| eine Zuordnung, in der mehrere Zeilen dieselbe Antwort haben dürfen | `ddmatch` oder `match` — genau dafür gebaut |
| HTML auf beiden Seiten (Formeln, Bilder) | `ddmatch` — der einzige Grund, ihn `match` vorzuziehen |
| dass jedes Element genau einmal verwendet wird | **weder** `ddmatch` **noch** `match`, sondern `ddwtos` |
| eine Reihenfolge statt einer Zuordnung | `ordering` |

**Auf `match` auszuweichen bringt nichts.** Auch dort hat jede Zeile ihr eigenes
Auswahlfeld mit allen Antworten darin; dieselbe Antwort zweimal zu wählen,
hindert niemand. Am selben Tag mit einer inhaltsgleichen `match`-Frage
gegengemessen: dreimal dieselbe Antwort gewählt, angenommen, 1,00 von 3,00 —
Wort für Wort dieselbe Rückmeldung wie bei `ddmatch`. Die Mehrfachverwendung
ist eine Eigenschaft der Zuordnungsfragen überhaupt, nicht ein Makel von
`ddmatch`.

**`ddwtos` ist der Typ mit Verbrauch, aber kein Ersatz eins zu eins.** Dort
verschwindet ein gezogenes Element aus dem Vorrat, solange es nicht
`<infinite/>` trägt. Der Preis: Die Ziehelemente sind reiner Text, kein HTML —
der Vorteil von `ddmatch` ist damit weg —, und die Zielzonen stehen im
Fragetext statt in einer zweiten Spalte. Eine Zuordnungstabelle baut man dort
mit einer Liste im Fragetext nach: `<p>Leiter: [[1]]</p><p>Nichtleiter:
[[2]]</p>`.

**Frag den Nutzer, welche der beiden Bedeutungen er meint**, bevor du eine
Zuordnungsfrage anlegst. Die Frage „darf dieselbe Antwort mehrfach vorkommen?"
entscheidet den Typ, und man sieht sie der Aufgabenstellung nicht an.

## Mehrfach Wahr/Falsch (`mtf`) — geprüft

Eine Tabelle: Zeilen sind Aussagen, Spalten sind die Antwortmöglichkeiten
(vorgegeben „Wahr" und „Falsch"). Der Typ kommt von der ETH Zürich und heißt
in der Oberfläche „Mehrfach Wahr/Falsch-Frage".

Die Bewertung steht **nicht** bei den Zeilen, sondern in einer eigenen
Gewichtsmatrix am Ende: je Zeile und Spalte ein `<weight>`. Bei *n* Zeilen sind
das *2n* Elemente. Fehlt eines, ist die Zeile stillschweigend unbewertet.

```xml
<question type="mtf">
  <name><text>Aussagen zum ohmschen Gesetz</text></name>
  <questiontext format="html"><text><![CDATA[<p>Welche Aussagen sind wahr?</p>]]></text></questiontext>
  <generalfeedback format="html"><text></text></generalfeedback>
  <defaultgrade>3.0000000</defaultgrade>
  <penalty>0.3333333</penalty>
  <hidden>0</hidden>
  <idnumber>et-ohm-mtf-01</idnumber>
  <scoringmethod><text>subpoints</text></scoringmethod>
  <shuffleanswers>true</shuffleanswers>
  <numberofrows>3</numberofrows>
  <numberofcolumns>2</numberofcolumns>
  <answernumbering>none</answernumbering>
  <deduction>0.000</deduction>
  <row number="1">
    <optiontext format="html"><text><![CDATA[<p>Kupfer leitet gut.</p>]]></text></optiontext>
    <feedbacktext format="html"><text></text></feedbacktext>
  </row>
  <row number="2">
    <optiontext format="html"><text><![CDATA[<p>Glas leitet gut.</p>]]></text></optiontext>
    <feedbacktext format="html"><text></text></feedbacktext>
  </row>
  <row number="3">
    <optiontext format="html"><text><![CDATA[<p>Silizium ist ein Halbleiter.</p>]]></text></optiontext>
    <feedbacktext format="html"><text></text></feedbacktext>
  </row>
  <column number="1"><responsetext format="moodle_auto_format"><text>Wahr</text></responsetext></column>
  <column number="2"><responsetext format="moodle_auto_format"><text>Falsch</text></responsetext></column>
  <weight rownumber="1" columnnumber="1"><value>1.000</value></weight>
  <weight rownumber="1" columnnumber="2"><value>0.000</value></weight>
  <weight rownumber="2" columnnumber="1"><value>0.000</value></weight>
  <weight rownumber="2" columnnumber="2"><value>1.000</value></weight>
  <weight rownumber="3" columnnumber="1"><value>1.000</value></weight>
  <weight rownumber="3" columnnumber="2"><value>0.000</value></weight>
</question>
```

Die Regel für die Matrix: **Genau eine `1.000` je Zeile**, in der Spalte, die
richtig ist. Alle übrigen Zellen `0.000`. Zeile 1 im Beispiel ist wahr, Zeile 2
falsch, Zeile 3 wahr.

| Element | Werte | Bedeutung |
|---|---|---|
| `scoringmethod` | `subpoints` · `mtfonezero` | Teilpunkte je Zeile oder alles-oder-nichts |
| `numberofrows` | Zahl | muss zur Anzahl der `<row>` passen |
| `numberofcolumns` | 2 | „Wahr"/„Falsch"; die Texte stehen in `<column>` |
| `answernumbering` | `none` `abc` `ABCD` `123` `iii` `IIII` | Nummerierung der Zeilen |
| `deduction` | Zahl | Abzug bei `mtfonezero`; bei `subpoints` ohne Wirkung |
| `shuffleanswers` | `true`/`false` | mischt die Zeilen |

Die Spaltentexte sind frei: Wer statt „Wahr"/„Falsch" lieber „trifft zu"/„trifft
nicht zu" hätte, ändert nur die beiden `<responsetext>`.

## Erweiterter Lückentext (`gapfill`) — geprüft

Der bequemste der drei: **Die Lücken stehen in eckigen Klammern im Fragetext.**
Ohne Ablenker baut der Import die richtigen Antworten daraus selbst; mit
Ablenkern stehen sie ausgeschrieben im XML, wie im Beispiel.

```xml
<question type="gapfill">
  <name><text>Größen und Einheiten</text></name>
  <questiontext format="html"><text><![CDATA[<p>Die [Spannung] wird in [Volt] gemessen.</p>]]></text></questiontext>
  <generalfeedback format="html"><text></text></generalfeedback>
  <defaultgrade>2.0000000</defaultgrade>
  <penalty>0.3333333</penalty>
  <hidden>0</hidden>
  <idnumber>et-einheiten-luecke-01</idnumber>
  <answerdisplay>dragdrop</answerdisplay>
  <delimitchars>[]</delimitchars>
  <casesensitive>0</casesensitive>
  <noduplicates>0</noduplicates>
  <disableregex>1</disableregex>
  <fixedgapsize>1</fixedgapsize>
  <optionsaftertext>0</optionsaftertext>
  <letterhints>0</letterhints>
  <singleuse>0</singleuse>
  <answer fraction="100" format="moodle_auto_format">
    <text>Spannung</text>
    <feedback format="moodle_auto_format"><text></text></feedback>
  </answer>
  <answer fraction="100" format="moodle_auto_format">
    <text>Volt</text>
    <feedback format="moodle_auto_format"><text></text></feedback>
  </answer>
  <answer fraction="0" format="moodle_auto_format">
    <text>Ampere</text>
    <feedback format="moodle_auto_format"><text></text></feedback>
  </answer>
</question>
```

**Alle Antworten oder keine.** Eine Frage ganz ohne `<answer>` bekommt beim
Import genau die Lückenwörter als richtige Antworten (gemessen). Sobald aber
ein `<answer>` im XML steht, leitet der Import nichts mehr ab. Eine Frage, die
nur einen Ablenker mitbringt, hat danach keine einzige richtige Antwort und
bricht in der Vorschau mit einem Fehler im Renderer ab
(`get_itemsettings(): Argument #1 ($rightanswer) must be of type string`,
gemessen 01.10.2026). Mit Ablenkern stehen deshalb alle Lückenwörter als
`<answer fraction="100">` im XML und jeder
**Ablenker** als `<answer fraction="0">` — ein Wort, das zur Auswahl steht,
aber in keine Lücke gehört. Die App bricht den Import einer `gapfill`-Frage
ohne richtige Antwort ab.

`defaultgrade` gehört trotzdem ins XML: Das Bearbeitungsformular hat kein Feld
dafür, und gemessen entspricht der Wert der **Anzahl der Lücken**. Zwei Lücken,
also `2.0000000`.

| Element | Werte | Bedeutung |
|---|---|---|
| `answerdisplay` | `dragdrop` · `gapfill` · `dropdown` | ziehen · tippen · auswählen |
| `delimitchars` | `[]` · `{}` · `##` · `@@` | Zeichen um die Lücke |
| `casesensitive` | 0/1 | Groß- und Kleinschreibung zählt |
| `noduplicates` | 0/1 | jedes Wort nur einmal verwendbar |
| `disableregex` | 0/1 | 1 = Antworten sind wörtlich, kein regulärer Ausdruck |
| `fixedgapsize` | 0/1 | alle Lücken gleich breit (verrät sonst die Wortlänge) |
| `optionsaftertext` | 0/1 | Auswahlwörter unter statt über dem Text |
| `letterhints` | 0/1 | Buchstabenhilfe |
| `singleuse` | 0/1 | jedes Zugelement nur einmal ziehbar |

Zwei Dinge, an denen man sich stösst:

- **Enthält der Fragetext selbst eckige Klammern**, etwa in einer Einheit, einer
  Quellenangabe oder einer abgesetzten Formel `\[ … \]`, wird daraus eine
  Lücke. Dann `delimitchars` auf `@@` umstellen; der Text enthält dann kein
  weiteres `@`. Mehr dazu unter „Formeln in Fragen".
- **Über das Formular** werden die Ablenker in ein einziges Feld „Falsche
  Antworten" kommagetrennt eingetragen. Moodle trennt dort nur am Komma und
  schneidet **keine Leerzeichen ab** — gemessen: aus `Ampere, Volt` wird ein
  Ablenker mit führendem Leerzeichen. Beim Schreiben über XML stellt sich die
  Frage nicht, weil jeder Ablenker sein eigenes `<answer>` hat.

# Die übrigen Zusatz-Plugins

Alles außerhalb der bisher genannten Typen ist ein Zusatz-Plugin. Die App
**liest** sie (Export und Übersicht funktionieren), **legt sie aber nicht an**.
Welche Typen eine Instanz hat und wie die App sie einordnet, zeigt
`fragetypen(sammlung)`.

Fragt der Nutzer nach einem solchen Typ, sag es offen und nenne die zwei Wege:
die Frage von Hand anlegen und dir zum Befüllen übergeben, oder den Typ
nachrüsten lassen — das ist ein Lückenbefund an das Projekt moocp: eine
Frage dieses Typs anlegen, exportieren, das Muster messen, einmal im Testkurs
durchspielen. Genau so sind `ddmatch`, `mtf` und `gapfill` dazugekommen.

## Zeichnungen in Fragen (SVG als `<file>`) — geprüft

Jeder Fragetyp mit `<questiontext>` kann eine selbst gezeichnete SVG als
Datei tragen: `<file name="x.svg" path="/" encoding="base64">` **innerhalb**
von `<questiontext>`, hinter `</text>`, im Text `<img src="@@PLUGINFILE@@/x.svg" alt="…" class="img-fluid">`.
Gemessen am 19.09.2026 (Import, Vorschau, Datei byte-gleich ausgeliefert).
Schreiben musst du nur das `<img>`: Liegt die Datei in `dateien\` neben der
XML-Datei, bettet `fragen_importieren` sie ein und prüft sie (`<title>`,
`<desc>`, kein `<script>`, kein externer Verweis). Hausstil, Muster und
Grenzen: **`references/zeichnungen.md`**.

## Bestehende Fragen ändern

### Warum nicht über XML

Der Import **legt immer neu an**. Es gibt keinen Weg, ein XML als neue Version
einer vorhandenen Frage einzuspielen. Wer eine Frage ändern will, muss durch ihr
Bearbeitungsformular — das erledigt die App:

```
frage_lesen(sammlung, frage)     -> frage-<id>\  (<feld>.html, dateien\, einstellungen.json, frage.xml)
<feld>.html bearbeiten, Einstellungen als Parameter
aendern(ordner, einstellungen)   -> Freigabe, speichern, die NEUE questionid in der Antwort
```

### Was beim Speichern passiert

**Es entsteht eine neue Version, nicht eine geänderte Frage.** Gemessen:

| | vorher | nachher |
|---|---|---|
| STACK-Frage | 13981, v1 | **13983**, v2 |
| Multiple Choice | 13984, v1 | **13985**, v2 |
| Multiple Choice mit SVG, über die App | 14960, v1 | **14966**, v2 |

Testfälle, Rückmeldebäume, Antworten und eingesetzte Varianten überstehen die
Änderung; die STACK-Fragetests liefen danach unverändert grün.

**Tests folgen der neuen Version.** Jeder Testplatz hat eine Auswahl
„Frageversion" mit „Immer die neueste", „v2 (neueste)" und „v1" — die Vorgabe
ist **„Immer die neueste"**. Eine Änderung wirkt also sofort in jedem Test, der
die Frage benutzt. Gibt es dort Versuche, verschiebt das rückwirkend
Bewertungen. **Vorher fragen.**

### Feldnamen

Die Namen hängen am Fragetyp. Statt zu raten: `einstellungen.json` im Ordner
von `frage_lesen` — dort steht, was es hier wirklich gibt. Die Textfelder
(Fragetext, allgemeines Feedback, Antworten, Rückmeldungen) liegen daneben als
`<feld>.html` und werden dort bearbeitet, nicht als Einstellung.

Gleich bei allen Typen:

| Schlüssel | Was |
|---|---|
| `name` | Fragename |
| `defaultmark` | Punktvorgabe |
| `penalty` | Abzug je Versuch |
| `idnumber` | Sachnummer |
| `status` | Bereit / Entwurf |

Multiple Choice zusätzlich je Antwort `fraction[0]` …, dazu `single`,
`shuffleanswers`, `answernumbering`.

STACK zusätzlich: `questionvariables`, je Eingabe `ans1type`, `ans1modelans`
(**nicht** `ans1tans`), `ans1boxsize` …, je Baum `prt1value`,
`prt1feedbackvariables` und je Knoten `prt1answertest[0]`, `prt1sans[0]`,
`prt1truescore[0]`, `prt1truenextnode[0]` … — der Index ist **0-basiert**,
`[0]` ist Knoten 1 (`references/stack.md`).

### Zwei Sicherungen

**`makecopy` muss `0` sein.** Steht dort `1`, legt das Formular eine zweite
Frage an, statt die vorhandene zu versionieren. Setz es nie.

**Erst prüfen, dann speichern.** `aendern` prüft zuerst, ob es alle genannten
Einstellungen gibt und ob die Werte als Option vorkommen, und bricht sonst ab,
bevor etwas geschrieben wird. Das fängt vor allem den stillen Fall ab, dass ein
Auswahlfeld einen Wert, den es nicht kennt, kommentarlos verwirft.

### Die Frage überhaupt erst wiederfinden

Um zu ändern, braucht man die **aktuelle** questionid — und die ändert sich bei
jedem Speichern. Über eine Sitzung hinaus ist deshalb die Sachnummer der
Einstieg: `fragen_lesen(sammlung, idnummer: "et-reihenschaltung-01")`. Findet
die App mehrere oder keine, zeig das dem Nutzer, statt zu raten.

Hat die Frage keine Sachnummer, bleibt der Name — mit dem bekannten Risiko,
dass Namen weder eindeutig noch stabil sind. Dann bei der Gelegenheit eine
Sachnummer setzen: `aendern(ordner, einstellungen: {"idnumber":
"et-reihenschaltung-01"})`.

### Wenn das Formular die eigene Frage nicht mehr annimmt

Ein per XML importierter Zustand kann die Formularvalidierung verletzen — der
Import prüft weniger als das Formular. Gemessener Fall: eine `essay`-Frage mit
`noinline` und `attachments 0` lässt sich nicht speichern, auch dann nicht,
wenn man nur den Fragetext ändern wollte. Einzelheiten oben beim Fragetyp.

Das Muster ist allgemeiner als dieser eine Fall: **Bricht das Speichern mit
einer Meldung ab, die von Feldern spricht, die du gar nicht angefasst hast,
liegt es nicht an deiner Änderung.** Dann die Meldung lesen — sie nennt die
Bedingung —, die genannten Felder im selben Speichervorgang mitsetzen und dem
Nutzer sagen, was sich dadurch mitändert.

### Was so nicht geht

Strukturänderungen. Eine zusätzliche Antwort (`addanswers`), ein weiterer
Knoten (`prt1nodeadd`) oder ein zusätzliches Eingabefeld entstehen erst nach
einem Klick auf den jeweiligen Knopf und einem weiteren Formulardurchlauf, weil
das Formular sich dabei selbst neu aufbaut. Auch die STACK-Testfälle stehen
nicht in diesem Formular, sondern auf der Testseite.

Für solche Umbauten ist eine **neue Frage** der ehrlichere Weg. Die alte dann
nicht stillschweigend entsorgen: Ob die alte Fassung weg soll, entscheidet
der Nutzer; erst dann `fragen_loeschen`.
