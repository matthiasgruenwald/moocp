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
