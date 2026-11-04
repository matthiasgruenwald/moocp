/* Gemeinsamer Block: die HTML-Regeln, kurz. Gilt für alles, was in Moodle
 * steht -- Aktivitäten, Fragen, Blätter einer Lernsituation. build.py setzt
 * ihn in die SKILL.md von moodle, moodle-fragen und lernsituation; die
 * ausführliche Fassung (html.md) steht in references/html.md jedes dieser
 * Skills. Was nur ein Skill braucht, steht bei ihm hinter dem Block.
 */
## HTML schreiben

Alles, was in Moodle steht, ist HTML: Textseite, Textfeld, Aufgabe, Buchkapitel, Beschreibung, Fragetext und Feedback — und die Blätter einer Lernsituation schon im Entwurf. Überall gelten dieselben Regeln. Die ausführliche Fassung mit Gründen, Beispielen und allen gemessenen Klassen steht in **`references/html.md`**; lies sie, sobald du mehr brauchst als Absätze und Listen — Tabellen mit eigenen Linien, Kästen, Bilder, Formeln, Platz zum Ausfüllen.

**Bedeutung, nicht Aussehen** („What you see is what you mean"). Das HTML sagt, was etwas ist — Überschrift, Merksatz, Tabelle —; wie es aussieht, bestimmen die Stylesheets der Instanz, am Bildschirm wie im Druck.

- **Keine `style`-Attribute.** Zwei Ausnahmen: die SchuCu-Tabelle einer Lernsituation, die Zeichen für Zeichen nach ihrer Vorlage übernommen wird, und Rahmenlinien an Tabellenelementen, wo die Linie die Aussage trägt — nur Stärke und Art, keine Farbe, und erst, wenn die Randklassen nicht reichen.
- **Überschriften beginnen bei `<h3>`.** `<h1>` und `<h2>` sind Moodle vorbehalten: `h1` trägt den Namen der Aktivität, `h2` gehört zur Seitenstruktur des Themes. Darunter `<h4>`, `<h5>`, ohne eine Ebene zu überspringen. Eine Überschrift ist ein echtes `<h*>`, kein fett gesetzter Absatz, und der Name der Aktivität steht nicht noch einmal oben im Inhalt.
- **Blöcke auf oberster Ebene** — `<h3>`, `<p>`, `<ul>`, `<table>` nacheinander, ohne Hülle um den ganzen Inhalt.
- **`<strong>` und `<em>`**, nie `<b>`, `<i>`, `<font>`, `<center>` und nie `<u>` (sieht aus wie ein Link). Echte Listen statt „1." im Absatz. Keine festen Breiten, keine `&nbsp;`-Ketten zum Einrücken, keine leeren Absätze als Abstand, keine Word-Reste (`class="Mso…"`), kein Markdown (`**`, `#`, `[…](…)`).
- **Tabellen immer mit Klasse** (`table table-bordered`). **Kästen** mit `alert alert-info` (Hinweis, Merksatz), `alert-warning` (Achtung), `alert-danger` (Gefahr), `alert-success` (Beispiel). Farbe ist nie die einzige Aussage — ein Kasten sagt mit seinem ersten Wort, was er ist („**Achtung:**") —, und es gibt **höchstens zwei Kastenarten je Seite**. Klassen in der Bootstrap-5-Schreibweise (`ms-3`, `text-start`, `fw-bold`).
- **Bilder** liegen als Datei in `dateien/` und stehen im Text als `<img src="@@PLUGINFILE@@/<name>" alt="…" class="img-fluid">` — nie mit einer `pluginfile.php`-Adresse, nie vom fremden Server. `alt` beschreibt, was zu sehen ist, nicht den Dateinamen.
- **Links** sagen mit ihrem Text, wohin sie führen, nie „hier" oder „Link"; eine Adresse, die gedruckt zählt, steht ausgeschrieben, ganz und ohne Kurzlink; immer `https://`, nie `//`. Ein Link auf eine Aktivität im Kurs ist absolut, `https://<Moodle aus status>/mod/<typ>/view.php?id=<cmid>`, mit ihrem Namen als Text — innerhalb einer Lernsituation mit ihrer Kennung („Infoblatt 1"), und diese Links setzt die App mit `links_setzen`.
- **Formeln** in LaTeX, `\( … \)` im Text und `\[ … \]` abgesetzt — erst, wenn `kurs_filter(kurs)` „Formeln: JA" meldet. `<` als `&lt;`, `&` als `&amp;`, Dezimalkomma `2{,}5`. Ein rohes `<` zerstört die Formel; an solchen Formelfehlern bricht die App das Schreiben ab, auch an alten, und die Reparatur gehört in den Plan.
- **Kein Code im Text:** kein `<script>`, keine `on…`-Attribute, kein `javascript:`, kein `srcdoc`. Code im Text liefe ohne Abschottung bei jedem Betrachter, auch bei der Lehrkraft; die App weist neuen ab. Interaktives kommt als Element in einen abgeschotteten Rahmen — in Kursinhalten, nicht in Fragen (Skill `moodle`, `references/elemente.md`). Programmcode zum Lesen ist davon nicht betroffen: Er steht als `<pre class="language-…"><code>…</code></pre>` (`references/html.md`, „Code").
- **Kein Kopf, kein Fuß, keine Seitenzahl, kein Feld für Name und Datum** im Inhalt: Moodle zeigt den Namen darüber, und beim Drucken setzt der Druck Kopf und Fuß.
- **Umlaute bleiben Umlaute** — „Uebertragungsmedium" auf einem Blatt ist ein Mangel, kein Ausweg.

Die meisten dieser Regeln prüft die App beim Lesen jeder Aktivität und nennt Verstöße unter „Befunde"; bei einer Lernsituation prüft sie das Prüfskript schon am Entwurf.
