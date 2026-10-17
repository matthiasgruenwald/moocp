# Domain-Doku

Wie Skills und Sitzungen die Fachsprache und die Entscheidungen dieses Projekts lesen.

## Vor dem Arbeiten lesen

- **`GLOSSARY.md`** im Wurzelverzeichnis: Begriffe der Arbeit an Moodle-Kursen und ihrer Sicherung. Die dortigen Wörter in Issues, Tests, Plänen und Vorschlägen verwenden; was dort unter _Vermeiden_ steht, nicht benutzen.
- **`docs/adr/`**: die Entscheidung zum betroffenen Bereich lesen, bevor etwas vorgeschlagen wird, was sie berührt. Die Nummer einer ADR ist die E-Nummer in der CLAUDE.md und in Kommentaren des Quelltexts (E21 = `0021-…`).

Ein Kontext, keine `CONTEXT-MAP.md`.

## Aufbau

```
/
├── CLAUDE.md          Anforderungen (A1–A11), Index der Entscheidungen
├── AGENTS.md          dünner Einstieg für Codex
├── GLOSSARY.md        Fachsprache
├── TODO.md            offene Punkte außerhalb von Specs und Tickets
├── docs/adr/          Entscheidungen E1–E22 und weitere
├── docs/agents/       Arbeitsregeln: Dokumentation, Workflow, Testen, Issue-Tracker
├── docs/specs/        Specs (vorläufig; maßgeblich ist das GitHub-Issue)
└── docs/plans/        Pläne
```

## Neue Entscheidung

Neue Entscheidungen bekommen die nächste freie Nummer (`0023-…`), im Aufbau der vorhandenen ADRs: Kopf mit Version und Status, **Entscheidung**, **Verworfen**. In der CLAUDE.md steht dazu eine Zeile im Index. Eine ADR, die eine frühere ersetzt, nennt sie und setzt deren Status auf „ersetzt durch …".

## ADR-Konflikte melden

Widerspricht ein Vorschlag einer ADR oder einer Anforderung, das offen benennen statt still zu überschreiben.
