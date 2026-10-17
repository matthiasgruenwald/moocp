# E4 Freigabe in der App statt im Chat

Seit 0.9.0 (2026-10-02). Status: gilt. Die Kurzfassung steht in [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

Ändern, Verschieben, Sichtbarkeit
und Löschen zeigen einen Dialog mit Änderungsübersicht und Zeilenvergleich;
ohne Entscheidung binnen 30 Minuten wird nichts geschrieben, ebenso, wenn der Client nicht mehr auf das Werkzeug wartet (Abbruch, etwa nach dem Zeitlimit von Bionic, E21): Dann schließt sich der Dialog, sonst schriebe eine späte Freigabe, während die KI den Vorgang für gescheitert hält. Mehrere Aktionen
an einem Objekt (Test, Fortschrittsliste, Board) gehen durch eine Freigabe,
ebenso Änderungen an Inhalten mehrerer Seiten eines Abschnitts
(`aendern_mehrere`, `links_setzen`) – der Dialog zeigt
jede Seite mit Namen und Zeilenvergleich, und die Grenze ist der Abschnitt.
Die Links einer Lernsituation setzt die App selbst (`links_setzen`), nicht
die KI von Hand: Das ist mechanisch, spart das Lesen und Bearbeiten jeder
Seite, und die App sichert zu, dass sich am sichtbaren Text nichts ändert.
Der Plan im Chat (A5) bleibt davor; eine Planungsebene im Code gibt es nicht.
Wie viele dieser Dialoge kommen, stellt die Lehrkraft ein (E20).

## Verworfen

Eine Liste freigegebener „Schreibkurse" – die Lehrkraft soll in
allen eigenen Kursen arbeiten können; die Sicherheit kommt aus Freigabe und
Namensprüfung.
