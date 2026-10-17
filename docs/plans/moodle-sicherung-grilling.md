# Moodle-Sicherung und Wiederherstellung: Klärungsstand

## Bereits geklärt

- moocp soll Moodles eigene Sicherung und Wiederherstellung bedienen.
- Export und Import sind unabhängig nutzbare Vorgänge. Eine Sicherung kann ohne anschließenden Import erstellt werden.
- Die Sicherungsdatei verbindet beide Schritte; ein automatischer Abgleich, eine Änderungsverfolgung und ein eigener Inhaltsnachbau gehören nicht zum Auftrag.
- Die App soll auch unter macOS nutzbar werden.

## Entscheidungen aus Runde 1

- **Q1 Begriffe:** Moodle-Begriffe für Oberfläche, Werkzeuge und Dokumentation; „Exportieren“ und „Importieren“ bleiben im Gespräch verständlich. Die geklärten Definitionen stehen in `GLOSSARY.md`.
- **Q2 Auswahl:** Einzelne Aktivitäten, mehrere ausgewählte Aktivitäten und Abschnitte sind der Hauptanwendungsfall. Ganze Kurse ebenfalls unterstützen, mit geringerer Priorität. Änderungsverfolgung bleibt bei Coursepilot und dessen Kontextdateien.
- **Q3 Wiederherstellungsziel:** Alle von Moodle angebotenen Wege unterstützen, soweit die Rechte der Lehrkraft sie zulassen: neuer Kurs, in bestehenden Kurs einfügen/verschmelzen, vorhandenen Kursinhalt löschen und wiederherstellen. Keine künstliche Beschränkung auf einen Weg.
- **Q4 Dateien:** Dauerhafte lokale Ablage in einem gewählten Ordner; vorhandene, auch außerhalb von moocp erzeugte `.mbz`-Dateien können wiederhergestellt werden. Sicherungsdateien werden nicht mit dem temporären Arbeitsordner geleert.
- **Q5 Instanzen:** Beide Instanzen bleiben gleichzeitig angemeldet. Feste Rollen bestimmen die übliche Übertragungsrichtung von der eigenen Testinstanz zur Produktivinstanz. Die Gegenrichtung wird nur auf ausdrücklichen Auftrag verwendet. Die Lehrkraft muss für normale Übertragungen weder die Anmeldung wechseln noch Quelle und Ziel erneut wählen.
- **Zusammenspiel:** Inhaltliche Arbeit erfolgt überwiegend mit Coursepilot über dessen eigenen MCP. moocp übernimmt Sicherung und Wiederherstellung. Ein Auftrag darf beide Schritte verbinden; beide Funktionen bleiben auch einzeln nutzbar.

Die technische Verankerung der Instanzrollen und die Übergabe des Kurskontexts zwischen den Werkzeugen sind noch festzulegen. Die Identität der Instanz muss bei Werkzeugaufrufen eindeutig bleiben; gleichlautende Kursnamen oder identische numerische IDs auf verschiedenen Instanzen dürfen nicht verwechselt werden.

## Entscheidungen aus Runde 2

- **Q6 Unterrichtsverteilung:** Meist ein Quellkurs und ein Durchführungskurs, aber auch mehrere Durchführungskurse auf derselben Produktivinstanz. Die bereitstellende Lehrkraft erstellt zentral Unterrichtseinheiten und kann diese für Kolleginnen und Kollegen verteilen lassen. Die Übertragung soll nach Auftrag vollständig automatisierbar sein.
- **Q7 Eindeutigkeit:** Kein still gewählter Wiederherstellungsweg bei unklarem Auftrag. Früh im Prozess Quelle, ausgewählte Inhalte, Zielinstanz, sämtliche Durchführungskurse und Wiederherstellungsweg deutlich nennen. Bei Unklarheit nachfragen; eine zusätzliche Rückfrage ist einer falschen Übertragung vorzuziehen. Löschungen sind kein nachträglicher Reparaturweg. Die ausdrücklich gewünschten nativen Wiederherstellungswege bleiben im Umfang.
- **Q8 Inhaltslücken:** Bekannte Einschränkungen durch den Ausschluss von Nutzerdaten vorab konkret kommunizieren und die Entscheidung über eine unvollständige Übertragung einholen. Die bestehende Datensperre bleibt erhalten.
- **Technische Untersuchung autorisiert:** Vorhandene Coursepilot-E2E-Testzugänge für die Testinstanz verwenden, insbesondere das bearbeitende Lehrkraftkonto. Sicherung und Wiederherstellung im Browser prüfen und die Formularstruktur für die spätere HTTP-Anbindung dokumentieren. Zugangsdaten und echte Instanzdaten bleiben außerhalb des öffentlichen Repositorys.

## Vorarbeiten aus Coursepilot

Geprüft wurde eine lokale Coursepilot-Kopie vom 6. Oktober 2026. Das dortige Glossar heißt noch `CONTEXT.md`.

- `prototype/mbz-restore/README.md`: Messung mit Moodle 5.0.8 vom 1. Oktober 2026. Serverseitiger Restore mit `MODE_IMPORT` und `TARGET_CURRENT_ADDING`; Anlegen aus Aktivitäts-XML, kein Nachweis eines allgemeinen instanzübergreifenden Dateiimports über die Oberfläche.
- `docs/adr/0028-aktivitaets-xml-als-anlegeweg.md`: Entscheidung für das Anlegen aus Aktivitäts-XML. Diese Funktion ist von der Wiederherstellung vollständiger Sicherungsdateien zu unterscheiden.
- `Plugin/src/local_coursepilot/skills/reference/activity-backup-experience.md`: Erfahrungen mit dem Backup-/Restore-Unterbau.
- `export_activity_backup` liefert trotz seines Namens die XML einer einzelnen Aktivität, keine vollständige `.mbz`-Datei.

Relevante Befunde aus dem Prototyp:

- Ohne Nutzerdaten können auch fachliche Inhalte fehlen, beispielsweise Glossar-Einträge. Vollständigkeit muss je Aktivitätsart geprüft werden.
- Ein fehlgeschlagener Restore kann Teilobjekte hinterlassen. Fehler und anschließender Kursstand müssen ausdrücklich geprüft werden.
- Wiederherstellen als neue Aktivität erhält nicht automatisch sämtliche Verweise auf eine zuvor vorhandene Aktivität. Abhängigkeiten und Verweise aus Zusatzmodulen sind besonders zu beachten.

Die dokumentierten Erfahrungen stammen aus serverseitigen PHP-Core-Aufrufen. Die HTTP-Formularschritte für Sicherung, Dateidownload, Upload und Wiederherstellung sind damit noch nicht belegt. Coursepilot-spezifische Ausschlüsse des XML-Anlegewegs gelten nicht automatisch für vollständige Moodle-Sicherungen.

## Ergänzende Formularprüfung

Die [offizielle Moodle-Dokumentation zur Wiederherstellung](https://docs.moodle.org/502/en/Course_restore) beschreibt neue und bestehende Kurse als Ziele sowie die nachfolgenden Schritte Einstellungen, Schema und Prüfung. Welche Optionen tatsächlich angeboten werden, hängt auch von Rechten, administrativen Vorgaben, Einstiegspunkt und Sicherungstyp ab. Die Formularauswahl muss deshalb auf der jeweiligen Instanz ermittelt werden; die vollständige Unterstützung der angebotenen Wege bedeutet keine Zusage, dass jeder Weg bei jeder Sicherungsart verfügbar ist.

## Nächster Schritt

Die Testgrenze wurde für die Spezifikation bestätigt: sämtliche Tests gegen eine echte Moodle-Installation laufen auf der kontrollierten Spike-Testinstanz, einschließlich vollständig ausgeführter Wiederherstellung und Rücklesen des Zielkurses. Bloßes Hochladen genügt nicht. Keine Testwiederherstellungen oder sonstigen Teständerungen auf der Produktivinstanz und keine zweite echte Instanz als Voraussetzung. Die Trennung unabhängiger Sitzungen wird zusätzlich gegen lokale HTTP-Gegenstellen geprüft. Im späteren Produktiveinsatz gemeldete Fehler sollen nach Möglichkeit auf Spike reproduziert und dort durch Regressionstests abgesichert werden; serverseitige Logs stehen dort für die Diagnose zur Verfügung.

Die fachliche Fragerunde ist abgeschlossen. Die nativen Formulare wurden auf der Testinstanz untersucht; der Einzelaktivitätsweg wurde einschließlich Download, erneutem Upload, Wiederherstellung und Rücklesen ausgeführt. Die gemessenen Abläufe und verbleibenden Testgrenzen stehen in [moodle-sicherung-formulare.md](moodle-sicherung-formulare.md), die HTTP- und macOS-Anpassungen in [moodle-sicherung-technik.md](moodle-sicherung-technik.md).

Als Nächstes kann daraus eine umsetzbare Spezifikation mit Arbeitspaketen entstehen. Nur neu auftauchende fachliche Entscheidungen werden zurück in die Klärung gegeben. Eine Implementierung ist damit noch nicht begonnen.
