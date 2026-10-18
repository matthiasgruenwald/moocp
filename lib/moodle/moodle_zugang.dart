// Der Zugang zu Moodle über HTTP, mit der Sitzung der Lehrkraft.
//
// Drei Dinge passieren hier und nirgends sonst:
//
//  1. Anmelden mit den Zugangsdaten, die die Lehrkraft in der App eingegeben
//     hat. Sie liegen nur im Arbeitsspeicher und nur, solange die App läuft;
//     sie werden nie gespeichert, nie protokolliert und nie an MCP gegeben.
//  2. Jede Anfrage prüfen, bevor sie rausgeht -- auch jedes Umleitungsziel:
//     zuerst gegen die Sperrliste (sperrliste.dart), dann gegen die
//     Positivliste. Geprüft werden Methode, Pfad, Parameter und bei
//     Schreibvorgängen die Formularwerte (etwa: ist es das Formular eines
//     Typs, den die App kennt?). Welche Kurse die Sitzung bearbeiten darf,
//     entscheidet Moodle selbst -- die App darf genau, was die Lehrkraft darf.
//     Was nicht auf der Liste steht, wird nicht angefragt. Das ist die Grenze,
//     die im Skill bisher nur beschrieben war; hier ist sie erzwungen.
//  3. Eine abgelaufene Sitzung erkennen (Umleitung auf die Anmeldeseite),
//     genau einmal neu anmelden. Lesen wird wiederholt; Schreiben meldet
//     SitzungAbgelaufen, und das Werkzeug baut den ganzen Vorgang neu auf.
//     Schlägt die Neuanmeldung fehl, werden die Zugangsdaten verworfen --
//     keine Schleife, denn Moodle sperrt Konten nach mehreren Fehlversuchen.
//     Nur wenn Moodle schon vor dem Senden des Passworts nicht erreichbar
//     war, bleiben sie: Das ist kein Fehlversuch, und die nächste Anfrage
//     versucht es wieder (etwa nach dem Aufwachen aus dem Standby).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../protokoll.dart';
import 'browserliste.dart';
import 'sicherung_regeln.dart';
import 'wiederherstellung_regeln.dart';
import 'sperrliste.dart';

class MoodleFehler implements Exception {
  MoodleFehler(this.meldung);
  final String meldung;
  @override
  String toString() => meldung;
}

/// Moodle war nicht zu erreichen: keine Verbindung, Abbruch, TLS-Fehler oder
/// keine Antwort innerhalb der Zeitgrenze.
class MoodleNichtErreichbar extends MoodleFehler {
  MoodleNichtErreichbar(super.meldung);
}

/// Die Sitzung lief während eines Schreibvorgangs ab. Neu angemeldet ist
/// bereits; der Vorgang muss von vorn beginnen (frisches Formular).
class SitzungAbgelaufen extends MoodleFehler {
  SitzungAbgelaufen() : super('Sitzung während des Schreibens abgelaufen.');
}

typedef Felder = List<MapEntry<String, String>>;

/// Eine Antwort von Moodle.
class Antwort {
  Antwort(this.status, this.adresse, this.bytes, this.inhaltstyp, {this.ort});
  final int status;
  final Uri adresse;
  final Uint8List bytes;
  final String? inhaltstyp;

  /// Location-Kopf einer Umleitung, sonst null.
  final String? ort;

  String get text => utf8.decode(bytes, allowMalformed: true);
}

/// Eine Datei für einen Upload.
class Anhang {
  Anhang(this.feld, this.dateiname, this.bytes, this.mime);
  final String feld;
  final String dateiname;
  final List<int> bytes;
  final String mime;
}

/// Eine Regel der Positivliste.
class Erlaubt {
  const Erlaubt(this.methode, this.pfad, this.zweck,
      {this.parameter, this.formular, this.inhalt, this.anhang});
  final String methode;
  final String pfad;
  final String zweck;
  final bool Function(Map<String, String> q)? parameter;
  final bool Function(Felder f)? formular;

  /// Prüft die hochgeladene Datei. Eine Regel mit diesem Prüfer passt nur auf
  /// Anfragen mit Datei.
  final bool Function(Anhang a)? anhang;

  /// Prüft einen JSON-Rumpf (Moodle-AJAX-Dienste), mit den Parametern der Adresse.
  final bool Function(Map<String, String> q, String rumpf)? inhalt;
}

String? wertIn(Felder f, String name) {
  for (final e in f) {
    if (e.key == name) return e.value;
  }
  return null;
}

/// Ob eine Seite das Skript der Druckaufbereitung „Aufgabenblatt-Druck" trägt.
///
/// Das Skript steht unter „Zusätzliches HTML", vor dem Schließen des
/// BODY-Tags, und damit im Quelltext jeder Seite mit Standardlayout (nicht
/// im Layout `embedded`, dort gibt Moodle das Zusätzliche HTML nicht aus).
/// Erkannt an der id seines Druckcontainers: Die setzt nur das Skript, sie
/// steht in keiner Moodle-Seite ohne es. Wofür die Skills das brauchen:
/// skills/moodle/references/drucken.md.
bool druckaufbereitungErkannt(String html) => html.contains('ab-print-root');

/// Der Pfad des Theme-Stylesheets einer Seite
/// (`/theme/styles.php/<theme>/<revision>/all`), ohne Rechner. Die Revision ändert sich, wenn die
/// Administration die Caches leert; die App liest sie bei jeder Anmeldung neu.
String? themeStylesheetIn(dom.Document doc) {
  for (final l in doc.querySelectorAll('link[rel="stylesheet"]')) {
    final u = Uri.tryParse(l.attributes['href'] ?? '');
    if (u != null && u.path.startsWith('/theme/styles.php/')) return u.hasQuery ? '${u.path}?${u.query}' : u.path;
  }
  return null;
}

class MoodleZugang {
  MoodleZugang(this.protokoll);

  /// Zeitgrenzen: Aufbau der Verbindung, und bis die Antwort vollständig da
  /// ist. Ohne sie kann eine hängende Anfrage ein Werkzeug beliebig lange
  /// blockieren.
  ///
  /// Moodle sperrt die Sitzung, solange eine Anfrage läuft; jede weitere
  /// Anfrage derselben Sitzung wartet dahinter (gemessen in den
  /// Browser-Skills: 50 ms wurden zu über 45 s, weil ein nicht abgewarteter
  /// Aufruf die Sperre hielt). Deshalb wird hier jede Anfrage abgewartet --
  /// nie eine abschicken und liegen lassen.
  static const Duration verbindungsgrenze = Duration(seconds: 20);
  static const Duration antwortgrenze = Duration(minutes: 2);

  final Protokoll protokoll;

  static bool _zahl(String? s) => s != null && RegExp(r'^\d+$').hasMatch(s);
  static bool _gesetzt(String? s) => s != null && s.isNotEmpty;

  /// Das Formular trägt die Marke seiner Klasse (`_qf__<klasse>`). Die Klassen
  /// wandern zwischen Moodle-Versionen den Namensraum (question_export_form
  /// wurde qbank_exportquestions\form\export_form), deshalb ein Muster.
  static bool _marke(Felder f, RegExp muster) => f.any((e) => muster.hasMatch(e.key));

  /// Dienste, die etwas ändern -- fürs Protokoll.
  static const Set<String> schreibendeDienste = {
    'core_courseformat_update_course', 'mod_quiz_add_random_questions', 'core_form_dynamic_form', //
    'mod_board_delete_column', 'mod_board_move_column', 'mod_board_lock_column', 'mod_board_delete_note',
    'mod_kanban_add_column', 'mod_kanban_delete_column', 'mod_kanban_move_column', 'mod_kanban_add_card',
    'mod_kanban_delete_card', 'mod_kanban_move_card',
  };

  static bool _nurSchluessel(Map<String, String> q, Set<String> erlaubt) =>
      q.keys.every(erlaubt.contains);

  /// Fragennummern, durch Komma getrennt, wie delete.php sie nimmt.
  static bool _fragenListe(String? s) => s != null && RegExp(r'^\d+(,\d+)*$').hasMatch(s);

  /// Die Rückfrage von delete.php: die Auswahl als `q<id>=1`, `deleteselected=1`.
  /// Dazu returnurl, genau die Fragenübersicht der Sammlung: Ohne sie bricht
  /// die Rückfrage in Moodle 5.1 mit einem PHP-Fehler ab (gemessen
  /// 30.09.2026, „out_as_local_url() on int"). Aufgerufen wird sie nie -- sie
  /// ist nur das Ziel der Umleitung nach dem Löschen, und der folgt die App
  /// nicht.
  static bool _loeschRueckfrage(Map<String, String> q) {
    final auswahl = RegExp(r'^q\d+$');
    return q.keys.every(
            (k) => const {'cmid', 'deleteselected', 'deleteall', 'returnurl'}.contains(k) || auswahl.hasMatch(k)) &&
        _zahl(q['cmid']) &&
        q['returnurl'] == '/question/edit.php?cmid=${q['cmid']}' &&
        q['deleteselected'] == '1' &&
        const {'0', '1'}.contains(q['deleteall'] ?? '1') &&
        q.keys.any(auswahl.hasMatch) &&
        q.entries.where((e) => auswahl.hasMatch(e.key)).every((e) => e.value == '1');
  }

  /// Die Bestätigung von delete.php: nur diese Felder, confirm ist der
  /// md5-Wert der Auswahl, den Moodle selbst in die Rückfrage schreibt.
  static bool _loeschBestaetigung(Map<String, String> w) =>
      w.keys.every(const {'cmid', 'courseid', 'deleteselected', 'deleteall', 'confirm', 'sesskey', 'returnurl'}.contains) &&
      _fragenListe(w['deleteselected']) &&
      RegExp(r'^[0-9a-f]{32}$').hasMatch(w['confirm'] ?? '') &&
      _gesetzt(w['sesskey']) &&
      (w['cmid'] == null || _zahl(w['cmid'])) &&
      (w['courseid'] == null || _zahl(w['courseid'])) &&
      const {'0', '1'}.contains(w['deleteall'] ?? '1');

  /// Aktivitätstypen, deren Formular die App kennt: anlegen und ändern.
  /// Ein Typ kommt erst hinein, wenn sein Formular im Testkurs gemessen ist.
  /// Die Übersicht „Unterstützte Aktivitäten und Fragetypen" in README.md
  /// (Teil 2) im selben Zug nachziehen.
  static const Set<String> schreibbareModule = {
    'page', 'label', 'assign', 'folder', 'subsection', 'book', 'quiz', 'qbank', //
    'checklist', 'wiki', 'board', 'kanban', 'url', 'resource',
  };

  /// Aktionen der Kursstruktur (core_courseformat_update_course), die die
  /// Werkzeuge benutzen. Andere -- etwa cm_stealth -- sind nicht gemessen.
  static const Set<String> kursAktionen = {
    'section_add', 'section_hide', 'section_show', 'section_move_after', 'section_delete', //
    'section_duplicate', 'cm_hide', 'cm_show', 'cm_move', 'cm_delete', 'cm_duplicate',
  };

  /// Die eigene Nutzer-ID, mitgelesen aus M.cfg. Dienste, die eine userid
  /// nehmen, dürfen nur mit dieser aufgerufen werden.
  int? _eigeneId;
  int? get eigeneId => _eigeneId;

  /// Die Aktivitäten, die die App seit der Anmeldung verborgen angelegt hat
  /// (aktivitaet_anlegen). Solange eine davon verborgen ist, gehört sie noch
  /// der Arbeitssitzung: Sie zu füllen fragt erst bei „alle", wie das Anlegen
  /// selbst ([fuellenAb] in kurs.dart). Nur im Speicher -- ein Neustart oder
  /// eine neue Anmeldung vergisst sie, dann fragt die App wieder ab „mittel".
  /// Kopien kommen nicht hinein: Bei ihnen ist der Zeilenvergleich zum
  /// Original der Sinn der Freigabe.
  final Set<int> selbstAngelegt = {};

  /// Moodle-AJAX-Dienste, die aufgerufen werden dürfen, mit einer Prüfung
  /// ihrer Argumente. Keiner liefert Daten anderer Personen.
  Map<String, bool Function(Map a)> get dienste => {
        // Kursstruktur: Abschnitte und Aktivitäten mit Name, Typ, Sichtbarkeit.
        'core_courseformat_get_state': (a) => _nur(a, {'courseid'}),
        // Kursstruktur ändern, nur mit den gemessenen Aktionen.
        'core_courseformat_update_course': (a) =>
            _nur(a, {'action', 'courseid', 'ids', 'targetsectionid', 'targetcmid'}) &&
            kursAktionen.contains(a['action']) &&
            a['ids'] is List,
        // Die eigenen Kurse (wie im Block „Meine Kurse") -- Name und Nummer.
        'core_course_get_enrolled_courses_by_timeline_classification': (a) =>
            _nur(a, {'classification', 'limit', 'offset', 'sort'}),
        // Die eigenen zuletzt besuchten Kurse, nur mit der eigenen userid.
        'core_course_get_recent_courses': (a) =>
            _nur(a, {'userid', 'limit', 'offset', 'sort'}) && _eigeneId != null && a['userid'] == _eigeneId,
        // Zufallsfragen in einen Test.
        'mod_quiz_add_random_questions': (a) => _nur(a, {'cmid', 'addonpage', 'randomcount', 'filtercondition'}),
        // Board: lesen (Notizen anderer gibt die App nicht heraus), Spalten
        // löschen, verschieben, sperren, eigene Notizen löschen.
        'mod_board_get_board': (a) => _nur(a, {'id', 'ownerid', 'groupid'}) && a['ownerid'] == 0,
        'mod_board_delete_column': (a) => _nur(a, {'id'}),
        'mod_board_move_column': (a) => _nur(a, {'id', 'sortorder'}),
        'mod_board_lock_column': (a) => _nur(a, {'id', 'status'}),
        'mod_board_delete_note': (a) => _nur(a, {'id'}),
        // Kanban: das gemeinsame Kursboard.
        'mod_kanban_get_kanban_content_init': (a) => _nur(a, {'cmid', 'boardid', 'timestamp'}),
        for (final k in const ['add_column', 'delete_column', 'move_column', 'add_card', 'delete_card', 'move_card'])
          'mod_kanban_$k': (a) => _nur(a, {'cmid', 'boardid', 'data'}),
        // Dynamische Formulare, nur die gemessenen Klassen.
        'core_form_dynamic_form': (a) => _nur(a, {'form', 'formdata'}) && dynamischeFormulare.contains(a['form']),
        // Sicherung: Fortschritt lesen.
        // Operation „restore" ist UNGEMESSEN (TODO.md); ohne Schlüssel gilt die Sicherung.
        'core_backup_get_async_backup_progress': (a) =>
            _nur(a, {'backupids', 'contextid', 'operation'}) &&
            a['backupids'] is List &&
            a['contextid'] is num &&
            (a['operation'] == null || a['operation'] == 'backup' || a['operation'] == 'restore'),
      };

  /// Formularklassen für core_form_dynamic_form.
  static const Set<String> dynamischeFormulare = {
    r'qbank_managecategories\form\question_category_edit_form',
    r'mod_kanban\form\edit_card_form',
    r'mod_kanban\form\edit_column_form',
  };

  static bool _nur(Map a, Set<String> schluessel) => a.keys.every(schluessel.contains);

  bool _dienstAufruf(Map<String, String> q, String rumpf) {
    final name = q['info'];
    final pruefen = dienste[name];
    if (pruefen == null) return false;
    try {
      final l = jsonDecode(rumpf);
      if (l is! List || l.length != 1) return false;
      final a = l.single;
      return a is Map && a['methodname'] == name && a['args'] is Map && pruefen(a['args'] as Map);
    } catch (_) {
      return false;
    }
  }

  /// Die Positivliste. Nur diese Anfragen gehen je raus -- auch als
  /// Umleitungsziel. Eine neue Funktion braucht hier einen Eintrag, und das
  /// soll auffallen.
  List<Erlaubt> get positivliste => [
        // ---- Anmelden
        Erlaubt('GET', r'^/login/index\.php$', 'Anmeldeseite',
            parameter: (q) => _nurSchluessel(q, {'testsession'})),
        Erlaubt('POST', r'^/login/index\.php$', 'Anmeldeformular',
            parameter: (q) => q.isEmpty),
        // ---- Lesen
        Erlaubt('GET', r'^/course/modedit\.php$', 'Bearbeitungsformular lesen',
            parameter: (q) => q.length == 1 && _zahl(q['update'])),
        Erlaubt('GET', r'^/course/editsection\.php$', 'Abschnittsformular lesen',
            parameter: (q) => _nurSchluessel(q, {'id', 'sr'}) && _zahl(q['id'])),
        // Nur lesen: Mit Formularwerten würde dieselbe Adresse Filter umschalten.
        Erlaubt('GET', r'^/filter/manage\.php$', 'Filtereinstellungen eines Kurses (kurs_filter)',
            parameter: (q) => q.length == 1 && _zahl(q['contextid'])),
        // Fragen und Tests: nie die Fragenübersicht (question/edit.php) -- sie
        // zeigt „Erstellt von" mit Klarnamen.
        Erlaubt('GET', r'^/question/banks\.php$', 'Fragensammlungen eines Kurses',
            parameter: (q) => q.length == 1 && _zahl(q['courseid'])),
        Erlaubt('GET', r'^/question/bank/importquestions/import\.php$', 'Kategorien, Importformular',
            parameter: (q) => q.length == 1 && _zahl(q['cmid'])),
        Erlaubt('GET', r'^/question/bank/exportquestions/export\.php$', 'Exportformular',
            parameter: (q) => q.length == 1 && _zahl(q['cmid'])),
        Erlaubt('GET', r'^/question/bank/exporttoxml/exportone\.php$', 'eine Frage als XML',
            parameter: (q) => q.length == 3 && _zahl(q['id']) && _zahl(q['cmid']) && _gesetzt(q['sesskey'])),
        Erlaubt('GET', r'^/question/bank/editquestion/question\.php$', 'Bearbeitungsformular einer Frage',
            parameter: (q) =>
                _nurSchluessel(q, {'cmid', 'id', 'qtype', 'category', 'courseid', 'returnurl'}) && _zahl(q['cmid'])),
        Erlaubt('GET', r'^/mod/quiz/edit\.php$', 'Zusammenstellung eines Tests',
            parameter: (q) => q.length == 1 && _zahl(q['cmid'])),
        Erlaubt('GET', r'^/question/type/stack/questiontestrun\.php$', 'STACK: Fragetests und Varianten',
            parameter: (q) => _nurSchluessel(q, {'questionid', 'cmid', 'seed'}) && _zahl(q['questionid'])),
        // Nur über eine Frage: Ohne questionid öffnet STACK den Notizblock nur
        // Administratoren (stack.dart, stackCas).
        Erlaubt('GET', r'^/question/type/stack/adminui/caschat\.php$', 'STACK: CAS-Notizblock',
            parameter: (q) => q.length == 2 && _zahl(q['questionid']) && _zahl(q['cmid'])),
        Erlaubt('GET', r'^/mod/checklist/edit\.php$', 'Fortschrittsliste: die Einträge',
            parameter: (q) => q.length == 1 && _zahl(q['id'])),
        Erlaubt('GET', r'^/mod/wiki/view\.php$', 'Wiki: Startseite oder eine Seite',
            parameter: (q) => q.length == 1 && (_zahl(q['id']) || _zahl(q['pageid']))),
        Erlaubt('GET', r'^/mod/wiki/map\.php$', 'Wiki: Seitenliste (option 5; 1 und 6 zeigen Namen)',
            parameter: (q) => q.length == 2 && _zahl(q['pageid']) && q['option'] == '5'),
        Erlaubt('GET', r'^/mod/board/view\.php$', 'Board: die Board-ID', parameter: (q) => q.length == 1 && _zahl(q['id'])),
        Erlaubt('GET', r'^/mod/kanban/view\.php$', 'Kanban: die Board-ID', parameter: (q) => q.length == 1 && _zahl(q['id'])),
        Erlaubt('GET', r'^/grade/grading/manage\.php$', 'Bewertungsmethode einer Aufgabe (Definition, keine Bewertung)',
            parameter: (q) =>
                _nurSchluessel(q, {'contextid', 'component', 'area'}) && _zahl(q['contextid']) && q['component'] == 'mod_assign'),
        Erlaubt('GET', r'^/grade/grading/form/(rubric|guide)/edit\.php$', 'Bewertungsschema: Definitionsformular',
            parameter: (q) => q.length == 1 && _zahl(q['areaid'])),
        Erlaubt('GET', r'^/mod/book/tool/print/index\.php$', 'Buch: alle Kapitel mit chapterid',
            parameter: (q) => q.length == 1 && _zahl(q['id'])),
        Erlaubt('GET', r'^/mod/book/edit\.php$', 'Buchkapitel: Formular',
            parameter: (q) =>
                _nurSchluessel(q, {'cmid', 'id', 'pagenum', 'subchapter'}) &&
                _zahl(q['cmid']) &&
                (_zahl(q['id']) || _zahl(q['pagenum']))),
        // Sicherung einer Aktivität (sicherung.dart). Nur die gemessenen Schritte
        // der Assistenten; Nutzerdaten bleiben aus (sicherung_regeln.dart).
        Erlaubt('GET', r'^/backup/backup\.php$', 'Sicherung: Einstiegsseite einer Aktivität',
            parameter: (q) => _nurSchluessel(q, {'id', 'cm'}) && _zahl(q['id']) && (q['cm'] == null || _zahl(q['cm']))),
        Erlaubt('GET', r'^/backup/restorefile\.php$', 'Sicherung: Seite Wiederherstellen (Downloadlink suchen)',
            parameter: (q) => _nurSchluessel(q, {'contextid'}) && _zahl(q['contextid'])),
        Erlaubt('GET', r'^/pluginfile\.php/\d+/user/backup/(?:\d+/)?[^/?#]+\.mbz$', 'Sicherungsdatei',
            parameter: (q) => q.length == 1 && q['forcedownload'] == '1'),
        Erlaubt('GET', r'^/draftfile\.php/\d+/user/draft/\d+/.+', 'Datei im Entwurfsbereich'),
        Erlaubt('GET', r'^/pluginfile\.php/\d+/.+', 'Datei im Kurs'),
        Erlaubt('POST', r'^/lib/ajax/service\.php$', 'Moodle-Dienst (nur lesend, siehe dienste)',
            parameter: (q) =>
                _nurSchluessel(q, {'sesskey', 'info'}) &&
                (q['sesskey'] ?? '').isNotEmpty &&
                dienste.containsKey(q['info']),
            inhalt: _dienstAufruf),
        // ---- Schreiben
        Erlaubt('GET', r'^/course/modedit\.php$', 'Formular „Aktivität anlegen"',
            parameter: (q) =>
                _nurSchluessel(q, {'add', 'type', 'course', 'section', 'return', 'sr'}) &&
                schreibbareModule.contains(q['add']) &&
                _zahl(q['course']) &&
                _zahl(q['section'])),
        Erlaubt('POST', r'^/course/modedit\.php$', 'Aktivität speichern',
            parameter: (q) => q.isEmpty,
            formular: (f) {
              final modul = wertIn(f, 'modulename');
              return _zahl(wertIn(f, 'course')) &&
                  schreibbareModule.contains(modul) &&
                  wertIn(f, '_qf__mod_${modul}_mod_form') != null;
            }),
        // Sicherung: die Schritte 1, 2 und 4 des Assistenten, nur ohne
        // Nutzerdaten. Schritt 4 startet die Sicherung (sicherung.dart).
        Erlaubt('POST', r'^/backup/backup\.php$', 'Sicherung: Schritte 1, 2 und 4 (ohne Nutzerdaten)',
            parameter: (q) => q.isEmpty,
            formular: (f) {
              final schritt = wertIn(f, 'stage');
              return const {'1', '2', '4'}.contains(schritt) &&
                  (_marke(f, RegExp(r'^_qf__backup_(initial|schema|confirmation)_form$'))) &&
                  _gesetzt(wertIn(f, 'sesskey')) &&
                  ohneNutzerdaten(f);
            }),
        Erlaubt('POST', r'^/course/editsection\.php$', 'Abschnitt speichern',
            parameter: (q) => q.isEmpty,
            formular: (f) => _zahl(wertIn(f, 'id')) && f.any((e) => e.key.startsWith('_qf__'))),
        Erlaubt('POST', r'^/question/bank/exportquestions/export\.php$', 'Fragen exportieren',
            parameter: (q) => _nurSchluessel(q, {'cmid'}),
            formular: (f) => _marke(f, RegExp(r'^_qf__.*export.*form$')) && wertIn(f, 'format') == 'xml'),
        Erlaubt('POST', r'^/question/bank/importquestions/import\.php$', 'Fragen importieren (Moodle-XML)',
            parameter: (q) => _nurSchluessel(q, {'cmid'}),
            formular: (f) => _marke(f, RegExp(r'^_qf__.*import.*form$')) && wertIn(f, 'format') == 'xml'),
        // Speichern erzeugt eine neue Version -- nie mit makecopy, das legte
        // eine zweite Frage an.
        Erlaubt('POST', r'^/question/bank/editquestion/question\.php$', 'Frage speichern (neue Version)',
            parameter: (q) => _nurSchluessel(q, {'cmid', 'id', 'courseid'}),
            formular: (f) =>
                _zahl(wertIn(f, 'id')) &&
                f.any((e) => RegExp(r'^_qf__qtype_[a-z]+_edit_form$').hasMatch(e.key)) &&
                (wertIn(f, 'makecopy') ?? '0') == '0'),
        // Fragen löschen (fragen.dart, fragenLoeschen). Ohne confirm zeigt
        // delete.php nur die Rückfrage und ändert nichts; bestätigt wird mit
        // deren Formular, so wie Moodle es ausgibt -- je nach Moodle als
        // Formular oder als Link, darum beide Wege, mit denselben Feldern.
        // Die Auswahl nimmt die Rückfrage wie das Formular der Sammlung als
        // q<id>=1 (gemessen 30.09.2026, Moodle 5.1: eine Liste in
        // deleteselected allein wählt nichts aus, Moodle leitet nur zurück).
        Erlaubt('GET', r'^/question/bank/deletequestion/delete\.php$', 'Fragen löschen: Rückfrage oder Bestätigung',
            parameter: (q) => _loeschRueckfrage(q) || _loeschBestaetigung(q)),
        Erlaubt('POST', r'^/question/bank/deletequestion/delete\.php$', 'Fragen löschen: Bestätigung',
            parameter: (q) => q.isEmpty,
            formular: (f) => _loeschBestaetigung({for (final e in f) e.key: e.value})),
        Erlaubt('GET', r'^/mod/quiz/edit\.php$', 'Frage in einen Test einfügen',
            parameter: (q) =>
                q.length == 4 &&
                _zahl(q['cmid']) &&
                _zahl(q['addquestion']) &&
                _zahl(q['addonpage']) &&
                _gesetzt(q['sesskey'])),
        Erlaubt('POST', r'^/mod/quiz/edit\.php$', 'Test: Seiten neu aufteilen oder Beste Bewertung',
            parameter: (q) => q.isEmpty,
            formular: (f) {
              final k = f.map((e) => e.key).toSet();
              return _zahl(wertIn(f, 'cmid')) &&
                  _gesetzt(wertIn(f, 'sesskey')) &&
                  (k.length == 4 && k.containsAll({'questionsperpage', 'repaginate'}) ||
                      k.length == 4 && k.containsAll({'maxgrade', 'savechanges'}));
            }),
        Erlaubt('POST', r'^/mod/quiz/edit_rest\.php$', 'Test: Punkte, Reihenfolge, Platz entfernen, Fragen mischen',
            parameter: (q) => q.isEmpty,
            formular: (f) {
              final k = f.map((e) => e.key).toSet();
              final klasse = wertIn(f, 'class'), feld = wertIn(f, 'field'), aktion = wertIn(f, 'action');
              return k.every(const {
                    'class', 'field', 'action', 'id', 'maxmark', 'previousid', 'page', 'newshuffle', //
                    'sesskey', 'courseid', 'quizid',
                  }.contains) &&
                  _zahl(wertIn(f, 'id')) &&
                  _zahl(wertIn(f, 'quizid')) &&
                  _gesetzt(wertIn(f, 'sesskey')) &&
                  ((klasse == 'resource' &&
                          !k.contains('newshuffle') &&
                          ((aktion == null && (feld == 'updatemaxmark' || feld == 'move')) ||
                              (aktion == 'DELETE' && feld == null))) ||
                      (klasse == 'section' &&
                          aktion == null &&
                          feld == 'updateshufflequestions' &&
                          const {'0', '1'}.contains(wertIn(f, 'newshuffle'))));
            }),
        Erlaubt('GET', r'^/question/type/stack/deploy\.php$', 'STACK: Varianten einsetzen',
            parameter: (q) =>
                q.length == 4 &&
                _zahl(q['questionid']) &&
                _zahl(q['cmid']) &&
                _zahl(q['deploymany']) &&
                _gesetzt(q['sesskey'])),
        Erlaubt('POST', r'^/question/type/stack/deploy\.php$', 'STACK: eine Variante einsetzen',
            parameter: (q) => q.isEmpty,
            formular: (f) =>
                f.length == 4 && _zahl(wertIn(f, 'questionid')) && _zahl(wertIn(f, 'cmid')) && _zahl(wertIn(f, 'deploy'))),
        // Der Notizblock rechnet nur. Mit questionid hat sein Formular auch
        // „Speichern" (action = savechat), das Variablen und Feedback ohne neue
        // Version in die Frage schreibt -- darum genau ein action, und das ist go.
        Erlaubt('POST', r'^/question/type/stack/adminui/caschat\.php$', 'STACK: Ausdruck ausrechnen',
            parameter: (q) => q.length == 2 && _zahl(q['questionid']) && _zahl(q['cmid']),
            formular: (f) =>
                f.every((e) => const {'cas', 'maximavars', 'simp', 'action'}.contains(e.key)) &&
                f.where((e) => e.key == 'action').map((e) => e.value).join('|') == 'go'),
        Erlaubt('POST', r'^/mod/checklist/edit\.php$', 'Fortschrittsliste: Eintrag anlegen oder ändern',
            parameter: (q) => q.isEmpty,
            formular: (f) {
              final k = f.map((e) => e.key).toSet();
              return _zahl(wertIn(f, 'id')) &&
                  _gesetzt(wertIn(f, 'sesskey')) &&
                  (k.containsAll({'action', 'indent', 'displaytext', 'linkurl', 'additem'}) && wertIn(f, 'action') == 'additem' ||
                      k.containsAll({'itemid', 'displaytext', 'linkurl', 'updateitem'}) && !k.contains('action')) &&
                  k.every(const {'id', 'sesskey', 'action', 'indent', 'displaytext', 'linkurl', 'additem', 'itemid', 'updateitem'}.contains);
            }),
        Erlaubt('GET', r'^/mod/checklist/edit\.php$', 'Fortschrittsliste: Eintrag löschen, verschieben, einrücken, Art',
            parameter: (q) =>
                q.length == 4 &&
                _zahl(q['id']) &&
                _zahl(q['itemid']) &&
                _gesetzt(q['sesskey']) &&
                const {'deleteitem', 'moveitemup', 'moveitemdown', 'indentitem', 'unindentitem', 'makerequired', 'makeoptional', 'makeheading'}
                    .contains(q['action'])),
        Erlaubt('GET', r'^/mod/wiki/create\.php$', 'Wiki: Formular für eine neue Seite',
            parameter: (q) =>
                (q.length == 3 && _zahl(q['swid']) && _gesetzt(q['title']) && q['action'] == 'new') ||
                // Ohne erste Seite leitet view.php hierher um -- nur das gemeinsame Wiki (uid 0).
                (q.length == 4 && _zahl(q['wid']) && (q['group'] == '' || _zahl(q['group'])) && q['uid'] == '0' && q.containsKey('title'))),
        Erlaubt('POST', r'^/mod/wiki/(create|view)\.php$', 'Wiki: neue Seite anlegen',
            parameter: (q) => _nurSchluessel(q, {'action', 'wid', 'swid', 'group', 'uid', 'title', 'id', 'pageid'}) && (q['uid'] ?? '0') == '0',
            formular: (f) => _gesetzt(wertIn(f, 'pagetitle')) && _marke(f, RegExp(r'^_qf__mod_wiki_create_form$'))),
        Erlaubt('GET', r'^/mod/wiki/edit\.php$', 'Wiki: Bearbeitungsformular (nur zum Speichern)',
            parameter: (q) => q.length == 1 && _zahl(q['pageid'])),
        Erlaubt('POST', r'^/mod/wiki/edit\.php$', 'Wiki: Seite speichern',
            parameter: (q) => _nurSchluessel(q, {'pageid', 'section', 'contentformat'}),
            formular: (f) => wertIn(f, 'newcontent_editor[text]') != null && _gesetzt(wertIn(f, 'editoption'))),
        Erlaubt('GET', r'^/mod/wiki/admin\.php$', 'Wiki: Seite löschen',
            parameter: (q) =>
                q.length == 5 &&
                _zahl(q['pageid']) &&
                _zahl(q['delete']) &&
                q['option'] == '1' &&
                q['listall'] == '1' &&
                _gesetzt(q['sesskey'])),
        Erlaubt('POST', r'^/mod/board/column_(create|update)_ajax\.php$', 'Board: Spalte anlegen oder umbenennen',
            parameter: (q) => q.length == 1 && (_zahl(q['boardid']) || _zahl(q['id']))),
        Erlaubt('POST', r'^/mod/board/note_(create|update)_ajax\.php$', 'Board: eigene Notiz anlegen oder ändern',
            parameter: (q) =>
                (q.length == 1 && _zahl(q['id'])) ||
                (q.length == 3 && _zahl(q['columnid']) && q['ownerid'] == '0' && _zahl(q['groupid']))),
        Erlaubt('POST', r'^/grade/grading/form/(rubric|guide)/edit\.php$', 'Bewertungsschema speichern (Definition)',
            parameter: (q) => _nurSchluessel(q, {'areaid'}),
            formular: (f) => _marke(f, RegExp(r'^_qf__gradingform_(rubric|guide)_')) && _zahl(wertIn(f, 'areaid'))),
        Erlaubt('POST', r'^/mod/book/edit\.php$', 'Buchkapitel speichern',
            parameter: (q) => q.isEmpty,
            formular: (f) => _zahl(wertIn(f, 'cmid')) && wertIn(f, '_qf__book_chapter_edit_form') != null),
        Erlaubt('GET', r'^/mod/book/delete\.php$', 'Buchkapitel löschen',
            parameter: (q) =>
                q.length == 4 && _zahl(q['id']) && _zahl(q['chapterid']) && q['confirm'] == '1' && _gesetzt(q['sesskey'])),
        Erlaubt('GET', r'^/mod/book/move\.php$', 'Buchkapitel einen Schritt verschieben',
            parameter: (q) =>
                q.length == 4 &&
                _zahl(q['id']) &&
                _zahl(q['chapterid']) &&
                (q['up'] == '0' || q['up'] == '1') &&
                _gesetzt(q['sesskey'])),
        // Upload einer Datei in den Entwurfsbereich. Eine .mbz-Datei geht nur über
        // die Regel darunter (wiederherstellung_regeln.dart prüft das Archiv vorher).
        Erlaubt('POST', r'^/repository/repository_ajax\.php$', 'Datei in den Entwurfsbereich',
            parameter: (q) => q.length == 1 && q['action'] == 'upload',
            anhang: (a) => !a.dateiname.toLowerCase().endsWith('.mbz')),
        Erlaubt('POST', r'^/repository/repository_ajax\.php$', 'Sicherungsdatei (.mbz) in den Entwurfsbereich',
            parameter: (q) => q.length == 1 && q['action'] == 'upload',
            formular: (f) => _zahl(wertIn(f, 'itemid')) && _gesetzt(wertIn(f, 'sesskey')),
            // UNGEMESSEN: der MIME-Typ, den Moodle für .mbz erwartet (TODO.md).
            anhang: (a) =>
                a.feld == 'repo_upload_file' &&
                RegExp(r'^[A-Za-z0-9_.-]{1,120}\.mbz$').hasMatch(a.dateiname) &&
                (a.mime == 'application/octet-stream' || a.mime == 'application/vnd.moodle.backup')),
        // Wiederherstellen (wiederherstellung.dart): die gemessenen Schritte.
        Erlaubt('GET', r'^/course/view\.php$', 'Kurs ansehen (Gegenlesen, Kontext; UNGEMESSEN)',
            parameter: (q) => _nurSchluessel(q, {'id'}) && _zahl(q['id'])),
        // Nur diese Felder: Marke, Sitzung, Draft-Itemid und ggf. der Absendeknopf und die Kurs-ID.
        // Jedes andere Feld lehnt die Regel ab (UNGEMESSEN: Feldnamen, TODO.md).
        Erlaubt('POST', r'^/backup/restorefile\.php$', 'Wiederherstellen: Datei hochladen (Formular)',
            parameter: (q) => _nurSchluessel(q, {'contextid'}) && (q['contextid'] == null || _zahl(q['contextid'])),
            formular: (f) =>
                f.every((e) => const {'contextid', 'sesskey', '_qf__course_restore_form', 'backupfile', 'submitbutton'}
                    .contains(e.key)) &&
                _marke(f, RegExp(r'^_qf__course_restore_form$')) &&
                _gesetzt(wertIn(f, 'sesskey')) &&
                _zahl(wertIn(f, 'backupfile')) &&
                (wertIn(f, 'contextid') == null || _zahl(wertIn(f, 'contextid')))),
        Erlaubt('GET', r'^/backup/restore\.php$', 'Wiederherstellen: Seite des Assistenten',
            parameter: (q) =>
                _nurSchluessel(q, {'contextid', 'filename'}) &&
                _zahl(q['contextid']) &&
                RegExp(r'^[A-Za-z0-9_.-]{1,200}$').hasMatch(q['filename'] ?? '')),
        // Weiterleitung nach dem Hochladen (UNGEMESSEN): Moodle nennt die Datei über ihren Dateiablagen-Hash.
        Erlaubt('GET', r'^/backup/restore\.php$', 'Wiederherstellen: Weiterleitung nach dem Hochladen (UNGEMESSEN)',
            parameter: (q) =>
                _nurSchluessel(q, {'contextid', 'pathnamehash', 'component', 'filearea'}) &&
                _zahl(q['contextid']) &&
                RegExp(r'^[a-f0-9]{40}$').hasMatch(q['pathnamehash'] ?? '') &&
                RegExp(r'^[a-z_]{1,50}$').hasMatch(q['component'] ?? 'backup') &&
                RegExp(r'^[a-z_]{1,50}$').hasMatch(q['filearea'] ?? 'draft')),
        // Sicherungsdetails (gemessen, Spike): das Weiter-Formular trägt nur diese Felder und stage=2.
        Erlaubt('POST', r'^/backup/restore\.php$', 'Wiederherstellen: Sicherungsdetails bestätigen',
            parameter: (q) => _nurSchluessel(q, {'contextid', 'filename'}),
            formular: (f) =>
                f.every((e) => const {'contextid', 'filepath', 'filename', 'stage', 'sesskey'}.contains(e.key)) &&
                wertIn(f, 'stage') == '2' &&
                _gesetzt(wertIn(f, 'sesskey'))),
        // Zielwahl je Zielweg (Issue #9): jeder Weg hat eine eigene, enge Schlüsselmenge.
        // Der Wert target ist der gemessene Moodle-Wert des Weges; ein anderer wird abgelehnt.
        // Kein _qf__-Feld auf dieser Seite (gemessen). Die Felder search (Kurssuche) und
        // catsearch (Kategoriesuche) gehören je nur zu den Wegen, die sie brauchen.
        for (final ziel in Zielweg.values)
          Erlaubt('POST', r'^/backup/restore\.php$', 'Wiederherstellen: Ziel „${ziel.nennung}" (Formular mit stage=2 oder 4)',
              parameter: (q) => _nurSchluessel(q, {'contextid', 'filename'}),
              formular: (f) {
                final erlaubt = {
                  'contextid', 'filepath', 'filename', 'stage', 'sesskey', 'target', 'targetid',
                  if (ziel == Zielweg.neuerKurs) 'catsearch',
                  if (ziel == Zielweg.anderKursVerschmelzen || ziel == Zielweg.anderKursErsetzen) 'search',
                };
                return const {'2', '4'}.contains(wertIn(f, 'stage')) &&
                    wertIn(f, 'target') == '${ziel.moodle}' &&
                    _zahl(wertIn(f, 'targetid')) &&
                    _gesetzt(wertIn(f, 'sesskey')) &&
                    f.every((e) => erlaubt.contains(e.key));
              }),
        // Kursformular (nur für die Kategorie eines neuen Kurses): ohne Angabe oder mit category.
        Erlaubt('GET', r'^/course/edit\.php$', 'Kursformular lesen (Kategorie des neuen Kurses)',
            parameter: (q) => _nurSchluessel(q, {'category'}) && (q['category'] == null || _zahl(q['category']))),
        // Kursverwaltung der Kategorie (Kontext der Kategorie; UNGEMESSEN).
        Erlaubt('GET', r'^/course/management\.php$', 'Kategorie ansehen (Kontext; UNGEMESSEN)',
            parameter: (q) => _nurSchluessel(q, {'categoryid'}) && _zahl(q['categoryid'])),
        // Einstellungen, Schema und Prüfung: ohne Nutzerdaten, mit dem Schalter „restore".
        for (final (schritt, form) in const [
          ('4', 'settings'),
          ('8', 'schema'),
          ('16', 'review'),
        ])
          Erlaubt('POST', r'^/backup/restore\.php$', 'Wiederherstellen: Schritt $schritt ($form)',
              parameter: (q) => _nurSchluessel(q, {'contextid', 'filename'}),
              formular: (f) =>
                  wertIn(f, 'stage') == schritt &&
                  _marke(f, RegExp('^_qf__restore_${form}_form\$')) &&
                  wertIn(f, 'restore') != null &&
                  _gesetzt(wertIn(f, 'sesskey')) &&
                  ohneNutzerdaten(f)),
        Erlaubt('POST', r'^/repository/draftfiles_ajax\.php$', 'Unterordner eines Dateibereichs lesen',
            parameter: (q) => q.length == 1 && q['action'] == 'list',
            formular: (f) =>
                f.length == 4 &&
                _zahl(wertIn(f, 'itemid')) &&
                (wertIn(f, 'filepath') ?? '').startsWith('/') &&
                wertIn(f, 'client_id') != null &&
                (wertIn(f, 'sesskey') ?? '').isNotEmpty),
        Erlaubt('POST', r'^/repository/draftfiles_ajax\.php$', 'Datei im Entwurfsbereich ersetzen',
            parameter: (q) => q.length == 1 && q['action'] == 'delete',
            formular: (f) =>
                _zahl(wertIn(f, 'itemid')) &&
                (wertIn(f, 'filename') ?? '').isNotEmpty &&
                (wertIn(f, 'sesskey') ?? '').isNotEmpty),
      ];

  /// Prüft eine Anfrage gegen die Positivliste, ohne sie zu senden.
  bool erlaubt(String methode, Uri uri, [Felder? formular, String? rumpf, Anhang? anhang]) {
    for (final e in positivliste) {
      if (e.methode != methode || !RegExp(e.pfad).hasMatch(uri.path)) continue;
      if (e.parameter != null && !e.parameter!(uri.queryParameters)) continue;
      if (e.formular != null && (formular == null || !e.formular!(formular))) continue;
      if ((e.anhang == null) != (anhang == null)) continue;
      if (e.anhang != null && !e.anhang!(anhang!)) continue;
      if ((e.inhalt == null) != (rumpf == null)) continue;
      if (e.inhalt != null && !e.inhalt!(uri.queryParameters, rumpf!)) continue;
      return true;
    }
    return false;
  }

  Uri? _basis;
  String? _benutzer;
  String? _passwort;
  final Map<String, String> _cookies = {};
  bool _angemeldet = false;
  Completer<void>? _anmeldungLaeuft;

  /// Nur gesetzt von [fuerTest]: Die Instanz ist eine lokale Testadresse mit
  /// http. Sonst gilt überall https.
  bool _testInstanz = false;

  /// Ein Zugang gegen eine lokale Testinstanz (Test-Doppel auf 127.0.0.1), mit
  /// derselben Anmeldung wie [anmelden], aber ohne die https-Pflicht. Der
  /// einzige Weg, http zu erlauben; die Positivliste lässt http nur für genau
  /// diese Adresse und diesen Port zu ([_schemeErlaubt]).
  ///
  /// Im Release-Bau wirft die Methode, bevor etwas geschieht.
  @visibleForTesting
  static Future<MoodleZugang> fuerTest(
    Protokoll protokoll,
    Uri basis, {
    required String benutzer,
    required String passwort,
  }) async {
    if (!kDebugMode) throw StateError('Testzugang nur im Testbau verfügbar.');
    if (basis.scheme != 'http' || basis.host != '127.0.0.1') {
      throw ArgumentError('Testzugang nur über http://127.0.0.1.');
    }
    final z = MoodleZugang(protokoll);
    z._testInstanz = true;
    z._basis = basis;
    z._benutzer = benutzer;
    z._passwort = passwort;
    await z._anmelden();
    return z;
  }

  /// Der sesskey der Sitzung, mitgelesen aus jeder HTML-Antwort (M.cfg).
  String? _sesskey;

  bool get angemeldet => _angemeldet;
  Uri? get basis => _basis;

  /// Ob die Instanz die Druckaufbereitung „Aufgabenblatt-Druck" hat, gesehen
  /// auf der Anmeldeseite ([druckaufbereitungErkannt]).
  bool get druckaufbereitung => _druckaufbereitung;
  bool _druckaufbereitung = false;

  /// Pfad des Theme-Stylesheets (/theme/styles.php/…), gesehen auf der
  /// Anmeldeseite ([themeStylesheetIn]); interaktive Elemente binden es ein
  /// (elemente.dart). null: keins gefunden.
  String? get themeStylesheet => _themeStylesheet;
  String? _themeStylesheet;

  // ---------------------------------------------------------------------
  // Anmelden und Abmelden
  // ---------------------------------------------------------------------

  Future<void> anmelden(String adresse, String benutzer, String passwort) async {
    final b = Uri.parse(adresse.trim());
    if (b.scheme != 'https' || b.host.isEmpty) {
      throw MoodleFehler('Die Moodle-Adresse muss mit https:// beginnen.');
    }
    // Ohne Angaben gar nicht erst fragen: Jeder Fehlversuch zählt bei Moodle
    // gegen die Kontosperre -- und eine bestehende Sitzung ginge verloren.
    if (benutzer.trim().isEmpty || passwort.isEmpty) {
      throw MoodleFehler('Benutzername und Passwort eingeben.');
    }
    _basis = Uri(scheme: b.scheme, host: b.host, port: b.hasPort ? b.port : null);
    _benutzer = benutzer.trim();
    _passwort = passwort;
    try {
      await _anmelden();
    } catch (_) {
      abmelden(stillschweigend: true);
      rethrow;
    }
  }

  /// Verwirft Sitzung und Zugangsdaten.
  void abmelden({bool stillschweigend = false}) {
    _cookies.clear();
    _sesskey = null;
    _eigeneId = null;
    selbstAngelegt.clear();
    _benutzer = null;
    _passwort = null;
    _angemeldet = false;
    _druckaufbereitung = false;
    _themeStylesheet = null;
    if (!stillschweigend) protokoll.eintrag(Art.anmeldung, 'Abgemeldet, Zugangsdaten verworfen');
  }

  /// Nur zum Testen der Neuanmeldung: vergisst die Sitzung, behält aber die
  /// Zugangsdaten. Die nächste Anfrage landet auf der Anmeldeseite.
  void sitzungVerwerfen() {
    _cookies.clear();
    _sesskey = null;
    protokoll.eintrag(Art.anmeldung, 'Sitzung verworfen (Test) -- nächste Anfrage meldet neu an');
  }

  Future<void> _anmelden() async {
    if (_benutzer == null || _passwort == null) {
      throw MoodleFehler('Nicht angemeldet. Bitte in der App anmelden.');
    }
    _cookies.clear();
    _sesskey = null;
    _angemeldet = false;

    // 1. Anmeldeseite: setzt das Sitzungs-Cookie und liefert den logintoken.
    final seite = await _roh('GET', _adresse('/login/index.php'));
    final doc = html_parser.parse(seite.text);
    final token = doc.querySelector('input[name="logintoken"]')?.attributes['value'];
    if (token == null) {
      throw MoodleFehler('Auf der Anmeldeseite fehlt das Anmeldeformular.');
    }
    // Die Anmeldeseite ist die einzige ganze Seite, die hier ohnehin geladen
    // wird; nachzusehen kostet keine weitere Anfrage.
    final druck = druckaufbereitungErkannt(seite.text);
    final stylesheet = themeStylesheetIn(doc);

    // 2. Formular senden. Moodle antwortet bei Erfolg mit einer Umleitung auf
    //    /login/index.php?testsession=…, bei Misserfolg wieder auf die
    //    Anmeldeseite ohne testsession.
    final formular = [
      MapEntry('username', _benutzer!),
      MapEntry('password', _passwort!),
      MapEntry('logintoken', token),
      const MapEntry('anchor', ''),
    ];
    Antwort r;
    try {
      r = await _roh('POST', _adresse('/login/index.php'), formular: formular);
    } on MoodleNichtErreichbar catch (e) {
      // Ob das Passwort angekommen und abgelehnt worden ist, weiß hier niemand:
      // zählt wie ein Fehlversuch, nicht wie „nicht erreichbar" (_neuAnmelden).
      throw MoodleFehler(e.meldung);
    }
    final ziel = _umleitung(r);
    if (ziel == null ||
        ziel.path != '/login/index.php' ||
        !ziel.queryParameters.containsKey('testsession')) {
      protokoll.eintrag(Art.anmeldung, 'Anmeldung fehlgeschlagen');
      throw MoodleFehler('Anmeldung fehlgeschlagen. Benutzername oder Passwort prüfen.');
    }

    // 3. testsession bestätigt, dass das Cookie ankommt; danach leitet Moodle
    //    auf die Startseite um. Der wird NICHT gefolgt -- das Dashboard
    //    enthält Daten, die hier niemand braucht.
    r = await _roh('GET', ziel);
    final weiter = _umleitung(r);
    if (weiter == null || weiter.path == '/login/index.php') {
      protokoll.eintrag(Art.anmeldung, 'Anmeldung fehlgeschlagen (Sitzung nicht bestätigt)');
      throw MoodleFehler('Anmeldung fehlgeschlagen: Moodle hat die Sitzung nicht bestätigt.');
    }
    _angemeldet = true;
    protokoll.eintrag(Art.anmeldung, 'Angemeldet bei ${_basis!.host}');
    if (druck != _druckaufbereitung || !_druckGemeldet) {
      protokoll.eintrag(
          Art.info,
          druck
              ? 'Druckaufbereitung „Aufgabenblatt-Druck" erkannt'
              : 'Keine Druckaufbereitung „Aufgabenblatt-Druck" auf dieser Instanz');
      _druckGemeldet = true;
    }
    _druckaufbereitung = druck;
    _themeStylesheet = stylesheet;
  }

  /// Nur einmal je Stand ins Protokoll, nicht bei jeder Neuanmeldung.
  bool _druckGemeldet = false;

  /// Genau eine Neuanmeldung, auch wenn mehrere Anfragen gleichzeitig
  /// merken, dass die Sitzung weg ist.
  Future<void> _neuAnmelden() async {
    final laufend = _anmeldungLaeuft;
    if (laufend != null) return laufend.future;
    final c = Completer<void>();
    _anmeldungLaeuft = c;
    try {
      protokoll.eintrag(Art.anmeldung, 'Sitzung abgelaufen -- melde neu an');
      await _anmelden();
      c.complete();
    } on MoodleNichtErreichbar catch (e) {
      // Das Passwort ist nicht gesendet (_anmelden): Die Zugangsdaten bleiben,
      // die App gilt weiter als angemeldet, und die nächste Anfrage meldet
      // neu an.
      _angemeldet = true;
      protokoll.eintrag(Art.anmeldung, 'Neuanmeldung: Moodle nicht erreichbar -- die nächste Anfrage versucht es wieder');
      c.completeError(e);
    } catch (e) {
      // Keine zweite Chance: Zugangsdaten verwerfen, damit kein Konto
      // durch wiederholte Fehlversuche gesperrt wird.
      abmelden(stillschweigend: true);
      protokoll.eintrag(Art.anmeldung, 'Neuanmeldung fehlgeschlagen -- Zugangsdaten verworfen');
      c.completeError(MoodleFehler(
          'Sitzung abgelaufen und Neuanmeldung fehlgeschlagen. Bitte in der App neu anmelden.'));
    } finally {
      _anmeldungLaeuft = null;
    }
    return c.future;
  }

  void _pruefeAngemeldet() {
    if (_basis == null || _passwort == null) {
      throw MoodleFehler('Nicht angemeldet. Bitte in der App anmelden.');
    }
  }

  // ---------------------------------------------------------------------
  // Lesen
  // ---------------------------------------------------------------------

  /// Liest eine Adresse mit der Sitzung. Landet die Anfrage auf der
  /// Anmeldeseite, wird einmal neu angemeldet und wiederholt.
  Future<Antwort> lesen(String pfadMitQuery) async {
    _pruefeAngemeldet();
    final uri = pfadMitQuery.startsWith('http') ? Uri.parse(pfadMitQuery) : _adresse(pfadMitQuery);
    var r = await _mitUmleitungen(uri);
    if (_istAnmeldeseite(r.adresse)) {
      await _neuAnmelden();
      r = await _mitUmleitungen(uri);
      if (_istAnmeldeseite(r.adresse)) {
        throw MoodleFehler('Nach der Neuanmeldung landet die Anfrage wieder auf der Anmeldeseite.');
      }
    }
    return r;
  }

  /// Der sesskey der Sitzung. Steht er noch nicht fest, liefert ihn die
  /// Anmeldeseite: Angemeldeten zeigt sie nur „Sie sind bereits angemeldet"
  /// -- ohne Blöcke, ohne Kursdaten.
  Future<String> sesskey() async {
    _pruefeAngemeldet();
    final bekannt = _sesskey;
    if (bekannt != null) return bekannt;
    for (var versuch = 0; versuch < 2; versuch++) {
      final r = await _roh('GET', _adresse('/login/index.php'));
      if (r.text.contains('name="logintoken"')) {
        // Nicht (mehr) angemeldet: Die Seite zeigt das Anmeldeformular.
        await _neuAnmelden();
        continue;
      }
      final s = _sesskey;
      if (s != null) return s;
      break;
    }
    throw MoodleFehler('Der sesskey der Sitzung ist nicht zu ermitteln.');
  }

  /// Liest die eigene Nutzer-ID aus M.cfg der Anmeldeseite nach.
  Future<void> eigeneIdErmitteln() async {
    _sesskey = null;
    await sesskey();
  }

  /// Ruft einen Moodle-AJAX-Dienst auf (lib/ajax/service.php) und gibt das
  /// Ergebnis zurück. Nur Dienste aus [dienste]. Bei abgelaufener Sitzung
  /// einmal neu anmelden und wiederholen.
  Future<Object?> dienst(String name, Map<String, Object?> args) async {
    for (var versuch = 0; versuch < 2; versuch++) {
      final key = await sesskey();
      final rumpf = jsonEncode([
        {'index': 0, 'methodname': name, 'args': args}
      ]);
      final r = await _roh('POST', _adresse('/lib/ajax/service.php?sesskey=$key&info=$name'),
          rumpf: rumpf);
      Object? j;
      try {
        j = jsonDecode(r.text);
      } catch (_) {
        throw MoodleFehler('$name: keine JSON-Antwort (HTTP ${r.status}).');
      }
      final fehler = j is List && j.isNotEmpty && j.first is Map && (j.first as Map)['error'] == true
          ? (j.first as Map)['exception'] as Map?
          : j is Map && j['error'] != null
              ? j
              : null;
      if (fehler == null && j is List && j.isNotEmpty) return (j.first as Map)['data'];
      final code = '${fehler?['errorcode'] ?? ''}';
      if (versuch == 0 &&
          const {'servicerequireslogin', 'requireloginerror', 'invalidsesskey'}.contains(code)) {
        _sesskey = null;
        await _neuAnmelden();
        continue;
      }
      throw MoodleFehler('$name abgelehnt: ${fehler?['message'] ?? r.text}');
    }
    throw MoodleFehler('$name: Sitzung nicht wiederherzustellen.');
  }

  // ---------------------------------------------------------------------
  // Schreiben
  // ---------------------------------------------------------------------

  /// Sendet ein Formular (application/x-www-form-urlencoded). Folgt keiner
  /// Umleitung -- die Antwort samt Location-Kopf geht an den Aufrufer.
  /// Landet es auf der Anmeldeseite: neu anmelden und SitzungAbgelaufen
  /// werfen; der Aufrufer baut den Vorgang neu auf.
  Future<Antwort> senden(String pfad, Felder formular) async {
    _pruefeAngemeldet();
    final r = await _roh('POST', _adresse(pfad), formular: formular);
    await _pruefeSitzungNachSchreiben(r);
    return r;
  }

  /// Ruft eine Adresse per GET auf, ohne Umleitungen zu folgen: für Aktionen,
  /// die Moodle als Link mit sesskey anbietet und nach denen es auf eine
  /// Ansichtsseite umleitet (etwa Buchkapitel löschen). Der Umleitung zu
  /// folgen hieße, eine Seite abzurufen, die niemand braucht.
  Future<Antwort> aufrufen(String pfadMitQuery) async {
    _pruefeAngemeldet();
    final r = await _roh('GET', _adresse(pfadMitQuery));
    await _pruefeSitzungNachSchreiben(r);
    return r;
  }

  /// Lädt eine Datei hoch (multipart/form-data).
  Future<Antwort> hochladen(String pfadMitQuery, Felder felder, Anhang datei) async {
    _pruefeAngemeldet();
    final r = await _roh('POST', _adresse(pfadMitQuery), formular: felder, anhang: datei);
    await _pruefeSitzungNachSchreiben(r);
    return r;
  }

  /// Lädt eine Sicherungsdatei (Pfad mit `?forcedownload=1`) als Stream nach
  /// [ziel]. Geschrieben wird zuerst nach `<ziel>.teil`; erst wenn die Größe
  /// mit der angekündigten übereinstimmt, wird umbenannt. Bei jedem Fehler
  /// verschwindet der Teil. Eine vorhandene Datei wird nie überschrieben.
  /// Gibt die Zahl der Bytes zurück.
  Future<int> herunterladen(String pfadMitQuery, File ziel) async {
    _pruefeAngemeldet();
    final uri = _adresse(pfadMitQuery);
    _pruefePositivliste('GET', uri, null, null);
    if (await ziel.exists()) throw MoodleFehler('Zieldatei existiert schon; nichts überschrieben.');
    final teil = File('${ziel.path}.teil');
    final client = HttpClient()
      ..userAgent = 'moocp (lokal)'
      ..connectionTimeout = verbindungsgrenze;
    IOSink? senke;
    var fertig = false;
    try {
      final req = await client.getUrl(uri);
      req.followRedirects = false;
      _cookies.forEach((k, v) => req.cookies.add(Cookie(k, v)));
      final res = await req.close().timeout(antwortgrenze);
      protokoll.eintrag(Art.moodle, 'GET ${uri.path}${_querySicher(uri)} → ${res.statusCode}');
      if (res.statusCode != 200) throw MoodleFehler('Download abgelehnt (HTTP ${res.statusCode}).');
      if (res.headers.contentType?.mimeType == 'text/html') {
        throw MoodleFehler('Download liefert eine Seite statt einer Datei (Anmeldung abgelaufen?).');
      }
      final erwartet = res.contentLength;
      if (erwartet < 0) {
        // Ohne angekündigte Größe gibt es keine Prüfung; dann wird nichts übernommen.
        throw MoodleFehler('Moodle nennt die Größe der Datei nicht; nicht übernommen.');
      }
      senke = teil.openWrite();
      var gelesen = 0;
      await for (final d in res.timeout(antwortgrenze)) {
        gelesen += d.length;
        senke.add(d);
      }
      final s = senke;
      senke = null;
      await s.close();
      if (gelesen != erwartet) {
        throw MoodleFehler('Die Datei ist unvollständig ($gelesen von $erwartet Bytes).');
      }
      await teil.rename(ziel.path);
      fertig = true;
      return gelesen;
    } on SocketException catch (e) {
      protokoll.eintrag(Art.fehler, 'GET ${uri.path}: nicht erreichbar');
      throw MoodleNichtErreichbar('Moodle nicht erreichbar: ${e.message}');
    } on TimeoutException {
      protokoll.eintrag(Art.fehler, 'GET ${uri.path}: keine Antwort innerhalb der Zeitgrenze');
      throw MoodleNichtErreichbar('Moodle antwortet nicht (${uri.path}). Später noch einmal versuchen.');
    } on IOException catch (e) {
      protokoll.eintrag(Art.fehler, 'GET ${uri.path}: Verbindung abgebrochen (${e.runtimeType})');
      throw MoodleNichtErreichbar('Verbindung zu Moodle abgebrochen (${e.runtimeType}). Später noch einmal versuchen.');
    } finally {
      client.close(force: true);
      try {
        await senke?.close();
      } catch (_) {}
      if (!fertig && await teil.exists()) await teil.delete();
    }
  }

  Future<void> _pruefeSitzungNachSchreiben(Antwort r) async {
    final ziel = _umleitung(r);
    final json = (r.inhaltstyp ?? '').contains('json') ? r.text : '';
    if ((ziel != null && _istAnmeldeseite(ziel)) ||
        json.contains('requireloginerror') ||
        json.contains('invalidsesskey')) {
      await _neuAnmelden();
      throw SitzungAbgelaufen();
    }
  }

  bool _istAnmeldeseite(Uri u) => u.path == '/login/index.php';

  Future<Antwort> _mitUmleitungen(Uri start) async {
    var uri = start;
    for (var i = 0; i < 8; i++) {
      final r = await _roh('GET', uri);
      final ziel = _umleitung(r);
      if (ziel == null) return r;
      // Umleitung auf die Anmeldeseite: nicht folgen, Aufrufer entscheidet.
      if (_istAnmeldeseite(ziel)) return Antwort(r.status, ziel, Uint8List(0), null);
      uri = ziel;
    }
    throw MoodleFehler('Zu viele Umleitungen ab ${start.path}');
  }

  Uri? umleitungsziel(Antwort r) => _umleitung(r);

  Uri? _umleitung(Antwort r) {
    if (r.status < 300 || r.status >= 400) return null;
    final ort = r.ort;
    if (ort == null) return null;
    return r.adresse.resolve(ort);
  }

  Uri _adresse(String pfadMitQuery) => _basis!.resolve(pfadMitQuery);

  // ---------------------------------------------------------------------
  // Eine einzelne Anfrage -- hier sitzt die Positivliste
  // ---------------------------------------------------------------------

  /// https ist Pflicht. Ausnahme nur die Testinstanz ([fuerTest]) auf ihrer
  /// eigenen Adresse und ihrem eigenen Port.
  bool _schemeErlaubt(Uri uri) =>
      uri.scheme == 'https' ||
      (_testInstanz && _basis!.scheme == 'http' && uri.scheme == 'http' && uri.port == _basis!.port);

  void _pruefePositivliste(String methode, Uri uri, Felder? formular, String? rumpf, [Anhang? anhang]) {
    if (_basis == null || uri.host != _basis!.host || !_schemeErlaubt(uri)) {
      throw MoodleFehler('Gesperrt: fremder Rechner oder kein https (${uri.host}).');
    }
    final regel = sperrregel(uri);
    if (regel != null) {
      // Parameterwerte gehören nicht ins Protokoll: studentid=45 wäre genau
      // das Datum, um das es geht.
      protokoll.eintrag(Art.gesperrt, 'Datenschutz-Sperre: $methode ${adresseOhneWerte(uri)} (Regel $regel)');
      throw MoodleFehler(
          'Gesperrt (Datenschutz): ${uri.path} zeigt personenbezogene Daten -- Bewertungen, '
          'Abgaben, Versuche, Profile oder Protokolle. Die App liest sie grundsätzlich nicht. '
          'Dem Nutzer sagen, dass dieser Teil der Aufgabe offen bleibt, oder -- falls die '
          'Adresse harmlos ist -- dass die Sperre zu weit ist (Regel $regel).');
    }
    if (erlaubt(methode, uri, formular, rumpf, anhang)) return;
    // Zur Fehlersuche die NAMEN der Parameter und Felder, nie ihre Werte.
    protokoll.eintrag(
        Art.gesperrt,
        'Gesperrt: $methode ${adresseOhneWerte(uri)}'
        '${formular == null ? '' : ' (Felder: ${formular.map((e) => e.key).toSet().join(', ')})'}');
    throw MoodleFehler(
        'Gesperrt: $methode ${uri.path} steht nicht auf der Positivliste dieses Servers '
        '(oder die Werte passen nicht zu dem, was dort erlaubt ist).');
  }

  /// Eine Anfrage des Browsers für ein Bildschirmfoto (bildschirmfoto.dart):
  /// geprüft gegen die Liste für Bildschirmfotos (browserliste.dart) statt
  /// gegen die Positivliste, gestellt mit der Sitzung der App -- das Cookie
  /// verlässt die App nicht. Umleitungen gehen an den Browser zurück; er
  /// folgt ihnen mit einer neuen Anfrage, die wieder hier geprüft wird.
  Future<Antwort> fuerBrowser(String methode, Uri uri,
      {required Set<String> seiten, String? rumpf, bool dokument = false}) {
    _pruefeAngemeldet();
    final (weg, grund) =
        browserPruefen(methode, uri, basis: _basis!, seiten: seiten, dokument: dokument, rumpf: rumpf);
    if (weg != BrowserWeg.ueberApp) {
      protokoll.eintrag(Art.gesperrt, 'Browser gesperrt: $methode ${adresseOhneWerte(uri)} ($grund)');
      throw MoodleFehler('Gesperrt: $methode ${uri.path} ($grund).');
    }
    return _roh(methode, uri, rumpf: rumpf, browser: true);
  }

  Future<Antwort> _roh(String methode, Uri uri,
      {Felder? formular, Anhang? anhang, String? rumpf, bool browser = false}) async {
    // Anfragen des Browsers sind in fuerBrowser geprüft, gegen ihre eigene
    // Liste; die Sperrliste gilt dort zuerst wie hier.
    if (!browser) _pruefePositivliste(methode, uri, formular, rumpf, anhang);
    final client = HttpClient()
      ..userAgent = 'moocp (lokal)'
      ..connectionTimeout = verbindungsgrenze;
    try {
      final req = await client.openUrl(methode, uri);
      req.followRedirects = false;
      _cookies.forEach((k, v) => req.cookies.add(Cookie(k, v)));
      if (anhang != null) {
        final grenze = 'moocp${Random.secure().nextInt(1 << 32).toRadixString(16)}';
        req.headers.contentType = ContentType('multipart', 'form-data', parameters: {'boundary': grenze});
        final b = BytesBuilder();
        void zeile(String s) => b.add(utf8.encode('$s\r\n'));
        for (final e in formular ?? const <MapEntry<String, String>>[]) {
          zeile('--$grenze');
          zeile('Content-Disposition: form-data; name="${e.key}"');
          zeile('');
          zeile(e.value);
        }
        zeile('--$grenze');
        zeile('Content-Disposition: form-data; name="${anhang.feld}"; '
            'filename="${anhang.dateiname.replaceAll('"', '')}"');
        zeile('Content-Type: ${anhang.mime}');
        zeile('');
        b.add(anhang.bytes);
        zeile('');
        zeile('--$grenze--');
        final body = b.takeBytes();
        req.contentLength = body.length;
        req.add(body);
      } else if (rumpf != null) {
        final body = utf8.encode(rumpf);
        req.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
        req.contentLength = body.length;
        req.add(body);
      } else if (formular != null) {
        final body = utf8.encode(formular
            .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
            .join('&'));
        req.headers.contentType =
            ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
        req.contentLength = body.length;
        req.add(body);
      }
      final res = await req.close().timeout(antwortgrenze);
      for (final c in res.cookies) {
        if (c.value.isEmpty || c.value == 'deleted') {
          _cookies.remove(c.name);
        } else {
          _cookies[c.name] = c.value;
        }
      }
      final bytes = await res
          .fold<BytesBuilder>(BytesBuilder(copy: false), (b, d) => b..add(d))
          .timeout(antwortgrenze);
      final a = Antwort(res.statusCode, uri, bytes.takeBytes(), res.headers.contentType?.mimeType,
          ort: res.headers.value(HttpHeaders.locationHeader));
      if (a.inhaltstyp == 'text/html' && _angemeldet) {
        final s = RegExp(r'"sesskey":"(\w+)"').firstMatch(a.text)?.group(1);
        if (s != null) _sesskey = s;
        final id = int.tryParse(RegExp(r'"userId":(\d+)').firstMatch(a.text)?.group(1) ?? '');
        if (id != null && id > 1) _eigeneId = id;
      }
      // Ins Protokoll: Methode, Pfad, Status. Keine Formularwerte, keine
      // Cookies, keine Parameterwerte der Anmeldung.
      // Lesende Dienstaufrufe (JSON-Rumpf) sind zwar POST, schreiben aber
      // nichts; ein GET mit sesskey dagegen ist eine Aktion.
      final dienst = uri.queryParameters['info'];
      final schreibt = rumpf != null
          ? schreibendeDienste.contains(dienst)
          : methode != 'GET' || uri.queryParameters.containsKey('sesskey');
      protokoll.eintrag(schreibt ? Art.schreiben : Art.moodle,
          '${browser ? 'Browser: ' : ''}$methode ${uri.path}${_querySicher(uri)}'
          '${anhang != null ? " (${anhang.dateiname})" : ""}'
          ' → ${res.statusCode}');
      return a;
    } on SocketException catch (e) {
      protokoll.eintrag(Art.fehler, '$methode ${uri.path}: nicht erreichbar');
      throw MoodleNichtErreichbar('Moodle nicht erreichbar: ${e.message}');
    } on TimeoutException {
      protokoll.eintrag(Art.fehler, '$methode ${uri.path}: keine Antwort innerhalb der Zeitgrenze');
      throw MoodleNichtErreichbar('Moodle antwortet nicht (${uri.path}, Zeitgrenze '
          '${antwortgrenze.inSeconds} s). Später noch einmal versuchen.');
    } on IOException catch (e) {
      // Abbruch mitten in der Antwort (HttpException) oder TLS-Fehler
      // (HandshakeException): nur der Typ, der Text kann Adressen enthalten.
      protokoll.eintrag(Art.fehler, '$methode ${uri.path}: Verbindung abgebrochen (${e.runtimeType})');
      throw MoodleNichtErreichbar('Verbindung zu Moodle abgebrochen (${e.runtimeType}). Später noch einmal versuchen.');
    } finally {
      client.close(force: true);
    }
  }

  String _querySicher(Uri uri) {
    if (uri.query.isEmpty) return '';
    if (uri.path == '/login/index.php') return '?…';
    // Der sesskey ist ein Schlüssel der Sitzung: nicht ins Protokoll.
    return '?${uri.query.replaceAll(RegExp(r'sesskey=[^&]*'), 'sesskey=…')}';
  }
}
