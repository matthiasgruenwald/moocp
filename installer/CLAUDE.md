# CLAUDE.md – Installer

Gilt für alles unter `installer/` und für `create_installer.bat`. Überblick und Regeln des Projekts: [../CLAUDE.md](../CLAUDE.md).

Die Entscheidung zum Installer (je Benutzer, Deinstallieren räumt alles ab, Umgang mit der Brücke) steht in [ADR 0015](../docs/adr/0015-installer.md).

- **Der Hinweis zur Nutzung steht an zwei Stellen**: am Anfang der README und
  auf der ersten Seite des Installers (`HinweisSeite` in
  `installer/moocp.nsi`). Wer ihn in der README ändert, zieht die Seite im
  selben Zug nach – dort gekürzt, weil alles ohne Scrollen daraufpassen muss,
  und danach am gebauten Installer nachgesehen.
- **`create_installer.bat` nie mit `sed -i` oder einem anderen Werkzeug bearbeiten, das Zeilenenden normalisiert.** Sie braucht CRLF (cmd liest Sprungmarken in Dateien mit LF nicht zuverlässig und setzt mitten in Zeilen auf). Weil `.gitattributes` Batch-Dateien normalisiert, zeigt `git status` den Schaden nicht an – er fällt erst beim Ausführen auf. Nach jeder Änderung daran prüfen: `tr -cd '\r' < create_installer.bat | wc -c` muss so viele CR zählen, wie die Datei Zeilen hat. Sie ist aus einer echten Eingabeaufforderung zu starten (PowerShell), nicht aus Git Bash: Dort erbt sie den Unix-`find` und bricht ab.
