# Changelog

## Unveröffentlicht
- Sichtbarkeit: Nach dem Umschalten prüft die KI, ob „verfügbar ohne Link“ noch gesetzt ist, und stellt es nach Rückfrage wieder her.
- Übertragung: Steht ein Ziel nach einem Abbruch auf „unklar“, nennt die App die Nummer des Vorgangs, damit sich der Stand mit der Statusabfrage klären lässt.
- Speichern: Hält ein Schutzdienst vor Moodle das Speichern an oder weist es ab, sagt die App es klar und übergibt es an Sie, damit Sie selbst im Browser speichern – beim Ändern, bei mehreren Seiten auf einmal, beim Setzen von Links und beim Anlegen, auch mit neuen Bildern und Dateien. Die App meldet nur dann „verified", wenn Moodle danach den übergebenen Stand zeigt.
- Speichern im Browser: Der Inhalt lässt sich unter Windows in der gewöhnlichen Editoransicht einfügen, mit Kästen, Tabellen, Bildern und Code-Blöcken; auf dem Mac liegt er als Text in der Zwischenablage. Die Schritte gehen der Reihe nach, und zeigt Moodle den neuen Stand noch nicht, lässt sich so oft neu prüfen, wie Sie wollen.
- Anmeldung: Hält ein Schutzdienst vor Moodle die Anmeldung an, gilt das nicht als falsches Passwort; Ihre Zugangsdaten bleiben, und das Protokoll nennt die Ray-ID für den Betreiber.
- Neu angelegte Textfelder: Die Rückleseprobe prüft keinen Namen mehr, den ein Textfeld gar nicht hat.
- Ändern: Wer unverändert neu speichert, bekommt „verified" nicht mehr ohne eine einzige Prüfung; eine Frage ohne neue Version wird als Abweichung gemeldet.

## 0.9.32
- Fragen: Muss eine Frage neu angelegt werden, etwa weil sich ihr Aufbau ändert, tauscht die KI sie in einem Schritt und mit einer Freigabe aus – die neue steht im Test an derselben Stelle mit denselben Punkten, und die alte wird auf Wunsch gelöscht.
- Aufträge mit Quelle: Kann die KI eine genannte Seite nicht lesen, etwa über den Link auf eine einzelne Wikiseite, fragt sie nach, statt ohne die Quelle weiterzuarbeiten.

## 0.9.30
- Boards, Kanban-Boards, Fortschrittslisten und Tests: Die App bestätigt nach dem Ändern selbst, dass alles angekommen ist, und die KI liest nach dem Schreiben nicht mehr eigens nach – das spart Zeit und Kontext.

## 0.9.28
- Speichern: Weist ein Schutzdienst vor Moodle das Speichern gleich ab („Sorry, you have been blocked"), sagt die App es klar und übergibt es an Sie wie bei seiner Prüfung; das Protokoll nennt die Ray-ID für den Betreiber.
- Programmcode in Seiten und Fragen: Weist ein Schutzdienst HTML-Code im Text ab, versucht die KI nicht mehr, betroffene Seiten und Fragen zu ändern, sondern lässt sie stehen und nennt sie Ihnen; neue Fragen mit solchem Code prüft sie vor dem Anlegen vollständig.

## 0.9.26
- Freigaben: Ein Return, eine Leertaste oder ein Klick, der beim Aufgehen des Dialogs noch einem anderen Fenster galt, gibt nichts mehr frei.
- Speichern: Hält ein Schutzdienst vor Moodle das Speichern an, sagt die App es klar und übergibt es an Sie, damit Sie selbst im Browser speichern – beim Ändern, bei mehreren Seiten auf einmal, beim Setzen von Links und beim Anlegen, auch mit neuen Bildern und Dateien; die KI schreibt Programmbeispiele möglichst so, dass es gar nicht dazu kommt.
- Speichern im Browser: Der Inhalt lässt sich in der gewöhnlichen Editoransicht einfügen, ohne Quelltextansicht und mit Kästen, Tabellen, Bildern und Code-Blöcken; die Schritte gehen der Reihe nach, und zeigt Moodle den neuen Stand noch nicht, lässt sich so oft neu prüfen, wie Sie wollen.
- STACK: Varianten lassen sich wieder einsetzen, die Prüfung meldet jeden Testfall statt nur jeden zweiten, und eine Frage mit Zufallswerten ohne Aufgabenhinweis wird gar nicht erst angelegt.
- Programmcode in Seiten und Fragen: Die KI schreibt ihn im Format des Editors mit Syntaxhervorhebung, und Lückenfragen mit Lücken im Code bleiben lösbar.

## 0.9.24
- Freigaben: In Claude Code und Codex verschwindet der Dialog nicht mehr nach einer Minute, und längere Vorgänge wie das Setzen vieler Links laufen zu Ende, statt für die KI scheinbar zu scheitern.
- Lernsituationen: Infoblätter tragen keine Rückverweise auf die Arbeitsblätter mehr, und die Materialübersicht der Handreichung führt Zeichnungen nicht mehr als eigene Zeilen.

## 0.9.22
- Freigaben: Warten weitere Anfragen hinter der offenen, zeigt der Dialog, wie viele, und das Protokoll nennt jede, die sich einreiht.
- Freigaben: Ein abgelaufener Dialog bleibt nicht mehr stehen, wenn schon die nächste Anfrage wartet, und die 30 Minuten zählen ab der Anfrage, auch während sie wartet.

## 0.9.21
- import_from_github.sh hinzugefügt

## 0.9.20
- Dateien: Eine verlinkte HTML-Seite, eine SVG-Zeichnung oder eine Datei in einem Verzeichnis schreibt die KI nur ohne Code; was schon dasteht, nennt sie beim Lesen.
- Interaktive Elemente: Zum Ziehen baut die KI sie so, dass es auch am Handy geht, und Text im Element, der nach Code klingt, bricht das Schreiben nicht mehr ab.
- Abschnitte: Reißt beim Anlegen die Verbindung ab, erfährt die KI auch dann, dass der Abschnitt schon im Kurs steht.
- STACK: Wählt eine neue Frage zufällig einen von mehreren Fällen, kommen alle gleich oft vor.

## 0.9.18
- Neu: interaktive Elemente – kleine Anwendungen zum Ausprobieren und Üben mitten in einer Seite, abgeschottet vom Rest von Moodle; die KI schlägt sie vor, wo sie passen, und Bildschirmfotos zeigen sie samt Fehlern im Skript.
- Seiten: Code direkt im Text schreibt die KI nicht mehr; was schon dasteht, bleibt und wird beim Lesen genannt.
- Abschnitte: Weist Moodle beim Anlegen Name oder Beschreibung ab, erfährt die KI, dass der Abschnitt trotzdem ohne Namen im Kurs steht, und legt keinen zweiten an.

## 0.9.16
- STACK: Rechnungen vorab im CAS ausprobieren geht jetzt auch ohne Administratorrechte; eine Frage ohne Fragetests gilt bei der Prüfung als „ohne Testfälle", nicht mehr als „nicht bestanden".
- STACK: Neue Fragen prüfen auf Wunsch, ob ein Bruch gekürzt oder wie abgezählt angegeben ist, zeigen Geldbeträge mit festen Nachkommastellen (1,50 €) und erkennen ein verrutschtes Komma; Zufallswerte baut die KI so, dass keine trivialen Aufgaben entstehen.
- Blätter übernehmen: Einen fachlichen Fehler im Material nennt die KI im Plan, mit einer Korrektur als Vorschlag.

## 0.9.14
- Neu: Die KI schlägt vor, welche Aktivität und welcher Fragetyp sich wofür anbietet – auch Board, Kanban-Board, Wiki, Fortschrittsliste und Übungstest, am Gerät, auf Papier oder gemischt, etwa ein Schritt im Computerraum oder ein abfotografiertes Blatt als Abgabe.
- Neu: Steckbrief des Kurses – Schulform, Anrede, Arbeitsweise und Ausstattung fragt die KI einmal und hält sie nach Ihrem Ja in den Konventionen des Kurses fest; auch für Lernsituationen.
- Tests: Die KI klärt zuerst, wozu ein Test dient – Übung, Selbstkontrolle, Diagnose oder Leistungsfeststellung – und schlägt die Einstellungen danach vor.
- Konventionen des Kurses: kein Fehlalarm mehr, nur weil darin von Bewertung, Abgabe oder Noten die Rede ist.
- Freigaben: Was die KI gerade verborgen angelegt hat, füllt sie bei „mittel" ohne Rückfrage – etwa die Spalten eines neuen Boards oder die Links zwischen den Blättern einer neuen Lernsituation.
- Fortschrittslisten: Neue Einträge entstehen auf Wunsch gleich als Überschrift oder optional.
- Lernsituationen: Neben den Blättern gehört jetzt jede Aktivität dazu, die die KI anlegt – Board, Kanban-Board, Wiki, Fortschrittsliste, Test mit Fragen, Verzeichnis, Datei, Link –, und die Blätter verlinken sie mit ihrem Namen.
- Fragen: Neue Fragen kommen in eine eigene Fragensammlung je Lernsituation oder Thema, nicht mehr in die Sammlung des ganzen Kurses.

## 0.9.12
- Zeichnungen in STACK-Fragen: Eingaben mit Großbuchstaben im Namen (etwa „ansG") lassen sich an die Zeichnung binden; Regler zeigen die Einheit hinter dem Wert.

## 0.9.10
- STACK: Neu angelegte Fragen mit Auswahlliste lassen sich nachträglich ändern.
- Neu: Zeichnungen in STACK-Fragen (JSXGraph) – aus den Zufallswerten gezeichnet oder zum Ziehen, mit Hinweisen, wann sie sich lohnen; geladen wird nur, was von Ihrem Moodle kommt.
- Bildschirmfotos: zeigen auch Zeichnungen in STACK-Fragen; eingebettete Rahmen laden nichts mehr an der App vorbei.
- STACK: In neuen Fragen mit mehreren Teilen meldet ein unbearbeiteter Teil „nicht bearbeitet – 0 Punkte", ohne Punktabzug.
- Fragen mit Zahlenergebnis: Neue Fragen nennen Einheit und Rundung im Text und werten danach – jede richtig gerundete Antwort zählt. In STACK lassen sich Zahl und Einheit eintippen, wie man sie schreibt („66,7 mA"), und andere Vorsätze werden umgerechnet.

## 0.9.8
- Neu: moocp arbeitet außer mit Claude Code auch mit Codex CLI und LM Studio – eingerichtet im Dialog „KI-Werkzeuge einrichten", jedes Werkzeug lässt sich dort abwählen; das Protokoll zeigt, welches sich verbunden hat. Mit LM Studio startet moocp bei Bedarf von selbst.
- Neu: Der Installer zeigt vor der Installation den Hinweis zur Nutzung – eigene Verantwortung, und was vorher mit Schulleitung, Datenschutz und Moodle-Betreiber zu klären ist; „Weiter" wird dort nach zehn Sekunden aktiv.
- Installer: Die Lizenz zeigt Sonderzeichen wieder richtig an.
- Neu: Oben im Fenster stellen Sie ein, wie oft die App vor einer Änderung fragt – alle, mittel oder keine Bestätigungen.
- Freigaben: Wartet das KI-Werkzeug nicht mehr auf die Antwort, schließt sich der Dialog, und es wird nichts geschrieben.
- Neu: Konventionen und Arbeitsdateien der KI liegen im verborgenen Verzeichnis „CLAUDE" statt auf einer Kursseite – je Kurs und je Abschnitt.
- Die KI liest die Konventionen eines Kurses von selbst und schlägt vor, welche festzuhalten sind.
- Verzeichnisse: Bessere Darstellung der Änderungen vor der Freigabe.
- Drucken: Eine Seite, die im Wesentlichen aus einer breiten Zeichnung besteht, kann quer gedruckt werden.
- Bildschirmfotos: Lange Seiten werden zwischen den Zeilen geteilt statt mitten hindurch; klarere Meldungen bei zu knappem Grund und zu dem, was der Browser nicht geladen hat.
- Arbeitsordner: keine eigene Vorschau gelesener Seiten mehr – wie eine Seite aussieht, zeigt Moodle.
- Wikis: Ein Wiki im Gruppenmodus liest und schreibt die KI nicht mehr, auch solange es leer ist oder der Kurs keine Gruppen hat.

## 0.9.7
- Add Quickstart

## 0.9.6
- Kleinere Korrekturen an der Update-Suche.

## 0.9.4
- Neu: automatische Updates über GitHub, auf Wunsch und nach Rückfrage.
- Neuer Dialog „Einstellungen", in dem jetzt auch „Claude einrichten" steckt.

## 0.9.2
- Fragensammlungen: Probleme beim Anlegen, Melden und Löschen behoben.
- STACK: Problem mit Testeingaben behoben.
- Freigaben: Eine Freigabe wirkt nicht mehr, wenn sich das Objekt inzwischen geändert hat.

## 0.9.0
- erste Veröffentlichung
