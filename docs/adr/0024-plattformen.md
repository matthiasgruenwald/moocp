# E24 Plattformen: Windows ausgeliefert, macOS aus dem Entwicklungsbau

Seit 0.9.0 (2026-10-02), als eigene ADR nachgetragen. Status: gilt für die Auslieferung; der Umfang für macOS wird in Spec 0001 (GitHub-Issue #1) geklärt. Die Kurzfassung steht im Index der [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

Ausgeliefert wird moocp für **Windows**: ein Installer je Benutzer (E15), Zugangsdaten mit DPAPI (E7), die Brücke als `moocp-bruecke.exe` (E21), Einstellungen unter `%APPDATA%`. Das ist die Plattform der Schulen, für die die App gebaut ist.

Auf **macOS** läuft die App aus dem Entwicklungsbau (`flutter run -d macos`, siehe README, Teil 4). Eine Veröffentlichung für den Mac gibt es nicht. Wo die Windows-Lösung an Windows hängt, ist für macOS eine eigene Lösung nötig; sie wird mit der Spec geklärt, nicht vorab:

- Ablage der Zugangsdaten (statt DPAPI)
- Ort von Einstellungen, Protokoll und Arbeitsordner
- Die Brücke für LM Studio und das Eintragen in die KI-Werkzeuge
- Installation und Update, falls es je eine Veröffentlichung gibt

## Folgen

- Eine Änderung, die Windows-spezifisch ist (Pfade, DPAPI, Installer), nennt das im Kommentar, damit die Mac-Fassung sie findet.
- Das Repository bleibt eines (Flutter, ADR 0025); es gibt keinen Zweig für den Mac.
- `flutter test` muss auf beiden Plattformen laufen, soweit die Tests nicht ausdrücklich Windows voraussetzen.

## Verworfen

Windows und macOS gleichzeitig auszuliefern: Es gäbe zwei Installer, zwei Wege für Zugangsdaten und Updates und eine Prüfung auf zwei Betriebssystemen, bevor die Funktionen selbst stehen. Offen bleibt, ob eine Veröffentlichung für den Mac je nötig wird.
