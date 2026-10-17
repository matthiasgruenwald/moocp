# Technische Prüfung: Moodle-Sicherung und Wiederherstellung

## Vorhandene HTTP-Anbindung

moocp bedient native Moodle-Formulare ohne gerenderten Browser:

1. `MoodleZugang` liest die Loginseite, übernimmt den `logintoken` und sendet die Anmeldung. Cookies und `sesskey` gehören zur jeweiligen Sitzung (`lib/moodle/moodle_zugang.dart`).
2. Der Formularparser übernimmt versteckte Felder und die wirksamen Eingabewerte. Änderungen werden als native Formularanfrage gesendet (`lib/moodle/formular.dart`, `formular_schreiben.dart`).
3. Uploads verwenden bereits Moodles Repository-API und die aus dem Formular ermittelte Repository-ID.
4. Jede Anfrage und jedes Umleitungsziel durchläuft Herkunftsprüfung, Sperrliste und Positivliste. Sicherungs- und Wiederherstellungspfade sind bisher nicht freigegeben.
5. Schreibvorgänge verlangen nach einer abgelaufenen Sitzung einen frisch aufgebauten Ablauf. Ein möglicherweise bereits ausgeführter Restore darf nicht blind wiederholt werden.

Der Browser dient zur Untersuchung und zum Testen der Formularfolge. Das spätere Werkzeug soll die entsprechende Folge mit der vorhandenen HTTP-Technik bedienen; Moodle erzeugt und verarbeitet die Sicherungsdatei.

## Erforderliche Erweiterungen

- Native Sicherungs- und Wiederherstellungsassistenten mit ihren Formularzuständen, Übergängen, Upload-/Downloadschritten und gegebenenfalls Hintergrundaufträgen abbilden.
- Nur die dafür gemessenen Pfade und Formulare in die Positivliste aufnehmen. Die Datensperre muss auch die Auswahl und den Inhalt einer binären Sicherungsdatei berücksichtigen; URL-Prüfung allein reicht nicht.
- Vorhandene Upload- und Formularhilfen wiederverwenden. Eine Umleitung allein ist bei einem mehrstufigen Assistenten kein Erfolgsnachweis.
- Große Sicherungsdateien und lang laufende Vorgänge berücksichtigen: Der bisherige HTTP-Zugang puffert Antworten/Uploads vollständig im Speicher und begrenzt Antworten auf zwei Minuten.
- Sicherungsdateien dauerhaft außerhalb des temporären Arbeitsordners ablegen.
- Gleichzeitige Instanzprofile in Anmeldung, Oberfläche, Zugangsdaten und MCP-Werkzeugen unterstützen. Mehrere `MoodleZugang`-Objekte können getrennte Cookies halten; die App verdrahtet bisher einen Zugang.
- Instanz und Kurs bei jedem Auftrag eindeutig bestimmen. Der Projektkontext liefert die übliche Quelle und die Durchführungskurse; die konkrete Zielidentität muss bis in die Werkzeugaufrufe erhalten bleiben.
- Vor Ausführung Quelle, Inhaltsauswahl, sämtliche Ziele und Wiederherstellungsweg sichtbar benennen. Ergebnis und Fehler je Durchführungskurs melden. Nach einem unklaren Abbruch zuerst den erreichten Zustand prüfen.
- Bestehende Freigabestufen berücksichtigen. Eine eindeutige Prozessmeldung und Nachfragen bei unklarem Auftrag gelten unabhängig davon, ob die Lehrkraft zusätzliche App-Freigaben eingeschaltet hat.

## macOS

Quellcodeprüfung, noch kein ausgeführter Build:

- Es fehlt ein macOS-Runnerprojekt.
- Dauerhafte Einstellungen brauchen einen macOS-Pfad; ohne `APPDATA` wird aktuell der Tempordner verwendet. App und eigenständige MCP-Brücke müssen denselben Ort verwenden.
- Das bereits vorhandene Paket für sichere Speicherung braucht eine geprüfte Schlüsselbundkonfiguration; Zugangsdaten sind nach Instanz zu trennen.
- KI-Einrichtung, Programmsuche und gegebenenfalls stdio-Brücke enthalten Windows-Pfade und `.exe`-Annahmen. HTTP-MCP kann ohne stdio-Brücke verwendet werden, soweit der jeweilige Client dies unterstützt.
- Der Schutz vor einem zweiten App-Start liegt ausschließlich im Windows-Runner. Auf macOS muss die exklusive Nutzung vor dem Leeren des gemeinsamen Arbeitsordners gesichert sein.
- Browser-Erkennung und Prozessbereinigung für Bildschirmfotos müssen macOS berücksichtigen.
- Netzwerkberechtigungen für ausgehenden Moodle-Zugriff und eingehenden lokalen MCP-Verkehr sowie Datei- und Schlüsselbundzugriffe prüfen.
- Windows-Updater und NSIS-Installer sind nicht auf macOS übertragbar. App-Bau, Verteilung und gegebenenfalls Signierung/Notarisierung sind gesondert festzulegen.

## Browserprüfung auf der Testinstanz

Der aktuelle, separat übertragene Testzugang funktioniert. Die Zugangsdaten liegen außerhalb des Repositorys, sind nur für das Benutzerkonto lesbar (Dateimodus 600) und wurden mit einem Datei-Parser statt `source` geladen. Für die Browserprüfung waren weder Coursepilot-OAuth noch Docker-Fixtures erforderlich.

Der vollständige Einzelaktivitätsweg über native Sicherung, Hintergrundabschluss, Dateidownload, lokalen Upload, Wiederherstellung und Rücklesen wurde ausgeführt. Eine eingeschränkte Kurssicherung wurde ebenfalls erstellt und geprüft; die zusätzlichen Zielmodi wurden erfasst. Probeaktivitäten und eigene Sicherungsdateien wurden anschließend bereinigt.

Die gemessenen Formularmarken, Felder, Zustände, AJAX-Dienste, Grenzen und Prüfergebnisse stehen in [moodle-sicherung-formulare.md](moodle-sicherung-formulare.md). Besonders relevant: Die bestätigte Zielauswahl „neuer Kurs“ legt bereits einen Platzhalter an; dieser Weg braucht eine Schreibfreigabe vor der Zielbestätigung und einen nativen Cleanup bei Abbruch.

Offen bleiben insbesondere Tests zwischen zwei Instanzen, große Sicherungen, eingebettete Dateien und Versions-/Pluginunterschiede. Die moocp-Werkzeuge selbst sind noch nicht implementiert. Zugangsdaten, Sitzungswerte und konkrete Instanzadressen gehören weiterhin nicht ins Repository.
