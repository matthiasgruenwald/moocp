# Features

- Bildschirmfotos: Bei einer schmalen Inhaltsbox werden links Textanfänge abgeschnitten. Im Live-Test auf der zweiten Testinstanz mit einer eigenen ZZ-Textseite mehrfach reproduziert; der rückgelesene Quelltext ist vollständig. Inhaltskoordinaten und Layoutänderungen zwischen Messen und Aufnahme prüfen, ohne den Ausschnitt auf Kopf oder Navigation auszuweiten.

Größere Folgearbeiten zur sicheren Wiederherstellung sind in [Issue #26](https://github.com/matthiasgruenwald/moocp/issues/26) zur menschlichen Klärung gesammelt. Die dortige Reihenfolge gilt nach Abschluss des aktuellen PR.
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

## Verbleibende Prüfungen (Issues #4 bis #10)

Offline geprüft sind die Regeln und Abläufe mit Fakes. Weitere Live-Messungen gelten nur im ausdrücklich dokumentierten Umfang. Die spätere ZZ-Messreihe belegt Aktivitätssicherung und Einfüge-Wiederherstellung von Quizzen; offene Fälle stehen unten und in Issue #26.

Im Testkurs (Präfix `ZZ`, Quelle und Ziel, nie ein Produktivkurs) nachprüfen:

- **#10 Übertragung in einem Auftrag (`uebertragen`), zuerst:** Ohne `datei` auf dem
  Testkurs sichern, dann je Ziel wiederherstellen; jedes Ziel bekommt eine eigene
  Nummer und einen eigenen Stand. Ungemessen: ob die Zusammenfassung in der Freigabe
  stimmt, ob der Bericht die Dubletten-Hinweise zeigt, ob Moodle die Namen-Prüfung vor
  dem Schreiben abfängt.
- **#10 Teilweise fehlgeschlagener Lauf:** Nur mit Fakes geprüft (fertig, fehlgeschlagen,
  fertig; das erste Ziel wird nicht erneut angefasst). Live ungemessen: wie ein Fehler
  bei einem zweiten Ziel entsteht, ohne Produktivkurs herbeizuführen.
- **#10 Ablehnung in der App:** Die Erkennung „abgelehnt" ist eine Annahme. Die App
  liefert bei Ablehnung keinen Vorgang und keine Ausnahme, und das Werkzeug ordnet
  das dann als abgelehnt ein. Prüfen: Kommt bei einer Ablehnung wirklich der Text
  „in der App abgelehnt" zurück, und stoppt der Lauf dann die übrigen Ziele?
- **#10 Wiederholungsschutz:** Dieselbe Datei für dasselbe Ziel gibt eine Rückfrage.
  Offen bleibt die Messung der Rückfrage bei einer frischen Sicherung (ohne `datei`) über den Quellkurs; `erneut` bleibt entfallen.
  `wiederherstellen_datei` schützt denselben Datei-/Zielauftrag zusätzlich durch den gespeicherten Vorgang;
  dieser Schutz ist über MCP mit einem lokalen HTTP-Doppel geprüft.
- **#10 Protokoll `uebertragungen.json`:** Ungemessen, ob ein Abbruch mitten im Lauf
  die bis dahin geschriebenen Einträge erhält, und ob eine beschädigte Datei wirklich
  unverändert stehen bleibt.
- **#10 Rundlauf A → Datei → B:** Nicht geprüft. Die Logik ist mit Fakes getestet; ein
  echter Rundlauf über `sichern_auswahl` und `wiederherstellen_datei` fehlt. Der Ablauf
  zwischen zwei Instanzen setzt voraus, dass beide denselben Sicherungsordner nutzen.
  Das ist ungemessen.
- **#10 Freigaben:** Ein Auftrag fragt einmal für alle Ziele, und jeder Schreibschritt
  fragt danach erneut. Offen, ob das für die Stufe „mittel" zu viel ist. Bei der
  Datei-Variante fehlt der Quellkurs, darum zeigt die Freigabe dort die einfachen
  Angaben statt der Zusammenfassung mit Quelle.
- **#10 Wiederholung:** `erneut` bleibt bewusst entfallen; eine Wiederholung läuft über `wiederherstellen_datei` mit `wiederholung_von`. Ob Coursepilot die Buchführung über die Übertragungen tatsächlich aus
  `uebertragungen.json` abgleicht, ist nicht geprüft; der Skill sagt nur, dass die
  Buchführung dort liegt.
- **#9 Zielwege (Wiederherstellen):** Nur `anderer_kurs_verschmelzen` durchgespielt; die löschenden
  Wege sind nie ausgeführt. Der Abbruch eines neuen Kurses fehlt (Abschnitt zu #9 unten).
- **#8 Wiederherstellen in bestehenden Kurs:** Die offenen Punkte stehen im Abschnitt
  zu #8 unten; dort steht auch, was gemessen ist.
- **#7 Auswahl sichern und #6 Aktivität sichern:** Die offenen Punkte stehen in den
  Abschnitten unten. Der Rahmen eines Abschnitts (ob Moodle ihn ohne die übrigen
  Aktivitäten hält) ist nicht gemessen.
- **#5 Rollen und Projektkontext:** Rein lokal; Moodle wird nicht angefragt. Die
  Richtungsregeln sind offline geprüft, ein Test auf der Instanz steht aus.
- **Bau:** Release-Bau und Windows-Installer sind mit dieser Änderung nicht geprüft.

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

## Lückenbefund: Gestaltungsstandard Informatik (Skill moodle)

LÜCKENBEFUND
Zum Nachrüsten: diesen Block unverändert im Projekt moocp einfügen.

Skill:      moodle
Art:        Typ nicht unterstützt
Typ:        choicegroup (Gruppenwahl), lightboxgallery (Bildergalerie)
Gefordert:  Beschreibung (intro) im Gestaltungsstandard ändern
Anlass:     „Partnerzuordnung und Bildanleitung nach dem Gestaltungsstandard für Informatik umsetzen“
Meldung:    Unbekannte Aktivitätsart "choicegroup" / "lightboxgallery". Coursepilot führt: label, page, url, folder, resource, choice, forum, assign, quiz.


# Bugs
- Sicherheit, Zugangsschlüssel im Klartext: Der Schlüssel des MCP-Servers steht im Klartext in `~/.claude.json` (Claude Code) und in `~/.codex/config.toml` (Codex CLI) und ist für jedes Programm des Benutzers lesbar. Bewusst so belassen (E6), solange Codex nicht über `codex mcp add` mit einer Umgebungsvariable eingerichtet wird (Q14). Umbau, falls gewünscht: Snippet und Umgebungsvariable statt Konfigurationsdatei.
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
- macOS: Die Werkzeuge Claude Code und Codex sind auf dem Mac nicht ausgeführt geprüft. Ob sie die Pfade `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin` tatsächlich lesen, ist offen ([0024](docs/adr/0024-plattformen.md), [0013](docs/adr/0013-ki-werkzeuge-einrichten.md)).
- Skills (#3a, [E30](docs/adr/0030-skills-eine-quelle.md)): Codex hat in einer frischen Sitzung (`codex exec`) einen Testskill unter `~/.agents/skills/zz-ladetest/` gefunden und gelesen (2026-10-17). Offen: ob das über den Skill-Mechanismus lief oder über eine Dateisuche; Codex hat den Ordner nicht per Skill-Aufruf geladen, nur die Datei gelesen. Die Prüfung mit einem Skill, der im Gespräch genutzt wird, steht noch aus. Dann die App umstellen: Quelle `~/.agents/skills`, Claude per Verlinkung, unter Windows Kopie als Rückfall.
- macOS: Ein Entfernen der KI-Werkzeug-Einträge gibt es auf dem Mac nicht, weil die Deinstallation (NSIS) dort fehlt. Entweder ein Befehl in der App oder ein Hinweis, wie man die Einträge von Hand löscht ([0013](docs/adr/0013-ki-werkzeuge-einrichten.md)).
- macOS: Der Kommentar oben in `lib/anmeldedaten.dart` beschreibt nur DPAPI und Windows-Konto; für den Mac ist er zu aktualisieren ([0026](docs/adr/0026-schluesselbund-mac.md)).
- macOS: Ein Release-Bau braucht eine Prüfung, ob der Schlüsselbund ohne Datenschutzgruppe auch dort gilt; der Entwicklerbau hat keine Team-ID ([0026](docs/adr/0026-schluesselbund-mac.md)).
- macOS: Der Arbeitsordner liegt im Temp-Verzeichnis (`$TMPDIR`), die Spec 0001 nennt dafür einen anderen Ort. Die Abweichung ist zu klären, bevor Sicherungen auf dem Mac entstehen (siehe unten).
- Codex-Sandbox blockiert den Flutter-Cache: Im Modus `workspace-write` schlägt `flutter analyze` und `flutter build` mit `Operation not permitted` unter `/opt/homebrew/share/flutter/bin/cache` fehl, obwohl der Ordner für `mg` beschreibbar ist (2026-10-17 geprüft). Abhilfe in `~/.codex/config.toml` (außerhalb des Repos) eingetragen, 2026-10-17 von der Lehrkraft am Terminal:
  ```toml
  [sandbox_workspace_write]
  writable_roots = ["/opt/homebrew/share/flutter/bin/cache"]
  ```
  Offen: Ob Codex damit `flutter analyze` und `flutter build` tatsächlich ausführt, ist noch nicht geprüft. Dafür den Codex-Lauf wiederholen, sobald der Bildschirmfototest wieder dran ist.
- `bildschirmfoto` ruft für eine Textseite `modedit.php?update=<cmid>` ab statt der Ansicht (`mod/page/view.php?id=<cmid>`); cmid 1101 liefert HTTP 500, cmid 1102 funktioniert. Das Werkzeug auf die Ansicht umstellen und mit Messung im Testkurs prüfen (A6).
- `bildschirmfoto` legt das PNG im Temp-Arbeitsordner der App ab (`/private/var/folders/…/moocp_arbeitsordner/`), nicht im Arbeitsordner des Repos, wie `docs/agents/testing.md` es beschreibt. Eine der beiden Angaben angleichen.

## Widersprüche zwischen Plänen und ADRs

Offen benannt, nicht still aufgelöst. Entscheidung jeweils durch die Lehrkraft beziehungsweise die Projektleitung.

- ~~**Arbeitsordner gegen dauerhafte Sicherungen:**~~ Entschieden in [E29](docs/adr/0029-sicherungen-und-verzweigung.md): Sicherungen liegen außerhalb des Arbeitsordners.
- ~~**Freigabestufe „keine“:**~~ Entschieden in [E29](docs/adr/0029-sicherungen-und-verzweigung.md): Rückfragen bei unklarem Auftrag gelten unabhängig von der Stufe; E20 bleibt unverändert.
- ~~**Datenschutz und Sicherungsdatei:**~~ Entschieden in [E29](docs/adr/0029-sicherungen-und-verzweigung.md): A1 bleibt unverändert. Selbst erzeugte Sicherungen gehen direkt; bei fremden Dateien fragt die App deutlich, dass Nutzerdaten enthalten sein können, ohne sie zu lesen. Die Lehrkraft entscheidet.
- ~~**Abnahme von #11 gegen die Schnittstelle:**~~ Entschieden in [E29](docs/adr/0029-sicherungen-und-verzweigung.md): Verzweigung am Rand, nicht im Moodle-Kern. Die Schnittstelle wird vor #11 festgelegt.
- **Codex und Browser:** Codex kann über `mcp__cua_repl` selbst einen Browser öffnen und steuern. Die Lehrkraft hat das Risiko bewusst akzeptiert; in der Dokumentation für Lehrkräfte nennen ([E29](docs/adr/0029-sicherungen-und-verzweigung.md)).

## Aktivität sichern (Issue #6): verbleibende Messlücken

Mit ZZ-Quizzen eigener und geteilter Sammlung im Testkurs ausgeführt und zurückgelesen. Die folgenden verbleibenden Messlücken gelten weiterhin; die Messreihe belegt keine anderen Aktivitätstypen.

- Antwort von `core_backup_get_async_backup_progress`: gemessen ist eine Liste mit `backupid`, `progress` (0 oder 1) und `status` (700 läuft, 1000 Ende). Ein Fehlerfeld (`error`/`errorcode`) gilt als fehlgeschlagen, alles Unbekannte als `unklar` (`bewerteFortschritt`, `lib/moodle/sicherung_regeln.dart`). Das Muster mit Zwischenständen ist nicht vollständig gemessen.
- Downloadlink: `core_backup_get_async_backup_links_backup` meldet auf der Testinstanz `backup_controller_dbops_loading_invalid_controller` und ist deshalb nicht der Weg. Die App liest stattdessen `/backup/restorefile.php?contextid=<ctx>` und nimmt genau den Link für den eigenen Dateinamen (`sicherungsLinks`); keiner oder mehrere Treffer heißen `unklar`. Gemessen: Moodle benutzt den eigenen Dateinamen, und der Downloadlink hat kein itemid-Segment: `/pluginfile.php/<ctx>/user/backup/<datei>.mbz?forcedownload=1`. Daneben steht ein Link `restorefile.php?action=choosebackupfile&filename=<datei>`, den die App nicht benutzt. UNGEMESSEN: ob die Seite die Datei immer listet (Rechte, Papierkorb, Abstände). Die Seite listet auch die eigenen Sicherungen anderer Vorgänge; die App übernimmt nur den einen Link.
- Rückfall (nicht gebaut): `/backup/backupfilesedit.php?currentcontext=<ctx>&contextid=<ctx>&filearea=backup&component=user`, falls die Seite Wiederherstellen nicht reicht.
- Teil des Downloadpfads: gemessen ist kein itemid-Segment nach `user/backup/`. Die Muster (`sicherungsLinks`, Positivliste, Sperrliste) lassen eine Zahl davor optional zu; ob Moodle die je setzt, ist nicht gemessen.
- Antwort mit `contentLength < 0` beim Herunterladen: die App lehnt ab (fail-closed, `herunterladen` in `lib/moodle/moodle_zugang.dart`); wie Moodle die Länge bei großen Dateien meldet, ist nicht gemessen.
- Feldnamen der Schema-Seite (Schritt 2): `setting_activity_<art>_<cmid>_included` und `_userinfo` sind angenommen; nur Schritt 4 ist gemessen.
- Nutzerdaten-Optionen: gemessen sind `users` und `enrolments`; `groups`, `userscompletion`, `logs`, `grade_histories`, `badges` stehen auf der Liste, damit sie nicht still eingeschaltet bleiben, sind aber ungemessen.
- Test für den Download fehlt: `herunterladen` hat keinen HTTP-Test. Der Weg braucht `fuerTest` (nur Debug-Bau, `http://127.0.0.1`, Anmeldung) und ein Fake-Moodle wie in `test/instanzen_test.dart`. Nachrüsten, dann mit Messung im Testkurs.
- Die Sperrliste lässt genau `/pluginfile.php/<ctx>/user/backup/<datei>.mbz?forcedownload=1` durch (itemid-Segment optional); andere Nutzerdateien bleiben gesperrt (Test in `test/sicherung_regeln_test.dart`).

## Auswahl sichern (Issue #7): UNGEMESSEN

Umgesetzt (`sichern_auswahl`, `auswahlSichern` in `lib/moodle/sicherung.dart`), nicht auf einer Instanz durchgespielt. Die folgenden Punkte sind im Code als UNGEMESSEN markiert; sie werden im Testkurs mit `ZZ`-Proben gemessen, bevor die Auswahl-Sicherung als geprüft gilt.

- Feldnamen und Reihenfolge der Schema-Seite sind auf der Testinstanz gemessen: `setting_section_section_<abschnittsid>_included` steht vor den Aktivitäten, die darin liegen (`setting_activity_<art>_<cmid>_included`). Die Tests (`test/sicherung_auswahl_test.dart`) folgen dieser Reihenfolge. Ungemessen bleibt die Stelle des `_userinfo`-Feldes je Abschnitt; es wird unabhängig vom Ort auf 0 gesetzt.
- Aktivität nur mit ihrem Abschnitt: gemessen (Testinstanz) verwirft Moodle auf Schritt 4 die ganze Auswahl, wenn der Abschnitt einer gewählten Aktivität aus ist. Umgesetzt: `schemaWahl` schaltet den Abschnitt jeder gewählten Aktivität als Rahmen ein, ohne seine übrigen Aktivitäten. Ungemessen: ob Moodle den Rahmen so hält; die Live-Messung ist offen.
- Bestätigungsseite (Schritt 4) bei Auswahl: erwartet sind die gewählten Abschnitte plus die Abschnitte gewählter Aktivitäten, und die genannten Aktivitäten plus alle Aktivitäten gewählter Abschnitte (`bestaetigungWahlFehler`). Ob Moodle auf Schritt 4 genau so ausweist, ist ungemessen; eine Abweichung bricht ab, bevor etwas läuft.
- Ganzer Kurs ohne Auswahl: die Auswahlseite muss genau die Aktivitäten der Kursübersicht nennen (`kursLesen`), sonst bricht die App ab. Ob Moodle Versteckte oder Papierkorb-Aktivitäten dort anders führt, ist ungemessen.
- Ganzer Kurs mit Auswahl bleibt Art „Kurs" (`auswahlArt`, `AuswahlArt.ganzerKursEingeschraenkt`). Die Freigabe nennt den Umfang; ob Moodle selbst im Dateinamen oder auf der Seite eine Unterscheidung macht, ist ungemessen.
- Inhaltslücken je Modultyp (`_inhaltsLuecke`, `lib/moodle/sicherung_regeln.dart`): die Liste (Glossar, Datenbank, Forum, Wiki, Aufgabe, Feedback, Fragebogen, Test, Lektion, Workshop, Auswahl, Chat, Journal, H5P, SCORM) stammt aus dem Moodle-Aufbau, nicht aus einer Messung. Ob und wie Moodle jeden Typ ohne Nutzerdaten sichert, ist ungemessen; eine Ergänzung oder Streichung ist ein Eintrag in dieser Liste.
- Dateiname der Kurssicherung `kurs-k<kurs>-<stempel>.mbz` (`kursSicherungsName`): Moodle übernimmt den Namen laut #6 von der Seite; ob das für Kurssicherungen gleich ist, ist ungemessen. Der Downloadlink wird wie bei #6 über `sicherungsLinks` gesucht.
- Dauer: die Anfrage `sichern_auswahl` hat ein Zeitlimit von einer Minute; danach läuft die Sicherung weiter und `sicherung_status` zeigt den Stand. Wie lange eine Kurssicherung dauert, ist ungemessen.
- Nutzerdaten-Optionen auf Kursebene (`setting_root_*`): wie bei #6 nur `users` und `enrolments` gemessen; die übrigen stehen auf der Liste, sind aber ungemessen.
- Positivliste und Sperrliste sind unverändert: der Kursweg `/backup/backup.php?id=<kurs>` ohne `cm` und die Schritte 1, 2 und 4 sind über die bestehenden Einträge erlaubt (Tests in `test/sicherung_regeln_test.dart`). Ob Moodle den Kursweg wie den Aktivitätsweg beantwortet, ist ungemessen.
- Änderung im Kurs zwischen Schritt 2 und Schritt 4: die Prüfung vergleicht nur die Seite von Schritt 4 mit der Bestellung, nicht mit dem Stand von Schritt 2. Ob das bei gleichzeitigem Bearbeiten reicht, ist ungemessen.

## Wiederherstellen in bestehenden Kurs (Issue #8): verbleibende Messlücken

Mit ZZ-Quizzen eigener und geteilter Sammlung im Quellkurs, in einem anderen Kurs derselben Instanz und auf einer anderen Instanz ausgeführt und zurückgelesen; jeweils über `anderer_kurs_verschmelzen`. Die Prüfung der Datei (Größe, Pfade, Nutzerdaten, Bewertungen, Format) ist offline getestet (`test/wiederherstellung_regeln_test.dart`); der Einfügeablauf gegen Moodle ist gemessen. Die folgenden Einschränkungen bleiben offen.

- Sichtbarkeit der wiederhergestellten Aktivitäten: Gemessen (Testinstanz, Zielkurs, Live-Messung #8): Moodle stellt sie sichtbar wieder her. Die App verbirgt die neuen Cmids danach über `cm_hide` (wie `sichtbarkeit_setzen`) und liest zurück; `verborgen: verified` nur, wenn alle neuen verborgen sind. Ungemessen ist, ob das Verbergen rechtzeitig greift und ob Lernende in der Zwischenzeit zugreifen können.
- Neue Abschnitte werden nach der Wiederherstellung nicht verborgen. Die App verbirgt nur die neuen Aktivitäten (`cm_hide`). Ungemessen, ob ein neuer Abschnitt in dieser Zeit sichtbar bleibt und ob Lernende ihn dann sehen.
- Fortschritt: Die Kennung für `core_backup_get_async_backup_progress` ist die Restore-ID aus dem Prüfformular (Feld `restoreid`), nicht der Dateinamen-Hash `filename` aus der Weiterleitung. Der frühere Aufruf mit dem Hash wurde von Moodle mit „Ungültiger Parameterwert" abgelehnt (gemessen). Gemessen: Die Fortschrittsabfrage zeigt den laufenden Auftrag und später dessen Ende. Andere Status- und Fehlerfälle bleiben offen (Issue #26).
- Schritt 2 (gemessen): Die Seite Sicherungsdetails ist ein schlichtes Formular ohne `mform`, das nur `contextid`, `filepath`, `filename`, `stage`, `sesskey` trägt. Ihr Weiter-Formular führt auf die Zielseite mit `stage=4`, und `target`, `targetid` und `search` sind vorausgefüllt. Die App setzt `target=4` und `targetid` = Kurs-ID und sendet dasselbe Formular. Danach folgen Einstellungen, Schema und Prüfung; sie sind gemessen und haben die Prüfungen bestanden.
- Kurssuche: Ungemessen, wie der Zielkurs erscheint, wenn die Zielseite die Kurssuche verlangt (`searchcourses`); die App nimmt nur den bereits vorausgefüllten Kurs.
- Kurskontext: Die Kontext-ID des Kurses wird aus `/course/view.php?id=<kurs>` gelesen (`Seitenangaben.aus`); ungemessen, ob diese Seite die Kontext-ID immer trägt.
- Upload-Schaltfläche und Feldname: `repository_ajax.php?action=upload` mit Feld `repo_upload_file` und Feld `itemid` ist aus dem Upload-Pfad übernommen; die Schaltfläche des Wiederherstellen-Formulars ist ungemessen. Das Feld `backupfile` in `restorefile.php` ist gemessen.
- Namenlose Absendeknöpfe: Die Schritte senden nur die Felder des Formulars selbst, ohne Absendeknopf-Namen. Gemessen angenommen für Sicherungsdetails, Schritte 4, 8 und 16 (Live-Messung #8); die Zielseite ist ebenfalls gemessen.
- Formularnamen: `_qf__restore_settings_form`, `_qf__restore_schema_form`, `_qf__restore_review_form` sind in den Schritten 4, 8 und 16 gemessen. Die Zielseite trägt kein `_qf__`-Feld (gemessen). `_qf__course_restore_form` (Upload) ist gemessen.
- Weiterleitung nach dem Hochladen (Live-Messung #8): Moodle leitet nach `/backup/restore.php?contextid=..&pathnamehash=..` um. Die Positivliste erlaubt das; der Ablauf in `wiederherstellung.dart` liest nur `filename` und bricht sonst ab. Ungemessen: ob Moodle `filename` in diesem Fall zusätzlich nennt.
- Feldliste von `restorefile.php` (`_qf__course_restore_form`, `sesskey`, `backupfile`, `contextid`, `submitbutton`): Die Positivliste lässt nur diese Felder zu. Die Ablehnung der POST-Anfrage in Live-Messung #8 ist nicht reproduziert; Ursache ungeklärt, eine Ablehnung ist ein Befund für diese Liste.
- MIME-Typ der .mbz im Upload (`application/octet-stream` oder `application/vnd.moodle.backup`) ist ungemessen.
- Größenobergrenze: 200 MB (`archivGrenzeStandard`, fest). Die Obergrenze des Upload-Formulars (`maxbytes`) wird nicht gelesen; die Funktion dafür ist entfernt, weil sie nirgends verdrahtet war. Nachrüsten nur mit Messung im Testkurs.
- Upload liest die ganze Datei mit `readAsBytes` in den Speicher (`lib/moodle/wiederherstellung.dart`, bis 200 MB). Ungemessen, ob das auf schwächeren Rechnern trägt; ein Strom-Upload wäre die Alternative, ist aber nicht gebaut und nicht gemessen.
- Archiv-Grenzen (`entpacktGrenzeStandard` 1 GB, `eintragGrenzeStandard` 20000, Verhältnis 200) sind Schätzwerte, nicht gemessen. Die Prüfung liest das Archiv vollständig in den Speicher, bevor sie entpackt; ein Strom-Lesen wäre bei großen Dateien besser.
- Nur .tar.gz (.mbz) wird unterstützt; ZIP-Archive lehnt die Prüfung ab.
- Abbruch oder verlorene Antwort nach dem Absenden von Schritt 16: Die App liest den Stand nach und wiederholt nie blind. Ob Moodle den Lauf nach einem Abbruch der Sitzung tatsächlich weiterführt, ist ungemessen.
- Freigabe-Test „Die Stufe steht in den Einstellungen …" schlug einmal im Gesamtlauf fehl und lief beim Wiederholen durch (Flake, nicht durch diese Änderung verursacht). Beobachten.

## Freigabe ohne Zeitlimit des KI-Aufrufs (Folgearbeit: Issue #26)

Die Freigabe wartet bis zu 30 Minuten, aber nur, solange die KI auf den Werkzeugaufruf wartet: Das Zeitlimit des MCP-Clients (vermutlich 60 Sekunden) schließt den Dialog (E4, `Freigaben.mitAbbruch`). Wer nicht am Fenster sitzt, verpasst die Frist, auch bei den Rückfragen, die bei jeder Stufe gelten (Wiederholung, E29). Lösung: Das Werkzeug kehrt sofort mit einer Nummer zurück („Freigabe liegt in der App“), der Dialog bleibt offen, und ein Statuswerkzeug meldet, ob geschrieben wurde, so wie bei Sicherung und Wiederherstellung. Offen: welche Werkzeuge es betrifft, wie ein später abgelehnter oder verfallener Vorgang gemeldet wird, damit die KI nie einen Lauf für gescheitert hält, der noch freigegeben werden kann (E4), und ein Test über den öffentlichen MCP-Aufruf.

## Doppelstart-Schutz (Ticket #19): offene Punkte
- Die Ende-zu-Ende-Prüfung fehlt: Die Reihenfolge (Doppelstart-Prüfung vor der Freigabe) ist nur im Code; ein Test braucht eine gültige .mbz-Vorlage (Testfixture) und einen Moodle-Doppel.
- `wiederherstellung_status` setzt einen Vorgang „anstehend" oder „hochgeladen" ohne laufende Sitzung auf „fehlgeschlagen". Das gibt die Sperre frei, obwohl das Senden vor dem Absturz geschehen sein kann. Bisheriges Verhalten, nicht geändert; prüfen.
- Ein Platzhalterkurs bei „neuer_kurs" nach einem Abbruch ist nicht gemessen; deshalb sperrt „fehlgeschlagen" bei neuem Kurs weiter.
- Fertige Wiederherstellungen sperren, bis sie ausdrücklich wiederholt werden (konservativ, ungemessen ob gewollt).
- Vorgänge ohne Fingerabdruck (vor diesem Stand) sperren nichts.

## Wiederherstellen: weitere Zielwege und Abbruch (Issue #9)

Umgesetzt (`zielwegPruefen`, `Zielweg` in `lib/moodle/wiederherstellung_regeln.dart`; `wiederherstellen` in `lib/moodle/wiederherstellung.dart`; Positivliste je Weg in `lib/moodle/moodle_zugang.dart`), offline getestet (`test/wiederherstellung_weg_test.dart`). Gemessen ist nur der angebotene Weg `anderer_kurs_verschmelzen`; andere Wege sind nicht durchgespielt. Die Werte der fünf Wege (2, 1, 0, 4, 3) stammen aus `docs/plans/moodle-sicherung-formulare.md`; was dort nicht steht, ist unten als UNGEMESSEN geführt.

- Löschende Wege (`aktueller_kurs_ersetzen` target 0, `anderer_kurs_ersetzen` target 3): nie ausgeführt. Ob Moodle vorhandene Inhalte vollständig entfernt und ob die Wiederherstellung danach ohne Rest läuft, ist ungemessen. Die Freigabe nennt den Kurs und sagt „vorhandene Inhalte werden gelöscht"; Test nur im Zielkurs der Testinstanz.
- Neuer Kurs (`neuer_kurs` target 2): Feldnamen des Platzhalter-Schemas sind nur mit dem Präfix `setting_course_course_fullname` / `setting_course_course_shortname` angenommen; keine Treffer führen zu einem Fehler. Das Sichtbarkeitsfeld `setting_course_course_visible` (auf `0` gesetzt) ist ungemessen.
- Neuer Kurs bleibt sichtbar, wenn das Formular kein Sichtbarkeitsfeld bietet. Das Ergebnis wird nicht zurückgelesen (anders als die Aktivitäten, siehe #8). Ungemessen, ob ein Platzhalterkurs so für Lernende zugänglich wird und wie lange.
- Neuer Kurs: Die Kursnummer nach dem Anlegen ist nicht gelesen; `targetid`-Rücklesen fehlt, deshalb bleibt `verified` bei neuen Kursen `false`.
- Neuer Kurs: Kategorie. `kategorie_id` wird nur übernommen, wenn gesetzt; ohne Angabe bleibt die Kategorie aus dem Formular, sonst Rückfrage. Der Kategorie-Kontext kommt aus `/course/management.php?categoryid=` (erlaubt, GET); ob diese Seite die Kontext-ID trägt, ist ungemessen.
- Neuer Kurs, Abbruch: NICHT umgesetzt. Bricht die Wiederherstellung vor dem Schritt 16 ab, bleibt der Platzhalterkurs möglicherweise stehen. Im Fehlertext steht nur ein Hinweis. Der Abbruch über Moodles nativen Cleanup mit Rücklesen fehlt; die Felder der Abbrechen- und Bestätigungs-Seite sind unbekannt. Nachrüsten im Testkurs, nicht in der Arbeitssitzung (A6).
- Fehlende Rechte: Verhalten bei Konten ohne Recht zum Anlegen, Löschen oder Wiederherstellen ist ungemessen; die App meldet den Fehler, wie Moodle ihn zurückgibt.
- Fehlende Plugins oder Formulare: Die App verlangt die Formulare der Schritte 2, 4, 8, 16; fehlt ein Formular, bricht sie mit Fehler ab. Welche Meldung Moodle dabei gibt, ist ungemessen.
- Die Positivliste ist je Weg eng: nur die Schlüsselmenge des jeweiligen Wegs (`catsearch` bei neuer_kurs, `search` bei den Wegen 4 und 3). Dass Moodle die Stufen 2 und 4 für jeden Weg gleich beantwortet, ist ungemessen.
- Fortschritt bei einem neuen Kurs: Die Abfrage `core_backup_get_async_backup_progress` mit `operation=restore` ist für jeden Weg ungemessen (siehe #8).
- Der Befehl `wiederherstellung_status` startet nie neu. Vorgänge im Stand „anstehend" oder „hochgeladen" werden als fehlgeschlagen markiert; ob ein Abbruch in Moodle danach sichtbar ist, ist ungemessen.

## Instanzprofile (Issue #4): offene Teile

- Profil löschen räumt die Einträge in Claude Code und Codex auf (Issue #28). Ungemessen: Aufräumen gegen die echten Programme, auf dem Mac (`~/.claude.json`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME`) und mit `claude` aus Claude Desktop; die Claude-Tests laufen auf dem Mac nicht (Werkzeugsuche). Die Brücke für Bionic kennt nur `moodle`, ein gelöschtes Profil hat dort nie einen Eintrag.

- Die Brücke für Bionic kennt nur den Namen `moodle`; weitere Profile sind dort nicht eingerichtet.
- Arbeitsordner: Bei mehreren Profilen je ein Unterordner nach Kennung (umgesetzt); Aufräumen beim Beenden prüfen, wenn Unterordner in Benutzung sind.
- Der Wechsel des Eintrags `moodle` zur Produktivinstanz (E31, Folgen) ist mit dem Umstellen des Testinstanz-Eintrags zu tun, nicht erledigt.

## Mac-Fassung (Issue #11, #3): UNGEMESSEN und Windows-Prüfung

Umgesetzt, nicht auf einem Mac durchgespielt. Alles hier ist offen, bis es im Testkurs gemessen ist (A6: nachrüsten mit Messung, nicht in der Arbeitssitzung).

UNGEMESSEN auf dem Mac:
- Bildschirmfotos: Der Wert `0` von `RemoteDebuggingAllowed` in `/Library/Managed Preferences/<Domäne>` ist nicht gemessen; die Lesung ist aus der Richtlinienlogik abgeleitet. Ob Chrome und Edge mit `--remote-debugging-port=0` aus einem `.app`-Bündel starten, ist offen. Die Bereinigung über `ps -axww` und `kill -9` nach Profilpfad ist nicht durchgespielt.
- Skills für Claude Code auf dem Mac: E30 verlangt `~/.agents/skills` mit Verlinkung von `~/.claude/skills`. Umgesetzt ist das nicht; die App kopiert weiter je Werkzeug. Codex liest auf dem Mac womöglich nicht `~/.codex/skills`; ungemessen.
- Konfigurationsorte: Claude Code (`~/.claude.json`, `CLAUDE_CONFIG_DIR`) und Codex (`~/.codex/config.toml`, `CODEX_HOME`) auf dem Mac sind nicht mit den Clients geprüft.
- Werkzeugsuche: `/opt/homebrew/bin`, `/usr/local/bin` und `~/.local/bin` sind fest verdrahtet; die Suche im Kern (`lib/einrichtung.dart`) ist nicht in die Schnittstelle `lib/plattform/` gewandert. Die Tests der Werkzeugsuche sind auf dem Mac übersprungen, weil sie echte Programme auf dem Rechner finden; sie brauchen injizierbare Suchordner.
- Schlüsselbund und Netzwerk: Die Netzwerkrechte stehen in den Entitlements, ein Lauf mit Moodle ist ungemessen.
- Fehlende Schriften für `tool/bilder_test.dart`: Die Bilder in `docs/bilder/` stammen von Windows; auf dem Mac weichen sie ab.

Prüfen unter Windows (nach dem Umbau in #11):
- Browsersuche über App Paths und die Programmordner; Richtlinie in HKLM und HKCU; PowerShell-Bereinigung nach Profil.
- Claude Desktop (MSIX), klassischer Installer und VS-Code-Erweiterung finden claude.exe; Bionic mit der Brücke.
- Die übersprungenen Mac-Tests laufen unter Windows (`flutter test`).
- `python` in `skills/lernsituation/SKILL.md` (Zeilen 148 und 158) ruft `python` wörtlich; auf dem Mac gibt es oft nur `python3`. Entscheidung offen, ob der Skill beide nennt.
- Ein Start ohne `HOME` (Mac) oder `APPDATA` (Windows) wirft `StateError` in `einstellungen_ort.dart`; ob der Start das als Meldung zeigt, ist ungeprüft.

Nicht Teil dieses Umbaus (eigene Aufgabe):
- Installer, Signierung, Notarisierung und Release-Bau für den Mac. Der Mac bleibt bei E24 ein Entwicklungsbau.

## Lernlandkarte (Ticket #23): offene Punkte
- Ändern (Verknüpfungen der Orte setzen) geht nicht: Der Typ der Lernlandkarte steht nicht in `schreibbareModule`, `aendern` lehnt vor jeder Freigabe ab. Ungemessen ist, unter welchem Modulnamen sie in Moodle läuft; der Ticket-Test nutzt einen erfundenen Typ.
- Entscheidung der Lehrkraft offen: Werkzeug für die Lernlandkarte nachrüsten (mit Messung im Testkurs) oder Verknüpfungen in der Moodle-Oberfläche setzen (A6). Ein Plugin scheidet nach E23 aus.
- Auswahlfelder mit Zielen (etwa ein Ort) landen in `einstellungen.json` als Anzeigetext, nicht als Nummer. Zwei Aktivitäten mit gleichem Namen lassen sich dort nicht unterscheiden.
- Verweise prüft die App nur in Textfeldern (`<feld>.html`), nicht in Auswahl- und Eingabefeldern.
- Erhaltene, fehlende und „fremde" Ziele (in einem anderen Kurs) werden nicht unterschieden: `_zielTitel` liest nur den Titel. Titel werden für höchstens 10 Ziele außerhalb des Kurses abgerufen; darüber steht ein Hinweis.
- Lehrkraft-Beobachtungen, nicht reproduziert und nicht gemessen: Verweise gehen beim Kopieren verloren; einmal die Warnung `Undefined array key "p1"`.
- Quiz-Wiederherstellung (`get_questions_category()` mit `false`, MDL-89981): nicht geprüft, nicht Teil von #23.

## Aufräumen (Befunde aus dem Review, nicht behoben)

- Doppelt: `seiteVon` (`lib/moodle/sicherung.dart`) und `restoreSeite` (`lib/moodle/wiederherstellung.dart`) lesen dieselben Formularseiten. Zusammenlegen, sobald beide Abläufe gemessen und gegen die Tests geprüft sind.
- `lib/mcp/mcp_dienst.dart` hat etwa 1700 Zeilen und trägt alle Werkzeugbeschreibungen und die Verdrahtung. Aufteilen nach Werkzeuggruppen, ohne Verhalten zu ändern.
- Der Dateiname der lokalen Testzugangsdatei trägt noch den alten Namen der Testinstanz (Pfad in `docs/agents/testing.md`, `tool/mac_start.sh`, `lib/anmeldedaten.dart`). Umbenennen erst, wenn die Datei des Nutzers umbenannt ist, und alle drei Stellen zusammen.
- Lesen von Formularen (`formularLesen`, Ticket #22): Die Sperre gilt nur im Prozess. Bricht ein Lesen mitten ab, bleibt der Ordner halb neu geschrieben, statt den vorherigen Stand zu behalten (Stagingordner und Austausch am Ende wären der Weg). Der gemeldete Fehler „Directory not empty“ ist nicht nachgestellt; ob es ihn noch gibt, muss im Test auf dem Gerät gemessen werden.
- Flaky: `test/frage_lesen_ordner_test.dart` („Gleichzeitiges Lesen derselben Frage") ist im Vollauf einmal gescheitert (`FileSystemException: Directory not empty` beim Löschen des Ordners in `formular_lesen.dart`, `_formularLesenOhneSperre`). Allein läuft er grün; Ursache ungeprüft, vermutlich Wettlauf beim Aufräumen. Geprüft (Ticket #20): Die Testdateien teilen keinen Arbeitsordner, jede legt ihn mit `createTempSync` und eigenem Präfix an; der Wettlauf liegt innerhalb dieses einen Tests (gleichzeitige Lesevorgänge, Ordner-Sperre und Neuanlage in `formular_lesen.dart`). Gehört zu #22, nicht geändert.
- Anhänge im Dateimanager (`mod_resource` und ähnliche): Ticket #21 liest nur Verweise im Bearbeitungsformular. Dateien, die nur im Dateimanager einer Aktivität liegen (`mod_resource`, `mod_folder`), sind dort eine Prüflücke („nicht lesbar"), bis eine erlaubte Leseseite in der Positivliste steht (`lib/moodle/moodle_zugang.dart`); danach im Testkurs messen.
- Wiederherstellung, Feldvergleich schreibbarer Typen: Der Vergleich nach der Wiederherstellung prüft nur Zahl und Namen der Aktivitäten, Anhänge (Inhalt per SHA-1, nie Adressen oder Textlängen) und Fragennamen. Wort- und einstellungsgenau (Text, Einstellungen, Beschreibungen) wird noch nicht verglichen. Kommt er, muss er Instanzadressen vor dem Vergleich normalisieren: Quell- und Zieldomain haben verschiedene Länge, jedes Bild und jeder Link erzeugte sonst eine Differenz. Test dafür: kürzere Zieldomain, drei Bilder, keine Abweichung.
- Prüflücken: Bei jeder Prüfung, die nicht verfügbar ist und als Prüflücke im Bericht steht (nicht schreibbare Typen, Dateimanager-Dateien, Fragenherkunft, unlesbare Archive), jeweils prüfen, ob sie sich einbauen lässt, und die Antwort im Testkurs messen.
- Wiederherstellung nach gemeldetem Fehler: Das Prozessende gilt nur bei Status 800 (`backup::STATUS_FINISHED_ERR`, aus dem Moodle-Quelltext, ungemessen). Im Testkurs messen, was `core_backup_get_async_backup_progress` bei einem wirklich fehlgeschlagenen Lauf liefert; sonst bleibt jeder Fehler beim Nachfragetext an die Verwaltung.
- Wiederherstellung (Ticket #21): Das Reparaturangebot bei nicht verifizierten Anhängen ist nur ein Hinweistext. Ein eigener, freigegebener Weg über `aktivitaet_aendern` fehlt; ohne ihn gibt es keine Reparatur.
- Backup-Controller: Die Statuswerte 700, 800 und 900 (laut Moodle-Quelltext wartend, ausführend, mit Fehler beendet) wertet `bewerteFortschritt` nicht aus; nur `status` 1000 mit `progress` 1 gilt als Ende. Ob der Fortschrittsdienst 900 als `error` meldet, ist im Testkurs zu messen.
- Die Sperre `ordnerSperre` in `aendern` (`lib/moodle/formular_schreiben.dart`) gilt auch während der Freigabe und hält andere Lesevorgänge dieses Ordners bis zu 30 Minuten auf. Sie umfasst bewusst Standprüfung bis Schreiben (Ticket #22); sie nur um den Schreib- und Lesevorgang zu legen, bräuchte nach der Freigabe eine erneute Standprüfung unter der Sperre. Erst mit einem Test dafür ändern.
- `lib/moodle/wiederherstellung.dart` und `lib/moodle/sicherung.dart` haben je etwa 800 Zeilen. Aufteilen (etwa Vorgangsspeicher, Archivprüfung, Gegenlesen), ohne Verhalten zu ändern.

MCP-Kennzeichnung: `wiederherstellen_datei` bleibt als ganzes Werkzeug `destructiveHint: true`, weil MCP keine vom Parameter `weg` abhängige Kennzeichnung bietet. In der App-Freigabe gilt die Löschwarnung nur für löschende Wege.

Messstand Quiz-Einfügen: Die zurückgelesenen Quizze waren verborgen. Die Dauer einer möglichen Sichtbarkeit dazwischen bleibt ungeprüft. Laufender Fortschritt und Abschluss wurden beobachtet; der Cron auf der Zielinstanz wurde durch die Lehrkraft bestätigt. Bei geteilter Sammlung blieb auf derselben Instanz der Bezug zur Quelle erhalten; auf der anderen Instanz entstand eine geteilte Sammlung. Herkunft bleibt dabei unverifiziert. Keine offenen Ad-hoc-Aufgaben nach Abschluss laut Lehrkraft; ZZ-Proben und die zusätzliche Sammlung sind aufgeräumt.

- Weitere Quellverweise der Art „Ticket #n“ und „Befund n“ außerhalb der bereinigten Sicherungs- und Herkunftslogik bei künftigen Änderungen durch die Begründung ersetzen.
