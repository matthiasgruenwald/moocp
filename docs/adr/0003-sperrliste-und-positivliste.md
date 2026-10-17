# E3 Sperrliste und Positivliste, beide im Code

Seit 0.9.0 (2026-10-02). Status: gilt. Die Kurzfassung steht in [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

Die Positivliste ist die
eigentliche Grenze; die Sperrliste greift davor, damit eine zu weit gefasste
Positivregel nichts Personenbezogenes durchlässt. Die einzige Ausnahme der
Sperrliste (Definition von Bewertungsschemata) hebt nur die Notenregel auf.
Eine Adresse kommt nur zusammen mit dem Werkzeug in die Positivliste, das sie
braucht – nie eine Freigabe ohne Aufrufer. `test/sperrliste_test.dart` hält
beide Listen gegeneinander.
