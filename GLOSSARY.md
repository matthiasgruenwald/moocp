# moocp

Begriffe für die Arbeit an Moodle-Kursen sowie deren Sicherung und Wiederherstellung.

## Sprache

**Aktivität**:
Ein konkretes Element in einem Moodle-Kurs, etwa eine bestimmte Textseite, Aufgabe oder ein Test.

**Aktivitätsart**:
Die Art einer Aktivität, etwa Textseite, Aufgabe oder Test.
_Vermeiden_: Aktivitätstyp

**Gruppierung**:
Eine benannte Zusammenstellung von Gruppen eines Kurses. Eine Aktivität kann auf eine Gruppierung beschränkt sein. Sicherungen ohne Nutzerdaten enthalten weder Gruppen noch Gruppierungen; die App liest nur Namen, nie Mitglieder.

**Sichern**:
Ausgewählte Kursinhalte über Moodles Sicherungsfunktion in eine Sicherungsdatei ausgeben. „Exportieren“ ist dafür eine verständliche Formulierung im Gespräch.

**Sicherungsdatei**:
Eine von Moodle erzeugte `.mbz`-Datei mit den ausgewählten Kursinhalten. Sie kann aufbewahrt und unabhängig von ihrer Erstellung wiederhergestellt werden.
_Vermeiden_: Aktivitäts-XML als Bezeichnung für eine vollständige Sicherungsdatei

**Wiederherstellen**:
Inhalte einer Sicherungsdatei über Moodles Wiederherstellungsfunktion in einen neuen oder bestehenden Kurs übernehmen. „Importieren“ ist dafür eine verständliche Formulierung im Gespräch.

**Kursimport**:
Moodles gesonderte Übernahme von Inhalten aus einem anderen Kurs derselben Instanz.
_Vermeiden_: Kursimport als Bezeichnung für die Wiederherstellung einer Datei aus einer anderen Instanz

**Unterrichtsverteilung**:
Die Übertragung bereitgestellter Unterrichtsinhalte aus einem Quellkurs in einen oder mehrere Durchführungskurse. Die Lehrkraft erstellt die Inhalte zentral; sie selbst oder andere Lehrkräfte führen den Unterricht damit durch.

**Quellkurs**:
Der Kurs, aus dem die ausgewählten Unterrichtsinhalte gesichert werden.

**Durchführungskurs**:
Ein Zielkurs, in dem bereitgestellte Unterrichtsinhalte mit einer Lerngruppe genutzt werden. Zu einem Quellkurs können mehrere Durchführungskurse auf derselben Zielinstanz gehören.

## Werkzeuge, Freigabe und Einrichtung

**MCP-Server**
Der Dienst, den die App selbst anbietet: lokal auf `127.0.0.1`, geschützt durch einen Zugangsschlüssel. KI-Werkzeuge sprechen ihn direkt an.
_Nicht zu verwechseln mit_: Brücke.

**Brücke**
Ein kleines Zusatzprogramm, das nur für Bionic gebraucht wird. Bionic startet Server nur als lokalen Befehl, deshalb nimmt die Brücke diese Aufrufe entgegen und reicht sie an den MCP-Server weiter.
_Nicht zu verwechseln mit_: MCP-Server.

**KI-Werkzeug**
Ein Programm, das die Werkzeuge der App für eine KI nutzbar macht. Unterstützt werden Claude Code, Codex CLI und Bionic (LM Studio).

**Freigabe**
Der Dialog in der App, in dem die Lehrkraft einen Schreibvorgang in Moodle bestätigt. Wie viele Freigaben kommen, stellt die Lehrkraft ein.
_Nicht zu verwechseln mit_: Bestätigungen (die Einstellung, die bestimmt, wie oft der Dialog erscheint).

**Bestätigungen**
Das Feld in der Titelzeile der App, in dem die Lehrkraft die Stufe der Freigaben einstellt: „alle", „mittel" (Voreinstellung) oder „keine".
_Nicht zu verwechseln mit_: Freigabe (der einzelne Dialog).

**Arbeitsordner**
Der feste Ordner der App, in dem gelesene Kursinhalte, Bildschirmfotos und Entwürfe liegen. Die App leert ihn beim Start und beim Beenden.
_Nicht zu verwechseln mit_: Arbeitsbereich (der Abschnitt oder die Seite, an der die KI gerade arbeitet).

**Arbeitsbereich**
Was die Lehrkraft zuletzt genannt hat, innerhalb des Kurses: ein Abschnitt, eine Lernsituation oder eine einzelne Seite.
_Nicht zu verwechseln mit_: Arbeitsordner.

**Sperrliste**
Die Liste im Code, die Adressen und Inhalte mit personenbezogenen Daten von jedem Zugriff ausschließt, auch wenn eine Positivregel sie erfasst.
_Nicht zu verwechseln mit_: Positivliste.

**Positivliste**
Die Liste im Code, die festlegt, welche Moodle-Adressen die App überhaupt anfragen darf. Sie ist die eigentliche Grenze für den Zugriff auf Moodle.
_Nicht zu verwechseln mit_: Sperrliste.

**Protokoll**
Der Verlauf in der App, in dem jede Anfrage an Moodle mit Methode, Pfad und Status steht, ohne Formularwerte und ohne Zugangsdaten.

**Bildschirmfoto**
Eine Aufnahme nur des Inhalts einer Seite, wie sie im Browser aussieht, als Bilddatei im Arbeitsordner. Jedes Bild braucht eine eigene Freigabe.
_Nicht zu verwechseln mit_: einem Bildschirmfoto des ganzen Rechners oder der App.

**Einrichtung**
Der Vorgang, mit dem die App die KI-Werkzeuge für Moodle einrichtet: Verbindung und Skills. Er läuft beim Start, wenn etwas fehlt, und lässt sich über die Titelzeile erneut öffnen.
_Nicht zu verwechseln mit_: Anmeldung (bei Moodle).

**Skill**
Ein Paket aus Anleitungen und Regeln, das ein KI-Werkzeug bei Bedarf lädt. Die App bringt die Skills `moodle`, `moodle-fragen` und `lernsituation` mit.
_Nicht zu verwechseln mit_: Werkzeug (eine Funktion der App, die die KI aufruft).

**Werkzeug**
Eine Funktion der App, die ein KI-Werkzeug über den MCP-Server aufruft, etwa zum Lesen oder Ändern eines Kurses.
_Nicht zu verwechseln mit_: Skill.

**Fragensammlung**
Die Moodle-Aktivität, in der Fragen und ihre Kategorien liegen. Der Test verweist auf sie.

**Fortschrittsliste**
Eine Moodle-Aktivität mit Einträgen, die man abhaken kann. Die App liest nur die Einträge, nie, wer sie abgehakt hat.

**Board**
Eine Moodle-Aktivität mit Spalten und eigenen Notizen, die jede Person für sich führt. Nicht im Einzelnutzermodus.
_Nicht zu verwechseln mit_: Kanban-Board.

**Kanban-Board**
Eine Moodle-Aktivität mit Spalten und Karten, die alle Teilnehmenden gemeinsam nutzen.
_Nicht zu verwechseln mit_: Board.

**Lernsituation**
Ein didaktischer Entwurf für berufsbildende Schulen, der in Moodle genau einem Kursabschnitt entspricht.
_Nicht zu verwechseln mit_: Abschnitt (der Moodle-Gliederungsteil des Kurses, ohne Didaktik).

**Entwurf**
Der Zwischenstand einer Lernsituation im Arbeitsordner, bevor sie in den Kurs übertragen ist. Maßgeblich ist danach, was in Moodle steht.
_Nicht zu verwechseln mit_: Entwurfsbereich (der Moodle-Ablageort für Dateien eines Felds).

**Interaktives Element**
Eine kleine HTML-Anwendung zum Ausprobieren oder Üben, die in einem abgeschotteten Rahmen eines Textes läuft. Keine Bewertung, kein Gedächtnis.
_Nicht zu verwechseln mit_: Aktivität (eine Moodle-Aktivität wie Test oder Board).

**Verborgen / sichtbar**
Die Moodle-Sichtbarkeit einer Aktivität oder eines Abschnitts. Verborgenes erscheint für Lernende nicht auf der Kursseite; Voraussetzungen können den Zugang zusätzlich einschränken.

**Sichtbarkeitswahl bei Wiederherstellungen**
Ob wiederhergestellte Inhalte ihre Sichtbarkeit aus der Quelle behalten („wie Quelle“) oder die neuen Aktivitäten nachträglich verborgen werden („verborgen“). Die Voraussetzungen der Quelle bleiben in beiden Fällen erhalten.
_Code_: `WiederherstellungsSichtbarkeit`

**Druckaufbereitung**
Eine Funktion einer Moodle-Instanz, die Aufgabenblätter zum Drucken aufbereitet. Ob sie vorhanden ist, erkennt die App, sie wird nicht eingestellt.

**SchuCu**
Das „Schulische Curriculum Berufsbildende Schulen“, eine Leitlinie für die BBS. Die SchuCu-Tabelle einer Lernsituation stützt sich darauf und weist ihre Fachbezüge aus. Das Gymnasium und die IGS haben ihr eigenes schulinternes Curriculum, das hier nicht gemeint ist.

**KI-Sitzung**
Die Verbindung eines KI-Werkzeugs zur App über den MCP-Server.
_Nicht zu verwechseln mit_: Moodle-Sitzung.

**Moodle-Sitzung**
Die Anmeldung bei Moodle, die die App über ein Sitzungscookie hält. Läuft sie ab, meldet sich die App neu an.
_Nicht zu verwechseln mit_: KI-Sitzung.
