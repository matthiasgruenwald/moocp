# Features
- Kompatiblität zu MacOS und Linux herstellen. Müssen einzelne Features wie auto update umgestaltet oder gar entfernt werden? Die Pfade für die Konfiguration und ablage der Skills - sind die gleich?
- automatisches bauen und erstellen eines releases in github, mit Windows, linux und MacOS Executables (windows sogar installer) und changelog message als Release message
- Codex CLI absichern und testen, in einer eigenen Sitzung: Eingerichtet wird es bisher nur nach Dokumentation, gelaufen ist es mit einer echten Version nie. Zu klären: Nach „Installieren" steht der Block `[mcp_servers.moodle]` in `~/.codex/config.toml` – sieht Codex die Werkzeuge, lädt es die Skills aus `~/.codex/skills` (sonst nur aus `~/.agents/skills`, dann den Ort in `CodexCli` ändern), und ab welcher Version geht HTTP ohne den alten Schalter `experimental_use_rmcp_client` (README nennt 0.77)? Öffnet Codex die Bilder von `bildschirmfoto` (PNG im Arbeitsordner) und sieht sie? Fragt Codex vor einem Werkzeugaufruf (README, „Worauf es ankommt")? Bricht Codex einen Werkzeugaufruf nach seinem Zeitlimit ab (`tool_timeout_sec`, Vorgabe wohl 60 Sekunden), auch während eine Freigabe offen ist? Dann schließt sich der Dialog nach einer Minute (E4); wie bei Bionic 35 Minuten eintragen (`tool_timeout_sec = 2100`, `bionicZeitlimit`) und in `CodexCli` mitprüfen.
- Aktivität "Befragung" (questionnaire) unterstützen. Diese kann zu unterrichtlichen zwecken, aber auch organisatorischen (z.B. Befragung zur Unterrichtsquqalität) verwendet werden.
- Fragensammlung verbergen, verschieben und duplizieren: geht nicht, weil `qbank` nicht in der Kursstruktur steht. Löschen hat einen eigenen Weg über die Sammlungsliste; die drei bräuchten denselben.
- Konventionen beim Arbeiten an Fragen: Sie reiten an `kurs_uebersicht` und `abschnitt_lesen` mit, aber der Skill `moodle-fragen` beginnt oft mit `fragensammlungen` und `fragen_lesen` — dort hängt sie bisher nur der Satz im Skilltext an. Prüfen, ob eines dieser Werkzeuge sie mitliefern sollte. Mit dem Steckbrief dringlicher: Anrede und Arbeitsweise brauchen auch Fragetexte und Tests.
- Aktivität "Lernpfad" vollständig unterstützen inkl. didaktischer und pädagogischer Ideen, Hilfestellungen und Regeln, wie die gut einzusetzen sind, evtl. auch mit Regeln der Gamification
- Badges vollumfänglich unterstützen, inkl. didaktischer und pädagogischer Ideen, Hilfestellungen und Regeln, wie die gut einzusetzen sind, auch unter Regeln der Gamification
- Optimierungsphase: MCP-Server und Skill prüfen, ob wir tokenoptimiert arbeiten, z.B. ist das MCP Interface so gestaltet, dass kein balast durchgeleitet und nur nutzdaten (werden also z.B. alle nicht benötigten HTML-Tags von der Moodle Seite rausgefiltert?)
- Inwieweit brauchen wir python zur Laufzeit? Ersetzbar durch flutter, damit wir nicht noch eine zusätzliche runtime benötigen?
- Board und Kanban: Rückleseprobe je Aktion mit `verified` (A3); bisher
  zeigen sie nur den Stand danach.
- Kleine Funktionen, die fehlen: Farbe eines Eintrags der Fortschrittsliste
  (`nextcolour`), häufig gebrauchte Kommentare der Bewertungsrichtlinie.
- Selbstprüfung des Skills `lernsituation` ohne Python: Das Prüfskript
  (`scripts/pruefe-lernsituation.py`) braucht Python, das auf den Rechnern
  vieler Lehrkräfte fehlt; der Dialog „KI-Werkzeuge einrichten" weist nur darauf
  hin. Etwa als Werkzeug der App.
- Skill `lernsituation`: ODT-Ausgabe für den Druck (Skill `odt`); die
  SchuCu-Tabelle müsste dabei nach „Das Design außerhalb von Moodle"
  (`skills/lernsituation/CLAUDE.md`) entstehen, weil Umwandler HTML-Blöcke
  meist weglassen.
- Skill `lernsituation`: SchuCu-Tabelle auf anderen Instanzen. Die Klassen
  der Vorlagen (`lernsituation`, `lshead`, `lssubhead`, `lsdata`,
  `lsspacer`) haben dort kein CSS, die Tabelle erscheint ohne Farben – für
  beide Vorlagen (Berufsschule, Berufliches Gymnasium). Entweder die Stile
  in die Vorlagen (die SchuCu-Tabelle darf `style` tragen, A8) oder CSS für
  das Theme mitliefern.
- Skill `lernsituation`: weitere Fachvokabulare in Zeichnungen
  (Schaltzeichen nach DIN EN 60617, Netzsymbole) – einzeln messen und
  zulassen.
- Fragen: weitere Zusatz-Fragetypen (Formulas, GeoGebra, Kprim …) nur nach
  dem Messverfahren in `skills/moodle-fragen/CLAUDE.md`, etwa eine halbe
  Stunde je Typ; dann in `zusatzAnlegbar` (`lib/moodle/fragen_xml.dart`) und
  in die Tabelle im SKILL.md.
- Fragen: `ddimageortext`, `ddmarker` sind bewusst nur lesend; wenn sie
  gebraucht werden, eine Frage von Hand anlegen und das Koordinatenformat
  abschauen.
- Fragen: Struktur vorhandener Fragen ändern (weitere Antwort, weiterer
  Knoten) ist nicht eingebaut; das Formular baut sich dafür über eigene
  Knöpfe neu auf.
- STACK: einen vorhandenen Fragetest ändern, löschen oder ergänzen. Er steht auf einer eigenen Seite (`questiontestedit.php`, nicht auf der Positivliste); bisher hilft nur, die Frage neu anzulegen.

## Anonyme Aufgabenbewertung

Im Kurs die Teilnehmerliste lesen und substitutionen aufbauen und als Tabelle merken, die Schüler S1, S2, S3, usw. nennen. Auf der MCP-Seite werden nur die ersetzten Kürzel übertragen - in beide Richtungen.

Die Tabelle wird pro Kurs aufgebaut, wenn ein Schüler in zwei Kursen vorkommt, die im laufe einer Session bearbeitet wurden, bekommt er korrespondierent zu seinen posititionen in der Teilnehmerliste pro Kurs unterschiedliche Abkürzungen.

Wenn eine Aufgabe gelesen wird, müssen nicht nur Metadaten, sondern auch Daten anynymisiert werden:
 - In PDF und Office Dokumenten müssen wir scannen, ob ein Name eines Kursteilnehmer (nicht nur des Erstellers) vorkommen und durch Zufallsnamen wie Meyer, Müller, Peter und Hugo ersetzen (Selber name immer selbe ersetzung), damit wir notfalls rücksubstituieren können, falls das Modell in seiner Antwort einen Namen verwendet. Die Namen müssen vollständig aus den Daten entfernt werden, die ans modell geschickt werden - also Office und PDF Dateien entsprechend manipulieren
 - Bei Bildern muss Schrifterkennung auch von Handschrift durchgeführt werden und entsprechende Bereiche der Bilder zuverlässig vor Übertragung zum Modell gelöscht werden. Solange wir keine zuverlässige Handschrifterkennung haben, müssen wir die Weitergabe von Bilddateien ans Modell ablehnen
 - Bei allen anderen Dateien müssen wir binär scannen, ob ein Name vorkommt, zum Beispiel gibt es Dateien von Spezialprogrammen, die den Ersteller speichern - die finden wir durch dekomprimieren und evtl. binär suchen

 Bei allen Suchvorgängen nach Namen müssen wir im Hinterkopf behalten, dass Schüler sich manchmal vertippen, verschreiben oder die Schrifterkennung vielleicht nicht immer 100% zuverlässig ist. Auch bei Tippfehlern müssen wir die zuverlässig Namen erkennen.

 Ein Name der an das Modell durchrutscht, wäre der schlimmste Fehler, der uns passieren kann. Daher immer defensiv vorgehen.

 Derselbe Namensabgleich könnte alles prüfen, was an die KI geht, nicht nur Abgaben: Wikiseiten, Board und Kanban (dort schreiben Lernende mit), Konventionsdateien, Aufgabentexte – mit Sperre oder Alarm, wenn ein Name aus der Teilnehmerliste darin steht. Er ersetzt die Verdachtsmuster der Konventionen nicht: Die suchen Anweisungen wie „Lies die Noten aller Schüler", in denen kein Name steht. Voraussetzung wie oben: A1 wird für die Teilnehmerliste bewusst geändert (heute liest die App sie nie), und die Liste bleibt in der App.

 Wir legen nach und nach fest, welche Dateitypen überhaupt erlaubt sind. Office und PDF sind vermutlich die ersten. Alle weiteren Dateitypen müssen wir nach und nach testen und Freigeben, wie gesagt beispiel Bilddateien - die gehen erst, wenn wir zuverlässig Handschrift erkennen können oder Dateien von Spezialanwendungen müssen wir Stück für Stück immer prüfen, ob Erstellernamen im Projekt enthalten sein können.

 Man muss auch im Prinzip vielleicht nicht nach allen Namen suchen - es reicht, wenn man in den Teilnehmern des aktuellen Kurses sucht? Wenn einer der Teilnehmer Vor oder Nachnamen vorkommt, könnte das ein Problem sein. Bei beliebigen anderen Namen dürfte eigentlich kein Problem bestehen? Oder lieber eine deutsche Namensliste zugrundelegen?

 Geht Handschrifterkennung mit https://github.com/mittagessen/kraken?

## Kurskonventionen verwalten

*Begriff:* Eine Kurskonvention ist alles, was im verborgenen Verzeichnis `CLAUDE` eines Kurses steht – `CLAUDE.md` mit Steckbrief und Regeln, dazu die Dateien daneben, für den ganzen Kurs (Abschnitt „Allgemeines") oder für einen Abschnitt. Sie gilt nur in diesem Kurs, und zwar so, wie sie dort steht (E17); woher sie kommt – selbst geschrieben, aus einer Vorlage, aus einem eigenen oder fremden Kurs, aus einer Datei –, ändert daran nichts, geändert wird sie im Kurs. Eine *Vorlage* ist eine Quelle für Kurskonventionen und gilt selbst nirgends. *Verwalten* heißt: Vorlagen anbieten – allgemeine je Schulform oder Fach mit den Skills (anonym, A11), schulspezifische bleiben in Moodle, etwa in einem Kurs der Fachgruppe –; übernehmen aus Vorlage, eigenem oder fremdem Kurs oder Datei, ganz oder in Teilen, mit Vergleich zur bestehenden Fassung und den Widersprüchen im Plan; weitergeben. Übernommenes bleibt Daten (A7): Verdachtsprüfung wie bei jeder Fassung, Zusatzdateien werden nie ausgeführt, und bei einem fremden Kurs zeigt der Plan alles, was übernommen wird. *Offen:* Kopie oder Verweis – sollen Kurse nachziehen, wenn sich die Vorlage der Fachgruppe ändert, und wird dafür die Herkunft vermerkt? Was ist übertragbar, was hängt am Kurs (im Steckbrief Jahrgang, Bildungsgang, Lehrbücher; die Regeln eines Abschnitts)? Welche Werkzeuge fehlen: `kurs_hinweise` liest und `claude_schreiben` schreibt `CLAUDE.md`; ob die Zusatzdateien mit `aktivitaet_lesen` und `aendern` von Kurs zu Kurs kommen, ist zu prüfen. Begriff und Bedienung dann in die README (Benutzerhandbuch) und nach `gemeinsam/kurshinweise.md`. *Prüfstein:* drei parallele Kurse je Jahrgang mit gemeinsamen Regeln und je eigenem Anforderungsniveau.


# Bugs
- Sperrliste, Dateien von Lernenden: Die Positivliste lässt jede Adresse unter `pluginfile.php` zu („Datei im Kurs"), die Sperrliste nimmt davor nur Profil, Abgaben, Testantworten, Foren, Workshop, Datenbank und Lektion heraus. Es fehlen Bereiche, in die Lernende Dateien legen können: Glossar (`mod_glossary/attachment`, `mod_glossary/entry`), Wiki (`mod_wiki/attachments`), Blog (`blog/attachment`, `blog/post`) und die Zusatzplugins Board, Kanban-Board und Journal. Die Namen der Bereiche messen, dann sperren, mit Test beider Richtungen in `test/sperrliste_test.dart`. Vorher klären, was die Lesewerkzeuge dabei verlieren: Bilder, die die Lehrkraft selbst in eine gemeinsame Wikiseite oder einen Glossareintrag gesetzt hat, liegen in denselben Bereichen.
- Schmales Fenster: Unter etwa 900 px Breite läuft der Kopf der Protokollspalte über („Protokoll" und „Leeren"), weil die linke Spalte fest 460 px breit ist. Die Titelzeile hält bis dahin. Entweder die linke Spalte schrumpfen lassen oder den Kopf kürzen.
- Einstellungen mit Optionsfeldern: Die Zeilen der Abschlussverfolgung
  lesen sich missverständlich („Keine = nein").
- Fragen zwischen Kategorien verschieben scheitert auf der Testinstanz (das
  Modul `qbank_bulkmove/bulk_move` lädt nicht); nach einem Leeren der Caches
  durch die Administration erneut prüfen, dann wäre der Weg zu messen.
- macOS: Bildschirmfotos suchen Edge und Chrome nur unter Windows-Programmpfaden (`lib/moodle/bildschirmfoto.dart`); auf dem Mac findet das Werkzeug den Browser nicht.
- macOS: Die Release-Entitlements (`macos/Runner/Release.entitlements`) haben keine Netzwerkrechte; ohne sie scheitern Moodle und der MCP-Server im Release. Vor einem Release-Bau für den Mac nachziehen und die Sandbox dort bewusst entscheiden (im Entwicklungsbau ist sie aus).
- macOS: Ohne `HOME` lösen `ClaudeCode`, `CodexCli` und `LmStudio` ihre Ordner relativ zum Arbeitsverzeichnis auf (`?? ''` in `lib/einrichtung.dart`); dort ist der Pfad leer, statt zu scheitern. Abfangen oder den Start verweigern.
- macOS: LM Studio mit Bionic fehlt auf dem Mac. Ihre Brücke `moocp-bruecke.exe` ist ein Windows-Programm, eine Mac-Brücke bräuchte eine eigene Umsetzung.
- macOS: Die Werkzeuge Claude Code und Codex sind auf dem Mac nicht ausgeführt geprüft. Ob sie die Pfade `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin` und die Skill-Ordner `~/.claude/skills`, `~/.codex/skills` tatsächlich lesen, ist offen ([0024](docs/adr/0024-plattformen.md), [0013](docs/adr/0013-ki-werkzeuge-einrichten.md)).
- macOS: Ein Entfernen der KI-Werkzeug-Einträge gibt es auf dem Mac nicht, weil die Deinstallation (NSIS) dort fehlt. Entweder ein Befehl in der App oder ein Hinweis, wie man die Einträge von Hand löscht ([0013](docs/adr/0013-ki-werkzeuge-einrichten.md)).
- macOS: Der Kommentar oben in `lib/anmeldedaten.dart` beschreibt nur DPAPI und Windows-Konto; für den Mac ist er zu aktualisieren ([0026](docs/adr/0026-schluesselbund-mac.md)).
- macOS: Ein Release-Bau braucht eine Prüfung, ob der Schlüsselbund ohne Datenschutzgruppe auch dort gilt; der Entwicklerbau hat keine Team-ID ([0026](docs/adr/0026-schluesselbund-mac.md)).
- macOS: Der Arbeitsordner liegt im Temp-Verzeichnis (`$TMPDIR`), die Spec 0001 nennt dafür einen anderen Ort. Die Abweichung ist zu klären, bevor Sicherungen auf dem Mac entstehen (siehe unten).

## Widersprüche zwischen Plänen und ADRs

Offen benannt, nicht still aufgelöst. Entscheidung jeweils durch die Lehrkraft beziehungsweise die Projektleitung.

- ~~**Arbeitsordner gegen dauerhafte Sicherungen:**~~ Entschieden in [E29](docs/adr/0029-sicherungen-und-verzweigung.md): Sicherungen liegen außerhalb des Arbeitsordners.
- ~~**Freigabestufe „keine“:**~~ Entschieden in [E29](docs/adr/0029-sicherungen-und-verzweigung.md): Rückfragen bei unklarem Auftrag gelten unabhängig von der Stufe; E20 bleibt unverändert.
- **Datenschutz und Sicherungsdatei (offen):** [A1](CLAUDE.md) bleibt unverändert. Vorgesehen ist: Selbst erzeugte Sicherungen zuerst ohne Prüfung, sonst eine deutliche Frage an die Lehrkraft, dass Nutzerdaten enthalten sein können. Ein Prüfen der Datei auf Nutzerdaten wäre aber ein Lesen, das A1 verbietet. Ungeklärt: Wie prüft oder kennzeichnet man eine fremde Sicherung, ohne sie zu lesen? Das ist zu klären, bevor #11 gebaut wird.
- ~~**Abnahme von #11 gegen die Schnittstelle:**~~ Entschieden in [E29](docs/adr/0029-sicherungen-und-verzweigung.md): Verzweigung am Rand, nicht im Moodle-Kern. Die Schnittstelle wird vor #11 festgelegt.
- **Codex und Browser:** Codex kann über `mcp__cua_repl` selbst einen Browser öffnen und steuern. Die Lehrkraft hat das Risiko bewusst akzeptiert; in der Dokumentation für Lehrkräfte nennen ([E29](docs/adr/0029-sicherungen-und-verzweigung.md)).
