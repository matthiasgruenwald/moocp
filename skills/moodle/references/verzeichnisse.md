# Verzeichnisse und Dateien

## Anlegen und bearbeiten

Ein Verzeichnis (`folder`) ist ein Dateibereich mit Unterordnern; eine Datei
als Aktivität (`resource`) ist ein Dateibereich mit genau einer Datei. Beides
steht im Ordner unter `bereiche/files/`.

```
Neu:        <ordner>\bereiche\files\Arbeitsblatt.pdf
            <ordner>\bereiche\files\Vorlagen\Messprotokoll.odt
            aktivitaet_anlegen(kurs, abschnitt_id, typ: "folder", name, ordner)

Bestehend:  aktivitaet_lesen(cmid)  ->  cm-<cmid>\bereiche\files\ …
            Dateien hinzufügen, ersetzen (gleicher Name), löschen
            aendern(cm-<cmid>)
```

Die Freigabe zeigt, welche Dateien neu, ersetzt und entfernt werden. Eine
ersetzte Datei behält ihren Namen und damit jeden Verweis im Kurs; eine
umbenannte ist für Moodle eine neue Datei, und alle Verweise zeigen weiter auf
die alte. Wähle bewusst und sag, was du gewählt hast.

Wichtige Einstellungen des Verzeichnisses:

| Schlüssel | Bedeutung |
|---|---|
| `display` | eigene Seite oder direkt auf der Kursseite einblenden |
| `showexpanded` | Unterordner aufgeklappt zeigen |
| `showdownloadfolder` | Knopf „Verzeichnis herunterladen" anbieten |

Eine Aufgabe hat einen eigenen Dateibereich für **Zusätzliche Dateien**
(`bereiche/introattachments/`) — Vorlagen und Material, das zur Aufgabe
gehört, ohne im Text eingebunden zu sein.

## Drei Rollen, die nicht vermischt werden

Diese Entscheidung fällt vor dem Anlegen, nicht danach.

| Verzeichnis | Für wen | Wo |
|---|---|---|
| `_Lehrerdateien` | **Unterrichtsmaterial der Lehrkraft**: Quelldateien, Lösungen als Datei, Bewertungsbögen | verborgen, je Hauptabschnitt |
| `CLAUDE` | **Arbeitsmaterial der KI**: `CLAUDE.md` mit den Konventionen, dazu Vorlagen, Schemata, Generatorskripte | verborgen, je Kurs oder je Abschnitt |
| ein gewöhnliches Verzeichnis | **Schülerdownload**: Arbeitsblätter, Vorlagen, Datensätze | sichtbar |

Beide ersten sind verborgen, aber nicht dasselbe. Das Kriterium ist, **wer die
Datei beim nächsten Mal öffnet**: ein Mensch mit einem Programm (`.odg` in
LibreOffice Draw, `.xcf` in Gimp, ein Bewertungsbogen als `.odt`) →
`_Lehrerdateien`. Nur die KI wieder (ein Generatorskript, ein Schema, eine
Vorlage für die KI, die Quelle einer Zeichnung, die ein Skript erzeugt) →
`CLAUDE`. Liegen beide im selben Abschnitt, bleibt die Trennung damit
eindeutig; leg nichts aus dem einen in das andere, „weil es da auch passt".

Eine Lehrerhandreichung ist keines von beiden: Sie wird gelesen, also ist sie
eine verborgene Textseite oder ein Buch im Abschnitt — siehe „Selbst erzeugte
Dateien" unten.

## Lehrermaterial oder Schülerdownload

**Lehrermaterial** — Quelldateien (`.odg`, `.xcf`, `.docx` zu einem Bild, das
im Kurs eingebunden ist), Lösungen, Erwartungshorizonte, interne Notizen:
verborgen. Die App legt ohnehin verborgen an; bleibt es dabei, ist nichts zu
tun.

> Für Zeichnungen, die du selbst als SVG erzeugst, entfällt das: Dort sind
> Quelle und Auslieferung dieselbe Datei, und es gibt nichts zusätzlich
> abzulegen. Siehe `references/zeichnungen.md`.

**Schülerdownload** — Arbeitsblätter, Vorlagen, Datensätze: nach dem Anlegen
mit `sichtbarkeit_setzen` freigeben.

### Die Falle: „ohne Link erreichbar"

Wo Moodle es erlaubt, gibt es neben „anzeigen" und „verbergen" eine dritte
Verfügbarkeit: *verfügbar, aber nicht auf der Kursseite angezeigt*. Sie sieht
aus wie verborgen, ist es aber nicht — das Verzeichnis ist über seine Adresse
für **jeden eingeschriebenen Teilnehmer abrufbar**. `kurs_uebersicht` zeigt es
als `[ohne Link erreichbar]`.

`sichtbarkeit_setzen` kann diesen Zustand zurücksetzen (an einer Aktivität
beobachtet, nicht gemessen). Hatte das Verzeichnis ihn, prüfe ihn danach und
stelle ihn mit `aendern` nach, wenn er gewollt war.

Für Lösungen und Erwartungshorizonte ist das ungeeignet. Stößt du beim Lesen
eines Kurses auf einen Lösungsordner in diesem Zustand, sag es dem Nutzer —
das ist so gut wie immer ungewollt.

**Ein `_Lehrerdateien`, das sichtbar ist, ist ein Fund.** Der Name sagt, dass
es verborgen gehört — sag es dem Nutzer, statt es stillschweigend zu ändern.
Dasselbe, wenn eines fehlt, obwohl im Abschnitt offensichtlich Quelldateien
zwischen dem Schülermaterial liegen.

Dasselbe gilt für den verbreiteten Behelf, Lösungen unter unauffälligem Namen
in einen sichtbaren Ordner zu legen. Das schützt nichts.

Prüfe außerdem den Zusammenhang: Ein sichtbarer Ordner in einem verborgenen
Abschnitt ist für Lernende nicht erreichbar. Umgekehrt nützt ein verborgener
Ordner nichts, wenn dieselbe Datei anderswo im Kurs offen verlinkt ist.

## Selbst erzeugte Dateien

Soll eine Datei erst entstehen (ein Datensatz als CSV, eine Vorlage zum
Weiterbearbeiten), schreib sie mit dem Datei-Werkzeug direkt in
`bereiche/files/` des Ordners, den `aktivitaet_anlegen` oder `aendern` nimmt.
Ein Blatt zum Lesen oder Bearbeiten ist dagegen keine Datei, sondern eine
Textseite oder Aufgabe (Abschnitt „Die Brücke" im SKILL.md): Eine Datei sieht
man in Moodle nicht ohne Herunterladen, und sie folgt nicht dem Theme.

## Dateien aus Moodle holen

`aktivitaet_lesen` legt jede Datei eines Verzeichnisses Byte für Byte nach
`bereiche/files/` — kein Download über den Browser, keine Rückfrage nötig,
denn es landet im Arbeitsordner der App, nicht im Download-Ordner.

Große Dateien nicht in den Kontext holen, wenn es nur um Existenz, Typ oder
Größe geht — das sagt die Übersicht der App schon. Und keine Personendaten:
Dateien aus Abgaben, Nutzerbereichen und Forenbeiträgen fragt die App gar
nicht erst an.
