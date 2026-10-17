# E19 Updates nur nach ausdrücklichem Ja, und nur von GitHub

Seit 0.9.2 (2026-10-03). Status: gilt. Die Kurzfassung steht in [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

Außer Moodle fragt die App genau eine Stelle: das Release dieses Repositorys. Beim ersten Start fragt sie in einem eigenen Dialog, ob sie einmal täglich nachsehen darf, und nennt dabei, was GitHub dadurch erfährt (IP-Adresse und Zeitpunkt); ohne Ja geht keine Anfrage hinaus, und die Antwort lässt sich in den Einstellungen ändern. Geprüft wird vor dem Einrichten: Ein Update bringt neue Skills mit, und der MCP-Server startet ohnehin zuletzt, also hängt noch keine Claude-Sitzung daran. Die Grenze liegt im Code wie überall: eigene Positivliste (`lib/update/updateliste.dart`) für jede Adresse und jedes Umleitungsziel, eigene Verbindung ohne Sitzungscookie, jede Anfrage mit Status im Protokoll; `test/update_test.dart` hält `update.dart` darauf fest. Geprüft wird nur, wer sich selbst ersetzen kann (die exe liegt im Installationsverzeichnis), und `--kein-update` schaltet es ganz ab. Der Installer läuft sichtbar; still wäre bequemer, aber wer ein Programm austauscht, soll sehen, was läuft. Kein MCP-Werkzeug dafür: Updates sind Sache der Lehrkraft, nicht Claudes.

## Verworfen

Eine Datei `autoupdate` im Installationsverzeichnis (die Einstellungen liegen je Benutzer unter `%APPDATA%`, werden beim Deinstallieren mitgelöscht und sind beim Start schon geladen; einen Administrator, der sie schriebe, gibt es bei einer Installation je Benutzer nicht); die Frage im Installer (wer selbst baut, läuft nie durch ihn, und die Antwort müsste trotzdem in die Einstellungen).
