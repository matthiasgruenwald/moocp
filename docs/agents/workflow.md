# Arbeitsregeln für die KI

- **Hier entsteht die Infrastruktur, nicht der Kursinhalt.** Dieses Projekt stellt App, Skills, Vorlagen und Prüfskripte bereit. Kursinhalte ändert hier niemand – weder in Moodle-Kursen noch in Entwürfen anderer Sitzungen; das tun Lehrkräfte in ihren eigenen Sitzungen. Zum Debuggen darf nach Rückfrage gelesen werden, über die App oder im Arbeitsordner. Befunde darin werden gemeldet, nicht behoben. Geschrieben wird in Moodle nur zum Testen im Testkurs (A10).
- **Änderungen, die Nutzerinnen und Nutzer merken**, bekommen eine Zeile
  unter der kommenden Version in CHANGELOG.md.
- **Die Übersicht „Unterstützte Aktivitäten und Fragetypen" (README, Teil 2) muss immer stimmen.** Sie gibt `schreibbareModule` (`lib/moodle/moodle_zugang.dart`) und `kernAnlegbar`, `zusatzAnlegbar`, `nurLesen` (`lib/moodle/fragen_xml.dart`) wieder, dazu die Werkzeuge je Art. Wer eine dieser Mengen ändert oder einer Art ein Werkzeug gibt oder nimmt, zieht die Übersicht im selben Zug nach.
- **Die Werkzeugtabellen und die Listen im Benutzerhandbuch (README, Teil 3) müssen immer stimmen**, vor allem die Spalte „Freigabe": Wer ein Werkzeug hinzufügt oder entfernt, seine Wirkung ändert oder ändert, wann es eine Freigabe verlangt, zieht die Tabelle im selben Zug nach; ebenso die Zusammenfassung „Sperrliste und Positivliste", wenn sich `sperrliste.dart`, die Positivliste in `moodle_zugang.dart` oder `browserliste.dart` ändern. Eine zweite Werkzeugliste an anderer Stelle gibt es nicht.
- **Skills**: Ein neues oder geändertes Werkzeug zieht den Skill nach, der es
  benutzt (A8 bewahren); alles Weitere in [skills/CLAUDE.md](../../skills/CLAUDE.md).
  Größere Umbauten der Skills vorher mit dem Nutzer besprechen.
## Agenten und Git

- **Upstream** ist `topse/moocp`, in der Arbeitskopie das Remote `upstream` (einmalig `git remote add upstream https://github.com/topse/moocp.git`). `origin` ist `matthiasgruenwald/moocp`. Auf Upstream wird nie gepusht; der Weg dorthin ist ein PR.
- **Freigaben nach A5 holt die Orchestrierung ein, bevor sie einen Implementierer startet.** Die bestätigten Entscheidungen stehen im Auftrag; der Agent fragt nicht erneut.
- **Ist eine Git-Aktion abgelehnt, arbeitet der Agent an allem weiter, was ohne sie geht** (Änderungen, Tests, Ticket-Kommentar), lässt die Änderungen im Worktree liegen und meldet am Ende in einem Satz, was fehlt. Die Orchestrierung committet und führt zusammen.
- **Der Commit-Trailer nennt das Modell, das den Commit tatsächlich erzeugt.**
- **RTK darf `git` nicht umschreiben**: `exclude_commands = ["git"]` in `~/Library/Application Support/rtk/config.toml` (Abschnitt `[hooks]`). Sonst wird `git status` zu `rtk git status`, und der Worktree-Guard lehnt es für Subagents ab, weil er den Befehl nicht als Git im eigenen Worktree belegen kann. Prüfung: `rtk hook check "git status"` meldet „No rewrite".

## Weitere Regeln

- **Unterstützt heißt mehr als anlegbar.** Eine Aktivität oder ein Fragetyp gilt erst als unterstützt, wenn die App sie anlegen und ändern kann und der Skill Anregungen gibt, wofür sie taugt – am Gerät, auf Papier und gemischt –, eine Aktivität außerdem erst, wenn der Skill `lernsituation` sie im Entwurf verwenden kann. Sonst bleibt sie technisch möglich und ungenutzt: Ein Modell schlägt vor, was es kennt, viele Lehrkräfte kennen die Möglichkeiten selbst nicht, und eine Lernsituation, deren Entwurf eine Aktivität nicht tragen kann, plant sie nie ein. Die Anregungen sind Vorschläge, keine Vorschriften; Form und Ort in [skills/CLAUDE.md](../../skills/CLAUDE.md), „Einsatz".
