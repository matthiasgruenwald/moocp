# E31 Ein MCP-Server je Moodle-Instanz, Namen Moodle und Moodle Test

Seit 2026-10-17. Status: umgesetzt mit Issues #4 und #14: je Profil Port, Servername, Zugang, Freigabestufe und MCP-Server; Profile werden in der Oberfläche verwaltet. Ergänzt [E1](0001-werkzeugschicht-und-skills.md) und [E13](0013-ki-werkzeuge-einrichten.md) um die Trennung der Instanzen. Die Oberfläche bleibt ein gemeinsames Fenster (E32). Die Kurzfassung steht im Index der [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

Jede angebundene Moodle-Instanz bekommt einen eigenen MCP-Server mit eigenem Port und eigenem Namen. Ein Server mit der Instanz als Werkzeugparameter wird nicht gebaut.

Namen:

| Anzeige in der App | Technischer Name (Werkzeugpräfix) | Instanz |
|---|---|---|
| Moodle | `moodle` | Produktivinstanz |
| Moodle Test | `moodle-test` | Testinstanz |

Der Anzeigename darf Leerzeichen enthalten, der technische Name nicht: Ein Werkzeug heißt `mcp__<name>__…`, und Leerzeichen sind darin nicht zulässig. Deshalb gibt es beide Namen. Der technische Name steht in der Konfiguration (Claude, Codex), der Anzeigename in der App.

Der Servername wird aus dem Instanzprofil abgeleitet, nicht im Code festgeschrieben. Ein weiteres Moodle bekommt einen eigenen Anzeigenamen und technischen Namen nach demselben Muster.

## Folgen

- Heute trägt der Eintrag `moodle` in Claude und Codex die Testinstanz. Mit dieser Entscheidung würde `moodle` die Produktivinstanz bezeichnen. Deshalb muss beim Umstellen der Eintrag für die Testinstanz nach `moodle-test` wandern, bevor `moodle` auf die Produktivinstanz zeigt. Sonst schreibt ein Test-Aufruf mit `mcp__moodle__…` versehentlich in die Produktivinstanz (A10).
- Die Freigabestufe (E20) und die Positivliste (E3) gelten je Instanz, nicht global.
- Skills nennen den Werkzeugnamen mit der Instanz (`mcp__moodle__…` für die Produktivinstanz, `mcp__moodle-test__…` für den Test). Die Skills müssen dafür nicht wissen, welche Domain dahinter liegt.
- Die Domain einer Instanz steht nur im Instanzprofil der App, nicht im Repository (A11).

## Verworfen

- **Ein Server, Instanz als Parameter aller Werkzeuge:** Alle Werkzeugaufrufe und Skills müssten sich ändern, und ein fehlender Parameter wäre eine Verwechslungsquelle.
- **Namen aus der Domain:** Lang, ändert sich bei einem Umzug, und sagt einer Lehrkraft nicht, welche Instanz gemeint ist.
- **Namen mit Leerzeichen als technischer Name:** Nicht als Werkzeugpräfix zulässig.
