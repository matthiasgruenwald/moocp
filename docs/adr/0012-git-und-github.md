# E12 Git; auf GitHub ein Stand je Version

Seit 0.9.0 (2026-10-02). Status: gilt. Die Kurzfassung steht in [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

Entwickelt wird in einem eigenen Repository. Auf GitHub erscheint je Version ein Commit mit dem Stand des Tags (`publish_tag_to_github.sh`), die Nachricht aus CHANGELOG.md. Pull Requests auf GitHub werden deshalb nicht zusammengeführt, sondern von Hand übernommen. Was auf GitHub selbst an main entsteht, etwa aus einer Cloud-Sitzung, holt `import_from_github.sh` auf den Zweig `github-import` herein, gemergt wird von Hand; die nächste Version setzt dann auf diese Commits auf, und `publish_tag_to_github.sh` bricht ab, solange einer davon im Tag fehlt. main auf GitHub wird nie überschrieben, das Hochladen geht ohne Force.

Zeilenenden LF, nur Batch-Dateien CRLF (`.gitattributes`).

## Verworfen

Die neue Version wie zuvor auf die letzte Version zu setzen und main zu überschreiben (die Commits verschwänden aus der Geschichte auf GitHub, und eine Cloud-Sitzung, die auf ihnen weiterarbeitet, liefe auseinander).
