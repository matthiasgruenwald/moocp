# E9 Fragen und Tests

Seit 0.9.0 (2026-10-02). Status: gilt. Die Kurzfassung steht in [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

(gilt für `moodle-fragen` und beim Portieren in die
App): anlegen per Moodle-XML-Import, ändern über das Bearbeitungsformular
(erzeugt eine neue Version mit neuer `questionid`); die Sachnummer
(`idnumber`) ist die stabile Kennung, Mehrdeutigkeit wird gemeldet, nicht
aufgelöst. Anlegbar sind die Kerntypen und Zusatztypen, deren XML
durchgemessen ist (von Hand anlegen, exportieren, eigene Frage schreiben,
importieren, vergleichen, Vorschau, aufräumen): derzeit `ddmatch`, `mtf`,
`gapfill`, STACK (nur mit gelaufenen Fragetests) und CodeRunner (gilt erst
als angelegt, wenn einmal über das Formular gespeichert – nur dort läuft die
Musterlösung durch die Sandbox). Prototypen werden nie angelegt. Fragen
löschen geht nur mit allen Versionen, nach Freigabe und mit Namensprüfung
(`fragen_loeschen`); steckt eine Frage in einem Test, verbirgt Moodle sie nur,
und das Werkzeug meldet es. Leere Kategorien löscht die App nicht.
