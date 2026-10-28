# Anlegen und Bearbeiten von Aktivitäten

## Ablauf

**Neu anlegen:**

```
1. Ordner im Arbeitsordner anlegen, etwa  <Arbeitsordner>\ls3-auftrag\
2. Inhalt hineinschreiben (Datei-Werkzeug):  page.html / introeditor.html …,
   Bilder nach dateien\, Dateien nach bereiche\<feld>\
3. aktivitaet_anlegen(kurs, abschnitt_id, typ, name, ordner, einstellungen)
4. Antwort lesen: cmid, verborgen, Rückleseprobe
```

**Bestehendes ändern:**

```
1. aktivitaet_lesen(cmid)            -> <Arbeitsordner>\cm-<cmid>\
2. <feld>.html bearbeiten, dateien\ und bereiche\ anpassen
3. aendern(ordner, einstellungen)    -> Freigabe in der App, schreiben, zurücklesen
```

Der Ordner eines gelesenen Objekts weiß selbst, was er ist (`.stand/`); für
`aendern` genügt der Pfad. Jede Änderung beginnt mit frischem Lesen, auch wenn
der Ordner von früher in der Sitzung noch da ist: Maßgeblich ist, was in Moodle
steht, und die Lehrkraft kann inzwischen selbst gespeichert haben. Zeigt Moodle
beim Schreiben einen anderen Stand als beim Lesen, bricht `aendern` ab — dann
neu lesen und die Änderung am neuen Stand noch einmal anbringen.

## Was in den Ordner gehört

| Typ | Inhalt | Dateibereich |
|---|---|---|
| `page` Textseite | `page.html` — **der Seiteninhalt** (Pflicht); `introeditor.html` nur für die Beschreibung | — |
| `label` Textfeld | `introeditor.html` — der ganze Inhalt (Pflicht); zum Namen siehe unten | — |
| `assign` Aufgabe | `introeditor.html` Beschreibung, `activityeditor.html` Arbeitsanweisungen (erscheinen erst bei der Abgabe) | `bereiche/introattachments/` Zusätzliche Dateien |
| `folder` Verzeichnis | `introeditor.html` optional | `bereiche/files/` mit Unterordnern |
| `resource` Datei | `introeditor.html` optional | `bereiche/files/` — die eine Datei |
| `url` Link | `introeditor.html` optional | — (Adresse als Einstellung `externalurl`) |
| `subsection` Unterabschnitt | — (Beschreibung danach über `abschnitt_lesen`/`aendern`) | — |
| `book`, `quiz`, `qbank`, `checklist`, `wiki`, `board`, `kanban` | `introeditor.html` optional | — |

Die häufigste Verwechslung: Der Inhalt einer Textseite gehört in `page.html`,
nicht in `introeditor.html`. Bilder liegen immer in `dateien/` und stehen im
Text als `@@PLUGINFILE@@/<name>`; die App lädt sie in den Entwurfsbereich des
Feldes, in dem sie vorkommen.

**Der Name eines Textfelds** ist sein „Titel im Kursindex", und der sagt, was das Textfeld ist: „Handlungssituation", „Hinweis zur Abgabe" — nicht der Textanfang. Ein kurzer Titel liest sich im Kursindex besser als ein abgeschnittener Satz, du findest das Textfeld damit in `kurs_uebersicht` wieder, und er bleibt stimmig, wenn sich der Text ändert. Das zählt, denn Moodle übernimmt beim Anlegen den mitgegebenen Namen und behält ihn beim Ändern, auch wenn sich der Text darunter ganz ändert (gemessen). Passt der Titel nach einer Änderung nicht mehr, gib in `aendern` einen neuen mit (`einstellungen: {"name": "…"}`); die Lehrkraft sieht ihn in der Freigabe. Heißt ein von Hand angelegtes Textfeld nach seinem alten Textanfang, schlag im Plan einen Titel vor. `name: ""` ließe Moodle den Namen aus dem jetzigen Textanfang bilden, aber nur einmal: Danach steht er fest wie jeder andere.

## Einstellungen setzen

Einstellungen gehen als Parameter `einstellungen` mit, Schlüssel wie in
`einstellungen.json`:

```json
{
  "duedate": "2026-10-15 23:55",
  "gradingduedate": "aus",
  "submissionplugins": { "Texteingabe online": "ja", "Dateiabgabe": "nein" },
  "grade": { "Maximalpunkte": "20" },
  "visible": "Auf der Kursseite verbergen"
}
```

| Art | Schreibweise |
|---|---|
| ein Steuerelement | der Wert als Text, wie er angezeigt wird: `"Nein"`, `"20"`, `"ja"` |
| Datum | `"JJJJ-MM-TT SS:MM"` oder `"aus"` |
| Optionsfelder mit demselben Namen | Beschriftung oder eindeutiger Wert aus `optionen`; deaktivierte Optionen sind nicht wählbar |
| mehrere Steuerelemente in einer Zeile | `{ "Beschriftung": "Wert" }` |

Unbekannte Schlüssel oder Werte brechen ab, **bevor** etwas geschrieben wird,
und die Meldung nennt die Möglichkeiten. Rate also nicht lange, sondern lies
die Meldung. Welche Schlüssel ein Typ hat, steht nach dem ersten Lesen in
`einstellungen.json`; beim Anlegen nennt Moodle fehlende Pflichtangaben mit
Feld und Beschriftung.

Den Namen setzt `aktivitaet_anlegen` selbst; beim Ändern ist er die
Einstellung `name`. Sichtbarkeit nie über `einstellungen`, sondern mit
`sichtbarkeit_setzen` — das geht über die Freigabe.

### Aufgabe (`assign`)

| Schlüssel | Bedeutung |
|---|---|
| `allowsubmissionsfromdate` | Abgabebeginn |
| `duedate` | Fälligkeitsdatum |
| `cutoffdate` | Letzte Abgabemöglichkeit |
| `gradingduedate` | An Bewertung erinnern |
| `submissionplugins` | Abgabetypen: `{ "Texteingabe online": "ja", "Dateiabgabe": "ja" }` |
| `grade` | Bewertung: `{ "Typ": "Punkt", "Maximalpunkte": "20" }` |
| `advancedgradingmethod_submissions` | Bewertungsmethode: einfache direkte Bewertung, Bewertungsrichtlinie, Rubrik |

**Die Falle mit `gradingduedate`:** Moodle setzt die Erinnerung an die
Bewertung beim Anlegen auf einen Termin nahe heute. Schiebt man nur `duedate`
in die Zukunft, liegt die Erinnerung davor, und das Formular wird mit „Der
Erinnerungstermin zur Bewertung kann nicht früher liegen als das
Fälligkeitsdatum" abgewiesen. Also immer mitbehandeln — `"aus"` oder ein
Datum nach der Frist.

Fristen an bestehenden Aufgaben zu ändern trifft Lernende unmittelbar; die
Freigabe zeigt es, sag es trotzdem vorher im Chat.

### Collabora (`collabora`) und Gruppenwahl (`choicegroup`)

Bei bestehenden Collabora-Aktivitäten und Gruppenwahlen ändert `aendern` ausschließlich Gruppenmodus
und Gruppierung. Lies die Aktivität frisch und verwende die angebotenen Optionen
aus dem Formular; eine Gruppierungsnummer aus einem anderen Kurs ist kein Beleg.
Texte, Dateien, Name, andere Einstellungen und unverändertes Neuspeichern bleiben
gesperrt. Dokumentinhalte werden damit nicht bearbeitet. Meldet das Zurücklesen `verified: false` mit „übrige Felder unverändert“, hat Moodle beim Speichern noch etwas anderes verändert: Sag es der Lehrkraft und lies die Aktivität neu, statt es zu überspielen.

### Gruppierungen nach der Wiederherstellung

Sicherungen ohne Nutzerdaten nehmen keine Gruppen und Gruppierungen mit. Auch
vorhandene Gruppen und „Getrennte Gruppen“ ersetzen die gewählte Gruppierung
nicht. Wer eine Aktivität mit Gruppierung wiederherstellt, ordnet sie danach zu:

1. Im Quellkurs `gruppierungen_lesen` und die Gruppierung der Aktivität
   (`aktivitaet_lesen`, Einstellung `groupingid`).
2. Im Zielkurs `aendern` mit `groupingid` auf den Namen aus der Quelle.
3. Meldet `aendern` eine **Rückfrage**, weil es die Gruppierung im Zielkurs nicht
   gibt: Stelle sie der Lehrkraft in diesen Worten -- „Soll die Gruppierung
   ‚…‘ mit den Gruppen … angelegt werden?" --, nenne die Gruppen aus der Quelle,
   und rufe erst nach ihrem Ja `gruppierung_anlegen` auf, danach `aendern` noch
   einmal. Ohne Ja bleibt die Aktivität ohne Gruppierung; sag ausdrücklich,
   dass sie fehlt. Lass sie nie stillschweigend weg.

Bestätige das Rückleseergebnis (`verified`), statt eine Übernahme zu behaupten.

### Wiki (`wiki`)

| Schlüssel | Bedeutung |
|---|---|
| `wikimode` | gemeinsam oder persönlich. **Nur das gemeinsame** bearbeitet die App; das persönliche besteht aus Nutzerdaten. Nach dem Anlegen nicht mehr änderbar. Ein Wiki im Gruppenmodus (`groupmode`) liest und schreibt die App nicht, auch solange der Kurs keine Gruppen hat: Mit Gruppen hat jede Gruppe eigene Seiten. |
| `firstpagetitle` | Titel der Startseite — die erste Seite muss genau so heißen |
| `defaultformat` | Standardformat; die App schreibt HTML |
| `forceformat` | Format festlegen |

Die Seiten selbst entstehen mit `wikiseite_schreiben`.

### Board (`board`)

| Schlüssel | Bedeutung |
|---|---|
| `templateid` | Board-Vorlage (Exit Ticket, SWOT, Project Kanban board …); bringt Spalten mit |
| `addrating` | Beiträge bewerten: nein, Teilnehmer/innen, Trainer/innen, alle |
| `hideheaders` | Spaltentitel vor Teilnehmer/innen verbergen |
| `sortby` | Sortierung: keine, Erstellungsdatum, Bewertung |
| `singleusermode` | Einzelnutzermodus: aus, privat, öffentlich — **bei privat und öffentlich arbeitet die App nicht auf den Boards** |
| `postbyenabled`, `postby` | Beiträge nur bis zu einem Datum |
| `userscanedit` | Teilnehmer/innen dürfen eigene Beiträge verschieben |
| `embed`, `hidename` | Board in die Kursseite einbetten, Namen dabei verbergen |
| `completionnotes` | Abschluss nach n Beiträgen |

### Kanban-Board (`kanban`)

| Schlüssel | Bedeutung |
|---|---|
| `userboards` | Persönliche Boards: keine, zusätzlich, ausschließlich — **die App arbeitet nur auf dem Kursboard** |
| `usenumbers`, `linknumbers` | Kartennummern verwenden, verlinken |
| `showauthors` | Kartenersteller/in anzeigen |
| `completioncreate`, `completioncomplete` | Abschluss nach n erstellten bzw. abgeschlossenen Karten |

### Fortschrittsliste (`checklist`)

| Schlüssel | Bedeutung |
|---|---|
| `teacheredit` | Aktualisiert von: nur Teilnehmer/in, nur Trainer/in, beide |
| `autopopulate` | Kursmodule anzeigen: nein, aktueller Abschnitt, ganzer Kurs |
| `autoupdate` | Abhaken bei Abschluss: nein, ja (nicht übergehbar), ja (übergehbar) |
| `useritemsallowed` | Teilnehmer/in darf eigene Einträge hinzufügen |
| `studentcomments`, `teachercomments` | Kommentare |
| `lockteachermarks` | Kennzeichnungen von Trainer/innen sperren |
| `duedatesoncalendar` | Fälligkeiten in den Kalender |
| `emailoncomplete` | E-Mail bei Abschluss |
| `maxgrade` | Beste Bewertung |

### Test (`quiz`)

Die Einstellungen eines Tests — Zeitfenster, Versuche, Bewertungsmethode,
Frageverhalten — stehen im Skill `moodle-fragen`, `references/tests.md`.

### Überall

`visible` (über `sichtbarkeit_setzen`), `cmidnumber`, `groupmode`,
Voraussetzungen und Abschlussverfolgung. Voraussetzungen stehen als JSON in
einem verborgenen Feld; setze sie nur, wenn der Nutzer sie ausdrücklich
vorgibt, und sag, was du gesetzt hast.

## HTML

Wie der Inhalt geschrieben wird — keine `style`-Attribute, Überschriften ab `<h3>`, Tabellen, Kästen, Bilder, Links, Platz zum Ausfüllen —, steht für alle Skills gleich in **`references/html.md`**.

## Bestehende Inhalte ändern

Der häufigste Fall im Alltag — und der mit dem größten Schadenspotenzial, weil
hier vorhandene Arbeit auf dem Spiel steht. Bewährtes Muster: lesen, prüfen,
**ergänzen statt ersetzen**.

- Bearbeite die gelesene `<feld>.html` gezielt an der Stelle, um die es geht.
  Schreib sie nicht aus dem Gedächtnis neu — dabei gehen Verweise, Bilder und
  Formatierungen verloren, die niemand vermisst, bis sie fehlen.
- Wirkt ein Feld unerwartet leer, halt an und klär, warum.
- Die Freigabe zeigt der Lehrkraft einen Zeilenvergleich. Ein Vergleich, in dem
  viel mehr rot ist als geplant, ist ein Grund, abzulehnen und neu anzusetzen.
- Nach dem Schreiben liest die App zurück (`verified`). `false` heißt: nicht
  alles ist angekommen — die Antwort nennt, was abweicht.

## Mehrere Aktivitäten hintereinander

Lege Inhalte in der Reihenfolge an, in der sie im Abschnitt stehen sollen —
neue Aktivitäten kommen ans Ende des Abschnitts. Das erspart das nachträgliche
Verschieben, das eine Freigabe je Schritt kostet. Ein Ordner je Aktivität; er
ist nur Zwischenstand und wird mit dem Arbeitsordner geleert.
