# E30 Skills: eine Quelle in `~/.agents/skills`, Claude per Verlinkung

Seit 0.9.23 (2026-10-17). Status: gilt als Richtung; die Umsetzung in der App ist offen (#3a). Ändert [E13](0013-ki-werkzeuge-einrichten.md) und [E21](0021-drei-ki-werkzeuge.md) in der Ablage der Skills, nicht in der Wahl der Werkzeuge. Die Kurzfassung steht im Index der [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

Die Skills liegen einmal in `~/.agents/skills`. Claude Code bekommt sie über eine Verlinkung in `~/.claude/skills`. Codex liest denselben Ordner, sobald geprüft ist, dass es das tut. Es gibt keine Kopien je Werkzeug mehr, damit die Stände nicht auseinanderlaufen.

Gründe: So arbeitet die Entwicklungsumgebung bereits bei anderen Skills; eine Quelle genügt.

## Folgen

- Unter Windows braucht ein Symlink Entwicklermodus oder Adminrechte. Dort bleibt die Kopie als Rückfall, bis geklärt ist, wie die App das löst.
- Die Vergleichslogik in `lib/einrichtung.dart` (`skillVergleichen`) muss auf die Quelle zeigen, nicht auf die Kopie je Werkzeug.
- Ob Codex `~/.agents/skills` tatsächlich lädt, ist nicht geprüft. Eine Testfrage an Codex hat keine Antwort gebracht: Codex meldete nur, dass es in dieser Sitzung noch keine Skills gelesen hat. Der Test muss mit einem Skill laufen, der tatsächlich benutzt wird.

## Verworfen

- **Kopien je Werkzeug (bisheriger Stand):** Zwei Stände, die auseinanderlaufen können.
- **Nur Codex-Ordner als Quelle:** Der Ordner `~/.agents/skills` ist die übliche Praxis.
