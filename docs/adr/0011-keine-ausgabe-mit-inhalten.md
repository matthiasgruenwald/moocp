# E11 Keine Ausgabe mit Inhalten

Seit 0.9.0 (2026-10-02). Status: gilt. Die Kurzfassung steht in [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

Die fertige App schreibt nichts auf eine Konsole; `debugPrint` ist stumm; Fehler erscheinen nur mit Typ (bei Dateifehlern mit Pfad), nie mit ihrem Text. Ausnahmen, die nichts aus Moodle tragen: die Brücke `moocp-bruecke.exe` (E21), deren stdout der MCP-Kanal des Clients ist und genau das trägt, was der MCP-Server über HTTP auch liefert; und die Auskünfte `moocp.exe --werkzeugliste` (Namen, Beschreibungen und Parameter der Werkzeuge, für die Brücke) und `moocp.exe --version`.
