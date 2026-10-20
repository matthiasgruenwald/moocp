// Ein Thema samt Lernlandkarte in mehrere Zielkurse verteilen.
// Hauptprüfgrenze ist der öffentliche MCP-Aufruf `uebertragen` mit allen echten
// internen Abläufen (Sichern, Prüfen, Wiederherstellen, Verbergen, Kartenerfassung,
// Neuverknüpfung, Rücklesen, Protokoll); nur Moodle ist ein lokaler HTTP-Server
// mit erfundenen Daten. Der Server kopiert wirklich: Jedes Ziel bekommt neue,
// fortlaufende Aktivitätsnummern, in jedem zweiten Ziel in umgekehrter Reihenfolge.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/einstellungen.dart';
import 'package:moocp/freigabe.dart';
import 'package:moocp/mcp/mcp_dienst.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/profil.dart';
import 'package:moocp/protokoll.dart';
import 'package:moocp/testzugang.dart';
import 'package:path/path.dart' as p;

import 'mcp_client.dart';

class _Akt {
  _Akt(
    this.cmid,
    this.kurs,
    this.abschnitt,
    this.modul,
    this.name, {
    this.sichtbar = true,
    this.placestore,
  });

  final int cmid;
  final int kurs;
  final int abschnitt;
  final String modul;
  final String name;
  bool sichtbar;
  String? placestore;
  String intro = '';
  String? html;
  String format = '1';
  bool backgroundImage = false;
  int? completionMinute;
  String? idnummer;
  String svgcode =
      '<svg><circle id="p1" cx="120"/><circle id="p2" cx="480"/><title id="titlep1">ZZ Karte</title><text id="textp1">ZZ Karte</text><title id="titlep2">ZZ Karte</title><text id="textp2">ZZ Karte</text></svg>';
}

const _sk = 'sk';
const _id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _Moodle {
  late HttpServer server;
  final akt = <_Akt>[];
  final kurse = <int, String>{
    12: 'ZZ Quelle',
    31: 'ZZ Ziel 1',
    32: 'ZZ Ziel 2',
    33: 'ZZ Ziel 3',
    34: 'ZZ Ziel 4',
    35: 'ZZ Ziel 5',
  };
  final abschnitte = <int, List<(int, String)>>{
    12: [(101, 'ZZ Thema'), (102, 'ZZ Rest')],
    for (final k in [31, 32, 33, 34, 35]) k: [(300 + k, 'ZZ Allgemein')],
  };
  int naechste = 1000;
  int restoreZiel = 0;
  bool nativeZielverweise = false;
  int erinnerungMinute = 23;
  bool erinnerungAktiv = false;
  String dateiInhalt = 'Eigene Dateiprobe';
  int backupStarts = 0;
  int backupVariation = 0;
  int restoreStarts = 0;
  bool duplikatNachRestore = false;
  bool duplikatErstellt = false;
  int kartenSpeicherungen = 0;
  bool restoreAntwortBlockieren = false;
  bool restoreBlockAufgebraucht = false;
  final restoreLaeuft = Completer<void>();
  final restoreFortsetzen = Completer<void>();
  void Function(_Akt)? kopieAendern;
  final startsJeZiel = <int, int>{};
  Set<int> gesichert = {};

  /// Ziele, deren Wiederherstellungsstart Moodle mit einem Serverfehler beantwortet.
  Set<int> serverFehlerBeiStart = {};

  /// Moodle schreibt beim Kopieren der Karte die Verweise nicht um (Annahme der App).
  Uri get basis => Uri.parse('http://127.0.0.1:${server.port}');

  _Akt neu(
    int kurs,
    int abschnitt,
    String modul,
    String name, {
    String? placestore,
    bool sichtbar = true,
  }) {
    final a = _Akt(
      naechste++,
      kurs,
      abschnitt,
      modul,
      name,
      placestore: placestore,
      sichtbar: sichtbar,
    );
    akt.add(a);
    return a;
  }

  /// Quellkurs 12: Thema (101) mit zwei Seiten und der Karte; Rest (102) mit einer Außenseite.
  /// Ziele 31–35 enthalten je eine gleich benannte Altseite, die kein Nachweis ist.
  late _Akt seiteA, seiteB, karte, karteB, aussen;
  void aufbauen({bool verweisAufAussen = false, bool doppelterTitel = false}) {
    akt.clear();
    naechste = 200;
    seiteA = neu(12, 101, 'page', 'ZZ Seite A');
    seiteA.idnummer = 'zz-seite-a';
    seiteB = neu(12, 101, 'page', 'ZZ Seite B');
    seiteB.idnummer = 'zz-seite-b';
    if (doppelterTitel) neu(12, 101, 'page', 'ZZ Seite A');
    aussen = neu(12, 102, 'page', 'ZZ Außen');
    karte = neu(12, 101, 'learningmap', 'ZZ Karte');
    karte.idnummer = 'zz-karte';
    karte.placestore = jsonEncode({
      'mapid': 'm1',
      'editmode': false,
      'hidepaths': true,
      'places': [
        {
          'id': 'p1',
          'linkId': 'a1',
          'linkedActivity': seiteA.cmid,
          'placecolor': null,
          'visitedcolor': null,
        },
        {
          'id': 'p2',
          'linkId': 'a2',
          'linkedActivity': seiteB.cmid,
          'placecolor': null,
          'visitedcolor': null,
        },
        {
          'id': 'p3',
          'linkId': 'a3',
          'linkedActivity': verweisAufAussen ? aussen.cmid : null,
          'placecolor': 'red',
          'visitedcolor': null,
        },
      ],
      'paths': [
        {'id': 'p1_2', 'from': 'p1', 'to': 'p2'},
      ],
      'startingplaces': ['p1'],
      'targetplaces': ['p3'],
    });
    karteB = neu(12, 101, 'learningmap', 'ZZ Karte B');
    karteB.idnummer = 'zz-karte-b';
    karteB.placestore = jsonEncode({
      'mapid': 'm2',
      'places': [
        {'id': 'p1', 'linkedActivity': seiteA.cmid},
      ],
      'paths': [],
    });
    naechste = 5000;
    for (final k in [31, 32, 33, 34, 35]) {
      neu(k, 300 + k, 'page', 'ZZ Seite A').idnummer = 'alt-seite-a-$k';
    }
    naechste = 1000;
  }

  String svgFuer(_Akt a) => a.svgcode;

  String seite(String body) =>
      '<script>M.cfg = {"sesskey":"$_sk","courseId":12,"contextid":"55"}; var repo={"id":4,"type":"upload"};</script>$body';
  String formular(
    Iterable<MapEntry<String, String>> felder, {
    String pfad = '/backup/restore.php',
  }) => seite(
    '<form class="mform" action="$pfad" method="post">${[const MapEntry('sesskey', _sk), ...felder].map((e) => '<input type="hidden" name="${e.key}" value="${const HtmlEscape().convert(e.value)}">').join()}</form>',
  );

  /// Liefert die Sicherung aus den beim letzten Backup gewählten Aktivitäten.
  List<int> archiv() {
    final a = Archive();
    final waehl = [
      for (final x in akt)
        if (gesichert.contains(x.cmid)) x,
    ];
    final eintraege = waehl
        .map(
          (x) =>
              '<activity><modulename>${x.modul}</modulename><title>${const HtmlEscape().convert(x.name)}</title>'
              '<directory>activities/${x.modul}_${x.cmid}</directory></activity>',
        )
        .join();
    a.addFile(
      ArchiveFile.bytes(
        'moodle_backup.xml',
        utf8.encode(
          '<moodle_backup><information><format>moodle2</format><type>course</type><variation>$backupVariation</variation></information>'
          '<activities>$eintraege</activities></moodle_backup>',
        ),
      ),
    );
    a.addFile(ArchiveFile.bytes('files.xml', utf8.encode('<files/>')));
    for (final x in waehl) {
      a.addFile(
        ArchiveFile.bytes(
          'activities/${x.modul}_${x.cmid}/inforef.xml',
          utf8.encode('<inforef/>'),
        ),
      );
    }
    return GZipEncoder().encodeBytes(TarEncoder().encodeBytes(a));
  }

  Object zustand(int kurs) => {
    'section': [
      for (final (id, titel) in abschnitte[kurs] ?? const <(int, String)>[])
        {
          'id': id,
          'number': (abschnitte[kurs]!.indexWhere((s) => s.$1 == id)) + 1,
          'title': titel,
          'visible': 1,
          'cmlist': [
            for (final x in akt)
              if (x.kurs == kurs && x.abschnitt == id) x.cmid,
          ],
        },
    ],
    'cm': [
      for (final x in akt)
        if (x.kurs == kurs)
          {
            'id': x.cmid,
            'module': x.modul,
            'name': x.name,
            'visible': x.sichtbar ? 1 : 0,
            'sectionid': x.abschnitt,
          },
    ],
  };

  int entwurf = 100;
  String formFuer(_Akt x) {
    entwurf++;
    if (x.modul == 'learningmap') {
      final dateiliste = x.backgroundImage
          ? '"list":[{"type":"file","filepath":"/","filename":"background.png","size":4,"datemodified":1,"url":"$basis/draftfile.php/55/user/draft/9/background.png"}]'
          : '"list":[]';
      return seite(
        '''<form class="mform" action="/course/modedit.php" method="post">
        <input name="_qf__mod_learningmap_mod_form" value="1"><input name="sesskey" value="$_sk">
        <input name="course" value="${x.kurs}"><input name="update" value="${x.cmid}">
        <input name="modulename" value="learningmap"><input name="name" value="${x.name}"><input name="cmidnumber" value="${x.idnummer ?? ''}">
        <select name="visible"><option value="0" ${x.sichtbar ? '' : 'selected'}>Verborgen</option><option value="1" ${x.sichtbar ? 'selected' : ''}>Sichtbar</option></select>
        <textarea name="introeditor[text]">${const HtmlEscape().convert(x.intro)}</textarea><input name="introeditor[itemid]" value="$entwurf">
        <input type="hidden" name="backgroundfile" value="${entwurf + 1000}">
        <textarea name="svgcode">${const HtmlEscape().convert(svgFuer(x))}</textarea>
        <input type="hidden" name="placestore" value='${const HtmlEscape().convert(x.placestore!)}'>
        <div class="fitem row" id="fitem_id_completionexpected"><div class="col-form-label">Erwarteter Abschluss</div><div class="felement" data-fieldtype="date_time_selector">
        <select name="completionexpected[year]"><option value="2026" selected>2026</option></select>
        <select name="completionexpected[month]"><option value="10" selected>10</option></select>
        <select name="completionexpected[day]"><option value="20" selected>20</option></select>
        <select name="completionexpected[hour]"><option value="12" selected>12</option></select>
        <select name="completionexpected[minute]"><option value="${x.completionMinute ?? erinnerungMinute}" selected>${x.completionMinute ?? erinnerungMinute}</option></select>
        <input type="hidden" name="completionexpected[enabled]" value="0"><input type="checkbox" name="completionexpected[enabled]" value="1" ${erinnerungAktiv ? 'checked' : ''}>
        </div></div>
        <input type="submit" name="submitbutton" value="Speichern"></form>''',
      ).replaceFirst(
        '</form>',
        '<script>M.form_filemanager.init(Y, {"target":"id_backgroundfile","itemid":$entwurf,"client_id":"c",$dateiliste});</script></form>',
      );
    }
    return seite(
      '''<form class="mform" action="/course/modedit.php" method="post">
        <input name="_qf__mod_page_mod_form" value="1"><input name="sesskey" value="$_sk"><input name="course" value="${x.kurs}">
        <input name="update" value="${x.cmid}"><input name="modulename" value="page"><input name="name" value="${x.name}">
        <input name="cmidnumber" value="${x.idnummer ?? ''}">
        <select name="visible"><option value="0" ${x.sichtbar ? '' : 'selected'}>Verborgen</option><option value="1" ${x.sichtbar ? 'selected' : ''}>Sichtbar</option></select>
        <textarea name="page[text]">${const HtmlEscape().convert(x.html ?? '<p>${x.name}</p>')}</textarea><input name="page[format]" value="${x.format}"><input name="page[itemid]" value="9">
        <div class="fitem row" id="fitem_id_completionexpected"><div class="col-form-label">Erwarteter Abschluss</div><div class="felement" data-fieldtype="date_time_selector">
        <select name="completionexpected[year]"><option value="2026" selected>2026</option></select>
        <select name="completionexpected[month]"><option value="10" selected>10</option></select>
        <select name="completionexpected[day]"><option value="20" selected>20</option></select>
        <select name="completionexpected[hour]"><option value="12" selected>12</option></select>
        <select name="completionexpected[minute]"><option value="$erinnerungMinute" selected>$erinnerungMinute</option></select>
        <input type="hidden" name="completionexpected[enabled]" value="0"><input type="checkbox" name="completionexpected[enabled]" value="1" ${erinnerungAktiv ? 'checked' : ''}>
        </div></div>
        <input type="submit" name="submitbutton" value="Speichern"></form>''',
    );
  }

  Future<void> starten() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final path = r.uri.path;
      final body = await const Utf8Decoder(allowMalformed: true).bind(r).join();
      String antwort;
      if (path == '/login/index.php') {
        if (r.method == 'POST' ||
            r.uri.queryParameters.containsKey('testsession')) {
          r.response.redirect(
            Uri.parse(
              r.method == 'POST' ? '/login/index.php?testsession=1' : '/my/',
            ),
            status: 303,
          );
          await r.response.close();
          return;
        }
        r.response.cookies.add(Cookie('MoodleSession', 'test'));
        antwort = r.cookies.isNotEmpty
            ? seite('Angemeldet')
            : '<form><input name="logintoken" value="tok"></form>';
      } else if (path == '/my/' || path == '/course/view.php') {
        antwort = seite('<p>ZZ Kurs</p>');
      } else if (path == '/lib/ajax/service.php') {
        final call = (jsonDecode(body) as List).single as Map;
        final args = (call['args'] as Map?) ?? const {};
        final dynamic data = switch (call['methodname']) {
          'core_course_get_enrolled_courses_by_timeline_classification' => {
            'courses': [
              for (final e in kurse.entries)
                {'id': e.key, 'fullname': e.value, 'shortname': 'ZZ${e.key}'},
            ],
          },
          'core_courseformat_get_state' => () {
            final kurs = (args['courseid'] as num).toInt();
            return zustand(kurs);
          }(),
          'core_courseformat_update_course' => () {
            if (args['action'] == 'cm_delete') {
              akt.removeWhere((x) => (args['ids'] as List).contains(x.cmid));
            }
            if (args['action'] == 'cm_hide') {
              for (final x in akt) {
                if ((args['ids'] as List).contains(x.cmid)) x.sichtbar = false;
              }
            }
            return <String, Object?>{};
          }(),
          'core_backup_get_async_backup_progress' => () async {
            if (restoreAntwortBlockieren &&
                !restoreBlockAufgebraucht &&
                restoreStarts > 0) {
              restoreBlockAufgebraucht = true;
              if (!restoreLaeuft.isCompleted) restoreLaeuft.complete();
              await restoreFortsetzen.future;
            }
            return [
              {'backupid': _id, 'progress': 1, 'status': 1000},
            ];
          }(),
          _ => throw StateError('Unerwarteter Dienst: ${call['methodname']}'),
        };
        final Object result = data is Future ? await data : data as Object;
        antwort = jsonEncode([
          {'error': false, 'data': result},
        ]);
      } else if (path == '/backup/backup.php') {
        if (r.method == 'GET') {
          antwort = formular([
            const MapEntry('stage', '1'),
            const MapEntry('_qf__backup_initial_form', '1'),
            const MapEntry('setting_root_users', '0'),
          ], pfad: path);
        } else {
          final f = Uri.splitQueryString(body);
          if (f['stage'] == '1') {
            antwort = formular([
              const MapEntry('stage', '2'),
              const MapEntry('_qf__backup_schema_form', '1'),
              const MapEntry('setting_root_users', '0'),
              for (final (id, _) in abschnitte[12]!) ...[
                MapEntry('setting_section_section_${id}_included', '1'),
                for (final x in akt)
                  if (x.kurs == 12 && x.abschnitt == id)
                    MapEntry(
                      'setting_activity_${x.modul}_${x.cmid}_included',
                      '1',
                    ),
              ],
            ], pfad: path);
          } else if (f['stage'] == '2') {
            antwort = formular([
              const MapEntry('stage', '4'),
              const MapEntry('_qf__backup_confirmation_form', '1'),
              const MapEntry('backup', _id),
              const MapEntry('setting_root_filename', 'download.mbz'),
              for (final e in f.entries)
                if (e.key.startsWith('setting_')) MapEntry(e.key, e.value),
            ], pfad: path);
          } else {
            backupStarts++;
            gesichert = {
              for (final e in f.entries)
                if (e.value == '1' &&
                    RegExp(r'^setting_activity_[a-z]+_(\d+)_included$')
                        .hasMatch(e.key))
                  int.parse(
                    RegExp(r'^setting_activity_[a-z]+_(\d+)_included$')
                        .firstMatch(e.key)!
                        .group(1)!,
                  ),
            };
            antwort = seite('Gestartet');
          }
        }
      } else if (path == '/backup/restorefile.php') {
        if (r.method == 'POST') {
          r.response.redirect(
            Uri.parse('/backup/restore.php?contextid=55&filename=abc'),
            status: 303,
          );
          await r.response.close();
          return;
        }
        antwort =
            '${formular([const MapEntry('_qf__course_restore_form', '1'), const MapEntry('backupfile', '9')], pfad: path)}'
            '<script>var repo = {"id":4,"type":"upload"};</script>'
            '<a href="/pluginfile.php/55/user/backup/1/download.mbz?forcedownload=1">download.mbz</a>';
      } else if (path == '/repository/repository_ajax.php') {
        final datei = RegExp(r'filename="([^"]+)"').firstMatch(body)!.group(1)!;
        antwort = jsonEncode({
          'url': '$basis/draftfile.php/55/user/draft/9/$datei',
        });
      } else if (path == '/pluginfile.php/55/user/backup/1/download.mbz') {
        final bytes = archiv();
        r.response.contentLength = bytes.length;
        r.response.add(bytes);
        await r.response.close();
        return;
      } else if (path == '/backup/restore.php') {
        if (r.method == 'GET') {
          antwort = formular([
            const MapEntry('contextid', '55'),
            const MapEntry('filename', 'abc'),
            const MapEntry('stage', '2'),
          ]);
        } else {
          final f = Uri.splitQueryString(body);
          if (f.containsKey('_qf__restore_review_form')) {
            if (serverFehlerBeiStart.contains(restoreZiel)) {
              r.response.statusCode = 500;
              await r.response.close();
              return;
            }
            restoreStarts++;
            startsJeZiel[restoreZiel] = (startsJeZiel[restoreZiel] ?? 0) + 1;
            _kopieren(restoreZiel);
            antwort = seite('Gestartet');
          } else if (f.containsKey('_qf__restore_schema_form')) {
            antwort = formular([
              const MapEntry('_qf__restore_review_form', '1'),
              const MapEntry('stage', '16'),
              const MapEntry('restore', _id),
            ]);
          } else if (f.containsKey('_qf__restore_settings_form')) {
            antwort = formular([
              const MapEntry('_qf__restore_schema_form', '1'),
              const MapEntry('stage', '8'),
              const MapEntry('restore', _id),
            ]);
          } else if (f.containsKey('target')) {
            restoreZiel = int.parse(f['targetid']!);
            antwort = formular([
              const MapEntry('_qf__restore_settings_form', '1'),
              const MapEntry('stage', '4'),
              const MapEntry('restore', _id),
            ]);
          } else {
            antwort = formular([
              const MapEntry('contextid', '55'),
              const MapEntry('filename', 'abc'),
              const MapEntry('stage', '4'),
              const MapEntry('target', '1'),
              const MapEntry('targetid', '0'),
            ]);
          }
        }
      } else if (path == '/draftfile.php/55/user/draft/9/zz-owned.txt') {
        r.response.headers.contentType = ContentType.text;
        r.response.write(dateiInhalt);
        await r.response.close();
        return;
      } else if (path == '/draftfile.php/55/user/draft/9/background.png') {
        r.response.headers.contentType = ContentType.binary;
        r.response.add([1, 2, 3, 4]);
        await r.response.close();
        return;
      } else if (path == '/repository/draftfiles_ajax.php') {
        antwort = jsonEncode({'list': []});
      } else if (path == '/course/modedit.php') {
        final ziel = int.tryParse(r.uri.queryParameters['update'] ?? '');
        if (r.method == 'POST') {
          final f = Uri.splitQueryString(body);
          final x = f['update'] == null
              ? neu(
                  int.parse(f['course']!),
                  101,
                  f['modulename']!,
                  f['name']!,
                  sichtbar: f['visible'] != '0',
                )
              : akt.firstWhere((a) => a.cmid == int.parse(f['update']!));
          if (x.modul == 'page') {
            x.html = f['page[text]'];
            x.format = f['page[format]'] ?? x.format;
          }
          x.intro = f['introeditor[text]'] ?? x.intro;
          if (x.modul == 'learningmap') {
            final vorherStore = x.placestore == null
                ? {'places': <Map<String, Object?>>[]}
                : jsonDecode(x.placestore!) as Map;
            final vorherLinks = {
              for (final ort in vorherStore['places'] as List)
                (ort as Map)['id']: (ort['linkedActivity'] as num?)?.toInt(),
            };
            x.placestore = f['placestore'];
            x.svgcode = f['svgcode']!;
            final karte = jsonDecode(x.placestore!) as Map;
            for (final ort in karte['places'] as List) {
              if (vorherLinks[ort['id']] ==
                  (ort['linkedActivity'] as num?)?.toInt()) {
                continue;
              }
              final cmid = (ort['linkedActivity'] as num?)?.toInt();
              if (cmid == null) continue;
              final ziel = akt.firstWhere((a) => a.cmid == cmid);
              final id = RegExp.escape('${ort['id']}');
              for (final tag in ['title', 'text']) {
                final beschriftung = RegExp(
                  '(<$tag id="$tag$id"[^>]*>)[^<]*(</$tag>)',
                );
                x.svgcode = x.svgcode.replaceAllMapped(
                  beschriftung,
                  (m) => '${m[1]}${ziel.name}${m[2]}',
                );
              }
            }
            kartenSpeicherungen++;
          }
          r.response.redirect(
            Uri.parse('/course/modedit.php?update=${x.cmid}'),
            status: 303,
          );
          await r.response.close();
          return;
        }
        if (r.uri.queryParameters['add'] != null) {
          final typ = r.uri.queryParameters['add']!;
          final neuForm = _Akt(
            0,
            int.parse(r.uri.queryParameters['course']!),
            101,
            typ,
            '',
            placestore: '{"mapid":"native-test","editmode":true,"places":[],"paths":[],"startingplaces":[],"targetplaces":[]}',
          );
          antwort = formFuer(neuForm).replaceAll(
            '<input name="update" value="0">',
            '<input name="section" value="${r.uri.queryParameters['section']}">',
          );
          if (typ == 'learningmap') {
            antwort = antwort.replaceFirst(
              '</form>',
              '<script>M.form_filemanager.init(Y, {"target":"id_backgroundfile","itemid":9});</script></form>',
            );
          }
          r.response.headers.contentType = ContentType.html;
          r.response.write(antwort);
          await r.response.close();
          return;
        }
        final x = akt.where((a) => a.cmid == ziel).firstOrNull;
        if (x == null) {
          r.response.statusCode = 404;
          await r.response.close();
          return;
        }
        if (duplikatNachRestore && !duplikatErstellt && restoreStarts > 0) {
          duplikatErstellt = true;
          neu(31, 331, 'page', 'ZZ Seite A')
            ..idnummer = seiteA.idnummer
            ..html = seiteA.html;
        }
        antwort = formFuer(x);
      } else {
        throw StateError('Unerwartete Adresse: $path');
      }
      r.response.headers.contentType = ContentType.html;
      r.response.write(antwort);
      await r.response.close();
    });
  }

  /// Moodle legt die gesicherten Aktivitäten im Zielkurs neu an: neue Nummern, Quellsichtbarkeit,
  /// die Karte mit unveränderten (veralteten) Verweisen. Jedes zweite Ziel in umgekehrter Reihenfolge.
  void _kopieren(int ziel) {
    var quelle = [
      for (final x in akt)
        if (gesichert.contains(x.cmid)) x,
    ];
    if (ziel.isOdd) quelle = quelle.reversed.toList();
    final kopien = <int, _Akt>{};
    for (final x in quelle) {
      final kopie = neu(
        ziel,
        300 + ziel,
        x.modul,
        x.name,
        sichtbar: x.sichtbar,
        placestore: x.placestore,
      );
      kopie.svgcode = x.svgcode;
      kopie.intro = x.intro;
      kopie.backgroundImage = x.backgroundImage;
      kopie.completionMinute = x.completionMinute;
      kopie.idnummer = x.idnummer;
      kopie.html = x.html;
      kopien[x.cmid] = kopie;
    }
    for (final kopie in kopien.values) {
      if (nativeZielverweise && kopie.placestore != null) {
        final store = jsonDecode(kopie.placestore!) as Map;
        for (final ort in (store['places'] as List).cast<Map>()) {
          final neu = kopien[ort['linkedActivity']];
          if (neu != null) ort['linkedActivity'] = neu.cmid;
        }
        kopie.placestore = jsonEncode(store);
      }
      kopieAendern?.call(kopie);
    }
  }
}

void main() {
  late _Moodle moodle;
  late Directory ordner;
  late McpDienst dienst;
  late McpTestClient client;
  late Freigaben freigaben;
  late Profil profil;
  late MoodleZugang zugang;
  final freigabeTitel = <String>[];
  final kartenAntworten = <bool>[];
  var kartenDialoge = 0;
  void Function()? beiKartenfreigabe;
  var kartenFreigabe = true;
  var normaleFreigabe = true;
  var testbindung = false;

  Future<void> dienstStarten() async {
    dienst = McpDienst(
      Einstellungen(schluessel: 'test', profile: [profil]),
      zugang,
      Protokoll(),
      freigaben,
      ordner.path,
      profil: profil,
      testzugang: testbindung
          ? Testzugang(
              kennung: profil.kennung,
              datei: 'unused.env',
              adresse: profil.adresse,
              kurse: {12, 31, 32, 33, 34, 35},
              bilder: true,
            )
          : null,
      sicherungsordner: ordner.path,
      uebertragungsprotokollPfad: p.join(ordner.path, 'uebertragungen.json'),
      antwortfrist: const Duration(seconds: 20),
    );
    await dienst.starten();
    client = McpTestClient(profil.port);
    await client.initialize();
  }

  setUp(() async {
    moodle = _Moodle()..aufbauen();
    await moodle.starten();
    ordner = Directory.systemTemp.createTempSync('verteilen-');
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    profil = Profil(
      kennung: 'stabil',
      name: 'Test',
      adresse: moodle.basis.toString(),
      port: port,
      mcpName: 'test',
    );
    // Mittlere Stufe: Übertragung, Sicherung, Wiederherstellung und jede Kartenänderung fragen.
    freigaben = Freigaben(Protokoll(), stufe: Bestaetigungen.mittel);
    freigabeTitel.clear();
    kartenAntworten.clear();
    kartenDialoge = 0;
    beiKartenfreigabe = null;
    kartenFreigabe = true;
    normaleFreigabe = true;
    testbindung = false;
    freigaben.addListener(() {
      final a = freigaben.aktuell;
      if (a == null || !a.offen) return;
      freigabeTitel.add(a.titel);
      final istKartenfreigabe = a.titel == 'Lernlandkarte ändern?';
      final ja =
          normaleFreigabe &&
          (!istKartenfreigabe ||
              (kartenDialoge < kartenAntworten.length
                  ? kartenAntworten[kartenDialoge]
                  : kartenFreigabe));
      if (istKartenfreigabe) {
        kartenDialoge++;
        beiKartenfreigabe?.call();
      }
      scheduleMicrotask(() => freigaben.entscheiden(ja));
    });
    zugang = await MoodleZugang.fuerTest(
      Protokoll(),
      moodle.basis,
      benutzer: 'e.mustermann',
      passwort: 'test',
    );
    await dienstStarten();
  });

  tearDown(() async {
    await dienst.stoppen();
    client.http.close(force: true);
    await moodle.server.close(force: true);
    ordner.deleteSync(recursive: true);
  });

  Map<String, Object?> auftrag({
    List<int> ziele = const [31, 32, 33, 34, 35],
  }) => {
    'sichtbarkeit': 'verborgen',
    'kurs': 12,
    'name_des_kurses': 'ZZ Quelle',
    'abschnitte': [
      {'id': 101, 'name': 'ZZ Thema'},
    ],
    'ziele': [
      for (final k in ziele)
        {
          'kurs': k,
          'name': moodle.kurse[k],
          'weg': 'aktueller_kurs_verschmelzen',
        },
    ],
  };

  Map<String, int?> links(_Akt karte) => {
    for (final o in (jsonDecode(karte.placestore!) as Map)['places'] as List)
      '${o['id']}': (o['linkedActivity'] as num?)?.toInt(),
  };
  _Akt inZiel(int kurs, String modul, String name, {bool neu = true}) =>
      moodle.akt.singleWhere(
        (a) =>
            a.kurs == kurs &&
            a.modul == modul &&
            a.name == name &&
            (neu ? a.cmid < 5000 : a.cmid >= 5000),
      );

  test('Zielkontext liest fachliche Belege und bestätigt einen Kandidaten auch bei keine', () async {
    freigaben.stufe = Bestaetigungen.keine;
    final vorher = moodle.karte.placestore;
    final text = await client.tool('lernlandkarte_zielkontext', {
      'cmid': moodle.karte.cmid,
      'ort': 'p1',
      'kandidaten': [moodle.seiteB.cmid],
    });
    final kontext = jsonDecode(text) as Map;
    expect(kontext['quelle']['cmid'], moodle.seiteA.cmid);
    expect(kontext['kandidaten'].single['name'], 'ZZ Seite B');
    expect(kontext['kandidaten'].single['inhalt'], contains('ZZ Seite B'));
    expect(moodle.karte.placestore, vorher);
    expect(kartenDialoge, 0);
    final ergebnis = await client.tool('lernlandkarte_verknuepfungen_setzen', {
      'cmid': moodle.karte.cmid,
      'name': moodle.karte.name,
      'kontext': kontext['kontext'],
      'begruendung': 'Die Seite führt das Thema weiter.',
      'zuordnungen': [
        {
          'ort': 'p1',
          'aktuell': moodle.seiteA.cmid,
          'ziel': moodle.seiteB.cmid,
        },
      ],
    });
    expect(ergebnis, contains('bestätigt'));
    expect(ergebnis, contains('verified: true'));
    expect(links(moodle.karte)['p1'], moodle.seiteB.cmid);
    expect(kartenDialoge, 1);
    expect(moodle.restoreStarts, 0);
  });

  test('auch eine direkte fachliche Zuordnung prüft den Zielinhalt nach der Entscheidung', () async {
    beiKartenfreigabe = () =>
        moodle.seiteB.html = '<p>Anderer Lerngegenstand</p>';
    final ergebnis = await client.tool('lernlandkarte_verknuepfungen_setzen', {
      'cmid': moodle.karte.cmid,
      'name': moodle.karte.name,
      'zuordnungen': [
        {
          'ort': 'p1',
          'aktuell': moodle.seiteA.cmid,
          'ziel': moodle.seiteB.cmid,
        },
      ],
    });
    expect(ergebnis, contains('Zielinhalt'));
    expect(moodle.kartenSpeicherungen, 0);
    expect(links(moodle.karte)['p1'], moodle.seiteA.cmid);
  });

  Future<Map> zielkontext({List<int>? kandidaten, int? quellkarte}) async =>
      jsonDecode(
        await client.tool('lernlandkarte_zielkontext', {
          'cmid': moodle.karte.cmid,
          'ort': 'p1',
          'kandidaten': ?kandidaten,
          'quellkarte': ?quellkarte,
        }),
      ) as Map;

  Future<String> kandidatSetzen(Map kontext, int ziel) =>
      client.tool('lernlandkarte_verknuepfungen_setzen', {
        'cmid': moodle.karte.cmid,
        'name': moodle.karte.name,
        'kontext': kontext['kontext'],
        'begruendung': 'Das gelesene Blatt behandelt denselben Lerngegenstand.',
        'zuordnungen': [
          {'ort': 'p1', 'aktuell': moodle.seiteA.cmid, 'ziel': ziel},
        ],
      });

  test('mehrere gleichnamige Kandidaten ändern ohne Entscheidung nichts und die Lehrkraft kann den zweiten wählen', () async {
    final zweiter = moodle.neu(12, 101, 'page', moodle.seiteB.name)
      ..html = '<p>Vertiefung zum Lerngegenstand</p>';
    final kontext = await zielkontext(
      kandidaten: [moodle.seiteB.cmid, zweiter.cmid],
    );
    expect((kontext['kandidaten'] as List).map((k) => k['cmid']), [
      moodle.seiteB.cmid,
      zweiter.cmid,
    ]);
    expect(moodle.kartenSpeicherungen, 0);
    expect(kartenDialoge, 0);
    final ergebnis = await kandidatSetzen(kontext, zweiter.cmid);
    expect(ergebnis, contains('verified: true'));
    expect(links(moodle.karte)['p1'], zweiter.cmid);
    expect(moodle.restoreStarts, 0);
  });

  test('Ablehnung bei keine lässt vorgeschlagenen Kandidaten offen und schreibt nichts', () async {
    freigaben.stufe = Bestaetigungen.keine;
    kartenFreigabe = false;
    final kontext = await zielkontext(kandidaten: [moodle.seiteB.cmid]);
    final ergebnis = await kandidatSetzen(kontext, moodle.seiteB.cmid);
    expect(ergebnis, contains('Zuordnung offen; verified: false'));
    expect(links(moodle.karte)['p1'], moodle.seiteA.cmid);
    expect(moodle.kartenSpeicherungen, 0);
    expect(kartenDialoge, 1);
  });

  test('kein passendes Ziel bleibt ohne Zusatzkopie offen und eine erfundene Nummer wird abgewiesen', () async {
    final kontext = await zielkontext(kandidaten: []);
    expect(kontext['kandidaten'], isEmpty);
    expect(kontext['status'], contains('kein passendes Ziel bleibt offen'));
    final ergebnis = await kandidatSetzen(kontext, 999999);
    expect(ergebnis, contains('nicht zum gelesenen Zielkontext'));
    expect(moodle.kartenSpeicherungen, 0);
    expect(moodle.restoreStarts, 0);
  });

  for (final zeitpunkt in ['vor', 'während']) {
    test(
      'veränderter Kandidateninhalt $zeitpunkt der Entscheidung verhindert Zuordnung',
      () async {
        final kontext = await zielkontext(kandidaten: [moodle.seiteB.cmid]);
        void aendern() => moodle.seiteB.html = '<p>Anderer Lerngegenstand</p>';
        if (zeitpunkt == 'vor') {
          aendern();
        } else {
          beiKartenfreigabe = aendern;
        }
        final ergebnis = await kandidatSetzen(kontext, moodle.seiteB.cmid);
        expect(ergebnis, contains('seit dem Vorschlag geändert'));
        expect(moodle.kartenSpeicherungen, 0);
        expect(links(moodle.karte)['p1'], moodle.seiteA.cmid);
      },
    );
  }

  test(
    'Quelländerung während der Entscheidung verhindert fachliche Zuordnung',
    () async {
      final kontext = await zielkontext(kandidaten: [moodle.seiteB.cmid]);
      beiKartenfreigabe = () => moodle.seiteA.html = '<p>Neue Quelle</p>';
      final ergebnis = await kandidatSetzen(kontext, moodle.seiteB.cmid);
      expect(ergebnis, contains('seit dem Vorschlag geändert'));
      expect(moodle.kartenSpeicherungen, 0);
    },
  );

  test('kursfremder Kandidat wird bereits beim Lesen zurückgewiesen', () async {
    final fremd = moodle.akt.firstWhere((a) => a.kurs == 31);
    final ergebnis = await client.tool('lernlandkarte_zielkontext', {
      'cmid': moodle.karte.cmid,
      'ort': 'p1',
      'kandidaten': [fremd.cmid],
    });
    expect(ergebnis, contains('keine Zielaktivität dieses Kurses'));
    expect(moodle.kartenSpeicherungen, 0);
  });

  test(
    'Profilwechsel während fachlicher Entscheidung schreibt nichts',
    () async {
      final kontext = await zielkontext(kandidaten: [moodle.seiteB.cmid]);
      beiKartenfreigabe = () => dienst.profil = Profil(
        kennung: 'fremd',
        name: 'Fremd',
        adresse: profil.adresse,
        port: profil.port,
        mcpName: 'fremd',
      );
      final ergebnis = await kandidatSetzen(kontext, moodle.seiteB.cmid);
      expect(ergebnis, contains('Profil oder Instanz'));
      expect(moodle.kartenSpeicherungen, 0);
    },
  );

  test('Neustart verwirft alte Kandidatenbelege', () async {
    final kontext = await zielkontext(kandidaten: [moodle.seiteB.cmid]);
    await dienst.stoppen();
    client.http.close(force: true);
    await dienstStarten();
    final ergebnis = await kandidatSetzen(kontext, moodle.seiteB.cmid);
    expect(ergebnis, contains('Zielkontext fehlt'));
    expect(moodle.kartenSpeicherungen, 0);
  });

  test('nicht mitkopiertes Quellziel wird über belegten Kontext auf vorhandenen Zielinhalt geklärt', () async {
    final kopiert = await client.tool('uebertragen', {
      'kurs': 12, 'name_des_kurses': 'ZZ Quelle',
      'aktivitaeten': [{'cmid': moodle.karte.cmid, 'name': moodle.karte.name}],
      'ziele': [{'kurs': 31, 'name': 'ZZ Ziel 1', 'weg': 'aktueller_kurs_verschmelzen'}],
    });
    expect(kopiert, contains('1 offen'));
    final karte = inZiel(31, 'learningmap', 'ZZ Karte');
    final kandidat = inZiel(31, 'page', 'ZZ Seite A', neu: false);
    final kontext = jsonDecode(await client.tool('lernlandkarte_zielkontext', {
      'cmid': karte.cmid, 'ort': 'p1', 'quellkarte': moodle.karte.cmid,
      'kandidaten': [kandidat.cmid],
    })) as Map;
    expect(kontext['quelle']['cmid'], moodle.seiteA.cmid);
    expect(kontext['karte']['kurs'], 31);
    final ergebnis = await client.tool('lernlandkarte_verknuepfungen_setzen', {
      'cmid': karte.cmid, 'name': karte.name, 'kontext': kontext['kontext'],
      'begruendung': 'Das vorhandene Blatt behandelt denselben Lerngegenstand.',
      'zuordnungen': [{'ort': 'p1', 'aktuell': moodle.seiteA.cmid, 'ziel': kandidat.cmid}],
    });
    expect(ergebnis, contains('bestätigt'));
    expect(ergebnis, contains('verified: true'));
    expect(ergebnis, contains('ungelöste andere Ziele'));
    expect(links(karte)['p1'], kandidat.cmid);
    expect(links(karte)['p2'], moodle.seiteB.cmid);
    expect(moodle.restoreStarts, 1, reason: 'kein zusätzlicher Kopierauftrag');
    expect(moodle.akt.where((a) => a.kurs == 31 && a.modul == 'page').length, 1);
  });

  test('inaktive Abschlusszeit mit neuem Minutenwert ändert keinen fachlichen Stand', () async {
    final kontext = await zielkontext(kandidaten: [moodle.seiteB.cmid]);
    beiKartenfreigabe = () => moodle.erinnerungMinute = 24;
    final ergebnis = await kandidatSetzen(kontext, moodle.seiteB.cmid);
    expect(ergebnis, contains('verified: true'), reason: ergebnis);
    expect(links(moodle.karte)['p1'], moodle.seiteB.cmid);
  });

  test('ein veränderter aktiver Abschlusstermin verhindert weiterhin die Zuordnung', () async {
    moodle.erinnerungAktiv = true;
    final kontext = await zielkontext(kandidaten: [moodle.seiteB.cmid]);
    beiKartenfreigabe = () => moodle.erinnerungMinute = 24;
    final ergebnis = await kandidatSetzen(kontext, moodle.seiteB.cmid);
    expect(ergebnis, contains('seit der Freigabe geändert'));
    expect(moodle.kartenSpeicherungen, 0);
    expect(links(moodle.karte)['p1'], moodle.seiteA.cmid);
  });

  test('Übertragung erhält standardmäßig sichtbare Karten und verborgene Blätter beim Neuverknüpfen', () async {
    moodle.seiteB.sichtbar = false;
    final args = auftrag(ziele: [31])..remove('sichtbarkeit');
    final ergebnis = await client.tool('uebertragen', args);
    final karte = inZiel(31, 'learningmap', 'ZZ Karte');
    expect(ergebnis, contains('1 verknüpft, 0 offen, 0 unklar'), reason: ergebnis);
    expect(karte.sichtbar, isTrue);
    expect(inZiel(31, 'page', 'ZZ Seite A').sichtbar, isTrue);
    expect(inZiel(31, 'page', 'ZZ Seite B').sichtbar, isFalse);
    expect(links(karte)['p1'], inZiel(31, 'page', 'ZZ Seite A').cmid);
    expect(links(karte)['p2'], inZiel(31, 'page', 'ZZ Seite B').cmid);
    expect(ergebnis, contains('Sichtbarkeit und Voraussetzungen nicht gegengeprüft'));
  });

  test('Thema samt Karte in fünf Zielkurse: jede Karte zeigt nur auf die Kopien ihres Zielkurses', () async {
    final ergebnis = await client.tool('uebertragen', auftrag());

    expect(ergebnis, contains('5 fertig'), reason: ergebnis);
    expect(
      ergebnis,
      contains('Lernlandkarten je Ziel: 5 verknüpft, 0 offen, 0 unklar'),
    );
    expect(moodle.backupStarts, 1);
    expect(moodle.startsJeZiel, {31: 1, 32: 1, 33: 1, 34: 1, 35: 1});
    final alleNeuen = <int>{};
    for (final k in [31, 32, 33, 34, 35]) {
      final a = inZiel(k, 'page', 'ZZ Seite A');
      final b = inZiel(k, 'page', 'ZZ Seite B');
      final karte = inZiel(k, 'learningmap', 'ZZ Karte');
      expect(links(karte), {
        'p1': a.cmid,
        'p2': b.cmid,
        'p3': null,
      }, reason: 'Ziel $k');
      // Die Altseite gleichen Titels im Ziel (cmid ab 5000) ist kein Nachweis.
      expect(links(karte)['p1'], lessThan(5000));
      expect(
        alleNeuen.add(a.cmid) && alleNeuen.add(b.cmid),
        isTrue,
        reason: 'Nummern sind je Ziel verschieden',
      );
      // Geometrie und übrige Einstellungen bleiben erhalten.
      final store = jsonDecode(karte.placestore!) as Map;
      expect(store['mapid'], 'm1');
      expect(store['hidepaths'], true);
      expect(store['paths'], [
        {'id': 'p1_2', 'from': 'p1', 'to': 'p2'},
      ]);
      expect(store['startingplaces'], ['p1']);
      expect(store['targetplaces'], ['p3']);
      expect((store['places'] as List)[2]['placecolor'], 'red');
      expect(
        moodle.svgFuer(karte),
        '<svg><circle id="p1" cx="120"/><circle id="p2" cx="480"/><title id="titlep1">ZZ Seite A</title><text id="textp1">ZZ Seite A</text><title id="titlep2">ZZ Seite B</title><text id="textp2">ZZ Seite B</text></svg>',
      );
      // Alles Kopierte bleibt verborgen; die Karte wird nie sichtbar.
      expect([a, b, karte].every((x) => !x.sichtbar), isTrue);
    }
    // Die Quelle ist unberührt.
    expect(links(moodle.karte), {
      'p1': moodle.seiteA.cmid,
      'p2': moodle.seiteB.cmid,
      'p3': null,
    });
    expect(moodle.kartenSpeicherungen, 10);
    // Jede Kartenänderung wurde in der App freigegeben (je Ziel eine), dazu die übrigen Freigaben.
    expect(freigabeTitel.where((t) => t == 'Lernlandkarte ändern?').length, 10);
    // Der Protokollstand ist je Ziel getrennt und endet bei „verknüpft".
    final protokoll = (jsonDecode(
      File(p.join(ordner.path, 'uebertragungen.json')).readAsStringSync(),
    ) as List).cast<Map>();
    for (final k in [31, 32, 33, 34, 35]) {
      final eintraege = protokoll.where((e) => e['kurs'] == k).toList();
      expect(eintraege.last['karten'], 'verknüpft');
      expect(eintraege.last['stand'], 'fertig');
    }
  });

  test(
    'fremde gleichnamige Ersatzaktivität wird nicht als Kopie verknüpft',
    () async {
      moodle.kopieAendern = (a) {
        if (a.kurs == 31 && a.modul == 'page' && a.name == 'ZZ Seite A') {
          a.idnummer = 'fremde-identitaet';
          a.html = '<p>Fremder Inhalt</p>';
        }
      };
      final ergebnis = await client.tool('uebertragen', auftrag(ziele: [31]));

      expect(
        ergebnis,
        contains('ist nicht mit übereinstimmendem Inhalt belegt'),
      );
      expect(ergebnis, contains('0 verknüpft, 1 offen'));
      final karte = inZiel(31, 'learningmap', 'ZZ Karte');
      expect(links(karte)['p1'], moodle.seiteA.cmid);
      expect(links(karte)['p2'], isNot(moodle.seiteB.cmid));
      expect(moodle.kartenSpeicherungen, 1);
    },
  );

  test('doppelte identische Zielkopien bleiben mehrdeutig', () async {
    // Das Ziel erhält nach der Wiederherstellungsprüfung eine zweite, in
    // Titel, cmidnumber und Inhalt identische Seite. Die Kartenzuordnung muss
    // diese echte Mehrdeutigkeit offenlassen.
    moodle.duplikatNachRestore = true;
    final ergebnis = await client.tool('uebertragen', auftrag(ziele: [31]));

    expect(
      moodle.akt.where(
        (a) => a.kurs == 31 && a.modul == 'page' && a.name == 'ZZ Seite A',
      ),
      hasLength(3),
    );
    expect(
      ergebnis,
      contains('Mehrere neue Aktivitäten belegen das Ziel identisch'),
    );
    expect(ergebnis, contains('0 verknüpft, 1 offen'));
    final karte = inZiel(31, 'learningmap', 'ZZ Karte');
    expect(links(karte)['p1'], moodle.seiteA.cmid);
    expect(links(karte)['p2'], isNot(moodle.seiteB.cmid));
    expect(moodle.kartenSpeicherungen, 1);
  });

  test('Zusammenfassung vor dem Kopieren nennt die Karte und ihre ungelösten Verweise', () async {
    moodle.aufbauen(verweisAufAussen: true);
    final texte = <String>[];
    freigaben.addListener(() {
      final a = freigaben.aktuell;
      if (a != null && a.offen && a.titel.startsWith('Übertragung')) {
        texte.add(a.punkte.join('\n'));
      }
    });
    await client.tool('uebertragen', auftrag(ziele: [31]));
    expect(texte.single, contains('Lernlandkarte „ZZ Karte"'));
    expect(texte.single, contains('3 verknüpfte Orte'));
    expect(
      texte.single,
      contains('Ort p3 zeigt auf „ZZ Außen", das nicht mitkopiert wird'),
    );
  });

  test('nicht mitkopiertes Ziel bleibt eine konkrete ungelöste Zuordnung: nichts zusätzlich kopiert, Karte offen', () async {
    moodle.aufbauen(verweisAufAussen: true);
    final ergebnis = await client.tool('uebertragen', auftrag(ziele: [31, 32]));

    expect(ergebnis, contains('2 fertig'));
    expect(
      ergebnis,
      contains('Lernlandkarten je Ziel: 0 verknüpft, 2 offen, 0 unklar'),
    );
    expect(
      ergebnis,
      contains(
        'Ort p3 (Quellziel „ZZ Außen"): Das Ziel gehört nicht zur kopierten Auswahl.',
      ),
    );
    expect(ergebnis, contains('unverifiziert'));
    for (final k in [31, 32]) {
      expect(
        moodle.akt.where((a) => a.kurs == k && a.name == 'ZZ Außen'),
        isEmpty,
        reason: 'nichts zusätzlich kopiert',
      );
      final karte = inZiel(k, 'learningmap', 'ZZ Karte');
      final l = links(karte);
      expect(
        l['p1'],
        inZiel(k, 'page', 'ZZ Seite A').cmid,
        reason: 'belegte Orte werden gesetzt',
      );
      // Der ungelöste Ort behält die Quellnummer, er wird nicht geraten.
      expect(l['p3'], moodle.aussen.cmid);
      expect(karte.sichtbar, isFalse);
    }
    final protokoll = (jsonDecode(
      File(p.join(ordner.path, 'uebertragungen.json')).readAsStringSync(),
    ) as List).cast<Map>();
    expect(protokoll.where((e) => e['kurs'] == 31).last['karten'], 'offen');
  });

  test('gleich benannte Quellaktivitäten: vor dem Kopieren stoppen, keine sichtbare ungeklärte Karte erzeugen', () async {
    moodle.aufbauen(doppelterTitel: true);
    final ergebnis = await client.tool('uebertragen', auftrag(ziele: [31]));
    expect(ergebnis, contains('nicht eindeutig 1:1'));
    expect(moodle.backupStarts, 0);
    expect(moodle.restoreStarts, 0);
    expect(moodle.kartenSpeicherungen, 0);
    expect(
      moodle.akt.where((a) => a.kurs == 31 && a.modul == 'learningmap'),
      isEmpty,
    );
  });

  test('Teilfehler: erfolgreiche Ziele bleiben, ein unklares Ziel startet nichts neu; Wiederholung und Neustart doppeln nichts', () async {
    moodle.serverFehlerBeiStart = {33};
    final ergebnis = await client.tool('uebertragen', auftrag());

    expect(
      ergebnis,
      contains('4 fertig, 1 fehlgeschlagen oder unklar'),
      reason: ergebnis,
    );
    expect(
      ergebnis,
      contains('Lernlandkarten je Ziel: 4 verknüpft, 0 offen, 0 unklar'),
    );
    expect(moodle.startsJeZiel, {31: 1, 32: 1, 34: 1, 35: 1});
    expect(moodle.akt.where((a) => a.kurs == 33 && a.cmid < 5000), isEmpty);
    expect(ergebnis, contains('Nicht erneut gesendet'));
    final startsVorher = moodle.restoreStarts;
    final speicherVorher = moodle.kartenSpeicherungen;

    // Wiederholung im selben Lauf der App.
    final wieder = await client.tool('uebertragen', auftrag());
    expect(wieder, contains('schon einmal übertragen'));
    expect(moodle.restoreStarts, startsVorher);
    expect(moodle.backupStarts, 1);

    // Nach einem Neustart der App: derselbe Schutz aus der gespeicherten Datei.
    await dienst.stoppen();
    client.http.close(force: true);
    await dienstStarten();
    final nachNeustart = await client.tool('uebertragen', auftrag());
    expect(nachNeustart, contains('schon einmal übertragen'));
    expect(moodle.restoreStarts, startsVorher);
    expect(moodle.kartenSpeicherungen, speicherVorher);
    expect(
      moodle.backupStarts,
      1,
      reason: 'auch eine neue Sicherung wird nicht begonnen',
    );
  });

  test('Neustart während laufender Wiederherstellung sperrt neue Sicherung desselben Quellziels', () async {
    moodle.restoreAntwortBlockieren = true;
    final ersterAufruf = client.tool('uebertragen', auftrag(ziele: [31]));
    await moodle.restoreLaeuft.future;
    expect(moodle.restoreStarts, 1);

    final ersterFehler = ersterAufruf.then<void>(
      (_) {},
      onError: (Object _) {},
    );
    await dienst.stoppen();
    client.http.close(force: true);
    await dienstStarten();
    moodle.backupVariation++;

    final nachNeustart = await client.tool('uebertragen', auftrag(ziele: [31]));
    expect(nachNeustart, contains('schon einmal übertragen'));
    expect(
      moodle.backupStarts,
      1,
      reason: 'die neue Sicherung hätte einen anderen Hash',
    );
    expect(moodle.restoreStarts, 1);

    moodle.restoreFortsetzen.complete();
    await ersterFehler;
  });

  test('abgelehnte Kartenänderung: Karte bleibt unverknüpft, offen, Wiederholung nur über die Karte selbst', () async {
    kartenFreigabe = false;
    final ergebnis = await client.tool('uebertragen', auftrag(ziele: [31]));

    expect(ergebnis, contains('1 fertig'));
    expect(
      ergebnis,
      contains('Lernlandkarten je Ziel: 0 verknüpft, 1 offen, 0 unklar'),
    );
    expect(ergebnis, contains('nicht freigegeben, nichts geändert'));
    expect(moodle.kartenSpeicherungen, 0);
    final wieder = await client.tool('uebertragen', auftrag(ziele: [31]));
    expect(wieder, contains('Die Lernlandkarten dieses Ziels sind „offen"'));
    expect(wieder, contains('lernlandkarte_verknuepfungen_setzen'));
    expect(moodle.restoreStarts, 1);
  });

  test(
    'Ablehnung der ersten Karte stoppt alle folgenden Karten und Zielkurse',
    () async {
      kartenAntworten.addAll([false, true]);
      final ergebnis = await client.tool(
        'uebertragen',
        auftrag(ziele: [31, 32]),
      );

      expect(ergebnis, contains('abgelehnt'));
      expect(moodle.startsJeZiel, {31: 1});
      expect(moodle.restoreStarts, 1);
      expect(moodle.kartenSpeicherungen, 0);
      expect(kartenDialoge, 1);
      expect(ergebnis, contains('nicht begonnen'));
      expect(
        moodle.akt.where((a) => a.kurs == 31 && a.modul == 'learningmap'),
        hasLength(2),
      );
      expect(moodle.akt.where((a) => a.kurs == 32 && a.cmid < 5000), isEmpty);
    },
  );

  test(
    'ändert sich Zielinhalt während Kartenfreigabe, wird nicht verknüpft',
    () async {
      beiKartenfreigabe = () {
        for (final a in moodle.akt.where(
          (a) => a.kurs == 31 && a.modul == 'page' && a.cmid >= 1000,
        )) {
          a.html = '<p>Inhalt während der Freigabe geändert</p>';
        }
      };
      final ergebnis = await client.tool('uebertragen', auftrag(ziele: [31]));

      expect(ergebnis, contains('offen'));
      expect(
        ergebnis,
        contains('Inhalt des Zieles hat sich seit der Kopierprüfung geändert'),
      );
      expect(moodle.kartenSpeicherungen, 0);
      expect(kartenDialoge, 2);
    },
  );

  test('anderes Editorformat verhindert Kartenverknüpfung', () async {
    beiKartenfreigabe = () {
      for (final a in moodle.akt.where(
        (a) => a.kurs == 31 && a.modul == 'page' && a.cmid >= 1000,
      )) {
        a.format = '2';
      }
    };
    final ergebnis = await client.tool('uebertragen', auftrag(ziele: [31]));

    expect(ergebnis, contains('offen'));
    expect(
      ergebnis,
      contains('Inhalt des Zieles hat sich seit der Kopierprüfung geändert'),
    );
    expect(moodle.kartenSpeicherungen, 0);
  });

  test('während der Kartenfreigabe ist das kopierte Ziel dauerhaft als ausstehend gespeichert', () async {
    final staende = <String>[];
    freigaben.addListener(() {
      if (freigaben.aktuell?.titel != 'Lernlandkarte ändern?') return;
      final protokoll = (jsonDecode(
        File(p.join(ordner.path, 'uebertragungen.json')).readAsStringSync(),
      ) as List).cast<Map>();
      staende.add(
        protokoll.where((e) => e['kurs'] == 31).last['karten'] as String,
      );
    });
    kartenFreigabe = false;
    final ergebnis = await client.tool('uebertragen', auftrag(ziele: [31]));
    expect(staende, ['ausstehend']);
    expect(ergebnis, contains('1 offen'));
    expect(moodle.restoreStarts, 1);
  });

  test('Quellkarte während der Startfreigabe geändert: keine veraltete Zuordnung kopieren', () async {
    freigaben.addListener(() {
      if (freigaben.aktuell?.titel.startsWith('Übertragung') != true) return;
      final store = jsonDecode(moodle.karte.placestore!) as Map;
      store['places'][0]['linkedActivity'] = moodle.seiteB.cmid;
      moodle.karte.placestore = jsonEncode(store);
    });
    final ergebnis = await client.tool('uebertragen', auftrag(ziele: [31]));
    expect(ergebnis, contains('Quellauswahl wurde seit dem Erfassen geändert'));
    expect(moodle.restoreStarts, 0);
    expect(moodle.kartenSpeicherungen, 0);
  });

  test(
    'zusätzliche fremde Verknüpfung an ursprünglich freiem Ort bleibt offen',
    () async {
      moodle.kopieAendern = (a) {
        if (a.modul != 'learningmap') return;
        final daten = jsonDecode(a.placestore!) as Map;
        for (final place in (daten['places'] as List).cast<Map>()) {
          if (place['id'] == 'p3') place['linkedActivity'] = 999999;
        }
        a.placestore = jsonEncode(daten);
      };
      final ergebnis = await client.tool('uebertragen', auftrag(ziele: [31]));
      expect(ergebnis, contains('0 verknüpft, 1 offen'));
      expect(
        ergebnis,
        contains(
          'Kartendaten oder Ortsziele weichen von der Quellerfassung ab',
        ),
      );
      expect(moodle.kartenSpeicherungen, 1);
    },
  );

  test('beim Kopieren veränderte Geometrie wird nicht als fertig verknüpfte Karte ausgegeben', () async {
    moodle.kopieAendern = (a) {
      if (a.modul == 'learningmap') {
        a.svgcode = '<svg><circle id="p1" cx="999"/></svg>';
      }
    };
    final ergebnis = await client.tool('uebertragen', auftrag(ziele: [31]));
    expect(ergebnis, contains('0 verknüpft, 1 offen'));
    expect(moodle.kartenSpeicherungen, 0);
  });

  test(
    'Profilwechsel während Kartenfreigabe schreibt keine Verknüpfung',
    () async {
      freigaben.addListener(() {
        if (freigaben.aktuell?.titel != 'Lernlandkarte ändern?') return;
        dienst.profil = Profil(
          kennung: 'fremd',
          name: 'Anderes Profil',
          adresse: moodle.basis.toString(),
          port: profil.port,
          mcpName: 'anderes',
        );
      });
      final ergebnis = await client.tool('uebertragen', auftrag(ziele: [31]));
      expect(ergebnis, contains('1 unklar'));
      expect(moodle.kartenSpeicherungen, 0);
    },
  );

  test(
    'mit datei weist das Ergebnis auf nicht verknüpfte Lernlandkarten hin',
    () async {
      // Eine Sicherung mit Karte liegt schon vor: Quelle ist nicht erfasst, die App sagt es.
      moodle.gesichert = {moodle.seiteA.cmid, moodle.karte.cmid};
      File(p.join(ordner.path, 'test.mbz')).writeAsBytesSync(moodle.archiv());
      final ergebnis = await client.tool('uebertragen', {
        'datei': 'test.mbz',
        'ziele': [
          {
            'kurs': 31,
            'name': 'ZZ Ziel 1',
            'weg': 'aktueller_kurs_verschmelzen',
          },
        ],
      });
      expect(ergebnis, contains('1 fertig'), reason: ergebnis);
      expect(ergebnis, contains('Das Archiv enthält Lernlandkarten'));
      expect(moodle.kartenSpeicherungen, 0);
    },
  );
  test('Moodle ergänzt beim Wiederherstellen technische Kartenkennung, Formatversion und Standarddeckkraft', () async {
    moodle.kopieAendern = (a) {
      if (a.modul != 'learningmap') return;
      final daten = jsonDecode(a.placestore!) as Map;
      daten['mapid'] = 'neue-kartenkennung';
      daten['version'] = 2024072201;
      daten['strokeopacity'] = 1;
      a.placestore = jsonEncode(daten);
    };
    final ergebnis = await client.tool('uebertragen', auftrag(ziele: [31]));
    expect(ergebnis, contains('1 verknüpft, 0 offen'));
    expect(
      links(inZiel(31, 'learningmap', 'ZZ Karte'))['p1'],
      inZiel(31, 'page', 'ZZ Seite A').cmid,
    );
    final daten =
        jsonDecode(inZiel(31, 'learningmap', 'ZZ Karte').placestore!) as Map;
    expect(daten['mapid'], 'neue-kartenkennung');
    expect(daten['version'], 2024072201);
    expect(daten['strokeopacity'], 1);
  });

  test(
    'abweichende Kartenbeschreibung bleibt vor dem Verknüpfen offen',
    () async {
      moodle.kopieAendern = (a) {
        if (a.modul == 'learningmap') a.intro = 'Fremde Beschreibung';
      };
      final ergebnis = await client.tool('uebertragen', auftrag(ziele: [31]));

      expect(
        ergebnis,
        contains('Formularinhalte oder Kartendaten weichen von der Quelle ab'),
      );
      expect(ergebnis, contains('0 verknüpft, 1 offen'));
      expect(moodle.kartenSpeicherungen, 0);
    },
  );

  test(
    'fehlendes Quell-Hintergrundbild bleibt vor dem Verknüpfen offen',
    () async {
      moodle.karte.backgroundImage = true;
      moodle.kopieAendern = (a) {
        if (a.modul == 'learningmap') a.backgroundImage = false;
      };
      final ergebnis = await client.tool('uebertragen', auftrag(ziele: [31]));

      expect(
        ergebnis,
        contains('Formularinhalte oder Kartendaten weichen von der Quelle ab'),
      );
      expect(ergebnis, contains('0 verknüpft, 1 offen'));
      expect(moodle.kartenSpeicherungen, 1);
      expect(
        links(inZiel(31, 'learningmap', 'ZZ Karte'))['p1'],
        moodle.seiteA.cmid,
      );
    },
  );

  test(
    'abweichende native Karteneinstellung bleibt vor dem Verknüpfen offen',
    () async {
      moodle.erinnerungAktiv = true;
      moodle.kopieAendern = (a) {
        if (a.modul == 'learningmap') a.completionMinute = 99;
      };
      final ergebnis = await client.tool('uebertragen', auftrag(ziele: [31]));

      expect(
        ergebnis,
        contains('Formularinhalte oder Kartendaten weichen von der Quelle ab'),
      );
      expect(ergebnis, contains('0 verknüpft, 1 offen'));
      expect(moodle.kartenSpeicherungen, 0);
    },
  );

  test('abweichende Deckkraft bleibt trotz zulässiger technischer Kartenmetadaten offen', () async {
    moodle.kopieAendern = (a) {
      if (a.modul != 'learningmap') return;
      final daten = jsonDecode(a.placestore!) as Map;
      daten['mapid'] = 'neue-kartenkennung';
      daten['version'] = 2024072201;
      daten['strokeopacity'] = 0.5;
      a.placestore = jsonEncode(daten);
    };
    final ergebnis = await client.tool('uebertragen', auftrag(ziele: [31]));
    expect(ergebnis, contains('0 verknüpft, 1 offen'));
    expect(moodle.kartenSpeicherungen, 0);
  });
  test('gebundener Testbetrieb verteilt nur eigene ZZ-Proben und übernimmt ihre belegten Kopien für Folgeaktionen', () async {
    await dienst.stoppen();
    client.http.close(force: true);
    testbindung = true;
    normaleFreigabe = false;
    freigaben.stufe = Bestaetigungen.alle;
    await dienstStarten();
    final entwurf = Directory(p.join(ordner.path, 'eigen'))..createSync();
    final eigene = <_Akt>[];
    for (final name in ['ZZ Eigene A', 'ZZ Eigene B']) {
      final dateiLink = name.endsWith('A')
          ? '<a href="@@PLUGINFILE@@/zz-owned.txt">Datei</a>'
          : '';
      File(p.join(entwurf.path, 'page.html'))
          .writeAsStringSync('<p>$name</p>$dateiLink');
      final dateien = Directory(p.join(entwurf.path, 'dateien'))..createSync();
      File(p.join(dateien.path, 'zz-owned.txt'))
          .writeAsStringSync(moodle.dateiInhalt);
      final angelegt = await client.tool('aktivitaet_anlegen', {
        'kurs': 12,
        'abschnitt_id': 101,
        'typ': 'page',
        'name': name,
        'ordner': 'eigen',
      });
      expect(angelegt, contains('verified: true'), reason: angelegt);
      eigene.add(moodle.akt.singleWhere((a) => a.kurs == 12 && a.name == name));
    }
    final karteOrdner = Directory(p.join(ordner.path, 'eigene-karte'))
      ..createSync();
    File(p.join(karteOrdner.path, 'lernlandkarte.json')).writeAsStringSync(
      jsonEncode({
        'orte': [
          {'id': 'p1', 'x': 120, 'y': 200},
          {'id': 'p2', 'x': 800, 'y': 200},
        ],
        'wege': [
          {'von': 'p1', 'nach': 'p2'},
        ],
      }),
    );
    final angelegteKarte = await client.tool('aktivitaet_anlegen', {
      'kurs': 12,
      'abschnitt_id': 101,
      'typ': 'learningmap',
      'name': 'ZZ Eigene Karte',
      'ordner': 'eigene-karte',
    });
    expect(angelegteKarte, contains('verified: true'), reason: angelegteKarte);
    final quellKarte = moodle.akt.singleWhere(
      (a) => a.kurs == 12 && a.name == 'ZZ Eigene Karte',
    );
    final kartenEntwurf = File(
      p.join(ordner.path, 'cm-${quellKarte.cmid}', 'introeditor.html'),
    );
    kartenEntwurf.writeAsStringSync('<p>ZZ unverlorener Entwurf</p>');
    final entwurfGespeichert = await client.tool('aendern', {
      'ordner': 'cm-${quellKarte.cmid}',
    });
    expect(
      entwurfGespeichert,
      contains('ist Lernlandkarte'),
      reason: entwurfGespeichert,
    );
    expect(
      kartenEntwurf.readAsStringSync(),
      '<p>ZZ unverlorener Entwurf</p>',
      reason: 'Besitzprobe überschreibt keinen Benutzerentwurf',
    );
    final verknuepft = await client.tool(
      'lernlandkarte_verknuepfungen_setzen',
      {
        'cmid': quellKarte.cmid,
        'name': quellKarte.name,
        'zuordnungen': [
          {'ort': 'p1', 'aktuell': 0, 'ziel': eigene[0].cmid},
          {'ort': 'p2', 'aktuell': 0, 'ziel': eigene[1].cmid},
        ],
      },
    );
    expect(verknuepft, contains('verified: true'), reason: verknuepft);
    eigene.add(quellKarte);
    moodle.erinnerungMinute =
        24; // ausgeschaltetes Datum ist kein geänderter Inhalt
    moodle.nativeZielverweise = true;
    final ergebnis = await client.tool('uebertragen', {
      'kurs': 12,
      'name_des_kurses': 'ZZ Quelle',
      'aktivitaeten': [
        for (final x in eigene) {'cmid': x.cmid, 'name': x.name},
      ],
      'ziele': [
        {'kurs': 31, 'name': 'ZZ Ziel 1', 'weg': 'aktueller_kurs_verschmelzen'},
      ],
    });
    expect(ergebnis, contains('1 fertig'), reason: ergebnis);
    expect(
      freigabeTitel,
      isEmpty,
      reason: 'keine persönliche Freigabe im begrenzten eigenen Testablauf',
    );
    final kartenKopie = inZiel(31, 'learningmap', 'ZZ Eigene Karte');
    final kopieLink = await client.tool('lernlandkarte_verknuepfungen_setzen', {
      'cmid': kartenKopie.cmid,
      'name': kartenKopie.name,
      'zuordnungen': [
        {
          'ort': 'p2',
          'aktuell': inZiel(31, 'page', 'ZZ Eigene B').cmid,
          'ziel': 0,
        },
      ],
    });
    expect(
      kopieLink,
      contains('verified: false'),
      reason: 'Nach dem Entkoppeln gibt es keinen belegten Zielnamen.',
    );
    final kopierterStore =
        jsonDecode(kartenKopie.placestore!) as Map<String, dynamic>;
    expect(
      (kopierterStore['places'] as List).singleWhere(
        (ort) => (ort as Map)['id'] == 'p2',
      ),
      isNot(contains('linkedActivity')),
    );
    expect(kopieLink, contains('automatisch freigegeben'));
    expect(freigabeTitel, isEmpty);
    final kopie = inZiel(31, 'page', 'ZZ Eigene A');
    moodle.dateiInhalt = 'Fremder ausgetauschter Dateiinhalt';
    final dateiGeaendert = await client.tool('loeschen', {
      'kurs': 31,
      'cmid': kopie.cmid,
      'name': kopie.name,
    });
    expect(
      dateiGeaendert,
      contains('Nicht gelöscht'),
      reason: 'Dateibytes sind Teil des Testbesitzes',
    );
    moodle.dateiInhalt = 'Eigene Dateiprobe';
    freigabeTitel.clear();
    moodle.erinnerungAktiv = true;
    final terminGeaendert = await client.tool('loeschen', {
      'kurs': 31,
      'cmid': kopie.cmid,
      'name': kopie.name,
    });
    expect(
      terminGeaendert,
      contains('Nicht gelöscht'),
      reason: 'Aktivierter Termin ist eine echte Änderung',
    );
    moodle.erinnerungAktiv = false;
    freigabeTitel.clear();
    final geloescht = await client.tool('loeschen', {
      'kurs': 31,
      'cmid': kopie.cmid,
      'name': kopie.name,
    });
    expect(geloescht, contains('verified: true'), reason: geloescht);
    expect(geloescht, contains('automatisch freigegeben'));
    final fremd = await client.tool('loeschen', {
      'kurs': 31,
      'cmid': 5000,
      'name': 'ZZ Seite A',
    });
    expect(fremd, contains('Nicht gelöscht'));
    expect(moodle.akt.any((a) => a.cmid == 5000), isTrue);
    // Ein weiteres gebundenes Profil darf nur die in dieser App-Sitzung belegte Sicherung übernehmen.
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final profil2 = Profil(
      kennung: 'zweites',
      name: 'Zweites Testprofil',
      adresse: moodle.basis.toString(),
      port: socket.port,
      mcpName: 'zweites',
    );
    await socket.close();
    final freigaben2 = Freigaben(
      Protokoll(),
      stufe: Bestaetigungen.alle,
      frist: const Duration(milliseconds: 150),
    );
    final dienst2 = McpDienst(
      Einstellungen(schluessel: 'test', profile: [profil2]),
      zugang,
      Protokoll(),
      freigaben2,
      ordner.path,
      profil: profil2,
      testzugang: Testzugang(
        kennung: profil2.kennung,
        datei: 'unused.env',
        adresse: profil2.adresse,
        kurse: {32, 33, 34},
        bilder: true,
      ),
      sicherungsordner: ordner.path,
    );
    await dienst2.starten();
    final client2 = McpTestClient(profil2.port);
    try {
      await client2.initialize();
      final datei = RegExp(r'Datei ([^\s]+\.mbz)')
          .firstMatch(ergebnis)!
          .group(1)!;
      moodle.nativeZielverweise = true;
      final uebernommen = await client2.tool('wiederherstellen_datei', {
        'datei': datei,
        'kurs': 32,
        'name': 'ZZ Ziel 2',
        'weg': 'aktueller_kurs_verschmelzen',
      });
      expect(uebernommen, contains('Wiederhergestellt'), reason: uebernommen);
      expect(uebernommen, contains('Belegte eigene ZZ-Kopien'));
      expect(uebernommen, contains('automatisch freigegeben'));
      final karte2 = inZiel(32, 'learningmap', 'ZZ Eigene Karte');
      final gesetzt = await client2.tool(
        'lernlandkarte_verknuepfungen_setzen',
        {
          'cmid': karte2.cmid,
          'name': karte2.name,
          'zuordnungen': [
            {
              'ort': 'p1',
              'aktuell': inZiel(32, 'page', 'ZZ Eigene A').cmid,
              'ziel': 0,
            },
          ],
        },
      );
      expect(
        gesetzt,
        contains('verified: false'),
        reason:
            'Für die entkoppelte Ortsbeschriftung ist kein Zielname belegt.',
      );
      expect(gesetzt, contains('automatisch freigegeben'));
      final nummer = RegExp(r'Nummer ([a-z0-9]+)')
          .firstMatch(uebernommen)!
          .group(1)!;
      karte2.svgcode = '<svg><circle id="extern-geaendert"/></svg>';
      await client2.tool('wiederherstellung_status', {'id': nummer});
      final vorher = freigaben2.testfreigaben;
      final stale = await client2.tool('loeschen', {
        'kurs': 32,
        'cmid': karte2.cmid,
        'name': karte2.name,
      });
      expect(stale, contains('Nicht gelöscht'));
      expect(
        freigaben2.testfreigaben,
        vorher,
        reason: 'Status liest keine fremde Änderung als neuen Testbesitz ein',
      );
      // Fertig, aber inhaltlich abweichend: niemals neuen Testbesitz ableiten.
      moodle.kopieAendern = (a) {
        if (a.modul == 'learningmap') {
          a.svgcode = '<svg><circle id="fremder-inhalt"/></svg>';
        }
      };
      final abweichend = await client2.tool('wiederherstellen_datei', {
        'datei': datei,
        'kurs': 33,
        'name': 'ZZ Ziel 3',
        'weg': 'aktueller_kurs_verschmelzen',
      });
      expect(abweichend, contains('Wiederhergestellt'), reason: abweichend);
      expect(abweichend, isNot(contains('Belegte eigene ZZ-Kopien')));
      final abweichendeKarte = inZiel(33, 'learningmap', 'ZZ Eigene Karte');
      final automatikVorher = freigaben2.testfreigaben;
      final nichtEigen = await client2.tool('loeschen', {
        'kurs': 33,
        'cmid': abweichendeKarte.cmid,
        'name': abweichendeKarte.name,
      });
      expect(nichtEigen, contains('Nicht gelöscht'));
      expect(freigaben2.testfreigaben, automatikVorher);
      moodle.kopieAendern = null;
      moodle.kopieAendern = (a) {
        if (a.modul == 'learningmap') a.placestore = quellKarte.placestore;
      };
      final alteVerweise = await client2.tool('wiederherstellen_datei', {
        'datei': datei,
        'kurs': 34,
        'name': 'ZZ Ziel 4',
        'weg': 'aktueller_kurs_verschmelzen',
      });
      expect(alteVerweise, contains('Wiederhergestellt'));
      expect(alteVerweise, isNot(contains('Belegte eigene ZZ-Kopien')));
      final alteKarte = inZiel(34, 'learningmap', 'ZZ Eigene Karte');
      final alteAutomatik = freigaben2.testfreigaben;
      final alteLoeschen = await client2.tool('loeschen', {
        'kurs': 34,
        'cmid': alteKarte.cmid,
        'name': alteKarte.name,
      });
      expect(alteLoeschen, contains('Nicht gelöscht'));
      expect(freigaben2.testfreigaben, alteAutomatik);
      moodle.kopieAendern = null;
      final gesichert = moodle.gesichert;
      moodle.gesichert = {moodle.aussen.cmid};
      File(p.join(ordner.path, 'fremde-zz.mbz'))
          .writeAsBytesSync(moodle.archiv());
      moodle.gesichert = gesichert;
      final fremdeDatei = await client2.tool('wiederherstellen_datei', {
        'datei': 'fremde-zz.mbz',
        'kurs': 32,
        'name': 'ZZ Ziel 2',
        'weg': 'aktueller_kurs_verschmelzen',
      });
      expect(fremdeDatei, contains('Nicht wiederhergestellt'));
      expect(
        freigaben2.testfreigaben,
        alteAutomatik,
        reason: 'ZZ-Namen im Archiv genügen nicht',
      );
    } finally {
      await dienst2.stoppen();
      client2.http.close(force: true);
    }
  });
}
