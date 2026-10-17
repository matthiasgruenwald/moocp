# Testen und Durchspielen

Die Anforderung A10 (Testkurs, Präfix `ZZ`, `flutter analyze` und `flutter test`) steht in [CLAUDE.md](../../CLAUDE.md).

- **Durchspielen ohne Claude-Sitzung:** `bash tool/neustart.sh [profilordner]`
  (prüfen, bauen, neu starten), `bash tool/mcp_aufruf.sh <werkzeug> '<json>'` (ein
  Werkzeug der laufenden App aufrufen). Aus Git Bash, nicht aus Python – warum,
  steht im Skript. Mehrere Aufrufe mit Freigaben nacheinander als Bash-Skript
  im Hintergrund, und dem Nutzer vorher die Liste der Freigaben nennen.
- **Selbst nachsehen statt um Bildschirmfotos bitten:** `bildschirmfoto` (E18)
  legt nach der Freigabe in der App PNG-Dateien in den Arbeitsordner (Pfad in
  der Antwort), die sich mit Read ansehen lassen. Jedes Bild ist eine
  Freigabe – vorher ankündigen.
- **Nach einem Neustart der App** im Hintergrund auf den MCP-Server warten
  (Eintrag „MCP-Server läuft auf …" in `%APPDATA%\moocp\protokoll.log`; er
  startet nach der Anmeldung), nicht um Bescheid bitten. Dasselbe beim Warten auf eine Freigabe. Geduldig:
  bis 30 Minuten, im Hintergrund, nicht nach wenigen Minuten aufgeben.
- **Bauen nur auf Auftrag, dann mit Test.** `flutter build` (auch Debug, auch macOS) darf die KI ausführen, wenn die Lehrkraft den Bau ausdrücklich verlangt oder ein Issue einen Bau vorsieht, der getestet wird. Der Bau gilt als Teil dieses Auftrags, nicht als Freibrief: Danach wird gestartet und geprüft (A10), und der Befund wird gemeldet. Ohne solchen Auftrag fragt die KI vorher. Nicht eingeschlossen sind Release-Bau und Installer (`create_installer.bat`); die brauchen einen eigenen, ausdrücklichen Auftrag. Die Berechtigung kommt aus diesem Absatz, nicht aus einer Freigabe im Einzelfall.

## Testkurse Spike-Instanz

- Kurs 41 ist die Quelle, Kurs 42 das Ziel. Die Nummern stehen im Kursnamen; der Zugriff läuft über den Teacher-Edit des Lehrkraft-Kontos. Schreibtests nur in diesen beiden Kursen, Probeobjekte mit Präfix `ZZ`, hinterher aufräumen. Nie auf der Produktivinstanz (A10).
- Der Werkzeugname für die Testinstanz ist `moodle-test`, für die Produktivinstanz `moodle` ([E31](../adr/0031-mcp-server-je-instanz.md)). Vor jedem Schreibaufruf prüfen, welcher Server antwortet. Der Eintrag `moodle` zeigt heute noch auf die Testinstanz; vor der Umstellung wird er nach `moodle-test` umbenannt.
