# E33 Gruppierungen lesen und anlegen; Fehlendes ist eine Rückfrage

Seit 2026-10-25. Status: umgesetzt; Lesen, Anlegen, Zuordnen und die Rückfrage sind auf einer Testinstanz durchgespielt. Ergänzt [E3](0003-sperrliste-und-positivliste.md) und [E29](0029-sicherungen-und-verzweigung.md). Die Kurzfassung steht im Index der [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

1. **Eine Gruppierung, die im Zielkurs fehlt, bricht nie still ab.** Nennt `aendern` bei `groupingid` einen Namen, den das Formular nicht anbietet, kommt vor dem Schreiben eine Rückfrage an die Lehrkraft (E29, unabhängig von der Freigabestufe). Sie nennt die vorhandenen Gruppierungen und den Weg weiter. Das gilt für jede Aktivität, die `aendern` ändern darf.
2. **`gruppierungen_lesen`** zeigt Gruppierungen und die Namen ihrer Gruppen. Die Gruppierung steht in ihrem Formular, die Gruppen darin auf der Zuordnungsseite. Mitglieder liest die App nicht; `group/index.php`, `members.php` und `overview.php` bleiben gesperrt (A1).
3. **`gruppierung_anlegen`** legt eine Gruppierung an, dazu die Gruppen, die es im Kurs noch nicht gibt, und ordnet sie zu. Das Zuordnen geht über die Zuordnungsseite. Die Freigabe gilt ab Stufe „alle", weil Gruppen und Gruppierungen keine Sichtbarkeit haben und Lernende sie nur über Aktivitäten erreichen. Gibt es die Gruppierung schon (etwa nach einem Abbruch mitten im Anlegen), ergänzt das Werkzeug nur fehlende Gruppen; es entfernt und benennt nichts um. Ein zweiter Aufruf führt so einen abgebrochenen zu Ende.
4. **Die Positivliste nimmt vier Lesepfade und drei Schreibpfade auf:** Neue Gruppe und neue Gruppierung nur mit `id` 0, Zuordnen nur als Hinzufügen. Entfernen, Umbenennen, Löschen und das Ändern bestehender Gruppen gibt es nicht. Ob `id` bei einer neuen Gruppe leer oder 0 ist, hängt vom Formular ab; beides gilt als neu.
5. **Die Gruppenwahl (`choicegroup`) gehört zu den Typen, bei denen `aendern` nur Gruppenmodus und Gruppierung ändert** (`MoodleZugang.nurGruppenModule`, wie Collabora). Ihr Formular ist ungemessen; deshalb muss das Zurücklesen alle übrigen Felder unverändert zeigen, sonst meldet das Werkzeug `verified: false` und nennt die abweichenden Feldnamen.
6. **Nach einer Wiederherstellung** bleibt die Zuordnung eine Handlung der Lehrkraft mit Werkzeugen: Gruppierungen der Quelle lesen, im Ziel `aendern` mit `groupingid`, bei Bedarf vorher anlegen. Die Rückmeldung der Wiederherstellung nennt diesen Weg.

## Verworfen

- **Gruppen und Gruppierungen mitsichern:** Das verlangte Nutzerdaten in der Sicherung (E29, A1).
- **Automatisch anlegen:** Eine Gruppierung ändert, wer eine Aktivität sieht oder bearbeitet. Die Lehrkraft entscheidet.
- **Gruppenübersicht lesen, um vorhandene Gruppen zu finden:** `group/overview.php` zeigt Mitglieder. Vorhandene Gruppen ergeben sich stattdessen aus der Zuordnungsseite einer bestehenden Gruppierung.

## Gemessen

- Die Zuordnungsseite hat eine leere `action`; die Nummer der Gruppierung steht nur in der Adresse der Seite. Gesendet wird deshalb an die Seitenadresse samt Query.
- Die Werte der Auswahl `addselect[]` sind keine reinen Zahlen; die Positivliste prüft nur eine kurze Kennung.
- Eine Textseite hat kein Feld `groupingid`; eine Aufgabe hat es.
- Löschen von Gruppen und Gruppierungen gibt es nicht; Proben bleiben im Testkurs stehen.

