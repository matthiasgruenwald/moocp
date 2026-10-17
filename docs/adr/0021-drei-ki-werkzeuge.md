# E21 Drei KI-Werkzeuge: Claude Code, Codex CLI, LM Studio

Seit 0.9.6 (2026-10-07). Status: gilt. Die Kurzfassung steht in [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

Die App braucht von einem Client dreierlei: MCP über HTTP zu `127.0.0.1` (E6), Skills im Format `SKILL.md` (E8) und eigene Werkzeuge für Dateien, weil alles Gelesene im Arbeitsordner liegt (E5). Das haben Claude Code, Codex CLI (OpenAI) und LM Studio mit seinem Agenten Bionic. Die Skills bleiben für alle dieselben und sagen nichts, was nur in einem Client gilt.

Je Werkzeug eine Unterklasse von `KiWerkzeug` (`lib/einrichtung.dart`):

- **Claude Code** trägt über `claude mcp add` ein.
- **Codex** über den Block `[mcp_servers.moodle]` in `config.toml`, ohne TOML-Paket (E14). Warum nicht `codex mcp add`: Kommentar zu `CodexCli`.
- **LM Studio** heißt hier sein Agent Bionic. Bionic startet Server nur als lokalen Befehl; die App schreibt deshalb in dessen interne Liste die Brücke `moocp-bruecke.exe` (`lib/mcp/bruecke.dart`), die den Werkzeugaufruf an den MCP-Server der App weiterreicht. Der Schlüssel steht so nicht in Bionic. Die Messungen zu Bionic stehen im Kommentar zu `LmStudio`, der Aufbau der Brücke im Kopf von `bruecke.dart`.

Die Brücke ist ein eigenes Programm ohne Flutter und eine einzige Datei, weil Bionic sie offen hält, solange es läuft: Installer und Bau legen sie dann beiseite (E15), statt zu scheitern. Nur der Werkzeugaufruf hängt an der App; initialize und tools/list beantwortet die Brücke selbst, und läuft die App nicht, startet sie die Brücke und wartet auf die Anmeldung (E13).

Weil Bionics Liste intern und undokumentiert ist: nur Einträge namens „moodle" anfassen, über eine Zwischendatei schreiben und im Dialog „eingetragen" sagen, nicht mehr. In allen Clients gilt: Eine Datei, die sich nicht lesen lässt, wird nie überschrieben. Skills liegen je Werkzeug in dessen eigenem Ordner (`~/.claude/skills`, `~/.codex/skills`, `~/.lmstudio/skills`). Welches Werkzeug sich verbunden hat, steht im Protokoll und in `status`.

Das Zeitlimit für Werkzeugaufrufe trägt die App in Bionic mit 35 Minuten ein, länger als die Frist einer Freigabe, damit diese zuerst endet (E4).

Der Hinweis zum Datenschutz gilt für jedes Werkzeug: LM Studio kann auch Cloud-Modelle benutzen, Claude Code und Codex lassen sich auf andere Anbieter umstellen. Dialog und README sagen deshalb „an das eingestellte Modell", nie „bleibt auf dem Rechner".

## Verworfen

Die App selbst als Brücke (`moocp.exe --mcp-stdio` – Bionic hielte exe, DLLs und `data\` gesperrt, und Update wie Neubau scheiterten, solange es läuft); für Bionic die Lehrkraft moocp zuerst starten zu lassen (ein Schritt mehr, und Bionic läuft oft den ganzen Tag) oder moocp mit der Brücke zu starten (ginge bei jedem Start von Bionic mit auf und meldete sich bei Moodle an); eine Werkzeugliste als Datei, die die App beim Start ablegt (nach einem Update veraltet, bis die neue Version lief, und ob sie es ist, verrieten nur Größe und Zeit der exe); dem Client geänderte Werkzeuge zu melden (`notifications/tools/list_changed` – kein anderer Client bekommt das, nach einem Update gilt überall: neue Sitzung); die ChatGPT-App (erreicht nur öffentliche HTTPS-Server; der Weg über OpenAIs Tunnel machte die Werkzeuge von außen erreichbar, gegen E6, und brächte trotzdem keinen Zugriff auf den Arbeitsordner); Ollama (Modellserver, kein MCP-Client); für Bionic das Eintragen von Hand (zu viel für Lehrkräfte), `mcp-remote` als Brücke (braucht Node.js, lädt fremden Code aus npm, und der Schlüssel stünde im Klartext in Bionic) und das Beenden von Bionic vor dem Schreiben (unnötig, es liest die Liste im laufenden Betrieb neu); ein gemeinsamer Skill-Ordner `~/.agents/skills` (Claude Code liest ihn nicht, und ein geteilter Ordner machte das Deinstallieren mehrdeutig); Verzeichnis-Junctions auf einen Ordner (hängt an einer Windows-Eigenheit, das Deinstallieren müsste sie von echten Ordnern unterscheiden); den Schlüssel in den Pfad zu legen, damit `codex mcp add --url` reicht (er stünde in jedem Protokoll, das Pfade schreibt, A4); Hinweise an die KI in `status`, Skills oder Werkzeugantworten, die Erlaubnis anzufordern oder die Bilder zu öffnen (ein schwaches Modell folgte ihnen nicht, ein starkes braucht sie nicht, und sie kosten Kontext), ebenso Bedienhinweise für schwache Modelle in der README (wer eines wählt, lebt damit; die README bliebe sonst nicht lesbar).
