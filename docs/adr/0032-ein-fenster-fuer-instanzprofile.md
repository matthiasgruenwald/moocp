# E32 Ein Fenster für mehrere Moodle-Instanzprofile

Seit 2026-10-18. Status: gilt. Ergänzt [E27](0027-einzelstart-mac.md) und
[E31](0031-mcp-server-je-instanz.md), ersetzt keine von beiden. Die Kurzfassung
steht im Index der [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

Mehrere Moodle-Instanzen werden in einem moocp-Fenster über einen Profilauswähler
bedient. Anmeldung, gespeicherte Anmeldedaten, Freigabestufe und MCP-Server
gehören jeweils zum ausgewählten Profil. Profilname und technischer MCP-Name
stehen in der Fenstertitelzeile und in Freigabe-, Einrichtungs- und
Einstellungsdialogen.

Profile lassen sich in der Oberfläche hinzufügen und bearbeiten. Ein neues
Profil bekommt einen eigenen Port, eindeutigen MCP-Namen und Arbeitsordner.
Claude Code und Codex werden mit dem technischen Namen und Port des gerade
ausgewählten Profils eingerichtet. Skills bleiben gemeinsam, da sie keine
Instanzdaten enthalten.

## Gründe

E27 sperrt einen zweiten Prozess aus, weil Einstellungen, Protokoll und
Arbeitsordner gemeinsam gehören und beim Beenden geleert werden. Getrennte
Fenster je Profil würden diese gemeinsam genutzten Dateien, die Einzelstartsperre
und die Bereinigung voneinander entkoppeln müssen. Ein Profilwähler hält den
Besitz beim einen Prozess; die schon getrennten Moodle-Zugänge und MCP-Dienste
bleiben voneinander isoliert.

## Folgen

- Wechseln des Profils ändert die sichtbare Anmeldung und Freigabestufe. Bereits
  angemeldete Profile und ihre MCP-Server bleiben aktiv.
- Für ein neu angelegtes Profil wird die MCP-Verbindung separat in Claude Code
  und Codex eingerichtet. Der Server startet nach der Anmeldung dieses Profils.
- Das Protokoll und die Einstellungsdatei bleiben gemeinsam und werden nur von
  diesem Prozess beschrieben. Der Arbeitsordner bleibt ein Prozessordner; bei
  mehreren Profilen liegen neue Arbeitsdateien in Kennungs-Unterordnern.
- E27s Unix-Socket und Windows-Mutex bleiben pro moocp-Prozess und werden nicht
  nach Profil aufgeteilt.

## Verworfen

- **Ein Fenster je Profil:** kollidiert mit E27 und würde die gemeinsamen
  Einstellungen, das Protokoll und die Bereinigung in mehrere Prozesse teilen.
- **Ein MCP-Server für alle Profile mit Instanzparameter:** widerspricht E31
  und macht eine ausgelassene Instanzangabe zur Verwechslungsquelle.
