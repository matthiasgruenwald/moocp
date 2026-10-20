/* Gemeinsamer Doku-Block der Skills, die in Moodle schreiben: Geschriebenes
 * selbst ansehen (Werkzeug bildschirmfoto). build.py setzt ihn zwischen die
 * Marker in SKILL.md. Nicht dort bearbeiten.
 */

## Selbst nachsehen: Bildschirmfotos

`bildschirmfoto` zeigt dir, wie eine Textseite, ein Buchkapitel, eine Seite eines gemeinsamen Wikis, eine Lernlandkarte oder eine Frage in der Vorschau im Browser aussieht — mit `druck: true` bei Seite, Buch und Wiki so, wie sie gedruckt wird. Eine Lernlandkarte wird nur am Bildschirm und nur im Kartenbereich gezeigt. Das Bild zeigt den Inhalt, ohne Kopf, Navigation und Blöcke.

**Wofür:** prüfen, was du geschrieben hast, wo der Quelltext es nicht verrät — ob Formeln gesetzt sind, wie ein Blatt im Ausdruck umbricht, ob eine Lernlandkarte im Kartenbereich korrekt dargestellt wird oder eine Frage in der Vorschau läuft und richtig aussieht. Bitte die Lehrkraft nicht um ein Bildschirmfoto, wenn du selbst nachsehen kannst.

**Nicht wofür:** zum Lesen von Inhalten — das tun die Lesewerkzeuge, vollständig und als Text. Und nicht routinemäßig nach jedem Schreiben: Jedes Bild erscheint in der App, und die Lehrkraft muss es freigeben.

- `grund` ist Pflicht: ein Satz für die Lehrkraft, was das Bild prüfen soll („Prüfen, ob die Formeln auf Infoblatt 2 gesetzt werden"). Er steht im Dialog über dem Bild.
- Geplante Bilder gehören in den Plan, und vor jedem kündigst du die Freigabe im Chat an.
- Verwirft die Lehrkraft das Bild, ist das ihre Entscheidung — frag nicht nach, sondern beschreib, was du prüfen wolltest, und lass sie selbst nachsehen.
- Meldet das Werkzeug, dass der Browser nicht steuerbar ist, gibt es auf diesem Rechner keine Bildschirmfotos. Weich nicht aus; die Lehrkraft sieht selbst nach.
- Kleine Abweichungen sind keine Befunde: Schriften von fremden Servern (etwa Google Fonts) fehlen, dort steht eine Ersatzschrift, und Formeln wirken etwas kräftiger.

Nur im ausdrücklich gebundenen Debug-Testbetrieb kann die App Bilder eigener verborgener ZZ-Textseiten und ZZ-Lernlandkarten in freigegebenen Testkursen automatisch freigeben. Eine Lernlandkarte muss in derselben App-Sitzung angelegt und zurückgelesen worden sein; zusätzlich müssen Profilkennung, tatsächliche Instanzadresse und Kurs passen. Lernlandkarten-Bilder brauchen außerdem `screenshots: true`. Das Werkzeug meldet diese Ausnahme ausdrücklich. Schalte sie nicht selbst ein und übertrage sie nicht auf andere Inhalte: Im normalen Betrieb bleibt jedes Bild persönlich freizugeben. Auch ein automatisch ausgegebenes PNG öffnest du selbst und vergleichst es mit dem zurückgelesenen Soll; eine ausgegebene Datei allein belegt keine Sichtprüfung.
