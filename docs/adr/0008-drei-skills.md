# E8 Drei Skills, getrennt nach Aufgabe:

Seit 0.9.0 (2026-10-02). Status: gilt. Die Kurzfassung steht in [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

`moodle` (Kurs), `moodle-fragen`
(Fragen und Tests), `lernsituation` (didaktischer Entwurf, geprüft und dann
über `moodle` in den Kurs; E17). Getrennt, weil die Beschreibung eines Skills trennscharf sein muss
und der geladene Kontext klein bleiben soll. Die Skills gehören zu diesem
Projekt (`skills/`); Gleichanteile werden in `skills/gemeinsam/` gepflegt
und von `skills/build.py` eingesetzt. `lernsituation` ist für
berufsbildende Schulen gebaut und deshalb wählbar (E13).
