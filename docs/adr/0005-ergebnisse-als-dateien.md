# E5 Große Ergebnisse als Dateien

Seit 0.9.0 (2026-10-02). Status: gilt. Die Kurzfassung steht in [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

Gelesenes landet vollständig im Arbeitsordner; zurück an die KI geht eine Übersicht mit Auswertung und Befunden, damit für einen Auftrag nur geöffnet wird, was er betrifft. Der Arbeitsordner ist keine Einstellung: fester Ort im Temp-Verzeichnis, beim Start und beim Beenden geleert, damit keine Kursinhalte liegen bleiben. Fest statt je Start neu, weil eine Claude-Sitzung einen Neustart der App überdauern kann – ein alter Pfad würde sonst als „außerhalb" gesperrt, was sich wie die Datensperre liest. Weil der Ort fest ist, läuft die App je Windows-Sitzung nur einmal, auch über installierte App und Entwicklerversion hinweg; ein zweiter Start holt die laufende nach vorn.
