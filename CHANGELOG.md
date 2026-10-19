# Changelog

## 0.9.23
- Lernlandkarten: Eine verborgene Karte lässt sich aus dem nativen Moodle-Formular anlegen; eine skriptfreie `lernlandkarte.json`-Vorlage kann Orte und Wege vorgeben, Ortsziele bleiben gezielt freigabegeschützt änderbar.
- Lernlandkarten: Zieländerungen verfallen, wenn sich Karte, Kurs oder Ziel während der Freigabe ändern; die Rückleseprobe vergleicht SVG, Kartendaten, Einstellungen und übrige Inhalte.
- Debug-Testbetrieb: Eigene verborgene ZZ-Lernlandkarten lassen sich im gebundenen Testumfang ohne persönliche Freigabe ändern und als Bild prüfen.
- Debug-Testbetrieb: Gebundene Testprofile melden sich selbst an; automatische Freigaben einschließlich Inhaltsbildern bleiben auf erlaubte Testkurse und eigene verborgene ZZ-Textseiten begrenzt.
- Änderungen speichern: Die Rückleseprobe wartet nicht mehr auf ihre eigene Ordnersperre.
- Moodle-Profile: Ein nicht mehr benötigtes Profil lässt sich in den Einstellungen löschen; Anmeldung, gespeicherte Zugangsdaten und der Eintrag in Claude Code, Codex und LM Studio werden dabei entfernt, und bleibt einer stehen, sagt die App welcher.
- Deinstallation: Die Einträge aller Moodle-Profile werden aus den KI-Werkzeugen entfernt, nicht nur der Eintrag „moodle“.
- Übertragung: Prüfprobleme bleiben auch bei abgeschlossenen Zielen sichtbar; Zeitlimitantworten nennen den laufenden Vorgang und das passende Statuswerkzeug.
- Wiederholungsschutz: Gescheiterte Wiederholungsversuche geben unklare Vorgänger nicht frei; parallele Übertragungen erhalten gegenseitig ihre Protokolleinträge.
- Wiederherstellung: Geteilte Fragensammlungen werden vor dem Start mit ihren Risiken genannt; unbestätigte Herkunft wird auch ohne Freigabedialog erklärt.
- Wiederherstellung: Die Freigabe nennt nur noch die Aktivitäten, die im Archiv wirklich stehen; leere Zeilen „„“ ()“ aus den Einstellungen des Archivs entfallen, und ein Quiz scheitert nicht mehr an einem angeblich unlesbaren Typ.
- Wiederherstellung: Dateien, die nur im Dateimanager einer Aktivität liegen, meldet die App als nicht lesbar (Prüflücke) statt als „fehlend im Ziel".
- Wiederherstellung: Enthält das Archiv mehrere Tests, vergleicht die App die Fragen je Test; ein Test, den sie nicht zuordnen kann, steht einzeln als Prüflücke. Liegen alle Fragen im Test selbst, gilt ihre Herkunft auch ohne angegebene Sammlung als eigen, auch bei späteren Statusabfragen.
- Wiederherstellung: Meldet Moodle einen Fehler, urteilt die App nicht danach, sondern liest den Zielkurs zurück: vollständig und gleich gilt als verifiziert, Abweichungen werden genannt, und ist das Ende des Hintergrundauftrags nicht belegt, bleibt der Vorgang gesperrt und die Antwort enthält eine fertige Nachfrage an die Verwaltung; „fehlgeschlagen" steht nur noch mit Beleg.
- Wiederherstellung: Fragenvergleiche bleiben nach Neustarts erhalten; unklare Versionen und eine nicht belegte Quellherkunft bleiben ausdrücklich Prüflücken.
- Formulare lesen: Ein Aktivitätstyp, den die App nicht ändern kann, steht mit „Prüflücke" im Ergebnis; die Verweise darin sind geprüft oder ausdrücklich als nicht geprüft benannt.
- Sicherung und Wiederherstellung: Bleibt der Fortschritt 15 Minuten stehen, meldet die App einen Stillstand mit der letzten Beobachtung, nicht einen Fehler und nicht einen Erfolg.
- Fragen lesen: Dasselbe Lesen mehrfach oder gleichzeitig bricht nicht mehr mit einem Ordnerfehler ab; der Ordner einer Frage gehört jeweils nur einem Lesen.
- Moodle-Profile: Mehrere Instanzen lassen sich in einem Fenster verwalten; Anmeldung, Freigabestufe und KI-Werkzeug-Einrichtung gelten je Profil.
- Moodle-Profile: Freigaben bleiben dem richtigen Profil zugeordnet; eine aktive Moodle-Adresse lässt sich erst nach der Abmeldung ändern.
- Testmodus: Automatische Freigaben gelten nur für ausdrücklich zugeordnete Testprofile und deren Moodle-Adresse.
- Wiederherstellung: Bilder und Anhänge werden gegen die ursprüngliche Sicherung geprüft; ein zwischenzeitlich ausgetauschtes Archiv, fehlende Dateien oder Unterschiede bleiben ausdrücklich unverifiziert.
- Wiederherstellung: Nur eindeutig zugeordnete Aktivitäten aus der Sicherung werden verborgen; parallele oder mehrdeutige Neuanlagen bleiben unberührt und werden zur Prüfung gemeldet.
- Sicherung und Wiederherstellung: Vorgänge bleiben bei mehreren KI-Sitzungen erhalten und bleiben an Profil und tatsächliche Moodle-Adresse gebunden; Umbenennen umgeht keine Wiederholungssperre, und vor einer bewussten Wiederholung zeigt die Freigabe den aktuellen Stand und das Dublettenrisiko.
- MCP-Aufrufe: Ungültige Antworten und Transportfehler melden einen Fehlerstatus statt Erfolg.
- macOS: Bildschirmfotos finden Edge, Chrome oder Chromium im Programmordner; eine Richtlinie, die die Fernsteuerung abschaltet, nennt die App.
- macOS: Die App darf Verbindungen aufbauen (Netzwerkrechte im Entwicklungsbau). Fehlt der Benutzerordner, bricht die App mit einem Fehler ab, statt einen falschen Ort zu nehmen.
- macOS: Der Einstellungsdialog sagt ausdrücklich, dass sich die Version auf dem Mac nicht selbst aktualisiert und nichts bei GitHub prüft.
- macOS: Die Einrichtung findet `python3`, wenn kein `python` da ist.
- macOS: MCP-Aufrufe im Entwicklungsbau können ein Moodle-Profil gezielt wählen; ohne Auswahl gilt das erste.
- Wiederherstellung: Eine Sicherungsdatei lässt sich in einen bestehenden Kurs einfügen, ohne etwas zu ersetzen; die Freigabe nennt Kurs, Datei und was neu angelegt wird, und die Datei wird vor dem Hochladen geprüft.
- Wiederherstellung: Fünf Ziele statt einem – als neuer Kurs (verborgen angelegt), in den aktuellen oder einen anderen Kurs, jeweils einfügen oder vorhandene Inhalte ersetzen. Ersetzen braucht eine eigene Bestätigung, die den Kurs nennt. Bei unklarer Angabe fragt die KI nach.
- Sicherung: Eine einzelne Aktivität lässt sich als Datei ohne Nutzerdaten in den Sicherungsordner der App sichern; nach der Freigabe läuft sie in Moodle und die Datei wird geprüft.
- Sicherung: Mehrere Aktivitäten, ganze Abschnitte oder der ganze Kurs lassen sich in einer Datei ohne Nutzerdaten sichern; die Freigabe nennt die Inhalte, die dabei fehlen.
- macOS: Die App startet als Entwicklerversion auf dem Mac; ein zweiter Start holt das laufende Fenster nach vorn, ohne den Arbeitsordner zu berühren.
- Übertragung: Jedes Profil bekommt eine Rolle (Quelle, Ziel), der Projektkontext hält Quellkurs und Durchführungskurse fest; fehlt etwas, fragt die KI nach, statt zu raten.
- Übertragung: Eine Auswahl lässt sich in einem Auftrag auf mehrere Zielkurse dieser Instanz übertragen; jedes Ziel hat sein eigenes Ergebnis, und fehlgeschlagene Ziele halten die übrigen nicht an. Dieselbe Datei für dasselbe Ziel wird nicht ohne Rückfrage ein zweites Mal eingespielt. Eine Einfüge-Wiederherstellung kann Inhalte doppelt anlegen.

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
