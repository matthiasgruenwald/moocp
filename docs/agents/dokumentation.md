# Regeln für die Dokumentation

Gelten für README.md, CLAUDE.md, CHANGELOG.md und alle Dateien unter `docs/`.

1. **README.md ist für Menschen, CLAUDE.md für die KI.** Was ein Mensch
   braucht, um das System zu verstehen, zu installieren, zu benutzen oder
   weiterzuentwickeln, steht in der README – auch die Architektur. Hier
   steht nur, was die KI bei der Arbeit an diesem Projekt braucht:
   Anforderungen, Entscheidungen, Arbeitsregeln.
2. **Die README hat vier Teile, in dieser Reihenfolge:** 1. Quickstart (der
   kürzeste Weg zum ersten Ergebnis, nur Schritte und ein Beispiel – keine
   Begründungen, keine Sonderfälle; alles Ausführliche steht im
   Benutzerhandbuch), 2. Vorstellung (was das System kann, mit Bildern, damit
   Interessierte wissen, woran sie sind), 3. Benutzerhandbuch (beginnt mit der
   Installation), 4. Entwicklerhandbuch.
3. **Nichts doppelt.** CLAUDE.md darf auf die README verweisen, die README
   nie auf CLAUDE.md.
4. **Kein Verlaufsprotokoll.** Weder hier noch in der README steht, wie etwas
   entstanden ist, was wann gemessen oder welcher Fehler wann behoben wurde.
   Es steht da, was gilt und warum. Die eine Ausnahme ist [CHANGELOG.md](../../CHANGELOG.md). Der Maßstab dort, aus dem sich alles Übrige ergibt: **Jede Zeile ist eine Überschrift – der Bereich und was sich geändert hat, aus der Sicht dessen, der es merkt.** Also:

   - *Überschrift, kein Absatz:* „Neu: automatische Updates über GitHub.", „STACK: Problem mit Testeingaben behoben." Wie etwas funktioniert und wie man es benutzt, steht in der README; wie der Fehler aussah und woran es lag, in den Commits.
   - *Blickrichtung:* „Was ist für mich jetzt anders?", nicht, was die App dafür tut. „Freigaben: Eine Freigabe wirkt nicht mehr, wenn sich das Objekt inzwischen geändert hat" – nicht „Freigaben werden vor dem Schreiben erneut geprüft".
   - *Bündeln:* Was zusammengehört, steht in einer Zeile mit den betroffenen Bereichen, nicht in dreien mit je einem Fall.
   - *Genau bleiben:* Lieber den Bereich weiter fassen als etwas benennen, das so gar nicht kaputt war.
   - *Nie hinein:* Ursache und Hergang, Dateinamen, Bezeichner, Entscheidungen (E…).
5. **Implementierungsdetails gehören als Kommentar an den Quelltext**, nicht
   in README oder CLAUDE.md: Moodle-Eigenheiten, Parameter, Formate,
   Fallstricke. Die Begründung steht dort, wo sie jemand braucht, der den Code
   ändern will.
6. Deutsch mit echten Umlauten in Texten, Kommentaren und Meldungen, auch
   in CHANGELOG.md: Die Zielgruppe sind deutsche Lehrkräfte, und die App
   zeigt den Text eines Releases im Update-Dialog selbst an. Bezeichner ohne
   Umlaute (`pruefeStand`), Moodle-Bezeichner englisch (`introeditor`,
   `duedate`). Kein künstliches Eindeutschen: Was im Deutschen so heißt,
   heißt so – **Version**, nicht „Fassung"; Release, Installer, Skill.

7. **Eine CLAUDE.md je Bereich, keine große:** diese hier für die App und
   das ganze Projekt, [skills/CLAUDE.md](../../skills/CLAUDE.md) für die Pflege der
   Skills, `skills/<skill>/CLAUDE.md` für Notizen zu einem Skill (nicht im
   Paket). Jede gehört zu dem Ordner, in dem man arbeitet, wenn man sie
   braucht.
8. **Offene Punkte außerhalb von Specs und deren Umsetzungstickets stehen in [TODO.md](../../TODO.md)**, nicht in README oder
   einer CLAUDE.md: fehlende Funktionen, Fehler und Aufgaben außerhalb des Codes. Was erledigt ist, fliegt dort heraus. „Noch durchzuspielen" kommt dort möglichst gar nicht hinein: Was umgesetzt ist, wird gleich geprüft, von Hand oder mit einem Test. Was dafür zu aufwendig ist (frischer Rechner, Schulnetz, Beobachtung über viele Sitzungen), würde auch später nicht geprüft – das bleibt draußen, bis ein Nutzer ein Problem meldet.

Architektur, Aufbau, Werkzeuge, Bauen und Prüfen: [README.md](../../README.md),
Teil 4.
