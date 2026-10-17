# E29 Sicherungen außerhalb des Arbeitsordners, Rückfragen unabhängig von der Freigabestufe, Plattformverzweigung am Rand

Seit 0.9.23 (2026-10-17). Status: gilt. Ergänzt [E5](0005-ergebnisse-als-dateien.md) und [E20](0020-freigabestufen.md), ersetzt keine von beiden. Die Kurzfassung steht im Index der [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

1. **Sicherungen liegen in einem dauerhaften Ordner außerhalb des Arbeitsordners.** Der Arbeitsordner bleibt bei Start und Ende geleert (E5). Ein Kurs-Export wird nie dorthin geschrieben, wo er geleert würde. Dieser Ausnahme gilt nur für Sicherungen, nicht für andere Ergebnisse.
2. **Rückfragen bei unklarem Auftrag gelten unabhängig von der Freigabestufe** (E20). Eine Rückfrage ist keine App-Freigabe, sondern eine Klärung vor dem Schreiben: Ziel unklar, Wiederherstellung in einen bestehenden Kurs, Dateien mit möglichen Nutzerdaten. Die Stufe „keine“ entfällt nur für die App-Freigabe vor dem Schreiben. Verschieben, Sichtbarkeit und Löschen fragen weiterhin immer.
3. **Die Plattformverzweigung liegt am Rand, nicht im Kern.** Pfade, Schlüsselbund, Einzelstart, Browsersuche, Installer und Aktualisierung unterscheiden die Plattformen. Die Moodle-Logik unter `lib/moodle/` kennt keine Plattformprüfung. Die Schnittstelle zwischen Kern und Plattform wird vor #11 festgelegt.
4. **Browser des KI-Werkzeugs.** E28 gilt für den Browser der App. Ein Werkzeug kann aber einen eigenen Browser öffnen und steuern. Bei Codex (`mcp__cua_repl`, Stand der Prüfung am 2026-10-17) ist das so. Das Risiko wird bewusst getragen und in der Dokumentation für Lehrkräfte genannt. Die App verlangt keine Änderung an der Codex-Konfiguration.

## Offen

- Umgang mit Sicherungsdateien, die die App nicht selbst erzeugt hat. A1 bleibt unverändert. Die Datei nicht zu lesen ist mit einer Prüfung auf Nutzerdaten nicht vereinbar. Lösung noch nicht entschieden ([TODO.md](../../TODO.md)).

## Verworfen

- **Sicherungen im Arbeitsordner:** Sie würden beim Start und Ende gelöscht.
- **Harte Sperre bei möglichen Nutzerdaten im Programm:** Die Lehrkraft entscheidet selbst; die App fragt deutlich nach.
- **Änderung von A1:** Die Lehrkraft will die Datensperre unverändert lassen.
