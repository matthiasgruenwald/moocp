# Testen und Durchspielen

Die Anforderung A10 (Testkurs, Präfix `ZZ`, `flutter analyze` und `flutter test`) steht in [CLAUDE.md](../../CLAUDE.md).

- **Durchspielen ohne Claude-Sitzung:** `bash tool/neustart.sh [profilordner]`
  (prüfen, bauen, neu starten),
  `bash tool/mcp_aufruf.sh <werkzeug> '<json>' [mcp-name]` (ein Werkzeug der
  laufenden App aufrufen). Ohne `mcp-name` wird das erste Profil verwendet.
  Unter Windows aus Git Bash, unter macOS aus der Shell aufrufen, nicht aus
  Python – warum, steht im Skript. Mehrere Aufrufe mit Freigaben nacheinander als Bash-Skript
  im Hintergrund, und dem Nutzer vorher die Liste der Freigaben nennen.
- **Selbst nachsehen statt um Bildschirmfotos bitten:** `bildschirmfoto` (E18)
  legt nach der Freigabe in der App PNG-Dateien in den Arbeitsordner (Pfad in
  der Antwort), die sich mit Read ansehen lassen. Jedes Bild ist eine
  Freigabe – vorher ankündigen.
- **Nach einem Neustart der App** im Hintergrund auf den MCP-Server warten
  (Eintrag „MCP-Server läuft auf …" in `%APPDATA%\moocp\protokoll.log`; er
  startet nach der Anmeldung), nicht um Bescheid bitten. Dasselbe beim Warten auf eine Freigabe. Geduldig:
  bis 30 Minuten, im Hintergrund, nicht nach wenigen Minuten aufgeben.
- **Bauen nur auf Auftrag, dann mit Test.** `flutter build` (auch Debug, auch macOS) darf die KI ausführen, wenn die Lehrkraft den Bau ausdrücklich verlangt oder ein Issue einen Bau vorsieht, der getestet wird. Der Bau gilt als Teil dieses Auftrags, nicht als Freibrief: Danach wird gestartet und geprüft (A10), und der Befund wird gemeldet. Ohne solchen Auftrag fragt die KI vorher. Nicht eingeschlossen sind Release-Bau und Installer (`create_installer.bat`); die brauchen einen eigenen, ausdrücklichen Auftrag. Die Berechtigung kommt aus diesem Absatz, nicht aus einer Freigabe im Einzelfall.

## Testzugang Testinstanz

- Die lokal bestätigte Zuordnung von Instanzen und Testkursen sowie der freigegebene Testrahmen stehen in `~/.config/moocp/e2e/testumgebung.md`. Vor Live-Messungen dort nachsehen; echte Kursnummern und Instanzangaben bleiben außerhalb des öffentlichen Repositorys.
- Die Zugangsdaten des Lehrkraft-Kontos (Teacher-Edit) für die Spike-Instanz liegen außerhalb des Repos in `~/.config/moocp/e2e/spike-credentials.env` (Rechte 600). Sie haben das Format `SCHLUESSEL=WERT` mit `TEACHER_USERNAME` und `TEACHER_PASSWORD`; `URL_INTERNAL` und `Host` darin betreffen die Testumgebung selbst, nicht die App.
- Die App liest sie nur im Debug-Bau, wenn `MOOCP_TESTZUGANG_PROFILE` eine Zuordnung aus Profilkennung zu Datei und Moodle-Adresse enthält (`lib/anmeldedaten.dart`). Beispiel mit erfundenen Angaben: `MOOCP_TESTZUGANG_PROFILE='{"standard":{"file":"/tmp/testzugang.env","address":"https://moodle.schule.example"},"a1b2c3d4":{"file":"/tmp/zweiter-testzugang.env","address":"https://zweite.schule.example"}}'`. Für das Standardprofil ist `MOOCP_TESTZUGANG` mit zusätzlichem `MOOCP_TESTZUGANG_ADRESSE` als gebundene Einzelzuordnung weiter möglich. Ohne passende Profilkennung und Adresse werden die Dateizugangsdaten und der automatische Freigabemodus nicht verwendet. Der Release-Bau ignoriert alle Variablen.
- **Begrenzter Debug-Testbetrieb:** Eine Bindung kann zusätzlich `"courses":[12]` und `"screenshots":true` enthalten. In diesen Kursen können Anlegen, Ändern, Zieländerungen und Löschen eigener verborgener ZZ-Proben automatisch freigegeben werden. Folgeaktionen gelten ausschließlich für in derselben App-Sitzung selbst erzeugte und erfolgreich zurückgelesene Proben oder deren vollständig gegen die Quelle geprüfte Kopien. Eine explizite eigene Auswahl kann in gebundene Testkurse eingefügt werden; eine Dateiwiederherstellung erkennt ausschließlich den Inhalts-Hash ihrer eigenen, geprüften Sicherung aus dieser Sitzung. Nur eindeutig neue, verborgene Kopien mit gleichem Formularinhalt, gleichen Kartendaten, belegten neuen Ortszielen und gleichen gelesenen Datei-Bytes werden übernommen. Prüflücken, fremde ZZ-Archive und Altbestand begründen keinen Testbesitz. Profilkennung, tatsächliche Instanzadresse, Kurs, Name und der vollständige Formularstand werden erneut geprüft; vorhandene ZZ-Objekte sind keine eigenen Proben. Bilder brauchen zusätzlich `screenshots:true`. Ohne diese Angaben gibt es keine Testautomatik. Andere Aktivitäten, Fragen, Abschnitte, Sichtbarkeit und sonstige Übertragungen verwenden weiterhin die normale Freigabemechanik. Im Release-Bau ist diese Ausnahme abgeschaltet (E18/E20).
- Die App lädt gebundene Testzugänge unabhängig vom gespeicherten Anmeldehaken und meldet alle gebundenen Profile selbst an, bevor ihre MCP-Server bereitgemeldet werden. Fehler eines Profils werden einzeln gemeldet; ein bereites Profil belegt keine zweite Anmeldung. Passwörter werden ausschließlich von der App gelesen.
- Bei einer ausdrücklichen Debug-Testprofilbindung beginnt diese Anmeldung vor einem eventuell wartenden Dialog „KI-Werkzeuge einrichten“. Der Dialog bleibt erforderlich; Testbetrieb richtet weder Verbindungen noch Skills automatisch ein.
- Start: `MOOCP_TESTZUGANG_PROFILE='{"standard":{"file":"/tmp/testzugang.env","address":"https://moodle.schule.example"}}' flutter run -d macos`
- `tool/neustart.sh` reicht diese Zuordnungen beim Mac-Neustart nur weiter, wenn `MOOCP_TESTZUGANG_PROFILE` oder die passende Legacy-Kombination `MOOCP_TESTZUGANG` und `MOOCP_TESTZUGANG_ADRESSE` ausdrücklich gesetzt ist; ohne Zuordnung startet die App mit der gespeicherten Anmeldung.
- **Mac-Bau im Temp-Ordner.** Im iCloud-Ordner scheitert CodeSign: iCloud (File Provider) hängt an Bundle und Ressourcen die Attribute `com.apple.fileprovider.fpfs#P` und `com.apple.FinderInfo`, und CodeSign lehnt sie ab. `bash tool/mac_bau.sh` baut deshalb in einer Temp-Kopie, kopiert `moocp.app` nach `build/macos/Build/Products/Debug/` und entfernt die Kopie auch nach einem Fehler. Der Ordner `build/` ist ignoriert und liegt im Repo, wo die Lehrkraft die App findet. Anschließend lässt sich die kopierte App mit `open build/macos/Build/Products/Debug/moocp.app` starten. Mit `bash tool/mac_bau.sh release` entsteht auf demselben Weg ein Bau ohne Debugmodus unter `build/macos/Build/Products/Release/`; er ignoriert die Testzugangs-Variablen. Die macOS-Anleitung unter Teil 4 der README beschreibt den Entwicklungsbau.
- Die KI liest diese Datei nicht, außer die Lehrkraft nennt sie ausdrücklich für einen Test. Werte gehören nicht in Chat, Protokoll oder Repo.

## Wiederholbarer Testplan für beide Instanzen

1. Private Zuordnung aus `~/.config/moocp/e2e/testumgebung.md` lesen und für jede Instanz ausdrücklich Profilkennung, vollständige Adresse, Zugangspfad und freigegebene Testkurse binden. Nichts aus Anzeigenamen oder einer Kursnummer ableiten. Zugangsinhalte nicht lesen. `courses` und `screenshots` nur für den bestätigten Testumfang setzen.
2. `flutter analyze` und `flutter test` ausführen, dann den Debug-Bau starten. `tool/mac_start.sh` wartet auf alle ausdrücklich gebundenen Testprofile. Pro Profil `status` über `tool/mcp_aufruf.sh` aufrufen; tatsächliche Instanz und angemeldeten Zustand prüfen. Bei fehlender zweiter Anmeldung die Voraussetzung konkret melden und den zweiten Rundlauf offenlassen.
3. Je Instanz den erlaubten Kurs mit `kurs_uebersicht` frisch lesen; Kursname, Abschnitt-ID und Restbestand festhalten. Im gemeldeten Arbeitsordner einen Entwurf mit `page.html` erstellen: Überschrift `ZZ Testbetrieb`, ein kurzer Absatz mit eindeutigem Laufkennzeichen. Mit `aktivitaet_anlegen` eine verborgene ZZ-Textseite erzeugen. Nur nach `verified: true` fortsetzen; cmid aus der Antwort festhalten, bei unklarem Ergebnis nicht erneut anlegen.
4. Den zurückgelesenen Ordner bearbeiten und mit `aendern` speichern. Wieder `verified: true` verlangen, danach `aktivitaet_lesen` und den gespeicherten Text mit dem Soll vergleichen.
5. `bildschirmfoto` mit der eigenen cmid und einem konkreten Prüfgrund aufrufen. Nur die ausgegebenen PNGs aus dem App-Arbeitsordner öffnen; Überschrift, Absatz und sichtbare Fehler mit dem rückgelesenen Text vergleichen. Browserfehler sind eine fehlende Voraussetzung, kein Anlass für einen anderen Browserzugang. Im normalen Betrieb bleibt die persönliche Freigabe erhalten.
6. Die eigene Probe nach frischer Namensprüfung mit `loeschen` entfernen, `verified: true` und den Restbestand über `kurs_uebersicht` prüfen. Keine vorhandenen ZZ-Objekte anderer Läufe löschen. Lauf einschließlich Profilstart für die zweite Instanz wiederholen.
7. Öffentliche MCP-Verträge und reale Dialogzustände separat prüfen: `flutter test test/testbetrieb_mcp_test.dart test/freigabe_dialoge_test.dart test/lernlandkarte_verteilen_mcp_test.dart`. Nur Moodle wird durch einen lokalen HTTP-Server ersetzt. Zustimmung, Ablehnung, Fristablauf und Abbruch durchlaufen echte Dialoge ohne Testautomatik. Karten-Zieländerungen prüfen Mehrdeutigkeit, Ziel- und Kurswechsel während des offenen Dialogs sowie das Erhalten der nicht beauftragten Kartendaten. Inhaltsbilder werden im Live-Rundlauf geprüft: Der App-Browser erlaubt ausschließlich HTTPS; die HTTP-Testgrenze darf diese Browserregel nicht aufweichen.

Öffentliche Belege nennen je Testrolle: Anmeldung, Schreib-/Rückleseprobe, Bild angesehen und Befund, Aufräumen und Restbestand. Zwischen „umgesetzt“, „geprüft“ und „wegen fehlender Voraussetzung offen“ unterscheiden; keine echten Adressen, Kursnummern, Zugangs- oder Nutzerpfade veröffentlichen.

## Themen samt Lernlandkarte verteilen

Der öffentliche MCP-Test verteilt ein Thema in fünf lokale Zielkurse mit
unterschiedlichen Aktivitätsnummern. Er prüft Karteninhalt, Ortsziele und
Sichtbarkeit, fehlende Ziele, mehrdeutige Quellauswahl, Quelländerung während
der Freigabe, Profilwechsel, Ablehnung, HTTP-Startfehler sowie Wiederholung und
Neustart ohne Doppelung. Nur Moodle wird ersetzt. Die Dialogtests prüfen
Zustimmung, Ablehnung, Fristablauf und Abbruch über die echte Oberfläche.

Live ausschließlich eigene ZZ-Proben in den privat gebundenen Kursen erzeugen:
zwei Textseiten und eine Karte mit zwei Ortszielen. Anfangsbestand festhalten,
Quellkarte zurücklesen, mit `uebertragen` die explizite Auswahl auf die verfügbaren
benannten Ziele verteilen. Pro Ziel neue Nummern, Karten-SVG, vollständige
Kartendaten und Ortsziele strukturiert gegen die Quelle prüfen; danach einen
Wiederholungsversuch ohne erneuten Start belegen. Auf einer zweiten Instanz
Sicherung und Wiederherstellung getrennt ausführen: die Kartenverknüpfung wird
dort nicht automatisch übernommen. Unbelegte Zuordnungen bleiben offen.

Je Ziel ein Inhaltsbild über die App öffnen und mit dem strukturierten Soll
vergleichen. Nur die gegen die eigene Quelle vollständig geprüften, unveränderten Kopien
erhalten im gebundenen Debug-Testbetrieb automatische Bildfreigaben. Ohne
diesen Nachweis gilt die persönliche Freigabe. Bei fehlender Freigabe den
Schritt als offen melden. Der Debug-Nachweis setzt die allgemeine
Wiederherstellungsverifikation nicht auf wahr.
Nur eigene Proben löschen und den Restbestand mit dem Ausgangsbestand
vergleichen. Eine konkrete Zahl realer Ziele erst nach tatsächlichem Rücklesen
und Sichtprüfung nennen.
