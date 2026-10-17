# Gemessene Moodle-Formulare für Sicherung und Wiederherstellung

Prüfung am 17. Oktober 2026 auf der autorisierten Testinstanz mit einem bearbeitenden Lehrkraftkonto. Die Sicherung nennt Moodle 5.1.7+ (Build 20260928), Sicherungsformat Moodle 2 und Sicherungsversion 5.1. Instanzadressen, echte Kursnummern und Sitzungskennungen werden hier nicht gespeichert.

## Einzelaktivität sichern

Der Link „Sicherung“ an einer Aktivität öffnet `/backup/backup.php?id=<kurs>&cm=<kursmodul>`.

Die Assistenten verwenden native POST-Formulare auf `/backup/backup.php`:

| Schritt | `stage` im Formular | Formularmarke | Wesentliche Felder |
|---|---|---|---|
| Einstellungen | `1` | `_qf__backup_initial_form` | `id`, gegebenenfalls `cm`, `backup`, `sesskey`, `setting_root_*` |
| Inhaltsauswahl | `2` | `_qf__backup_schema_form` | `setting_activity_<art>_<cmid>_included`, `setting_activity_<art>_<cmid>_userinfo` |
| Bestätigung | `4` | `_qf__backup_confirmation_form` | Gewählte Einstellungen, Inhaltsauswahl, `setting_root_filename` |

Der normale Vorwärtsknopf heißt `submitbutton`; außerdem gibt es `previous`, `cancel` und auf der ersten Seite `oneclickbackup`. Die Weiter-Schritte sollen ausdrücklich durchlaufen werden, damit Auswahl und Bestätigung geprüft werden können.

Auf dem geprüften Konto ist `setting_root_users=0` bereits als verstecktes Feld vorgegeben. Abhängige Nutzerdatenoptionen sind deaktiviert. Das ist eine Eigenschaft des geprüften Kontos, keine allgemeine Garantie für andere Konten oder Instanzen.

Für die Probe wurden nur Aktivitäten, Dateien und Filter eingeschaltet. Gruppen, Kalender, Blöcke, Badges, Inhaltsspeicher und alte Kursdateien wurden nicht einbezogen. Der Export enthielt ausschließlich die eigens angelegte, verborgene Textseite.

## Hintergrundverarbeitung und Download

„Sicherung ausführen“ meldet zunächst „Der Sicherungsvorgang ist vorbereitet“ und „Vorgang anstehend“. Die Datei ist zu diesem Zeitpunkt noch nicht herunterladbar.

Die Oberfläche verlinkt `/backup/restorefile.php?contextid=<kontext>`. Dort erscheinen Sicherungsbereiche für Aktivität, Kurs und persönliche Dateien. Diese Bereiche nicht vollständig als KI-Ausgabe übernehmen, sondern die angeforderte Sicherung gezielt ermitteln.

Der tatsächlich geladene Browsercode `core_backup/async_backup` verwendet native AJAX-Dienste auf `/lib/ajax/service.php`:

- `core_backup_get_async_backup_progress` mit `backupids` und `contextid`.
- `core_backup_get_async_backup_links_backup` mit `filename`, `contextid` und `backupid`.
- `core_backup_get_async_backup_links_restore` mit `backupid` und `contextid`.

Beim geprüften Export meldete der Fortschrittsdienst am Ende `progress=1` und `status=1000`. Erst danach bot die Sicherungsliste Download- und Wiederherstellungslinks an. Der Download erfolgte über einen von Moodle gelieferten `/pluginfile.php/.../user/backup/...mbz?forcedownload=1`-Link. Pfad und Kontext müssen aus der Antwort übernommen werden.

Die heruntergeladene Probe war 2457 Bytes groß und ein TAR-Archiv mit `.mbz`-Endung, kein ZIP. Im Archiv geprüft: genau eine Aktivität, `users=0`, keine `users.xml`, unveränderter Name und Seiteninhalt samt Umlauten. Daraus keine generelle Zusage über alle Archivformate oder Aktivitätsarten ableiten.

## Lokale Sicherungsdatei hochladen

`/backup/restorefile.php?contextid=<kontext>` enthält ein POST-Formular mit `_qf__course_restore_form`, `contextid`, `sesskey` und dem Draft-Dateifeld `backupfile`.

Der Knopf `backupfilechoose` öffnet Moodles native Dateiauswahl. Der geprüfte Upload verwendet `/repository/repository_ajax.php`; das Dateifeld heißt `repo_upload_file`, weitere Felder sind `title`, `author`, `license` und `itemid`. Repository-ID und weitere Zustandswerte zur Laufzeit aus dem Dateiauswahldialog ermitteln.

Die im Browser heruntergeladene Probe wurde erneut lokal ausgewählt, unter ihrem `.mbz`-Dateinamen hochgeladen und im Wiederherstellungsformular angezeigt. Das Uploadlimit des geprüften Formulars beträgt 200 MB; nicht fest im Werkzeug hinterlegen.

## Einzelaktivität wiederherstellen

Nach Absenden des Uploadformulars öffnet Moodle `/backup/restore.php?contextid=<kontext>&filename=<laufzeitkennung>`.

| Schritt | `stage` im Formular | Formularmarke / Felder |
|---|---|---|
| Sicherungsdetails bestätigen | `2` | `contextid`, `filepath`, `sesskey` |
| Ziel auswählen | `4` | `contextid`, `filepath`, `sesskey`, `target`, `targetid`, `search`, `searchcourses` |
| Einstellungen | `4` | `_qf__restore_settings_form`, `restore`, `setting_root_*` |
| Schema | `8` | `_qf__restore_schema_form`, `restore`, `setting_activity_*` |
| Prüfung | `16` | `_qf__restore_review_form`, `restore`, gewählte Einstellungen |

Im geprüften Aktivitätskontext bot die Zielseite ausschließlich „In einem vorhandenen Kurs wiederherstellen“ mit `target=4` an. Der Zielkurs wurde über die native Kurssuche ermittelt und anhand der Radioauswahl `targetid` überprüft. Die Suche selbst kann eine vorläufige Pflichtfeldmeldung zeigen; danach wird mit dem ausgewählten Kurs fortgefahren.

Die Bestätigungs- und Zielseiten besitzen einen normalen Weiter-Knopf ohne Namen. Die folgenden Formulare verwenden `submitbutton`. Doppelte Formularfelder wie `contextid` kommen tatsächlich vor; der vorhandene Listenparser darf sie nicht in eine Map zusammenfassen.

Bei der Probe blieben `users=0` und `setting_root_enrolments=0`. Rechteänderungen und alte Kursdateien wurden deaktiviert. Das Ausführen der Wiederherstellung führte wiederum zu einem Hintergrundauftrag, nicht zu einem sofortigen Erfolg.

Nach Abschluss wurde die neue Textseite im selben Testkurs geöffnet und ihr Inhalt gegen den ursprünglichen Probeinhalt geprüft. Es existierten Original und neue Kopie mit unterschiedlichen Kursmodul-IDs; beide waren verborgen. Damit ist für diesen Einfügeweg belegt: eine neue Aktivität entsteht, das Original wird nicht aktualisiert.

## Kurssicherung mit ausgewählten Inhalten

Ohne `cm` startet `/backup/backup.php?id=<kurs>` eine Kurssicherung. Die Schema-Seite enthält zusätzlich `setting_section_section_<abschnittsid>_included` und die einzelnen Aktivitätsfelder. So lassen sich Abschnitte oder mehrere einzelne Aktivitäten im selben nativen Ablauf auswählen.

Für die zweite Probe wurden alle Inhalte abgewählt und ausschließlich der allgemeine Abschnitt sowie die eigene Probeaktivität eingeschaltet. Die Bestätigungsseite wurde anhand der versteckten `*_included`-Felder auf genau diese Auswahl geprüft. Die eingeschränkte Kurssicherung wurde anschließend zur Hintergrundverarbeitung angenommen.

Nach Abschluss wurde auch diese Sicherung heruntergeladen und als Archiv geprüft: 3890 Bytes, genau die ausgewählte Aktivität, `users=0`, keine `users.xml`. Die Inhaltsauswahl schränkt den Inhalt ein; der Sicherungstyp bleibt trotzdem „Kurs“.

## Zielwege bei einer Kurssicherung

Im Kurskontext bot die Zielseite drei getrennte POST-Formulare auf `/backup/restore.php` an:

| Formular | `target` | Bedeutung von `targetid` |
|---|---|---|
| Neuer Kurs | `2` | Gewählter Kursbereich |
| Aktueller Kurs, verschmelzen | `1` | Versteckte ID des aktuellen Kurses |
| Aktueller Kurs, Inhalte löschen und wiederherstellen | `0` | Versteckte ID des aktuellen Kurses |
| Anderer bestehender Kurs, verschmelzen | `4` | Gewählter Kurs aus der Kurssuche |
| Anderer bestehender Kurs, Inhalte löschen und wiederherstellen | `3` | Gewählter Kurs aus der Kurssuche |

Die Formulare enthalten außerdem `contextid`, `filepath`, `stage=4` und `sesskey`. Die neue Kursauswahl verwendet `catsearch`, die bestehende Kursauswahl `search`. Die Weiter-Knöpfe der Kurssicherung sind namenlose Submit-Inputs. Nicht den global ersten Weiter-Knopf verwenden, sondern den zum gewünschten Zielformular gehörenden.

Beim neuen Kurs wurden Einstellungen und Schema geöffnet. Das Schema enthält anpassbare Felder für Kursname, Kurzname und Kursbeginn (`setting_course_course_fullname[...]`, `setting_course_course_shortname[...]`, `setting_course_course_startdate[...]`) sowie die Inhaltsauswahl. Der Vorgang wurde anschließend über „Abbrechen“ und die Bestätigung „Ja“ beendet, ohne die Wiederherstellung auszuführen. Die löschenden Zielwege wurden ausschließlich als angebotene Optionen erfasst, nicht ausgeführt.

### Bereits die Zielauswahl kann schreiben

Der [Moodle-Core 5.1](https://github.com/moodle/moodle/blob/MOODLE_501_STABLE/public/backup/util/ui/restore_ui_stage.class.php#L450) legt bei der bestätigten Auswahl „neuer Kurs“ bereits vor dem Einstellungsformular einen Platzhalterkurs an. Der [native Abbruchpfad](https://github.com/moodle/moodle/blob/MOODLE_501_STABLE/public/backup/util/ui/restore_ui.class.php#L207) entfernt diesen temporären Kurs wieder. Im Browser wurde dieser Abbruch einschließlich Bestätigungsdialog durchlaufen; die Löschlogik ist durch den Core-Code belegt.

Die lokalisierten Platzhalternamen wurden über Moodles Sprachdienst gelesen; die anschließende native Kurssuche lieferte unter dem Lehrkraftkonto keinen Treffer dafür. Eine direkte Datenbank- oder Administrationsprüfung wurde nicht durchgeführt. Der Core-Cleanup prüft den booleschen Rückgabewert von `delete_course` nicht; ein Erfolgsredirect allein ist deshalb kein ausreichender Cleanup-Nachweis für das spätere Werkzeug.

Folgerung für moocp: Die Grenze für Schreibfreigaben liegt bei diesem Weg bereits vor der Zielbestätigung. Beim Abbruch muss der native Cleanup ausgeführt werden. Den Tab zu schließen oder den Wizardzustand zu vergessen ist kein gleichwertiger Abbruch.

## Bereinigung

Original und wiederhergestellte Kopie der Probeaktivität wurden gezielt über Moodles Oberfläche entfernt. Nach Neuladen war keine der beiden mehr im Abschnitt vorhanden. Die beiden selbst erzeugten Sicherungsdateien wurden aus dem persönlichen Sicherungsbereich entfernt; die vier bereits vorhandenen Sicherungsdateinamen blieben nach Speichern und Rücklesen unverändert erhalten.

Die heruntergeladenen Probearchive enthalten ausschließlich Testmaterial und liegen außerhalb des Repositorys im Browser-Downloadbereich.

## Abgrenzung des Teststands

- Einzelaktivität: Sichern, Hintergrundabschluss, Download, Archivprüfung, lokaler Upload, Wiederherstellen und Rücklesen der neuen Aktivität ausgeführt.
- Kurssicherung mit eingeschränkter Auswahl: Auswahl, Ausführung, Hintergrundabschluss, Download und Archivprüfung ausgeführt; sämtliche angebotenen Zielwege erfasst, neuer Kurs bis zum Schema geöffnet und nativ abgebrochen.
- Löschende Wiederherstellung und abgeschlossene Neuanlage eines Kurses wurden nicht ausgeführt.
- Noch nicht geprüft: Übertragung auf eine zweite Instanz, große Sicherungen, eingebettete Dateien, mehrere unterschiedliche Aktivitätsarten, Versions- und Pluginunterschiede sowie gezielt erzeugte Fehler oder Verbindungsabbrüche.
- Das sind Browsermessungen für die spätere moocp-Anbindung, noch keine implementierten moocp-Werkzeuge und keine automatisierte Regressionstestsuite.
