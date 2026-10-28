# Lesen: Kursstruktur und Inhalte

## Adressen deuten

Der Nutzer wirft dir meist einfach eine Adresse hin. Daraus liest du:

| Adresse | Was du hast |
|---|---|
| `/course/view.php?id=123` | Kurs 123 |
| `/course/view.php?id=123&section=4` | Kurs 123, Abschnitt an Position 4 |
| `/course/section.php?id=456` | Abschnitt mit der id 456 |
| `/mod/<typ>/view.php?id=789` | **cmid** 789 (nicht die Instanz-ID!) |
| `/course/modedit.php?update=789` | cmid 789 |

Der häufigste Denkfehler: `id` in einer `/mod/...`-Adresse ist die **course
module id**, nicht die Kurs-ID und nicht die Aufgaben-ID. Genau diese cmid
nehmen die Werkzeuge. Den Kurs dazu nennt `aktivitaet_lesen(cmid)` in seiner
Übersicht.

## Kursstruktur

`kurs_uebersicht(kurs)` antwortet etwa so:

```
Kurs 12 „Beispielkurs": 6 Abschnitte, 41 Aktivitäten (7 verborgen)
Abschnitt 0 [id 1540] „Allgemeines"
  15271 page „Aufgabe 3: Aufbau und Funktionsweise von Schützen"
Abschnitt 4 [id 1547] „Kachel 4"
  15449 quiz „ZZ Probetest" [verborgen]
  15438 subsection „Phase 1"
      Abschnitt 7 [id 4768] „Phase 1" (Unterabschnitt)
        15439 label „Handlungssituation …"
```

- **Die Nummer** ist die Position, **die id** in eckigen Klammern das, was die
  Werkzeuge brauchen (`abschnitt_id`, `ziel_abschnitt_id`,
  `nach_abschnitt_id`). Die Nummer ändert sich beim Verschieben, die id nie.
- **Typen** stehen intern (`assign`, `page`, `label`, `folder`, `resource`,
  `url`, `quiz` …). Übersetze sie für den Nutzer: „Aufgabe", „Textseite",
  „Textfeld", „Verzeichnis", „Datei", „Link", „Test".
- **Ein Unterabschnitt steht zweimal da**: als Aktivität `subsection` mit
  cmid, und eingerückt darunter als eigener Abschnitt mit id. Die cmid braucht
  man zum Verschieben des ganzen Unterabschnitts, die id zum Beschreiben und
  als Ziel für Inhalte. Gezählt wird er nur einmal.

### Sichtbarkeit richtig lesen

| Angabe | Bedeutung für Lernende |
|---|---|
| (keine) | sichtbar |
| `[verborgen]` | nicht sichtbar, nicht erreichbar |
| `[ohne Link erreichbar]` | nicht auf der Kursseite, **aber über die Adresse abrufbar** |
| `[eingeschränkt]` | sichtbar, aber an Voraussetzungen geknüpft |

Verschachtelung musst du nicht nachrechnen: Ist ein Abschnitt verborgen, sind
es die Aktivitäten darin auch, und die Übersicht zeigt das so.

„Ohne Link erreichbar" schützt nichts — wer die Adresse kennt oder rät, kommt
dran. Für Lösungen ist es ungeeignet. Die App meldet unter **„ACHTUNG, für
Lernende erreichbar"** alles, was nach Lösung, Erwartungshorizont, Klausur oder
Lehrermaterial klingt und trotzdem erreichbar ist. Das ist ein Verdachtsraster,
kein Beweis — sag es dem Nutzer trotzdem von selbst; er hat es mit Sicherheit
nicht absichtlich so eingestellt.

Bei sehr großen Kursen: Gib nicht alles aus. Zeig die Abschnitte mit Anzahl der
Aktivitäten und geh auf Nachfrage in die Tiefe.

## Inhalt einer Aktivität

`aktivitaet_lesen(cmid)` liest das Bearbeitungsformular in `cm-<cmid>/` (Aufbau
im SKILL.md, Abschnitt „Inhalte lesen"). Warum das Formular und nicht die
Ansichtsseite: Nur dort steht der **gespeicherte** Quelltext. Die Ansichtsseite
zeigt eine aufbereitete Fassung — Filter angewendet, Adressen umgeschrieben —,
und wer die zurückspeichert, verändert die Seite unbemerkt.

Die Übersicht der App ist der Wegweiser: Gliederung, Bilder, Verweise,
Einstellungen, Befunde. Maßgeblich bleibt der Quelltext im Ordner.

### Einstellungen lesen

`einstellungen.json` ist eine Liste von Einträgen, gemessen an einer Aufgabe:

```json
{ "schluessel": "duedate", "label": "Fälligkeitsdatum", "wert": "2026-10-01 00:00" }
{ "schluessel": "cutoffdate", "label": "Letzte Abgabemöglichkeit", "wert": "aus" }
{ "schluessel": "submissionplugins", "label": "Abgabetypen", "wert": "Texteingabe online: nein · Dateiabgabe: ja" }
{ "schluessel": "grade", "label": "Bewertung", "wert": "Typ: Punkt · … · Maximalpunkte: 100" }
```

Die Werte stehen so, wie Moodle sie anzeigt — Datumsangaben als
`JJJJ-MM-TT SS:MM` oder `aus`, Auswahlfelder mit ihrem Text, Kästchen als `ja`
oder `nein`, mehrere Steuerelemente in einer Zeile als `Beschriftung: Wert`,
getrennt durch `·`. Ein Datum, dessen Kästchen nicht gesetzt ist, steht als
`aus`, auch wenn Moodle im Formular den heutigen Tag vorbelegt hat — wer die
Vorbelegung als Frist meldet, meldet ein Datum, das nirgends gilt. Der
`schluessel` ist genau das, was `aendern` und `aktivitaet_anlegen` als
Einstellung annehmen (Schreibweise in `references/bearbeiten.md`).

Optionsfelder mit demselben Namen bilden eine Auswahl. Ihr `wert` ist die
Beschriftung der gewählten Option, `auswahlwert` deren technischen Wert;
`optionen` enthält die angebotenen Werte
und Beschriftungen sowie gegebenenfalls `deaktiviert: true`. Verwende diese
Angaben beim Setzen, statt die Auswahl als `ja` oder `nein` zu behandeln.

Einträge mit `"verborgen": true` sind Felder, die Moodle nicht anzeigt (etwa
Voraussetzungen als JSON). Gib sie nicht ungefragt aus.

## Aufgaben (mod_assign) im Besonderen

Hier liegt die gefährlichste Stelle, und sie sieht harmlos aus:

| Adresse | Was sie zeigt |
|---|---|
| `/mod/assign/view.php?id=123` | den Aufgabentext |
| `/mod/assign/view.php?id=123&action=grading` | **alle Namen, Abgaben und Bewertungen** |

Ein Parameter Unterschied. Die App sperrt die zweite Form, und kein Werkzeug
fragt sie an. Interessant und unkritisch sind dagegen: Abgabefrist,
Verfügbarkeitszeitraum, erlaubte Abgabetypen, Punktzahl — alles in
`einstellungen.json`.

## Verzeichnisinhalt

Der Inhalt eines Verzeichnisses liegt nach `aktivitaet_lesen` in
`cm-<cmid>/bereiche/files/`, mit Unterordnern, Byte für Byte. Textartige
Dateien (`.txt`, `.csv`, `.md`, `.svg`, `.html`) kannst du dort direkt lesen,
Binärdateien (PDF, Bilder, Office) mit den lokalen Werkzeugen
weiterverarbeiten. Große Dateien nicht in den Kontext holen, wenn es nur um
ihre Existenz oder Größe geht.
