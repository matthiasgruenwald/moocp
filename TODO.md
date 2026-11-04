# Features

Offene Punkte außerhalb von Specs und Umsetzungstickets. Je Punkt höchstens drei Zeilen; Ergebnisse von Messungen stehen im Quelltext oder in der ADR ([Regeln](docs/agents/dokumentation.md), Regel 8).

## Aktivitäten und Fragen

- Aktivität „Befragung" (questionnaire) unterstützen, für Unterricht wie für Organisatorisches (etwa Befragung zur Unterrichtsqualität).
- Aktivität „Lernpfad" und Badges vollständig unterstützen, samt didaktischen Hinweisen und Regeln zur Gamification.
- Fortschrittsliste: Farbe eines Eintrags (`nextcolour`); Bewertungsrichtlinie: häufig gebrauchte Kommentare.
- Auswahlgruppen (`choicegroup`) und Bildergalerien ändern: siehe #44. Collabora und `choicegroup` fehlen auf der Testinstanz; beim ersten echten Einsatz Gruppenmodus, Gruppierung und `verified` prüfen.
- Fragensammlung (`qbank`) verbergen, verschieben, duplizieren: geht nicht, weil sie nicht in der Kursstruktur steht; Löschen hat einen eigenen Weg über die Sammlungsliste, die drei brauchten denselben.
- Fragen zwischen Kategorien verschieben scheitert auf der Testinstanz (`qbank_bulkmove/bulk_move` lädt nicht); nach dem Leeren der Caches erneut prüfen.
- Fragen: Struktur vorhandener Fragen ändern (weitere Antwort, weiterer Knoten) ist nicht eingebaut. Weitere Zusatz-Fragetypen (Formulas, GeoGebra, Kprim …) nur nach dem Messverfahren in `skills/moodle-fragen/CLAUDE.md`; `ddimageortext` und `ddmarker` bleiben bewusst nur lesend.
- STACK: vorhandenen Fragetest ändern, löschen oder ergänzen. Er liegt auf `questiontestedit.php` (nicht auf der Positivliste); bisher hilft nur Neuanlegen.
- Konventionen bei Fragen: `fragensammlungen` und `fragen_lesen` liefern sie nicht mit (nur der Skilltext verweist darauf); prüfen, ob eines davon sie mitliefern sollte.
- Kurskonventionen verwalten: Vorlagen (allgemein je Schulform/Fach anonym mit den Skills, schulspezifisch in Moodle) anbieten, aus Vorlage, eigenem oder fremdem Kurs oder Datei mit Vergleich übernehmen. Offen: Kopie oder Verweis, was ist übertragbar, ob Zusatzdateien mit `aktivitaet_lesen`/`aendern` von Kurs zu Kurs kommen. Prüfstein: drei parallele Kurse je Jahrgang mit gemeinsamen Regeln.

## Lernlandkarten

- Verknüpfungsstatus abfragbar machen: #47. SVG-Layout und Kartenpunkte bearbeiten: #58.
- Rücklesen meldete einmal `verified: false`, obwohl ein frisches Lesen stimmte; nicht reproduziert. Tritt es wieder auf, die Teilprüfungen in `lernlandkarte_verknuepfungen_setzen` einzeln ausgeben.
- Vorlage zeichnet nur ein Rechteck statt des Hintergrundbilds; offen, ob sie es einbinden soll.
- Auswahlfelder mit Zielen landen in `einstellungen.json` als Anzeigetext; gleichnamige Aktivitäten lassen sich dort nicht unterscheiden. Verweise prüft die App nur in Textfeldern (`<feld>.html`).
- Unterrichtsverteilung: Der Fingerabdruck der Kartenkopie entfernt alle Ortsbeschriftungen (`ohneOrtsbeschriftung`); auf `_gleicheSvgMitNeubeschriftungen` einengen, mit Test für eine echte Änderung an Form oder Ort.
- Quiz-Wiederherstellung (`get_questions_category()` mit `false`, MDL-89981) nicht geprüft.

## Sicherung, Wiederherstellung, Übertragung

- Freigaben ohne Zeitlimit des KI-Aufrufs: #34. Vergleich nach der Wiederherstellung und Prüflücken: #35. Anhänge reparieren: #36. Fehlerzustände und Doppelstart: #37. Ersetzende Wege und neuer Kurs: #38.
- Ungemessene Annahmen bei Sicherung und Wiederherstellung stehen als `UNGEMESSEN` im Quelltext (`lib/moodle/sicherung*.dart`, `wiederherstellung*.dart`); sie werden nur im Testkurs gemessen, nie in einer Arbeitssitzung (A6).
- Übertragung (`uebertragen`) auf der Instanz durchspielen: Zusammenfassung in der Freigabe, Dubletten-Hinweise im Bericht, teilweise fehlgeschlagener Lauf, Ablehnung in der App (stoppt sie die übrigen Ziele?), Erhalt der Einträge in `uebertragungen.json` bei Abbruch.
- Übertragung: Ein Auftrag fragt einmal für alle Ziele und danach jeden Schreibschritt erneut; offen, ob das für die Stufe „mittel" zu viel ist.
- Freigabetest „Die Stufe steht in den Einstellungen …" scheiterte einmal im Gesamtlauf (Flake); beobachten.
- Gruppierungen: Eine ZZ-Probe-Gruppierung mit zwei Gruppen steht auf der Testinstanz und lässt sich nur in Moodle löschen. Wiederherstellung: ob die Rückmeldung je Aktivität „Gruppenmodus gesetzt, Gruppierung leer" ausweisen soll, hängt von 50 Formularlesevorgängen bei 50 Aktivitäten ab.
- Sichtbarkeit: Setzt `sichtbarkeit_setzen` »verfügbar ohne Link« zurück, und bei welchen Umschaltungen? Messung im Testkurs, Werkzeug oder Hinweis danach anpassen: #45.

## Skills

- `lernsituation`: Selbstprüfung braucht Python (`scripts/pruefe-lernsituation.py`), das vielen Lehrkräften fehlt; als Werkzeug der App oder mit Flutter ersetzen. Im Skill steht `python` wörtlich, auf dem Mac oft nur `python3`.
- `lernsituation`: ODT-Ausgabe für den Druck (Skill `odt`); die SchuCu-Tabelle müsste nach „Das Design außerhalb von Moodle" (`skills/lernsituation/CLAUDE.md`) entstehen.
- `lernsituation`: SchuCu-Tabelle auf anderen Instanzen ohne CSS für `lernsituation`, `lshead`, `lssubhead`, `lsdata`, `lsspacer`: Stile in die Vorlagen (`style` ist dort erlaubt, A8) oder CSS fürs Theme mitliefern. Weitere Fachvokabulare für Zeichnungen (DIN EN 60617, Netzsymbole) einzeln messen.
- Skills: Prüfen, ob Codex Skills aus `~/.agents/skills` über den Skill-Mechanismus lädt (bisher nur die Datei gelesen); danach Quelle `~/.agents/skills` und Verlinkung nach E30 umsetzen (#40).
- Optimierungsphase: Prüfen, ob MCP-Schnittstelle und Skills tokensparend sind, ob also nur Nutzdaten ohne unnötige HTML-Tags durchgeleitet werden.

## Anonyme Aufgabenbewertung

Aufgabenabgaben nur anonymisiert an die KI: Teilnehmerliste pro Kurs auf Kürzel (S1, S2 …) abbilden, Namen in PDF, Office und Binärdateien (auch mit Tippfehlern) vor der Übergabe ersetzen und zurücksubstituieren, Bilder erst mit zuverlässiger Handschrifterkennung (etwa kraken) zulassen, Dateitypen einzeln freigeben. Voraussetzung: A1 wird für die Teilnehmerliste bewusst geändert, die Liste bleibt in der App.
Derselbe Namensabgleich könnte alles prüfen, was an die KI geht (Wiki, Board, Kanban, Konventionsdateien); er ersetzt die Verdachtsmuster der Konventionen nicht. Offen: nur Namen des aktuellen Kurses oder eine deutsche Namensliste.

## Plattformen und Betrieb

- Windows ungemessen nach dem Umbau (#11): Browsersuche und Richtlinie in HKLM/HKCU, Claude Desktop (MSIX) und Installer finden `claude.exe`, Release-Bau und Installer, Übergabe an die Lehrkraft mit echtem Schutzdienst.
- macOS: Browser aus einem `.app`-Bündel mit `--remote-debugging-port=0`, Richtlinienwert `0` und Prozessbereinigung nicht durchgespielt; Claude Code und Codex lesen ihre Pfade (`~/.local/bin`, `/opt/homebrew/bin`, Konfigurationsorte) womöglich anders (siehe #40, [0024](docs/adr/0024-plattformen.md)).
- macOS: Schlüsselbund im Release-Bau ohne Datenschutzgruppe prüfen ([0026](docs/adr/0026-schluesselbund-mac.md)). Entfernen der KI-Werkzeug-Einträge fehlt (keine Deinstallation): Befehl in der App oder Hinweis ([0013](docs/adr/0013-ki-werkzeuge-einrichten.md)).
- macOS: Ohne `HOME` lösen `ClaudeCode`, `CodexCli` und `LmStudio` ihre Ordner relativ auf (`?? ''` in `lib/einrichtung.dart`), ein Start ohne `HOME`/`APPDATA` wirft `StateError` in `einstellungen_ort.dart`; abfangen oder verweigern.
- macOS: Der Arbeitsordner liegt im `$TMPDIR`, die Spec (#1, `docs/specs/0001-macos-sicherung-wiederherstellung.md`) nennt einen anderen Ort; klären, bevor Sicherungen dort entstehen. LM Studio mit Bionic fehlt auf dem Mac (die Brücke ist ein Windows-Programm).
- Linux-Port: #57. Release automatisch bauen und in GitHub veröffentlichen (Windows-Installer, macOS, Linux; Changelog als Release-Text).
- Codex CLI mit echter Version prüfen: sieht es die Werkzeuge aus `[mcp_servers.moodle]`, lädt es Skills, ab welcher Version geht HTTP ohne `experimental_use_rmcp_client` (README nennt 0.77), öffnet es die PNGs von `bildschirmfoto`, nimmt es `tool_timeout_sec = 2100` an? Dazu in `~/.codex/config.toml` den Flutter-Cache als `writable_roots` freigeben, damit `flutter analyze` unter der Sandbox läuft.
- Protokoll: „KI-Werkzeug verbunden: …" (`oninitialized` in `mcp_dienst.dart`) erscheint seit dem 09.10.2026 nicht mehr; ohne es zeigt das Protokoll nicht, welcher Client schrieb (E21). Prüfen, ob `status` es noch weiß.
- Schutzdienst: Antrag auf Ausnahme beim Betreiber vorbereiten (was die App tut, A1–A4, warum sie sich offen zu erkennen gibt) und klären, wer ihn je Instanz stellt ([0034](docs/adr/0034-uebergabe-und-schutzdienst.md)).
- Instanzprofile: Die Brücke für Bionic kennt nur den Namen `moodle`; weitere Profile fehlen dort. Der Eintrag `moodle` muss noch auf die Produktivinstanz umgestellt werden (E31). Aufräumen der Arbeitsunterordner beim Beenden prüfen, wenn Ordner in Benutzung sind.
- Zwischenablage mit HTML auf dem Mac: erst, wenn die App dort ausgeliefert wird ([0034](docs/adr/0034-uebergabe-und-schutzdienst.md)).

# Bugs

- Bildschirmfotos: Bei schmaler Inhaltsbox werden links Textanfänge abgeschnitten (auf der zweiten Testinstanz reproduziert, der Quelltext ist vollständig). Inhaltskoordinaten und Layoutänderungen zwischen Messen und Aufnahme prüfen, ohne den Ausschnitt auf Kopf oder Navigation auszuweiten.
- Sicherheit: Der MCP-Schlüssel steht im Klartext in `~/.claude.json` und `~/.codex/config.toml`; bewusst so (E6). Umbau auf Umgebungsvariable möglich, wenn Codex per `codex mcp add` eingerichtet wird.
- Sperrliste: `pluginfile.php` ist zugelassen, gesperrt sind nur Profil, Abgaben, Testantworten, Foren, Workshop, Datenbank, Lektion. Es fehlen Bereiche, in die Lernende Dateien legen: Glossar (`mod_glossary/attachment`, `entry`), Wiki (`mod_wiki/attachments`), Blog sowie Board, Kanban, Journal. Namen messen, sperren, Tests in `test/sperrliste_test.dart`; vorher klären, was die Lesewerkzeuge verlieren (Bilder der Lehrkraft in Wiki oder Glossar).
- Schmales Fenster: Unter etwa 900 px läuft der Kopf der Protokollspalte über (linke Spalte fest 460 px).
- Formulare lesen (`formularLesen`): Bricht ein Lesen mitten ab, bleibt der Ordner halb neu geschrieben; Stagingordner mit Austausch am Ende, Flake `test/frage_lesen_ordner_test.dart` ("Directory not empty"): #39. Dateien nur im Dateimanager (`mod_resource`, `mod_folder`) sind eine Prüflücke, bis eine Leseseite auf der Positivliste steht: #35.
- `ordnerSperre` in `aendern` hält bis zu 30 Minuten (Freigabe) andere Lesevorgänge desselben Ordners auf; nur mit einer erneuten Standprüfung unter der Sperre und einem Test dafür verkürzen.
- Wiederherstellung: `wiederherstellung_status` setzt einen Vorgang „anstehend"/„hochgeladen" ohne laufende Sitzung auf „fehlgeschlagen" und gibt damit die Sperre frei, obwohl das Senden geschehen sein kann (#37). Die Reihenfolge Doppelstart-Prüfung vor Freigabe hat noch keinen Ende-zu-Ende-Test (braucht eine gültige .mbz-Fixture).
- Widerspruch Codex und Browser: Codex kann über `mcp__cua_repl` selbst einen Browser steuern; das Risiko ist akzeptiert ([0029](docs/adr/0029-sicherungen-und-verzweigung.md)), steht aber noch nicht in der Dokumentation für Lehrkräfte.
- Aufräumen: Große Dateien teilen (`mcp_dienst.dart`, `moodle_zugang.dart`, `formular_schreiben.dart`, `wiederherstellung.dart`, `sicherung.dart`): #43. Der Dateiname der lokalen Testzugangsdatei trägt noch den alten Namen der Testinstanz (`docs/agents/testing.md`, `tool/mac_start.sh`, `lib/anmeldedaten.dart`); alle drei Stellen mit der Datei des Nutzers zusammen umbenennen. Quellverweise der Art „Ticket #n" und „Befund n" im Quelltext bei Änderungen durch die Begründung ersetzen.
