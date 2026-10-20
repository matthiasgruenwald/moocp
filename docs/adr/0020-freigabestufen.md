# E20 Wie viele Freigaben, stellt die Lehrkraft ein, nicht Claude

Seit 0.9.6 (2026-10-07). Status: gilt. Die Kurzfassung steht in [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

Drei Stufen in einem Feld der Titelzeile (`Bestaetigungen` in `lib/freigabe.dart`): „mittel" wie E4, „alle" zusätzlich vor jedem Vorgang, der in Moodle etwas erzeugt (verborgen Anlegen, Duplizieren, Kategorie anlegen, Fragen importieren) und vor dem Füllen und Ändern dessen, was die App seit der Anmeldung selbst verborgen angelegt hat, solange es verborgen ist, „keine" ohne Schreibfreigaben; fachliche Karten-Zuordnungen erfordern weiterhin eine menschliche Entscheidung (E20). Gerade Angelegtes ist noch nichts Bestehendes, es zu füllen gehört zum Anlegen (`fuellenAb` in `lib/moodle/kurs.dart`); sonst kostete eine Lernsituation mit Board, Fortschrittsliste und Test bei „mittel" je einen Dialog für etwas, das niemand außer der KI gesehen hat. Kopien zählen nicht dazu – bei ihnen ist der Zeilenvergleich zum Original der Sinn der Freigabe –, und Verschieben, Sichtbarkeit und Löschen fragen immer. Entschieden wird an einer Stelle, `Freigaben.anfragen`: Jede Anfrage nennt mit `ab`, ab welcher Stufe sie kommt, und liegt die eingestellte darunter, gilt sie als erteilt. So kann kein Werkzeug die Einstellung übersehen, und eine neue Freigabe ist von selbst dabei. Die Stufe steht in den Einstellungen und gilt über einen Neustart hinweg – eine, die sich von selbst zurückstellte, überraschte; dass sie Rückfragen abschaltet, zeigt das Feld rot und das Protokoll bei jedem Start. Die Freigabe je Bildschirmfoto hängt nicht daran (`ab: keine`, also immer): Sie entscheidet nicht über eine Änderung, sondern darüber, welches Bild aus dem Kurs an Claude geht (A1, E18). Claude erfährt die Stufe über `status` und nach einer ausgelassenen Freigabe in der Antwort des Werkzeugs – damit die Skills keine Rückfrage ankündigen, die nicht kommt –, kann sie nicht ändern und soll nie vorschlagen, sie zu senken. Gebündelt wird nur, was ein Werkzeugaufruf zusammen erledigt (`aendern_mehrere`, `links_setzen`, `fragen_importieren`): Über mehrere Aufrufe hinweg bräuchte es eine Planungsebene im Code, und die ist mit E4 verworfen.

### Sichtbarkeit wiederhergestellter Inhalte

Wiederherstellungen sind eine Ausnahme vom Grundsatz „neu Angelegtes ist
verborgen“ (A3): Bei `wiederherstellen_datei` und `uebertragen` gilt
`sichtbarkeit: wie_quelle` als Vorgabe. Moodle übernimmt Sichtbarkeit und
Voraussetzungen aus der Sicherung; die App ändert sie nicht nachträglich.
Ein ausdrücklich gewähltes `verborgen` verbirgt nur eindeutig zugeordnete
neue Aktivitäten nach dem Wiederherstellen. Das kann kurzzeitig sichtbare
Inhalte nicht verhindern. Ein neuer Kurs bleibt als Platzhalter verborgen,
sofern sein Formular dies bietet; die Wahl betrifft die wiederhergestellten Inhalte.

Die Wahl steht vor dem Start in der Freigabe, bei Übertragungen in der
Zusammenfassung und je Ziel. Die Freigabestufe bleibt maßgeblich. Die Wahl
bleibt im Vorgang über Statusabfragen und Neustarts erhalten; Vorgänge ohne
gespeicherte Wahl behalten das bisherige Verbergen. Eine andere Wahl hebt
den Doppelstart-Schutz nicht auf.

Die Rückleseprobe vergleicht weiterhin Zahl, Namen und Aktivitätsarten sowie
Anhänge und Fragen im bisher möglichen Umfang. Bei `wie_quelle` sind
Sichtbarkeit und Voraussetzungen ausdrücklich nicht gegengeprüft; `verified`
bestätigt nur die übrigen Prüfungen. Die Neuverknüpfung kopierter Lernlandkarten
erhält ihre vor dem Verknüpfen gelesene Sichtbarkeit. Ungelöste Ortsziele
bleiben offen und werden benannt.

Pauschales Verbergen würde die bereitgestellte Unterrichtseinheit gegenüber
der Quelle verändern. Eine zusätzliche Rückfrage zur Sichtbarkeitswahl ist
deshalb kein eigener Hauptweg: Der Plan nennt die Vorgabe, die App-Freigabe
zeigt ihre Wirkung. Wer verborgen wiederherstellen will, beauftragt das ausdrücklich.

### Fachliche Zuordnung von Kartenorten

Eine fachliche Ortszuordnung zu einer vorhandenen Zielaktivität ist eine
menschliche Entscheidung und bleibt unabhängig von der Freigabestufe
erforderlich. Der Dialog zeigt Karte, Kurs, bisherigen und vorgeschlagenen
Zielnamen samt Identitäten sowie die Begründung der KI als Vorschlag.
Erst danach wird geschrieben; geänderte Quell-, Karten- oder Zielinhalte
verlangen eine neue Entscheidung. Das gilt für ausdrücklich beauftragte
Zielwechsel über MCP. Die mechanische Neuverknüpfung nachgewiesener Kopien
bei einer Übertragung folgt weiterhin der eingestellten Freigabestufe.

Lesebelege für KI-Kandidaten bleiben in der App-Sitzung und verfallen nach
30 Minuten. Sie binden den Vorschlag an Profil, Instanz, Kartenkurs, Ort,
Quelle und Kandidateninhalt. Die Fachbeurteilung bleibt bei KI und Lehrkraft;
die App prüft Identitäten, Stand und Entscheidung. Ohne passenden Kandidaten
bleibt der Ort offen. Ein zusätzlicher Kopierauftrag ist eine eigene Entscheidung.

### Begrenzte Ausnahme im Debug-Testbetrieb

Für den ausdrücklich bewilligten unbeaufsichtigten Testbetrieb darf die App eigene verborgene ZZ-Textseiten und ZZ-Lernlandkarten automatisch freigeben. Erforderlich sind eine Bindung an Profilkennung und tatsächliche Instanzadresse sowie eine ausdrückliche Testkursliste; Inhaltsbilder brauchen zusätzlich `screenshots:true`. Folgeaktionen prüfen die in dieser App-Sitzung erzeugte cmid, Kurs, Name und den vollständigen zuletzt zurückgelesenen Formularstand. Vorhandene ZZ-Objekte, andere Inhalte, fremde Kurse und Release-Bauten erhalten keine Testautomatik. Die Ausnahme ist keine Freigabestufe und kann nicht über MCP eingeschaltet werden. Jeder automatische Vorgang steht im Protokoll und in der Werkzeugantwort. Sperr-/Positivlisten, Browserrichtlinien, Inhaltsausschnitt, Cookie-Isolation und Arbeitsordner gelten unverändert.

Eine explizite Auswahl eigener Proben darf auch in gebundene Testkurse eingefügt werden. Dafür wird nur die in derselben App-Sitzung erstellte, vollständig geprüfte Sicherungsdatei am Inhalts-Hash erkannt. Die neuen Aktivitäten müssen eindeutig zum tatsächlichen Kopiervorgang gehören und verborgen sein. Bevor Folgeaktionen automatisch erlaubt werden, vergleicht die App ihre vollständigen Formularinhalte, Kartendaten und gelesenen Datei-Bytes mit der eigenen Quelle; nur technische Kennungen, die unwirksamen Datumswerte einer ausgeschalteten Terminerinnerung und belegte neue Ortsziele werden normalisiert. Der Aktivierungsschalter und aktive Termine bleiben Teil des Inhaltsnachweises. Ungelesene Inhalte, alte Quellverweise oder Abweichungen erhalten keinen Testbesitz. Das gilt auch beim ausdrücklich gebundenen zweiten Profil. Die allgemeine Wiederherstellungsverifikation bleibt davon unabhängig; ihre Prüflücken werden weiter berichtet. Ein Statusaufruf darf bereits übernommene, später geänderte Inhalte nicht erneut zu eigenen Proben erklären. Belege verfallen mit der App-Sitzung oder dem Ende der Quellprofilbindung. Kopien bleiben außerhalb der normalen Menge selbst angelegter Aktivitäten. Standproben lesen in eigene temporäre Ordner, erhalten bearbeitete Entwürfe und binden auch bei Folgeaktionen alle gelesenen Dateiinhalte; ungelesene Dateien erhalten keine automatische Freigabe.

Die persönliche Freigabe im normalen Betrieb bleibt bestehen. Ablauf und Nachweise stehen in der [Testanleitung](../agents/testing.md).

## Verworfen

„keine" beim Start auf „mittel" zurückfallen zu lassen (das rote Feld und der Protokolleintrag sind die Sichtbarkeit, die es braucht), und die Stufe über MCP erreichbar zu machen.
