# E6 Nur lokal

Seit 0.9.0 (2026-10-02). Status: gilt. Die Kurzfassung steht in [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

MCP über Streamable HTTP auf `127.0.0.1`, Zugangsschlüssel
als Bearer-Token, Host- und Origin-Prüfung. Dass der Schlüssel im Klartext in
den Einstellungen und in der Konfiguration von Claude Code und Codex steht
(E21), ist für ein lokales Werkzeug in Kauf genommen.
