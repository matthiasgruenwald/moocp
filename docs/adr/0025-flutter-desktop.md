# E25 Flutter als Rahmen der Desktop-App

Seit 0.9.0 (2026-10-02), als eigene ADR nachgetragen. Status: gilt. Die Kurzfassung steht im Index der [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

moocp ist eine Flutter-Desktop-App mit einem Code für Windows und macOS. Die App enthält Fenster (Anmeldung, Freigabedialog, Protokoll, Einstellungen), den MCP-Server auf `127.0.0.1` (E6) und die Moodle-Sitzung in einem Prozess. Die Skills sind keine Flutter-Teile, sondern Pakete von `skills/build.py` (E8, E13).

Folgen für den Code:

- **Keine nachgeladene Logik.** Alles, was die App tut, steht im ausgelieferten Code. Es gibt kein Werkzeug, das beliebigen Code ausführt oder beliebige Adressen anfragt (A1, E3).
- **Wenige Pakete, nur freizügige Lizenzen** (E14). Wo ein Paket auf einer Plattform fehlt oder native Teile mitbrächte (WebView, TOML), wird es nicht aufgenommen (E18, E21).
- **Eigenes Programm nur dort, wo ein Client es offen hält:** Die Brücke ist darum ohne Flutter geschrieben (E21).

## Verworfen

Eine Webanwendung oder ein Browser-Plugin (die Sitzung der Lehrkraft und die Datensperre ließen sich nicht im Code der App erzwingen, E1 verwirft die Chrome-Erweiterung). Ein Python- oder Node-Dienst (brächte eine Laufzeit auf den Rechner der Lehrkraft, die zu installieren und zu aktualisieren wäre). Ein MCP-Server ohne Fenster (die Freigabe in der App, E4, braucht eine Oberfläche).
