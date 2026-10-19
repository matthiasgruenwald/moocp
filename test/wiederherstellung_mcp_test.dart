// Öffentliche MCP-Verträge; nur Moodle wird durch einen lokalen HTTP-Server ersetzt.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/einstellungen.dart';
import 'package:moocp/freigabe.dart';
import 'package:moocp/mcp/mcp_dienst.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/moodle/sicherung.dart';
import 'package:moocp/moodle/sicherung_regeln.dart';
import 'package:moocp/moodle/wiederherstellung_regeln.dart';
import 'package:moocp/profil.dart';
import 'package:moocp/protokoll.dart';
import 'package:path/path.dart' as p;

class _Moodle {
  late HttpServer server;
  int requests = 0;
  int starts = 0;
  int backupStarts = 0;
  String modul = 'page';
  String title = 'ZZ Blatt';
  int downloads = 0;
  bool failProgress = false;
  bool linkAvailable = true;
  static final backupBytes = List<int>.generate(1024, (i) => i % 256);
  int writes = 0;
  int progressReads = 0;
  Object progress = <String, Object?>{'progress': 0.2};
  Completer<void>? hold;
  bool completed = false;
  static const restore = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  Uri get basis => Uri.parse('http://127.0.0.1:${server.port}');
  String page(String body) => '<script>M.cfg = {"sesskey":"sk","courseId":12,"contextid":"55"};</script>$body';
  String form(Map<String, String> fields, {String path = '/backup/restore.php'}) => page(
    '<form class="mform" action="$path" method="post">${{'sesskey': 'sk', ...fields}.entries.map((e) => '<input type="hidden" name="${e.key}" value="${e.value}">').join()}</form>',
  );
  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      requests++;
      final path = r.uri.path;
      final body = await const Utf8Decoder(allowMalformed: true).bind(r).join();
      String answer;
      if (path == '/login/index.php') {
        if (r.method == 'POST' || r.uri.queryParameters.containsKey('testsession')) {
          r.response.redirect(Uri.parse(r.method == 'POST' ? '/login/index.php?testsession=1' : '/my/'), status: 303);
          await r.response.close();
          return;
        }
        r.response.cookies.add(Cookie('MoodleSession', 'test'));
        answer = r.cookies.isNotEmpty ? page('Angemeldet') : '<form><input name="logintoken" value="tok"></form>';
      } else if (path == '/my/' || path == '/course/view.php') {
        answer = page('<p>ZZ Kurs</p>');
      } else if (path == '/lib/ajax/service.php') {
        final call = (jsonDecode(body) as List).single as Map;
        Object? data;
        switch (call['methodname']) {
          case 'core_course_get_enrolled_courses_by_timeline_classification':
            data = {
              'courses': [
                {'id': 12, 'fullname': 'ZZ Kurs', 'shortname': 'ZZ'},
              ],
            };
          case 'core_courseformat_get_state':
            data = {
              'cm': [
                if (completed) {'id': 70, 'module': modul, 'name': title, 'visible': 0, 'sectionid': 1},
              ],
              'section': [
                {
                  'id': 1,
                  'visible': 1,
                  'cmlist': [if (completed) 70],
                },
              ],
            };
          case 'core_backup_get_async_backup_progress':
            progressReads++;
            final waiting = hold;
            if (waiting != null) await waiting.future;
            if (failProgress) {
              r.response.write('kein JSON');
              await r.response.close();
              return;
            }
            data = [
              {'backupid': restore, ...(progress as Map).cast<String, Object?>()},
            ];
          default:
            throw StateError('Unerwarteter Dienst: ${call['methodname']}');
        }
        answer = jsonEncode([
          {'error': false, 'data': data},
        ]);
      } else if (path == '/repository/repository_ajax.php') {
        writes++;
        answer = jsonEncode({'url': '$basis/draftfile.php/55/user/draft/9/test.mbz'});
      } else if (path == '/backup/backup.php') {
        if (r.method == 'GET') {
          answer = form({'stage': '1', '_qf__backup_initial_form': '1', 'setting_root_users': '0'}, path: path);
        } else {
          final f = Uri.splitQueryString(body);
          if (f['stage'] == '1') {
            answer = form({
              'stage': '2',
              '_qf__backup_schema_form': '1',
              'setting_root_users': '0',
              'setting_section_section_1_included': '1',
            }, path: path);
          } else if (f['stage'] == '2') {
            answer = form({
              'stage': '4',
              '_qf__backup_confirmation_form': '1',
              'backup': restore,
              'setting_root_filename': 'download.mbz',
              'setting_root_users': '0',
              'setting_section_section_1_included': '1',
            }, path: path);
          } else {
            backupStarts++;
            answer = page('Gestartet');
          }
        }
      } else if (path == '/pluginfile.php/55/user/backup/1/download.mbz') {
        downloads++;
        r.response.contentLength = backupBytes.length;
        r.response.add(backupBytes);
        await r.response.close();
        return;
      } else if (path == '/backup/restorefile.php') {
        if (r.method == 'POST') {
          writes++;
          r.response.redirect(Uri.parse('/backup/restore.php?contextid=55&filename=abc'), status: 303);
          await r.response.close();
          return;
        }
        final upload = form({'_qf__course_restore_form': '1', 'backupfile': '9'}, path: path);
        final link = linkAvailable
            ? '<a href="/pluginfile.php/55/user/backup/1/download.mbz?forcedownload=1">download.mbz</a>'
            : '';
        answer = '$upload<script>var repo = {"id":4,"type":"upload"};</script>$link';
      } else if (path == '/backup/restore.php') {
        if (r.method == 'GET') {
          answer = form({'contextid': '55', 'filename': 'abc', 'stage': '2'});
        } else {
          writes++;
          final f = Uri.splitQueryString(body);
          if (f.containsKey('_qf__restore_review_form')) {
            starts++;
            answer = page('Gestartet');
          } else if (f.containsKey('_qf__restore_schema_form')) {
            answer = form({'_qf__restore_review_form': '1', 'stage': '16', 'restore': restore});
          } else if (f.containsKey('_qf__restore_settings_form')) {
            answer = form({'_qf__restore_schema_form': '1', 'stage': '8', 'restore': restore});
          } else if (f.containsKey('target')) {
            answer = form({'_qf__restore_settings_form': '1', 'stage': '4', 'restore': restore});
          } else {
            answer = form({'contextid': '55', 'filename': 'abc', 'stage': '4', 'target': '1', 'targetid': '12'});
          }
        }
      } else if (path == '/mod/quiz/edit.php') {
        answer = page(
          '<script>var quiz = {"quizid": 8};</script><li class="slot qtype_multichoice" id="slot-1"><span class="questionname">ZZ Frage</span></li>',
        );
      } else if (path == '/question/bank/importquestions/import.php') {
        answer = page('<select name="category"><option value="1,55">ZZ Sammlung (1)</option></select>');
      } else if (path == '/question/bank/exportquestions/export.php') {
        if (r.method == 'GET') {
          answer = form({'_qf__export_form': '1', 'format': 'xml'}, path: path);
        } else {
          answer = '<a href="/pluginfile.php/55/question/export/1/export.xml">Export</a>';
        }
      } else if (path == '/pluginfile.php/55/question/export/1/export.xml') {
        answer = '<?xml version="1.0"?><quiz><question type="multichoice"><name><text>ZZ Frage</text></name><idnumber>ZZ-1</idnumber></question></quiz>';
      } else if (path == '/course/modedit.php') {
        answer = page('<form class="mform"></form>');
      } else {
        throw StateError('Unerwartete Adresse: $path');
      }
      r.response.headers.contentType = ContentType.html;
      r.response.write(answer);
      await r.response.close();
    });
  }
}

class _Client {
  _Client(this.port);
  final int port;
  final http = HttpClient();
  int id = 0;
  String? session;
  Future<Map> call(String method, [Map<String, Object?>? params]) async {
    final r = await http.postUrl(Uri.parse('http://127.0.0.1:$port/mcp'));
    r.headers
      ..set('Authorization', 'Bearer test')
      ..set('Accept', 'application/json, text/event-stream')
      ..contentType = ContentType.json;
    if (session != null) r.headers.set('Mcp-Session-Id', session!);
    r.write(jsonEncode({'jsonrpc': '2.0', 'id': ++id, 'method': method, 'params': ?params}));
    final response = await r.close();
    session ??= response.headers.value('mcp-session-id');
    final body = await utf8.decoder.bind(response).join();
    expect(response.statusCode, 200, reason: body);
    final decoded = jsonDecode(body) as Map;
    expect(decoded['error'], isNull, reason: body);
    return decoded['result'] as Map;
  }

  Future<void> initialize() async {
    await call('initialize', {
      'protocolVersion': '2025-06-18',
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'contract-test', 'version': '1'},
    });
    final r = await http.postUrl(Uri.parse('http://127.0.0.1:$port/mcp'));
    r.headers
      ..set('Authorization', 'Bearer test')
      ..set('Accept', 'application/json, text/event-stream')
      ..set('Mcp-Session-Id', session!)
      ..contentType = ContentType.json;
    r.write(jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}));
    await (await r.close()).drain<void>();
  }

  Future<String> tool(String name, Map<String, Object?> args) async {
    final r = await call('tools/call', {'name': name, 'arguments': args});
    return (r['content'] as List).map((e) => (e as Map)['text']).join('\n');
  }

  Future<String> waitStatus(String toolName, String number, bool Function(String) ready) async {
    var result = '';
    for (var i = 0; i < 100; i++) {
      result = await tool(toolName, {'id': number});
      if (ready(result)) return result;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('Status wurde nicht erreicht: $result');
  }
}

void main() {
  late _Moodle external;
  late Directory folder;
  late McpDienst service;
  late _Client client;
  late Freigaben approvals;
  late Profil profile;
  late MoodleZugang moodle;
  final arguments = <String, Object?>{
    'datei': 'test.mbz',
    'weg': 'aktueller_kurs_verschmelzen',
    'kurs': 12,
    'name': 'ZZ Kurs',
  };
  Future<void> startService() async {
    final log = Protokoll();
    service = McpDienst(
      Einstellungen(schluessel: 'test', profile: [profile]),
      moodle,
      log,
      approvals,
      folder.path,
      profil: profile,
      sicherungsordner: folder.path,
      antwortfrist: const Duration(seconds: 1),
    );
    await service.starten();
    client = _Client(profile.port);
    await client.initialize();
  }

  void writeArchive({bool quiz = false, bool image = false}) {
    external.modul = quiz ? 'quiz' : 'page';
    external.title = quiz ? 'ZZ Quiz' : 'ZZ Blatt';
    final archive = Archive();
    for (final e in <String, String>{
      'moodle_backup.xml':
          '<moodle_backup><information><format>moodle2</format><type>activity</type></information><activities><activity><modulename>${external.modul}</modulename><title>${external.title}</title><directory>activities/${external.modul}_7</directory></activity></activities></moodle_backup>',
      'activities/${external.modul}_7/inforef.xml': image ? '<inforef><file><id>1</id></file></inforef>' : '<inforef/>',
      'files.xml': image
          ? '<files><file><id>1</id><component>mod_page</component><filename>bild.png</filename><contenthash>0000000000000000000000000000000000000000</contenthash></file></files>'
          : '<files/>',
      if (quiz) 'activities/quiz_7/quiz.xml': '<quiz><question_instance><question_reference><questionbankentryid>1</questionbankentryid><version>1</version></question_reference></question_instance></quiz>',
      if (quiz) 'questions.xml': '<question_bank_entry id="1"><idnumber>ZZ-1</idnumber><question_version><question_versions><version>1</version><questions><question><name>ZZ Frage</name></question></questions></question_versions></question_version></question_bank_entry>',
    }.entries) {
      archive.addFile(ArchiveFile.bytes(e.key, utf8.encode(e.value)));
    }
    File(p.join(folder.path, 'test.mbz'))
        .writeAsBytesSync(GZipEncoder().encodeBytes(TarEncoder().encodeBytes(archive)));
  }

  setUp(() async {
    external = _Moodle();
    await external.start();
    folder = Directory.systemTemp.createTempSync('restore-mcp-');
    writeArchive();
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    profile = Profil(
      kennung: 'stable',
      name: 'Vorher',
      adresse: external.basis.toString(),
      port: port,
      mcpName: 'test',
    );
    final log = Protokoll();
    approvals = Freigaben(log, stufe: Bestaetigungen.keine);
    moodle = await MoodleZugang.fuerTest(log, external.basis, benutzer: 'e.mustermann', passwort: 'test');
    await startService();
  });
  tearDown(() async {
    external.hold?.complete();
    await service.stoppen();
    client.http.close(force: true);
    await external.server.close(force: true);
    folder.deleteSync(recursive: true);
  });

  test('MCP veröffentlicht löschende Wiederherstellung als destruktiv', () async {
    final list = await client.call('tools/list');
    final tool = (list['tools'] as List).cast<Map>().singleWhere((t) => t['name'] == 'wiederherstellen_datei');
    expect(tool['annotations']['readOnlyHint'], false);
    expect(tool['annotations']['destructiveHint'], true);
  });

  test('Start, Zeitlimit, Profilumbenennung und Neustart behalten Wiederholungsschutz', () async {
    external.hold = Completer<void>();
    final result = await client.tool('wiederherstellen_datei', arguments);
    expect(external.starts, 1, reason: result);
    final number = RegExp(r'Nummer ([a-z0-9]+)').firstMatch(result)!.group(1)!;
    expect(result, contains('wiederherstellung_status'));
    external.progress = {'error': 'failed', 'progress': 0.2};
    external.hold!.complete();
    external.hold = null;
    await client.waitStatus('wiederherstellung_status', number, (t) => t.contains('Moodle meldet einen Fehler'));
    await service.stoppen();
    client.http.close(force: true);
    profile = profile.copyWith(name: 'Nachher');
    await startService();
    final duplicate = await client.tool('wiederherstellen_datei', arguments);
    expect(duplicate, contains(number));
    expect(external.starts, 1);
  });
  test('Status-Zeitlimit nennt Werkzeug und Nummer; erneute Abfrage startet nichts', () async {
    external.progress = {'unexpected': true};
    final started = await client.tool('wiederherstellen_datei', arguments);
    final number = RegExp(r'Nummer ([a-z0-9]+)').firstMatch(started)!.group(1)!;
    final writes = external.writes;
    external.progress = {'progress': 1, 'status': 1000};
    external.completed = true;
    external.hold = Completer<void>();
    final pending = await client.tool('wiederherstellung_status', {'id': number});
    expect(pending, contains(number));
    expect(pending, contains('wiederherstellung_status'));
    external.hold!.complete();
    external.hold = null;
    final finished = await client.waitStatus('wiederherstellung_status', number, (t) => t.contains('fertig'));
    expect(finished, contains('fertig'));
    expect(finished, contains('übereinstimmend'));
    expect(external.writes, writes);
    expect(external.starts, 1);
  });

  test('bewusste Wiederholung liest den aktuellen Altvorgang vor der Freigabe ohne zu schreiben', () async {
    external.progress = {'unexpected': true};
    final started = await client.tool('wiederherstellen_datei', arguments);
    final number = RegExp(r'Nummer ([a-z0-9]+)').firstMatch(started)!.group(1)!;
    final writes = external.writes;
    final reads = external.progressReads;
    external.progress = {'progress': 1, 'status': 1000};
    external.completed = true;
    // Stufe bleibt „keine": Die Rückfrage vor einer Wiederholung gilt trotzdem (E29).
    String? approval;
    approvals.addListener(() {
      final current = approvals.aktuell;
      if (current == null) return;
      approval = current.punkte.join(' ');
      scheduleMicrotask(() => approvals.entscheiden(false));
    });
    await client.tool('wiederherstellen_datei', {...arguments, 'wiederholung_von': number});
    expect(external.progressReads, reads + 1);
    expect(approval, contains('beendet'));
    expect(approval, contains('Dubletten'));
    expect(external.writes, writes);
    expect(external.starts, 1);
  });

  test('zwei MCP-Sitzungen sehen dieselben Vorgänge', () async {
    final other = _Client(profile.port);
    addTearDown(() => other.http.close(force: true));
    await other.initialize();
    await other.tool('sicherung_status', {});
    external.progress = {'unexpected': true};
    final started = await client.tool('wiederherstellen_datei', arguments);
    final number = RegExp(r'Nummer ([a-z0-9]+)').firstMatch(started)!.group(1)!;
    final status = await other.tool('wiederherstellung_status', {'id': number});
    expect(status, contains(number));
    expect(status, isNot(contains('Keine Wiederherstellung')));
  });

  test('ein anderes Zielprofil darf einen fremden Vorgang weder abfragen noch gegenlesen', () async {
    external.progress = {'unexpected': true};
    final started = await client.tool('wiederherstellen_datei', arguments);
    final number = RegExp(r'Nummer ([a-z0-9]+)').firstMatch(started)!.group(1)!;
    await service.stoppen();
    client.http.close(force: true);
    profile = Profil(
      kennung: 'anderes',
      name: 'Anderes Profil',
      adresse: external.basis.toString(),
      port: profile.port,
      mcpName: 'anderes',
    );
    await startService();
    external.progress = {'progress': 1, 'status': 1000};
    external.completed = true;
    final reads = external.progressReads;
    final writes = external.writes;
    final status = await client.tool('wiederherstellung_status', {'id': number});
    expect(status, contains('Keine Wiederherstellung'));
    expect(external.progressReads, reads);
    expect(external.writes, writes);
  });

  test('Quellfragen bleiben für den Vergleich nach Neustart und erneutem Status erhalten', () async {
    writeArchive(quiz: true);
    external.progress = {'unexpected': true};
    final started = await client.tool('wiederherstellen_datei', arguments);
    final number = RegExp(r'Nummer ([a-z0-9]+)').firstMatch(started)!.group(1)!;
    await service.stoppen();
    client.http.close(force: true);
    await startService();
    external.progress = {'progress': 1, 'status': 1000};
    external.completed = true;
    final status = await client.tool('wiederherstellung_status', {'id': number});
    expect(status, contains('Fragenzahl und Fragennamen stimmen mit der Quelle überein (1)'));
    expect(status, contains('Fragenherkunft nicht bestätigt'));
    final again = await client.tool('wiederherstellung_status', {'id': number});
    expect(again, contains('Fragenzahl und Fragennamen stimmen mit der Quelle überein (1)'));
    expect(external.starts, 1);
  });

  test('kollidierende Sachnummern in einer Zielsammlung bestätigen keine Quellherkunft', () async {
    writeArchive(quiz: true);
    external.progress = {'progress': 1, 'status': 1000};
    approvals.stufe = Bestaetigungen.mittel;
    String? approval;
    approvals.addListener(() {
      final current = approvals.aktuell;
      if (current == null) return;
      approval = current.punkte.join(' ');
      scheduleMicrotask(() {
        external.completed = true;
        approvals.entscheiden(true);
      });
    });
    final result = await client.tool('wiederherstellen_datei', {...arguments, 'sammlung': 90});
    expect(approval, contains('keine eigene Quellherkunft'));
    expect(result, contains('Fragenherkunft nicht bestätigt'));
    expect(result, isNot(contains('verborgen: verified')));
  });

  test('Sicherung: Zeitlimit und Neustart erlauben spätere Dateiabholung ohne neuen Start', () async {
    external.hold = Completer<void>();
    final started = await client.tool('sichern_auswahl', {
      'kurs': 12,
      'name_des_kurses': 'ZZ Kurs',
      'ganzer_kurs': true,
    });
    expect(external.backupStarts, 1, reason: started);
    final number = RegExp(r'Nummer ([a-z0-9]+)').firstMatch(started)!.group(1)!;
    expect(started, contains('sicherung_status'));
    external.progress = {'unexpected': true};
    external.hold!.complete();
    external.hold = null;
    await client.waitStatus('sicherung_status', number, (t) => t.contains('Unklar'));
    await service.stoppen();
    client.http.close(force: true);
    await startService();
    external.progress = {'progress': 1, 'status': 1000};
    external.hold = Completer<void>();
    final waiting = await client.tool('sicherung_status', {'id': number});
    expect(waiting, contains(number));
    expect(waiting, contains('sicherung_status'));
    external.hold!.complete();
    external.hold = null;
    final result = await client.waitStatus('sicherung_status', number, (t) => t.contains('fertig'));
    expect(result, contains('fertig'));
    expect(result, contains('verified'));
    expect(external.backupStarts, 1);
    expect(external.downloads, 1);
    final downloaded = folder.listSync().whereType<File>().singleWhere((f) => p.basename(f.path).startsWith('kurs-'));
    expect(await downloaded.readAsBytes(), _Moodle.backupBytes);
    await client.tool('sicherung_status', {'id': number});
    expect(external.downloads, 1);
  });

  test('Altvorgänge sperren nach Umbenennung und dürfen ohne Profilbindung kein Moodle abfragen', () async {
    final legacy = Vorgaenge(folder.path);
    final bytes = await File(p.join(folder.path, 'test.mbz')).readAsBytes();
    final old = await legacy.neuWiederherstellung(
      kurs: 12,
      datei: 'test.mbz',
      fingerabdruck: fingerabdruck(
        bytes,
        instanz: 'Alter Anzeigename',
        kurs: 12,
        weg: Zielweg.aktuellerKursVerschmelzen,
      ),
    );
    await legacy.aktualisieren(
      old,
      wiederherstellung: WiederherstellungStand.laufend,
      backupid: _Moodle.restore,
      kontext: 55,
    );
    final reads = external.progressReads;
    final status = await client.tool('wiederherstellung_status', {'id': old.id});
    expect(status, contains('Keine Wiederherstellung'));
    final duplicate = await client.tool('wiederherstellen_datei', arguments);
    expect(duplicate, contains(old.id));
    final repeat = await client.tool('wiederherstellen_datei', {...arguments, 'wiederholung_von': old.id});
    expect(repeat, contains('keine sichere Profilbindung'));
    expect(external.progressReads, reads);
    expect(external.starts, 0);
    expect(external.writes, 0);
  });

  test('Sicherung: Fehler vor 100 Prozent und unbekannter Status werden über MCP gemeldet', () async {
    for (final progress in [
      {'progress': 0.2, 'error': 'failed'},
      {'unexpected': true},
    ]) {
      external.progress = progress;
      final started = await client.tool('sichern_auswahl', {
        'kurs': 12,
        'name_des_kurses': 'ZZ Kurs',
        'ganzer_kurs': true,
      });
      final number = RegExp(r'Nummer ([a-z0-9]+)').firstMatch(started)!.group(1)!;
      expect(started, contains(progress.containsKey('error') ? 'fehlgeschlagen' : 'Unklar'));
      expect(started, isNot(contains('verified: true')));
      expect(external.downloads, 0);
      final result = await client.tool('sicherung_status', {'id': number});
      expect(result, contains(progress.containsKey('error') ? 'fehlgeschlagen' : 'Unklar'));
    }
  });

  test('Sicherung: fremde und ungebundene Altvorgänge bleiben ohne Moodle-Zugriff', () async {
    for (final owner in ['fremd', null, profile.kennung]) {
      final store = Vorgaenge(folder.path, profilKennung: owner);
      final old = await store.neu(kurs: 12, cmid: 1, datei: 'old.mbz');
      await store.aktualisieren(old, stand: SicherungStand.laufend, backupid: _Moodle.restore, kontext: 55);
      final result = await client.tool('sicherung_status', {'id': old.id});
      expect(result, contains('Keine Sicherung'));
    }
    final overview = await client.tool('sicherung_status', {});
    expect(overview, 'Noch keine Sicherung.');
    expect(external.progressReads, 0);
    expect(external.downloads, 0);
  });

  test('Sicherung und Wiederherstellung melden Stillstand mit Nummer statt Fehler oder Erfolg', () async {
    final now = DateTime(2026, 10, 19, 10);
    jetzt = () => now;
    addTearDown(() => jetzt = DateTime.now);
    final store = Vorgaenge(folder.path, profilKennung: profile.kennung, instanzBasis: () => external.basis);
    final backup = await store.neu(kurs: 12, cmid: 1, datei: 'old.mbz');
    final restore = await store.neuWiederherstellung(kurs: 12, datei: 'test.mbz');
    await store.aktualisieren(
      backup,
      stand: SicherungStand.laufend,
      backupid: _Moodle.restore,
      kontext: 55,
      fortschritt: 0.2,
      fortschrittSeit: now.subtract(const Duration(minutes: 16)),
    );
    await store.aktualisieren(
      restore,
      wiederherstellung: WiederherstellungStand.laufend,
      backupid: _Moodle.restore,
      kontext: 55,
      fortschritt: 0.2,
      fortschrittSeit: now.subtract(const Duration(minutes: 16)),
    );
    for (final pair in [('sicherung_status', backup.id), ('wiederherstellung_status', restore.id)]) {
      final result = await client.tool(pair.$1, {'id': pair.$2});
      expect(result, contains('Stillstand'));
      expect(result, contains(pair.$1));
      expect(result, contains(pair.$2));
      expect(result, isNot(contains('fehlgeschlagen')));
      expect(result, isNot(contains('verified')));
    }
    expect(external.starts, 0);
    expect(external.backupStarts, 0);
    expect(external.writes, 0);
  });
  test('später Abfragefehler nach MCP-Zeitlimit bleibt als unklarer Vorgang gesperrt', () async {
    external.hold = Completer<void>();
    final started = await client.tool('wiederherstellen_datei', arguments);
    final number = RegExp(r'Nummer ([a-z0-9]+)').firstMatch(started)!.group(1)!;
    external.failProgress = true;
    external.hold!.complete();
    external.hold = null;
    var overview = '';
    for (var i = 0; i < 100; i++) {
      overview = await client.tool('sicherung_status', {});
      if (overview.contains('unklar')) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(overview, contains('unklar'));
    expect(overview, contains('wiederherstellung_status $number'));
    await service.stoppen();
    client.http.close(force: true);
    await startService();
    final duplicate = await client.tool('wiederherstellen_datei', arguments);
    expect(duplicate, contains(number));
    expect(external.starts, 1);
  });
  for (final otherInstallationPath in [false, true]) {
    test(
      'gleiche Profilkennung schützt alte Vorgänge nach Wechsel ${otherInstallationPath ? 'des Installationspfads' : 'der Moodle-Instanz'}',
      () async {
        external.progress = {'unexpected': true};
        final restored = await client.tool('wiederherstellen_datei', arguments);
        final restoreId = RegExp(r'Nummer ([a-z0-9]+)').firstMatch(restored)!.group(1)!;
        final backed = await client.tool('sichern_auswahl', {
          'kurs': 12,
          'name_des_kurses': 'ZZ Kurs',
          'ganzer_kurs': true,
        });
        final backupId = RegExp(r'Nummer ([a-z0-9]+)').firstMatch(backed)!.group(1)!;
        await service.stoppen();
        client.http.close(force: true);
        final target = otherInstallationPath ? external : _Moodle();
        if (!otherInstallationPath) {
          await target.start();
          addTearDown(() => target.server.close(force: true));
        }
        final newAddress = target.basis.replace(path: otherInstallationPath ? '/anderes-moodle' : '');
        profile = profile.copyWith(adresse: newAddress.toString());
        moodle = await MoodleZugang.fuerTest(Protokoll(), newAddress, benutzer: 'e.mustermann', passwort: 'test');
        await startService();
        target.progress = {'progress': 1, 'status': 1000};
        target.completed = true;
        final requests = target.requests;
        expect(await client.tool('wiederherstellung_status', {'id': restoreId}), contains('Keine Wiederherstellung'));
        expect(await client.tool('sicherung_status', {'id': backupId}), contains('Keine Sicherung'));
        expect(await client.tool('sicherung_status', {}), 'Noch keine Sicherung.');
        expect(target.requests, requests, reason: 'Die lokale Instanzbindung muss vor jeder Moodle-Anfrage greifen.');
      },
    );
  }
  for (final restart in [false, true]) {
    test(
      'ausgetauschtes Quellarchiv wird ${restart ? 'nach Neustart' : 'während des Hintergrundlaufs'} nie verifiziert',
      () async {
        writeArchive(image: true);
        external.progress = {'unexpected': true};
        if (!restart) external.hold = Completer<void>();
        final started = await client.tool('wiederherstellen_datei', arguments);
        final number = RegExp(r'Nummer ([a-z0-9]+)').firstMatch(started)!.group(1)!;
        writeArchive();
        external.completed = true;
        external.progress = {'progress': 1, 'status': 1000};
        if (restart) {
          await service.stoppen();
          client.http.close(force: true);
          await startService();
        } else {
          external.hold!.complete();
          external.hold = null;
        }
        final status = await client.waitStatus('wiederherstellung_status', number, (text) => text.contains('fertig'));
        expect(status, contains('Prüflücke'));
        expect(status, contains('Quellaufnahme'));
        final overview = await client.tool('sicherung_status', {});
        expect(overview, contains('verified: false'));
        expect(external.starts, 1);
      },
    );
  }
  test('fehlender Start-Inhalts-Hash bleibt bei Anhangprüfung eine ausdrückliche Prüflücke', () async {
    final store = Vorgaenge(folder.path, profilKennung: profile.kennung, instanzBasis: () => external.basis);
    final old = await store.neuWiederherstellung(kurs: 12, datei: 'test.mbz');
    await store.aktualisieren(
      old,
      wiederherstellung: WiederherstellungStand.laufend,
      backupid: _Moodle.restore,
      kontext: 55,
      vorherCmids: [],
      wiederherstellungAktivitaeten: [(modul: 'page', titel: 'ZZ Blatt')],
    );
    external.completed = true;
    external.progress = {'progress': 1, 'status': 1000};
    final result = await client.tool('wiederherstellung_status', {'id': old.id});
    expect(result, contains('Inhalts-Hash fehlt'));
    expect(result, contains('Prüflücke'));
    expect(await client.tool('sicherung_status', {}), contains('verified: false'));
  });
}
