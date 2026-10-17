# E15 Installer mit NSIS, je Benutzer, Deinstallieren räumt alles ab

Seit 0.9.0 (2026-10-02). Status: gilt. Die Kurzfassung steht in [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

Ohne Administratorrechte nach `%LOCALAPPDATA%\Programs\moocp`, weil Daten und die Einrichtung der KI-Werkzeuge ohnehin je Benutzer liegen. Die VC++-Laufzeit liegt neben der exe statt `vc_redist` (bräuchte Administratorrechte). Die Version steht nur in `pubspec.yaml`; der Installer liest sie aus der gebauten exe. Deinstallieren entfernt Programm, Einstellungen mit Schlüssel, Protokoll, gespeicherte Anmeldedaten, Arbeitsordner und die Einrichtung in allen KI-Werkzeugen, damit nichts von der Lehrkraft zurückbleibt; ein Update behält Daten und Einrichtung. Eine laufende App wird nie beendet, sondern die Lehrkraft gebeten, sie zu schließen – nur das reguläre Beenden leert den Arbeitsordner. Die Brücke für LM Studio (E21) hält dagegen keinen Zustand: Läuft sie beim Update, benennt der Installer sie um und legt die neue daneben – ein laufendes Programm lässt sich nicht ersetzen, aber umbenennen, und Bionic arbeitet mit der alten weiter, bis es neu verbindet –; beim Deinstallieren beendet er sie, nachdem ihr Eintrag ausgetragen ist.

Den Installer auf dem Entwicklungsrechner nicht deinstallieren, ohne zu fragen: Er teilt die Datenordner mit der Entwicklerversion.

## Verworfen

Ersetzen beim Neustart des Rechners (geht ohne Administratorrechte nicht) und die Bitte, Bionic zu schließen (ein Schritt mehr für die Lehrkraft, und unnötig).
