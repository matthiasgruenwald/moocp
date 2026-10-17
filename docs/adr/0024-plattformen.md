# E24 Plattformen: Windows ausgeliefert, macOS aus dem Entwicklungsbau

Seit 0.9.0 (2026-10-02), als eigene ADR nachgetragen. Status: gilt. Die Lösungen für macOS stehen im Abschnitt „Ergebnis für macOS“ unten (Stand 0.9.23, 2026-10-17). Die Kurzfassung steht im Index der [CLAUDE.md](../../CLAUDE.md).

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

## Ergebnis für macOS

Die vier offenen Stellen sind auf dem Mac so gelöst (Stand 0.9.23):

- **Zugangsdaten:** Das Passwort liegt im Schlüsselbund des Benutzers statt unter DPAPI. Haken und Benutzername stehen wie unter Windows in `shared_preferences`. Der Entwicklerbau hat keine Team-ID und nutzt deshalb nicht die Datenschutz-Gruppe des Schlüsselbunds. Entscheidung und Verworfenes: [0026](0026-schluesselbund-mac.md).
- **Einstellungen, Protokoll und Arbeitsordner:** Einstellungen und `protokoll.log` liegen unter `~/Library/Application Support/moocp` statt unter `%APPDATA%` (`lib/einstellungen_ort.dart`). Der Arbeitsordner liegt wie unter Windows im Temp-Verzeichnis des Systems, auf dem Mac also im benutzerbezogenen `$TMPDIR`. Dass dieser Ort und die Spec 0001 auseinanderlaufen, steht in [TODO.md](../../TODO.md). Die Einzelstart-Sperre läuft auf dem Mac über einen Unix-Socket im Einstellungsordner: [0027](0027-einzelstart-mac.md).
- **Brücke und KI-Werkzeuge:** Auf dem Mac gibt es keine Brücke. LM Studio mit Bionic wird nicht angeboten, weil dessen Brücke ein Windows-Programm ist. Claude Code und Codex CLI sprechen HTTP-MCP und werden über ihre Kommandozeile bzw. `~/.codex/config.toml` eingetragen. Gesucht werden sie im `PATH`, unter `~/.local/bin`, `/opt/homebrew/bin` und `/usr/local/bin`. Skills liegen in `~/.claude/skills` und `~/.codex/skills`. Ob die Clients auf dem Mac diese Pfade tatsächlich lesen, ist nicht ausgeführt geprüft; das steht in [TODO.md](../../TODO.md).
- **Installation und Update:** Es gibt keinen Installer und keine Selbstaktualisierung. Die App läuft aus dem Entwicklungsbau (`flutter run -d macos`, README Teil 4). `updateMoeglich` gibt außerhalb von Windows `false` zurück.

Bildschirmfotos sind auf dem Mac noch nicht umgesetzt. Browsersuche und Prozessbereinigung kommen mit #11 und #3b. Die Entscheidung, nur den App-Browser zu nutzen, steht in [0028](0028-bildschirmfoto-app-browser.md).

## Verworfen

Windows und macOS gleichzeitig auszuliefern: Es gäbe zwei Installer, zwei Wege für Zugangsdaten und Updates und eine Prüfung auf zwei Betriebssystemen, bevor die Funktionen selbst stehen. Offen bleibt, ob eine Veröffentlichung für den Mac je nötig wird.
