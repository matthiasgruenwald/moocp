# E33 Gruppierungen lesen und anlegen; Fehlendes ist eine Rückfrage

Seit 2026-10-26. Status: umgesetzt, auf einer Instanz noch nicht gemessen. Ergänzt [E3](0003-sperrliste-und-positivliste.md) und [E29](0029-sicherungen-und-verzweigung.md). Die Kurzfassung steht im Index der [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

1. **Eine Gruppierung, die im Zielkurs fehlt, bricht nie still ab.** Nennt `aendern` bei `groupingid` einen Namen, den das Formular nicht anbietet, kommt vor dem Schreiben eine Rückfrage an die Lehrkraft (E29, unabhängig von der Freigabestufe). Sie nennt die vorhandenen Gruppierungen und den Weg weiter. Das gilt für jede Aktivität, die `aendern` ändern darf.
2. **`gruppierungen_lesen`** zeigt Gruppierungen und die Namen ihrer Gruppen. Die Gruppierung steht in ihrem Formular, die Gruppen darin auf der Zuordnungsseite. Mitglieder liest die App nicht; `group/index.php`, `members.php` und `overview.php` bleiben gesperrt (A1).
3. **`gruppierung_anlegen`** legt eine Gruppierung an, dazu die Gruppen, die es im Kurs noch nicht gibt, und ordnet sie zu. Das Zuordnen geht über die Zuordnungsseite. Die Freigabe gilt ab Stufe „alle", weil Gruppen und Gruppierungen keine Sichtbarkeit haben und Lernende sie nur über Aktivitäten erreichen. Gibt es die Gruppierung schon, ändert das Werkzeug nichts.
4. **Die Positivliste nimmt vier Lesepfade und drei Schreibpfade auf:** Neue Gruppe und neue Gruppierung nur mit `id` 0, Zuordnen nur als Hinzufügen. Entfernen, Umbenennen, Löschen und das Ändern bestehender Gruppen gibt es nicht.
5. **Nach einer Wiederherstellung** bleibt die Zuordnung eine Handlung der Lehrkraft mit Werkzeugen: Gruppierungen der Quelle lesen, im Ziel `aendern` mit `groupingid`, bei Bedarf vorher anlegen. Die Rückmeldung der Wiederherstellung nennt diesen Weg.

## Verworfen

- **Gruppen und Gruppierungen mitsichern:** Das verlangte Nutzerdaten in der Sicherung (E29, A1).
- **Automatisch anlegen:** Eine Gruppierung ändert, wer eine Aktivität sieht oder bearbeitet. Die Lehrkraft entscheidet.
- **Gruppenübersicht lesen, um vorhandene Gruppen zu finden:** `group/overview.php` zeigt Mitglieder. Vorhandene Gruppen ergeben sich stattdessen aus der Zuordnungsseite einer bestehenden Gruppierung.
