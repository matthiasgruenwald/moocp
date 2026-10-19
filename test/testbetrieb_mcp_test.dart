import 'dart:async';
// Öffentliche MCP-Aufrufe; ausschließlich Moodle ist ein lokaler HTTP-Server.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/einstellungen.dart';
import 'package:moocp/freigabe.dart';
import 'package:moocp/mcp/mcp_dienst.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/profil.dart';
import 'package:moocp/protokoll.dart';
import 'package:moocp/testzugang.dart';

import 'mcp_client.dart';

class TestMoodle {
  late HttpServer server;
  bool vorhanden = false;
  Completer<void>? wartet;
  Completer<void>? fortsetzen;
  String name = 'ZZ Probe';
  String inhalt = '<h3>ZZ Probe</h3><p>Vorher</p>';
  int objektKurs = 12;
  bool lernlandkarteVorhanden = false;
  int lernlandkarteSpeicherungen = 0;
  String placestore =
      '{"places":[{"id":"p1","linkedActivity":70}],"paths":[{"id":"w1","from":"p1","to":"p1"}],"startingplaces":["p1"],"targetplaces":[]}';
  Uri get basis => Uri.parse('http://127.0.0.1:${server.port}');
  String seite(String text) =>
      '<script>M.cfg = {"sesskey":"sk","courseId":12,"contextid":"55"};</script>$text';
  Future<void> starten() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final body = await utf8.decoder.bind(r).join();
      String antwort;
      if (r.uri.path == '/login/index.php') {
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
      } else if (r.uri.path == '/lib/ajax/service.php') {
        final call = (jsonDecode(body) as List).single as Map;
        if (call['methodname'] == 'core_courseformat_get_state' &&
            wartet != null &&
            !wartet!.isCompleted) {
          wartet!.complete();
          await fortsetzen!.future;
        }
        final data = switch (call['methodname']) {
          'core_course_get_enrolled_courses_by_timeline_classification' => {
            'courses': [
              {'id': 12, 'fullname': 'ZZ Kurs', 'shortname': 'ZZ'},
            ],
          },
          'core_courseformat_get_state' => {
            'section': [
              {
                'id': 1,
                'number': 0,
                'title': 'Allgemeines',
                'visible': 1,
                'cmlist': [
                  if (vorhanden || lernlandkarteVorhanden) 70,
                  if (lernlandkarteVorhanden) 71,
                  if (lernlandkarteVorhanden) 72,
                ],
              },
            ],
            'cm': [
              if (vorhanden || lernlandkarteVorhanden)
                {
                  'id': 70,
                  'module': 'page',
                  'name': lernlandkarteVorhanden ? 'ZZ Ziel' : name,
                  'visible': 0,
                  'sectionid': 1,
                },
              if (lernlandkarteVorhanden) ...[
                {
                  'id': 71,
                  'module': 'learningmap',
                  'name': 'ZZ Karte',
                  'visible': 0,
                  'sectionid': 1,
                },
                {
                  'id': 72,
                  'module': 'page',
                  'name': 'ZZ Ziel',
                  'visible': 0,
                  'sectionid': 1,
                },
              ],
            ],
          },
          'core_courseformat_update_course' => () {
            vorhanden = false;
            return <String, Object?>{};
          }(),
          _ => throw StateError('Unerwarteter Moodle-Dienst'),
        };
        antwort = jsonEncode([
          {'error': false, 'data': data},
        ]);
      } else if (r.uri.path == '/course/modedit.php') {
        if (r.method == 'POST') {
          final f = Uri.splitQueryString(body);
          if (f['modulename'] == 'learningmap') {
            placestore = f['placestore']!;
            lernlandkarteSpeicherungen++;
            r.response.redirect(
              Uri.parse('/course/modedit.php?update=71'),
              status: 303,
            );
            await r.response.close();
            return;
          }
          vorhanden = true;
          name = f['name']!;
          inhalt = f['page[text]']!;
          r.response.redirect(
            Uri.parse('/mod/page/view.php?id=70'),
            status: 303,
          );
          await r.response.close();
          return;
        }
        if (r.uri.queryParameters['update'] == '71') {
          antwort = seite(
            '''<form class="mform" action="/course/modedit.php" method="post">
          <input name="_qf__mod_learningmap_mod_form" value="1"><input name="sesskey" value="sk">
          <input name="course" value="12"><input name="update" value="71">
          <input name="modulename" value="learningmap"><input name="name" value="ZZ Karte">
          <textarea name="svgcode">&lt;svg&gt;&lt;circle id="p1"/&gt;&lt;/svg&gt;</textarea>
          <input type="hidden" name="placestore" value='${const HtmlEscape().convert(placestore)}'>
          <input type="submit" name="submitbutton" value="Speichern"></form>''',
          );
        } else {
          antwort = seite(
            '''<form class="mform" action="/course/modedit.php" method="post">
          <input name="_qf__mod_page_mod_form" value="1"><input name="sesskey" value="sk"><input name="course" value="$objektKurs">
          <input name="modulename" value="page"><input name="name" value="$name">
          <select name="visible"><option value="0" selected>Verborgen</option><option value="1">Sichtbar</option></select>
          <textarea name="page[text]">${const HtmlEscape().convert(inhalt)}</textarea>
          <input name="page[format]" value="1"><input name="page[itemid]" value="9">
          <input type="submit" name="submitbutton" value="Speichern"></form>''',
          );
        }
      } else if (r.uri.path == '/mod/page/view.php') {
        antwort = seite(
          '<p>Außerhalb des Inhalts</p><main id="region-main"><div class="generalbox center">$inhalt</div></main>',
        );
      } else {
        antwort = seite('ZZ Kurs');
      }
      r.response.headers.contentType = ContentType.html;
      r.response.write(antwort);
      await r.response.close();
    });
  }
}

void main() {
  late TestMoodle extern;
  late Directory ordner;
  late McpDienst dienst;
  late McpTestClient client;
  late Freigaben freigaben;
  late MoodleZugang moodle;
  late Profil profil;
  Future<void> starten({
    String? kennung,
    String? adresse,
    Set<int> kurse = const {12},
    bool bilder = true,
  }) async {
    final port = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    profil = Profil(
      kennung: 'test',
      name: 'Test',
      adresse: extern.basis.toString(),
      port: port.port,
      mcpName: 'test',
    );
    await port.close();
    dienst = McpDienst(
      Einstellungen(schluessel: 'test'),
      moodle,
      Protokoll(),
      freigaben,
      ordner.path,
      profil: profil,
      testzugang: Testzugang(
        kennung: kennung ?? 'test',
        datei: 'unused.env',
        adresse: adresse ?? profil.adresse,
        kurse: kurse,
        bilder: bilder,
      ),
    );
    await dienst.starten();
    client = McpTestClient(profil.port);
    await client.initialize();
  }

  Future<String> anlegen({int kurs = 12, String name = 'ZZ Probe'}) =>
      client.tool('aktivitaet_anlegen', {
        'kurs': kurs,
        'abschnitt_id': 1,
        'typ': 'page',
        'name': name,
        'ordner': 'entwurf',
      });
  setUp(() async {
    extern = TestMoodle();
    await extern.starten();
    ordner = await Directory.systemTemp.createTemp('moocp-testbetrieb-');
    await Directory('${ordner.path}/entwurf').create();
    await File('${ordner.path}/entwurf/page.html').writeAsString(extern.inhalt);
    freigaben = Freigaben(
      Protokoll(),
      stufe: Bestaetigungen.alle,
      frist: const Duration(milliseconds: 150),
    );
    moodle = await MoodleZugang.fuerTest(
      Protokoll(),
      extern.basis,
      benutzer: 'e.mustermann',
      passwort: 'erfunden',
    );
  });
  tearDown(() async {
    client.http.close(force: true);
    await dienst.stoppen();
    moodle.abmelden();
    await extern.server.close(force: true);
    await ordner.delete(recursive: true);
  });

  test('eigene ZZ-Textseite wird über MCP angelegt, geändert, zurückgelesen und aufgeräumt', () async {
    await starten();
    expect(await anlegen(), contains('verified: true'));
    await File('${ordner.path}/cm-70/page.html')
        .writeAsString('<h3>ZZ Probe</h3><p>Nachher</p>');
    expect(
      await client.tool('aendern', {'ordner': 'cm-70'}),
      contains('verified: true'),
    );
    expect(
      await client.tool('aktivitaet_lesen', {'cmid': 70}),
      contains('Gelesen: ZZ Probe'),
    );
    expect(
      await File('${ordner.path}/cm-70/page.html').readAsString(),
      contains('Nachher'),
    );
    expect(
      await client.tool('loeschen', {
        'kurs': 12,
        'cmid': 70,
        'name': 'ZZ Probe',
      }),
      contains('verified: true'),
    );
    expect(
      await client.tool('kurs_uebersicht', {'kurs': 12}),
      isNot(contains('ZZ Probe')),
    );
  });

  test('Lernlandkarte wird über MCP gelesen, ein Ziel freigegeben geschrieben und zurückgelesen', () async {
    extern.lernlandkarteVorhanden = true;
    freigaben.stufe = Bestaetigungen.keine;
    await starten();
    final gelesen = await client.tool('aktivitaet_lesen', {'cmid': 71});
    expect(gelesen, contains('Ort p1'));
    expect(gelesen, contains('Aktivität 70'));
    final geschrieben = await client.tool(
      'lernlandkarte_verknuepfungen_setzen',
      {
        'cmid': 71,
        'name': 'ZZ Karte',
        'zuordnungen': [
          {'ort': 'p1', 'aktuell': 70, 'ziel': 72},
        ],
      },
    );
    expect(geschrieben, contains('verified: true'));
    expect(
      (jsonDecode(extern.placestore) as Map)['places'][0]['linkedActivity'],
      72,
    );
    final stale = await client.tool('lernlandkarte_verknuepfungen_setzen', {
      'cmid': 71,
      'name': 'ZZ Karte',
      'zuordnungen': [
        {'ort': 'p1', 'aktuell': 70, 'ziel': 70},
      ],
    });
    expect(stale, contains('seit dem Lesen anders'));
    expect((jsonDecode(extern.placestore) as Map)['paths'], isNotEmpty);
  });

  test(
    'fehlendes Ziel und abgelehnte Freigabe ändern die Karte nicht',
    () async {
      extern.lernlandkarteVorhanden = true;
      await starten();
      final fehlend = await client.tool('lernlandkarte_verknuepfungen_setzen', {
        'cmid': 71,
        'name': 'ZZ Karte',
        'zuordnungen': [
          {'ort': 'p1', 'aktuell': 70, 'ziel': 999},
        ],
      });
      expect(fehlend, contains('keine vorhandene Aktivität'));

      final angefragt = Completer<void>();
      void listener() {
        if (freigaben.aktuell?.titel == 'Lernlandkarte ändern?' &&
            !angefragt.isCompleted) {
          angefragt.complete();
        }
      }

      freigaben.addListener(listener);
      final aufruf = client.tool('lernlandkarte_verknuepfungen_setzen', {
        'cmid': 71,
        'name': 'ZZ Karte',
        'zuordnungen': [
          {'ort': 'p1', 'aktuell': 70, 'ziel': 72},
        ],
      });
      await angefragt.future.timeout(const Duration(seconds: 2));
      freigaben.entscheiden(false);
      expect(await aufruf, contains('nicht freigegeben'));
      freigaben.removeListener(listener);
      expect(extern.lernlandkarteSpeicherungen, 0);
      expect(
        (jsonDecode(extern.placestore) as Map)['places'][0]['linkedActivity'],
        70,
      );
    },
  );
  for (final fall in ['Profil', 'Adresse', 'Kurs', 'Name']) {
    test('falscher $fall erhält keine automatische Schreibfreigabe', () async {
      await starten(
        kennung: fall == 'Profil' ? 'fremd' : null,
        adresse: fall == 'Adresse' ? 'https://fremd.schule.example' : null,
        kurse: fall == 'Kurs' ? {34} : {12},
      );
      expect(
        await anlegen(name: fall == 'Name' ? 'Fremde Seite' : 'ZZ Probe'),
        contains('Nicht angelegt'),
      );
      expect(
        await client.tool('kurs_uebersicht', {'kurs': 12}),
        isNot(contains('cmid 70')),
      );
      expect(freigaben.testfreigaben, 0);
    });
  }

  test('vorhandene fremde ZZ-Seite wird nicht automatisch gelöscht', () async {
    extern.vorhanden = true;
    await starten();
    expect(
      await client.tool('loeschen', {
        'kurs': 12,
        'cmid': 70,
        'name': 'ZZ Probe',
      }),
      contains('Nicht gelöscht'),
    );
    expect(
      await client.tool('kurs_uebersicht', {'kurs': 12}),
      contains('ZZ Probe'),
    );
    expect(freigaben.testfreigaben, 0);
  });

  for (final fall in ['Inhalt', 'Kurs', 'Name']) {
    test(
      'nachträglich fremder $fall hebt die automatische Objektfreigabe auf',
      () async {
        await starten();
        expect(await anlegen(), contains('verified: true'));
        switch (fall) {
          case 'Inhalt':
            extern.inhalt = '<p>Fremder Inhalt</p>';
          case 'Kurs':
            extern.objektKurs = 34;
          case 'Name':
            extern.name = 'ZZ Fremd';
        }
        expect(
          await client.tool('loeschen', {
            'kurs': 12,
            'cmid': 70,
            'name': extern.name,
          }),
          contains('Nicht gelöscht'),
        );
        expect(
          await client.tool('kurs_uebersicht', {'kurs': 12}),
          contains(extern.name),
        );
        expect(
          freigaben.testfreigaben,
          1,
          reason: 'Nur das Anlegen war automatisch freigegeben',
        );
      },
    );
  }
  test(
    'MCP-Abbruch während der Vorprüfung erzeugt keine automatische Probe',
    () async {
      await starten();
      extern.wartet = Completer<void>();
      extern.fortsetzen = Completer<void>();
      final beendet = Completer<void>();
      void protokollGeaendert() {
        if (!beendet.isCompleted &&
            freigaben.protokoll.eintraege.any(
              (e) => e.text == 'Die KI wartet nicht mehr -- nicht gespeichert',
            )) {
          beendet.complete();
        }
      }

      freigaben.protokoll.addListener(protokollGeaendert);
      // Nach MCP-Abbruch gibt es keine Antwort mehr. Der echte Protokolleintrag
      // synchronisiert nur das Ende; das Ergebnis prüfen wir erneut über MCP.
      final verworfen = anlegen().then<void>(
        (_) {},
        onError: (Object e) {
          if (e is! HttpException && e is! SocketException) throw e;
        },
      );
      await extern.wartet!.future;
      await client.notification('notifications/cancelled', {
        'requestId': client.id,
        'reason': 'Testabbruch',
      });
      extern.fortsetzen!.complete();
      await beendet.future;
      freigaben.protokoll.removeListener(protokollGeaendert);
      expect(
        await client.tool('kurs_uebersicht', {'kurs': 12}),
        isNot(contains('ZZ Probe')),
      );
      expect(freigaben.testfreigaben, 0);
      client.http.close(force: true);
      await verworfen;
    },
  );
}
