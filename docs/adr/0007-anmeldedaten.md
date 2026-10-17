# E7 Anmeldedaten

Seit 0.9.0 (2026-10-02). Status: gilt. Die Kurzfassung steht in [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

Standard: nur im Arbeitsspeicher, solange die App
läuft. Mit Haken nach erfolgreicher Anmeldung gespeichert, das Passwort mit
DPAPI verschlüsselt, und beim Start automatisch angemeldet; Haken weg löscht
beides. Bei abgelaufener Sitzung genau eine Neuanmeldung, danach Zugangsdaten
verwerfen – Moodle sperrt Konten nach Fehlversuchen. War Moodle schon vor dem
Senden des Passworts nicht erreichbar, ist das kein Fehlversuch: Die
Zugangsdaten bleiben, die nächste Anfrage versucht es wieder. Leere Zugangsdaten gehen
gar nicht erst an Moodle, und solange angemeldet ist, gibt es keinen
Anmeldeknopf – ein Fehlversuch würde die laufende Sitzung verwerfen.
