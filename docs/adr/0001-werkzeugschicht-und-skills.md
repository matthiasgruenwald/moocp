# E1 Die App ist die Werkzeugschicht, die Skills sind die Wissensschicht

Seit 0.9.0 (2026-10-02). Status: gilt. Die Kurzfassung steht in [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

Die App spricht Moodle über HTTP mit einer eigenen Sitzung und bietet
Werkzeuge über MCP an; die Skills tragen Didaktik, Regeln und Ablauf.

## Verworfen

Die Chrome-Erweiterung als Werkzeugschicht (Rückgaben je Textfeld
nach 1000 Zeichen abgeschnitten, ein nicht vorhersagbarer Inhaltsfilter –
vollständiges Lesen zum Bearbeiten war nicht zuverlässig möglich); Umweg über
Downloads (Freigabe je Seite, alle Schwächen der Erweiterung bleiben); den
Filter umgehen (nie – er schützt Sitzungsdaten); Web-Service-Token oder
eigenes Moodle-Plugin (setzt Administratorhandeln auf dem Server
voraus).
