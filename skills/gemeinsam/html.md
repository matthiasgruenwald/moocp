/* Gemeinsamer Block: die HTML-Regeln, ausführlich, samt den gemessenen
 * Bootstrap-Klassen. build.py setzt ihn in references/html.md von moodle,
 * moodle-fragen und lernsituation; die Kurzfassung (html-kurz.md) steht im
 * SKILL.md. Dieselben Regeln prüfen die App beim Lesen
 * (lib/moodle/auswertung.dart) und das Prüfskript des Skills lernsituation am
 * Entwurf (HtmlRegeln); die Grenze für Rahmenlinien steht in allen drei --
 * wer sie ändert, ändert alle. Ebenso die Formelfehler (lib/moodle/formeln.dart,
 * formel_fehler im Prüfskript); an ihnen bricht die App das Schreiben ab.
 */
# HTML schreiben

Alles, was in Moodle steht, ist HTML: Textseite, Textfeld, Aufgabe, Buchkapitel, Beschreibung eines Abschnitts, Fragetext, Feedback und Erwartungshorizont — und die Blätter einer Lernsituation schon im Entwurf. Für alles gelten dieselben Regeln. Was ein Skill zusätzlich braucht, steht bei ihm: die Stellen einer Frage, an denen gar kein HTML stehen darf, die Druckaufbereitung mancher Instanzen, die festen Formen der Blätter einer Lernsituation.

Die Regeln sind keine Geschmacksfrage. Die App prüft die meisten beim Lesen jeder Aktivität und nennt Verstöße unter „Befunde"; das Prüfskript des Skills `lernsituation` prüft sie am Entwurf, bevor etwas in Moodle steht. Wo hier „gemessen" steht, ist es auf der Testinstanz ausprobiert: Probeknoten in eine Seite gehängt, die berechneten Stile ausgelesen, eine erfundene Klasse als Kontrolle; „wirkt nicht" heißt, es sieht aus wie ohne Klasse.

## Bedeutung, nicht Aussehen

„What you see is what you mean": Das HTML sagt, was etwas *ist* — eine Überschrift, ein Merksatz, eine Tabelle, eine Warnung. Wie es aussieht, bestimmen die Stylesheets der Instanz, am Bildschirm wie im Druck, und damit das Corporate Design. Ein Inhalt sieht danach aus wie jede andere Seite im Kurs, und so soll es sein.

```html
<h3>Überschrift</h3>
<p>Fließtext mit <strong>Betonung</strong> und <em>Hervorhebung</em>.</p>
<ul><li>Aufzählung</li></ul>
<ol><li>Nummerierte Schritte</li></ol>
<p>Mehr dazu: <a href="https://www.muster-gmbh.example/datenblatt">https://www.muster-gmbh.example/datenblatt</a></p>
```

Eine Klasse kommt dazu, wenn sie Bedeutung trägt, die das Theme von sich aus nicht zeigt — ein Kasten für einen Merksatz, die Linien einer Tabelle —, nicht, um etwas hübscher zu machen. Wer ein Aussehen nachbaut — Schriftgröße, Farbe, Einzug, Abstand —, baut es gegen das Theme: Der Kurs wirkt zusammengewürfelt, und beim nächsten Theme-Wechsel stimmt nichts mehr.

## Keine style-Attribute

Das Theme setzt das Aussehen global. Jedes Inline-Style hebelt es für diesen einen Inhalt aus, und ein `style="color:#003366"` überlebt keinen Theme-Wechsel.

**Zwei Ausnahmen.** Die **SchuCu-Tabelle einer Lernsituation** (`<table class="lernsituation">`, Skill `lernsituation`) folgt einer fein abgestimmten Vorlage mit `style`-Angaben und `&nbsp;` in den Abstandszellen; sie wird Zeichen für Zeichen übernommen, und nichts daran wird „aufgeräumt" — auch nicht beim Ändern der Seite. Und **Rahmenlinien an Tabellenelementen**, wo die Linie die Aussage trägt und die Randklassen nicht reichen — eng umgrenzt, unten unter „Wenn die Linien die Aussage tragen".

Ein **interaktives Element** ist keine Ausnahme davon, sondern ein eigenes Dokument in seinem Rahmen: Dort trägt ein `<style>`-Block die Anordnung, Farben und Schriften kommen auch dort vom Theme, außer in einer Zeichnung nach dem Hausstil (Skill `moodle`, `references/elemente.md`). Für die Seite, in der es steht, gilt alles hier.

## Überschriften: Inhalt beginnt bei h3

**`<h1>` und `<h2>` sind Moodle vorbehalten.** `h1` trägt den Namen der Aktivität oder den Seitentitel, `h2` gehört zur Seitenstruktur des Themes. Wer sie im Inhalt verwendet, konkurriert mit der Seitengliederung: Die Dokumentstruktur wird für Screenreader unbrauchbar, und im Theme sieht die Überschrift aus wie ein Seitentitel.

**Inhaltsüberschriften beginnen deshalb bei `<h3>`**, Unterpunkte mit `<h4>`, `<h5>`. Keine Ebene überspringen — auf `<h3>` folgt `<h4>`, nicht `<h5>`.

**Nur echte `<h*>` sind Überschriften.** Screenreader, Inhaltsverzeichnisse und Druckaufbereitungen erkennen nur sie; ein fett gesetzter Absatz zählt nicht, und im Druck hält nur eine echte Überschrift mit ihrem folgenden Absatz zusammen.

**Der Name steht nicht noch einmal im Inhalt.** Moodle zeigt den Namen der Aktivität als `h1` darüber, im Ausdruck ebenso; eine erste Zeile mit demselben Titel steht dann doppelt da. Im Buch ist der Kapiteltitel die Überschrift des Kapitels, der Inhalt darin beginnt wieder bei `<h3>`. In Fragen braucht man Überschriften selten; wenn doch — ein langer Erwartungshorizont, eine Situationsbeschreibung —, dann ebenso ab `<h3>`.

## Blöcke auf oberster Ebene

`<h3>`, `<p>`, `<ul>`, `<table>`, `<div class="alert …">` stehen nacheinander auf oberster Ebene, **ohne umschließendes `<div>` oder `<span>` um den ganzen Inhalt**. Eine Hülle trägt keine Bedeutung und stört alles, was den Inhalt nach Blöcken verarbeitet — den Editor, eine Druckaufbereitung, die ihre Seiten nach der Höhe jedes Blocks umbricht.

Soll ein Element leer bleiben und trotzdem wirken (ein Feld zum Ausfüllen), ist es ein `<div>`, nie ein `<span>`: Der Moodle-Editor (TinyMCE) entfernt leere `span` schon beim Öffnen einer Seite; speichert jemand die Seite danach von Hand, ist es weg. Ein leeres `div` lässt er stehen und füllt es nur mit `&nbsp;` (gemessen 30.09.2026).

## Was etwas ist — und wie es geschrieben wird

| Was es ist | HTML |
|---|---|
| Überschrift, auch eine nur fett gesetzte Zeile, die als Überschrift dient | `<h3>`, darunter `<h4>` |
| Betonung, Hervorhebung | `<strong>`, `<em>` — nie `<b>`, `<i>`, und nie `<u>`: Unterstrichenes hält jeder für einen Link |
| Aufzählung, nummerierte Schritte | echte Listen `<ul>` / `<ol>`, nicht „1." oder „–" am Anfang eines Absatzes |
| Hinweis, Merksatz, Definition | `<div class="alert alert-info">` |
| Achtung, häufiger Fehler | `<div class="alert alert-warning">`, beginnt mit „**Achtung:**" |
| Gefahr, Sicherheitshinweis | `<div class="alert alert-danger">`, beginnt mit „**Gefahr:**" |
| Beispiel, vorgerechnete Aufgabe | `<div class="alert alert-success">` |
| Rahmen ohne besondere Bedeutung | `<div class="border rounded p-3">` |
| Tabelle | `<table class="table table-bordered">`, Kopfzeile in `<thead>` mit `<th>` |
| Bild, Foto | Datei in `dateien/`, `<img src="@@PLUGINFILE@@/<name>" alt="…" class="img-fluid">` |
| Zeichnung | selbst gezeichnet als SVG-Datei, eingebunden wie ein Bild (`references/zeichnungen.md`) |
| Befehl, Dateiname, Code im Text | `<code>`; mehrzeilig `<pre class="language-…"><code>…</code></pre>` (unten „Code") |
| Link | Text sagt, wohin; Adresse ausgeschrieben, wo sie gedruckt zählt (unten „Links") |
| Kopf- und Fußzeile, Logo, Seitenzahl, Feld für Name und Datum | entfällt — Moodle zeigt den Namen der Aktivität darüber, und beim Drucken setzt der Druck Kopf und Fuß |
| Formel, auch ein einzelnes Formelzeichen im Text | LaTeX: `\( … \)` im Text, `\[ … \]` abgesetzt — nur wenn `kurs_filter` „Formeln: JA" meldet (unten „Formeln") |

## Code

Mehrzeiliger Code steht so, wie der Editor ihn mit seinem Code-Werkzeug einfügt, damit die Lehrkraft ihn dort später weiterbearbeiten kann:

```html
<pre class="language-javascript"><code>function summe(a, b) {
  return a + b;
}</code></pre>
```

- **Die Klasse nennt die Sprache:** `language-markup` für HTML und XML, sonst `language-javascript`, `language-python`, `language-java`, `language-sql`, `language-css` usw. Ist auf der Instanz ein Code-Highlighter an (`kurs_filter`), färbt er danach ein; ist keiner an, bleibt es ein gewöhnlicher Block in fester Breite – richtig ist die Form in beiden Fällen.
- **`<`, `>` und `&` im Code als `&lt;`, `&gt;`, `&amp;`**, sonst hält Moodle sie für HTML.
- **Keine Zeilen aus `<code>…</code><br>` in einem Absatz**, auch wenn der Kurs es schon so hat – das ist kein Block, und der Editor kann es nicht als Code bearbeiten. Was so schon in Moodle steht, wird als Befund gemeldet, nicht nebenbei umgebaut.
- **Ausnahme Lücken in Fragen:** Steht eine Lücke im Code, gilt im Skill `moodle-fragen` `references/fragetypen.md`, „Lücken im Code".
- **Beispielcode möglichst ohne Ereignis-Attribute:** `knopf.addEventListener("click", berechne)` statt `<button onclick="berechne()">`, außer das Attribut ist selbst der Lernstoff. Auch als Text in `<pre><code>` hält ein Schutzdienst vor manchen Instanzen ein Formular mit `onclick=` und ähnlichem für einen Angriff und das Speichern an.
- **HTML-Code als Text** (`&lt;p id="…"&gt;`, `&lt;input …&gt;`) weist ein Schutzdienst vor manchen Instanzen in jedem Formular ab, in jeder Auszeichnung und auch aus dem Browser der Lehrkraft; reines JavaScript ohne Tag kam durch, ein Import auch mit HTML-Code (auf der Testinstanz gemessen, 29.10.2026). Abgewiesen wird der ganze Inhalt, nicht die Änderung: Steht solcher Code schon in einer Seite oder Frage, lässt sie sich über das Formular gar nicht mehr ändern, auch nicht an anderen Feldern. Hat ein Werkzeug das im Auftrag einmal gemeldet, gilt es für alle weiteren Formulare dieser Instanz: Objekte mit HTML-Code im Text nicht mehr zu ändern versuchen, sondern so lassen und der Lehrkraft am Ende auflisten; neue Fragen mit HTML-Code vor dem Import vollständig prüfen, denn danach lässt sich nichts mehr korrigieren; CodeRunner-Fragen mit HTML-Code im Text gehen dann gar nicht (sie müssen einmal über das Formular). Den Code nie tarnen, um durchzukommen (Ersatzzeichen, Umkodierung, Code als Bild): Er muss für Lernende richtig und kopierbar bleiben.
- **Meldet ein Werkzeug, der Schutzdienst habe das Speichern angehalten oder abgewiesen, oder lehnt Moodle ein Formular mit HTTP 403 ab:** nicht noch einmal versuchen und keinen Umweg nehmen, etwa löschen und neu anlegen oder neu importieren – das zerreißt Versionen und Verwendung in Tests. Beim Schutzdienst bittet die App die Lehrkraft, selbst im Browser zu speichern; danach sagt die Antwort, was in Moodle steht. Hat er abgewiesen, gelingt das im Browser oft auch nicht; dann bleibt es, wie es ist. Beim HTTP 403 ohne diese Bitte anhalten und die Lehrkraft fragen, wie bei jeder Lücke: Sie ändert es selbst in Moodle, und du sagst genau, wo und was. Weiter geht es nur mit frisch Gelesenem.

## Tabellen

Hier lohnt sich eine Klasse immer — eine nackte `<table>` steht in vielen Themes ohne Linien und Abstände da.

```html
<table class="table table-bordered">
  <thead><tr><th>Merkmal</th><th>Bedeutung</th></tr></thead>
  <tbody><tr><td>…</td><td>…</td></tr></tbody>
</table>
```

| Klasse | Wirkung |
|---|---|
| `table` | Grundformatierung — bei Tabellen immer |
| `table-bordered` | Linien um alle Zellen |
| `table-borderless` | keine Linien zwischen den Zellen (gemessen 25.09.2026) |
| `table-striped` | abwechselnd eingefärbte Zeilen |
| `table-sm` | kompaktere Zeilen |
| `table-responsive` | als Wrapper-`<div>`, macht breite Tabellen scrollbar |

Viel Text gehört nicht in eine Zelle, sondern in Absätze unter der Tabelle: Eine hohe Zeile liest sich schlecht, und eine Druckaufbereitung zerteilt sie nicht.

### Wenn die Linien die Aussage tragen

Manche Tabellen ergeben erst mit *ihren* Linien Sinn: das T-Konto (eine Linie unter Soll und Haben, eine in der Mitte), das Kalkulationsschema (ein Strich über der Zwischensumme, ein Doppelstrich über der Summe), eine Tabelle, deren Spaltengruppen eine kräftigere Linie trennt. `table-bordered` zieht alle Linien oder keine; hier werden sie einzeln gesetzt — **zuerst mit Klassen**, gemessen am 25.09.2026 in Anzeige und Druck:

```html
<table class="table border-0">
  <thead>
    <tr><th class="border-0 border-bottom border-2 border-dark">Soll</th>
        <th class="border-0 border-bottom border-start border-2 border-dark">Haben</th></tr>
  </thead>
  <tbody>
    <tr><td class="border-0">Anfangsbestand 5.000,00 €</td>
        <td class="border-0 border-start border-2 border-dark">Abgang 1.200,00 €</td></tr>
  </tbody>
</table>
```

Drei Dinge daran sind nicht verhandelbar, jedes hat ohne sich einen sichtbaren Fehler erzeugt:

- **`border-0` an der Tabelle.** Das Theme zieht über `table` eine dünne graue Linie; ohne `border-0` steht sie über der ersten Zeile, auch bei `table-borderless`.
- **`border-0` zuerst an jeder Zelle, die Linien bekommt**, dann die Seiten (`border-top`, `border-bottom`, `border-start`, `border-end`). Jede Zelle hat hier an allen vier Seiten die Linienart „durchgezogen", nur mit Breite 0; `border-2` allein macht daraus einen grauen Kasten um die Zelle.
- **`border-dark`.** Ohne Farbklasse ist die Linie das helle Grau des Themes und sieht aus wie ein Versehen.

**Was Klassen nicht können, darf `style`** — etwa den Doppelstrich unter einer Summe. Das ist die einzige Stelle neben der SchuCu-Tabelle, an der `style` erlaubt ist, und auch hier eng: nur an Tabellenelementen (`table`, `thead`, `tbody`, `tfoot`, `tr`, `th`, `td`, `col`, `colgroup`), nur Rahmenlinien (`border`, `border-top`/`-right`/`-bottom`/`-left` und deren `-width` und `-style`), nur Stärke und Art, **keine Farbe** — ohne Farbangabe folgt die Linie der Textfarbe, am Bildschirm wie im Druck. Breite, Höhe, Schrift, Hintergrund und Ausrichtung gehören auch an einer Tabelle nicht in `style`.

```html
<table class="table table-borderless border-0">
  <tbody>
    <tr><td>Zwischensumme</td><td class="text-end">900,00 €</td></tr>
    <tr><td>+ 19 % Umsatzsteuer</td><td class="text-end">171,00 €</td></tr>
    <tr><td style="border-top: 4px double;">Summe</td>
        <td class="text-end" style="border-top: 4px double;">1.071,00 €</td></tr>
  </tbody>
</table>
```

An einer Zelle mit `style`-Linie **keine** Randklasse: Die Klassen wirken mit Vorrang (`!important`), `border-0` daneben löscht die Linie wieder.

## Kästen und besondere Absätze

Merkkasten, Achtung-Hinweis, Beispielblock — dafür gibt es fertige Klassen. Gemessen wirken alle folgenden:

| Muster | Wofür | Gemessen |
|---|---|---|
| `<div class="alert alert-info">` | Hinweis, Merksatz | eigener Hintergrund, Rahmen, Innenabstand |
| `<div class="alert alert-warning">` | Achtung, häufiger Fehler | dito, gelblich |
| `<div class="alert alert-success">` | Beispiel, Bestätigung | dito, grünlich |
| `<div class="alert alert-danger">` | Gefahr, Sicherheitshinweis | dito, rötlich |
| `<div class="alert alert-secondary">` | neutraler Kasten | dito, grau |
| `<blockquote class="blockquote">` | Zitat | größere Schrift |
| `<footer class="blockquote-footer">` | Quelle unter dem Zitat | kleiner, gedämpft |
| `<p class="lead">` | Vorspann, erster Absatz | größere Schrift |
| `<p class="small">` | Kleingedrucktes | kleinere Schrift |
| `<span class="text-muted">` | zurückgenommen, z. B. Quellenangabe | blassere Farbe |
| `<span class="badge bg-primary">` | kurze Auszeichnung, Schlagwort | farbiger Hintergrund, fett, klein |
| `<div class="border rounded p-3">` | schlichter Kasten ohne Farbe | Rahmen, Ecken, Innenabstand |

**Farbe darf nicht die einzige Aussage sein.** Ein `alert-danger` muss auch ohne seine Farbe als Warnung lesbar sein — also mit einem Wort beginnen, das es sagt („**Achtung:**", „**Gefahr:**"). Sonst geht die Information für einen Teil der Klasse verloren, und im schwarz-weißen Ausdruck ohnehin.

**Nicht mehr als zwei Kastenarten je Seite.** Wer Hinweis, Achtung, Beispiel, Merksatz und Zusammenfassung in fünf Farben nebeneinanderstellt, hat keine Gliederung gebaut, sondern eine Ampelanlage. Hat eine Vorlage mehr, ordne nach der Bedeutung zu und fasse zusammen, was dasselbe meint.

**Eine Lösung steht nie auf einer Seite für Lernende**, auch nicht in einem Kasten oder einem aufklappbaren Element: Sie ist dort lesbar, im Quelltext ohnehin. Sie gehört auf eine eigene, verborgene Seite. (In einer Frage ist das Feedback der Ort dafür; Moodle zeigt es erst nach dem Versuch.)

### Karten und Listen brauchen ihre Hülle

Diese Klassen wirken **nur innerhalb ihres Elternteils** — allein gesetzt tun sie nichts, ohne dass es auffällt:

```html
<div class="card">
  <div class="card-header">Überschrift der Karte</div>
  <div class="card-body">
    <h5 class="card-title">Titel</h5>
    <p>Inhalt.</p>
  </div>
</div>

<ul class="list-group">
  <li class="list-group-item">Erster Punkt</li>
</ul>
```

Gemessen: `card-body` allein hat keinen Innenabstand, in einer `card` sind es 16 px. Dasselbe bei `list-group-item`. Wer nur die innere Klasse setzt, sieht keinen Fehler — er sieht nur nichts.

Ebenfalls gemessen: `figure` wirkt nicht, `figure-caption` schon. Und `badge` allein hat keinen Hintergrund; die Farbe kommt erst mit `bg-primary`, `bg-success` und so weiter.

## Utility-Klassen: Bootstrap-5-Schreibweise

Bootstrap 4 und 5 benennen Abstand, Ausrichtung und Schriftschnitt unterschiedlich. Die Testinstanz versteht beide Schreibweisen — gemessen am 10.09.2026, mit identischem Ergebnis:

| Bootstrap 4 | Bootstrap 5 | gemessen |
|---|---|---|
| `ml-3` / `mr-2` | `ms-3` / `me-2` | beide 16 px bzw. 8 px |
| `pl-3` | `ps-3` | beide 16 px |
| `text-left` / `text-right` | `text-start` / `text-end` | beide wie erwartet |
| `float-left` | `float-start` | beide links |
| `font-weight-bold` | `fw-bold` | beide 700 |
| `badge-success` | `bg-success` | beide dieselbe Farbe |

Richtungsneutrale Klassen wie `p-3` und `mb-3` heißen in beiden Fassungen gleich.

**Nimm die Bootstrap-5-Schreibweise** (`ms-3`, `text-start`, `fw-bold`, `bg-success`): Die Kompatibilitätsfassung verschwindet irgendwann, und Inhalte leben länger als Moodle-Versionen. Wer bestehende Inhalte liest, findet beides — das ist kein Fehler und muss nicht angefasst werden. **Und in beiden Fällen sparsam:** Unterrichtsmaterial braucht selten Abstände; wer Abstand will, nimmt einen neuen Absatz.

## Bilder

```html
<p><img src="@@PLUGINFILE@@/schaltplan.svg" alt="Reihenschaltung aus zwei Widerständen an 12 V" class="img-fluid"></p>
```

- **Die Datei liegt in `dateien/`** des Ordners, dessen Feld sie einbindet, und steht im Text als `@@PLUGINFILE@@/<name>`. Die App lädt sie in den Entwurfsbereich dieses Felds; Moodle löst den Platzhalter beim Speichern auf. Jedes Feld hat seinen eigenen Entwurfsbereich: Dieselbe Zeichnung in zwei Feldern oder auf zwei Blättern liegt in beiden `dateien/`.
- **Nie eine Adresse selbst eintragen** — keine `pluginfile.php`-Adresse (sie zeigt auf eine Kopie, die beim nächsten Duplizieren des Kurses ins Leere läuft), kein Bild vom fremden Server (es kann verschwinden oder sich ändern, und seine Rechte sind nicht geklärt), keine `data:`-Adresse im Quelltext.
- **Ein Bild ersetzen** heißt: in `dateien/` eine Datei gleichen Namens hineinlegen. Ein neues Bild braucht einen neuen Namen und seinen Verweis im Text.
- **Immer `alt`.** Er beschreibt, was zu sehen ist, nicht den Dateinamen — für Screenreader und für den Fall, dass das Bild fehlt. Leer (`alt=""`) nur bei reiner Dekoration.
- **`class="img-fluid"`** statt `width`, `height` oder `style`: Das Bild passt sich jeder Breite an, auch im Druck.
- Zeichnungen: `references/zeichnungen.md`. Fotos und Bildschirmfotos kommen als PNG oder JPG vom Nutzer, mit geklärter Herkunft.

## Formeln

Mathematische Ausdrücke stehen als LaTeX im HTML, und Moodles Filter MathJax setzt sie im Browser, am Bildschirm wie im Druck. Ob ein Kurs das tut, zeigt `kurs_filter(kurs)`. Ruf es einmal je Kurs auf, bevor die erste Formel geschrieben wird, bei einer Lernsituation also schon vor dem Entwurf. Nur bei „Formeln: JA" schreibst du LaTeX; sonst sähen die Lernenden den Quelltext. Ist MathJax im Kurs aus, nennt die Antwort, wo die Lehrkraft ihn einschaltet; frag sie, ob sie das tut, bevor du Formeln schreibst. Ist er für die ganze Instanz abgeschaltet, ist das eine Lücke, die du meldest.

LaTeX kannst du, und MathJax setzt den Mathematik-Teil davon. Auf der Testinstanz gemessen (01.10.2026): Brüche, Wurzeln, Indizes, `\text{…}` mit Umlauten, `aligned`, `pmatrix`, Summen, Integrale, Grenzwerte und Chemie mit `\ce{…}`. Ganze Dokumente, Pakete, `tabular` und TikZ gibt es nicht; Tabellen bleiben HTML-Tabellen, Zeichnungen SVG. Was hier steht, betrifft das HTML um die Formel:

```html
<p>Nach dem ohmschen Gesetz fließt der Strom \(I = \frac{U}{R}\).</p>
<p>\[ \begin{aligned} P &amp;= U \cdot I \\ &amp;= 230\,\mathrm{V} \cdot 2{,}5\,\mathrm{A} \\ &amp;= 575\,\mathrm{W} \end{aligned} \]</p>
```

- **`\( … \)` im Text, `\[ … \]` abgesetzt**, eine abgesetzte Formel in einem eigenen `<p>`. Einfache Dollarzeichen setzt Moodle nicht — `$E = mc^2$` bleibt so stehen (gemessen) —, ein Preis mit „$" ist deshalb ungefährlich. `$$ … $$` würde gesetzt, aber eine Schreibweise für alles liest sich leichter.
- **`<`, `>` und `&` maskieren**, wie überall im HTML: `&lt;` und `&gt;` (oder `\lt`, `\gt`), `&amp;` in `aligned` und Matrizen. Ein rohes `<` hält der Browser für den Anfang eines Tags. Gemessen: Aus `\(x<y\)` wurde „\(x", der Rest der Formel fehlte, und nichts war gesetzt. Moodle speichert das rohe Zeichen unverändert, die Rückleseprobe sieht also keinen Unterschied — der Fehler fällt erst den Lernenden auf.
- **Kein HTML in der Formel.** MathJax liest den Text zwischen den Begrenzern, nicht die Tags; Hervorhebung und Zeilenumbruch macht LaTeX selbst (`\boldsymbol{…}`, `aligned`).
- **Dezimalkomma in Klammern: `2{,}5`.** Ohne sie setzt LaTeX nach dem Komma einen Abstand wie nach einem Satzzeichen, gemessen „3, 5" statt „3,5". Einheiten stehen aufrecht und mit kleinem Abstand (`230\,\mathrm{V}`, `2{,}5\,\mathrm{k\Omega}`), der Malpunkt ist `\cdot`.
- **Formelzeichen im Fließtext auch als Formel** — „die Spannung \(U\)" —, damit sie aussehen wie in der Gleichung daneben. Keine Bilder von Formeln und kein Nachbau mit `<sup>`, `<sub>` oder „x²": Gesetzt bleibt eine Formel in jeder Größe und im Druck scharf, und sie lässt sich später ändern.
- **Begrenzer werden überall gesetzt, auch in einer Überschrift**, nur nicht in `<code>`. Wer zeigen will, wie man LaTeX schreibt, setzt es deshalb in `<code>` (gemessen).

**Ein Formelfehler ist ein Syntaxfehler, kein Schönheitsfehler.** Eine Formel ohne Ende im selben Absatz (meist ein rohes `<`), HTML in einer Formel oder LaTeX zwischen einfachen `$` — die App bricht jedes Schreiben eines Felds ab, das so etwas enthält, bevor etwas an Moodle geht, auch wenn der Fehler schon vorher in Moodle stand. Beim Lesen stehen solche Stellen unter „FORMELFEHLER", vor den übrigen Befunden. Steht dort einer in einem Feld, das du ändern sollst, gehört die Reparatur in den Plan: Sie ist meist mechanisch (`<` wird `&lt;`), aber sie ändert, was die Lehrkraft geschrieben hat, und braucht deshalb ihr Ja.

## Links

Ein Link ist im Ausdruck nur so viel wert wie sein sichtbarer Text — Kursinhalte werden gedruckt, und im Notfallbetrieb ohne Netz bleibt nur das Papier.

- **Der Linktext sagt, wohin der Link führt.** „Hier", „Link", „mehr", „Video" sagen auf Papier nichts und am Bildschirm wenig. Führt der Link auf eine Seite oder Aktivität, ist ihr Name der Text, genau wie er dort steht; innerhalb einer Lernsituation genügt die Kennung davor („Infoblatt 1").
- **Wo die Adresse zählt** — Quellenangaben, Fundstellen, alles, was man gedruckt nachschlagen soll —, steht sie ausgeschrieben als Linktext oder in Klammern hinter dem Titel: „Erklärvideo VLAN-Tagging (https://…)". Lange Adressen trotzdem ganz, notfalls in einer eigenen Zeile. Keine Kurzlinks: Die sind in ein paar Jahren tot, und niemand sieht mehr, wohin sie führten.
- **Zu jedem Link nach außen ein Halbsatz, wofür** er gebraucht wird und wie lange das dauert („8 min, bis 3:40 reicht").
- **Immer `https://`.** Keine protokollrelativen Adressen (`//…`), die gedruckt unvollständig sind, und kein `http://`.
- **Ein Link auf eine Aktivität im Kurs ist absolut**, mit der Adresse der Instanz aus `status`: `<a href="https://<Moodle aus status>/mod/<typ>/view.php?id=<cmid>">Infoblatt 1</a>`. Nur so erkennt die App ihn beim Lesen als Verweis auf eine Aktivität, prüft den Linktext gegen deren Namen und sieht nach einem Duplizieren, ob er noch auf das Original zeigt. Die Links zwischen den Seiten eines Abschnitts setzt die App selbst (`links_setzen`, Skill `moodle`).

## Platz zum Ausfüllen

Wo Lernende etwas eintragen, hängt der Platz davon ab, wo geantwortet wird:

- **Wird in Moodle abgegeben**, braucht es keinen — die Antwort steht in der Abgabe.
- **Wird das Blatt ausgedruckt ausgefüllt** und meldet `status` die Druckaufbereitung „Aufgabenblatt-Druck", ist es ihr Karofeld (`<div class="ab-loesungsplatz-2"></div>`, je 2 cm ein `div`; im Skill `moodle`, `references/drucken.md`). Ohne Druckaufbereitung genügt eine Tabelle mit leeren Zeilen (`table table-bordered`); die Klassen `ab-…` wirken dort nicht.
- **Der Platz ist immer leer.** Eine Lösung darin wäre gedruckt unsichtbar, steht aber für alle lesbar in der Seite.

Wo geantwortet wird und wie groß der Platz ist, gehört als Vorschlag in den Plan, wenn der Auftrag es nicht schon sagt.

## Was nicht hineingehört

- `<font>`, `<center>`, `<b>`, `<i>`, `<u>` — für Betonung `<strong>` und `<em>`, sonst nichts;
- `style`-Attribute, außer an der SchuCu-Tabelle und für Rahmenlinien an Tabellenelementen;
- feste Pixelbreiten, `width` und `height` an Bildern;
- `&nbsp;`-Ketten zum Einrücken und leere Absätze als Abstand — einrücken tut eine Liste, Abstand setzt das Theme;
- aus Word oder einem Umwandler übernommenes HTML: `class="MsoNormal"`, `<span>`-Hüllen, `style` an jedem Absatz. Die Vorlage liefert Text und Struktur; das HTML wird neu geschrieben;
- eine Hülle um den ganzen Inhalt, `<h1>` und `<h2>`, der Name der Aktivität als erste Zeile;
- Kopf- und Fußzeile, Logo, Seitenzahl, Feld für Name und Datum;
- Markdown — `**fett**`, `# Überschrift`, `[Text](Adresse)`, `` `Code` `` —, das im HTML als Zeichen stehen bleibt;
- Formeln als Bild, mit `<sup>` und `<sub>` nachgebaut oder zwischen einfachen `$`;
- Code: `<script>`, `on…`-Attribute (`onclick` …), `javascript:`-Adressen und `<iframe srcdoc>`. Code im Text läuft ohne Abschottung in der Sitzung jedes Betrachters, auch der Lehrkraft; die App weist neuen ab und nennt alten beim Lesen. Interaktives kommt als Element in einen abgeschotteten Rahmen (Skill `moodle`, `references/elemente.md`), in Fragen gar nicht;
- Umschreibungen von Umlauten: „Uebertragungsmedium" auf einem Blatt ist ein Mangel, kein Ausweg.
