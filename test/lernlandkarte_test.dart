// Ticket #23 (Spec #17): Lernlandkarte-Verknüpfungen prüfbar machen oder die
// Prüflücke melden. Gelesen wird über den Weg des Werkzeugs aktivitaet_lesen
// (formularLesen); geändert über aendern. Die Moodle-Grenze ist ein lokales
// Test-Doppel auf 127.0.0.1, der Arbeitsordner ein Temp-Verzeichnis.
//
// Die Feldstruktur stammt aus mod_learningmap 0.9.16, Commit
// c8c61bba1266a1f4126b71adefc371612d379dd4 (mod_form.php und activityselector.mustache):
// https://github.com/bycs-lp/mod_learningmap/tree/c8c61bba1266a1f4126b71adefc371612d379dd4
// Eigenständig aufgebautes HTML mit Musterdaten, kein Plugin-Code und kein Live-Dump.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:moocp/freigabe.dart';
import 'package:moocp/moodle/formular_lesen.dart';
import 'package:moocp/moodle/formular_schreiben.dart';
import 'package:moocp/moodle/lernlandkarte.dart';
import 'package:moocp/moodle/lernlandkarte_entwurf.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/protokoll.dart';
import 'package:path/path.dart' as p;

/// Ein Moodle-Doppel: Anmeldung, zwei Bearbeitungsformulare (ein nicht
/// schreibbarer Typ mit Verknüpfungen, eine Textseite) und 404 für alles
/// übrige. Jede POST-Anfrage an modedit.php wird gezählt.
class _Doppel {
  late HttpServer _server;
  final Set<String> _angemeldet = {};
  int _zaehler = 0;

  /// Anfragen, die Moodle als Speichern eines Formulars erhalten hat.
  final List<String> speichern = [];

  /// Moodle speichert `linkedActivity` je nach Weg als Zahl oder als Text.
  bool zielAlsText = false;

  static const benutzer = 'e.mustermann';
  static const passwort = 'test-geheim-23';
  static const sesskey = 'sk23';

  /// Die tatsächlichen Feldarten: editor-Beschreibung, rohe SVG-Textarea,
  /// verborgenes placestore-JSON und ein Auswahlfeld ohne Namen.
  /// Verweise sind absolut mit der Instanzadresse, so wie Moodle sie speichert.
  String get karte => _karte.replaceAll(
    '"linkedActivity":101',
    zielAlsText ? '"linkedActivity":"101"' : '"linkedActivity":101',
  );

  String get _karte =>
      '''<form class="mform" method="post" action="/course/modedit.php">
<input type="hidden" name="sesskey" value="$sesskey">
<input type="hidden" name="modulename" value="learningmap">
<input type="hidden" name="course" value="12">
<input type="hidden" name="update" value="31">
<div id="fitem_id_name" class="mb-3 row fitem"><div class="col-md-3 col-form-label"><label for="id_name">Name</label></div>
<div class="col-md-9 felement" data-fieldtype="text"><input type="text" name="name" id="id_name" value="ZZ Karte"></div></div>
<div id="fitem_id_intro" class="mb-3 row fitem"><div class="col-md-3 col-form-label"><p>Beschreibung</p></div>
<div class="col-md-9 felement" data-fieldtype="editor"><textarea name="introeditor[text]"><p>Start: <a href="$basis/mod/page/view.php?id=101">ZZ Seite</a> und <a href="$basis/mod/page/view.php?id=404">ZZ Fehlt</a></p></textarea></div></div>
<div id="fitem_id_svgcode" class="mb-3 row fitem"><div class="col-md-9 felement" data-fieldtype="textarea">
<textarea name="svgcode" id="id_svgcode">&lt;svg xmlns="http://www.w3.org/2000/svg"&gt;&lt;circle id="p1"/&gt;&lt;/svg&gt;</textarea></div></div>
<input type="hidden" name="placestore" value='{ "places": [{"id":"p1","linkId":"a1","linkedActivity":101,"placecolor":null,"visitedcolor":null}], "paths":[], "startingplaces":["p1"], "targetplaces":[] }'>
<select id="learningmap-activity-selector"><option value="0">(keine)</option><option value="101" selected>ZZ Seite</option></select>
</form>''';

  /// Eine Textseite im selben Kurs, zum Gegenbeweis: kein Prüflücke-Hinweis.
  static const seite =
      '''<form class="mform" method="post" action="/course/modedit.php">
<input type="hidden" name="sesskey" value="$sesskey">
<input type="hidden" name="modulename" value="page">
<input type="hidden" name="course" value="12">
<input type="hidden" name="update" value="101">
<div id="fitem_id_name" class="mb-3 row fitem"><div class="col-md-9 felement" data-fieldtype="text"><input type="text" name="name" id="id_name" value="ZZ Seite"></div></div>
<div id="fitem_id_intro" class="mb-3 row fitem"><div class="col-md-9 felement" data-fieldtype="editor"><textarea name="page[text]"><p>ZZ Text</p></textarea></div></div>
</form>''';

  Uri get basis => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> starten() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_antworte);
  }

  Future<void> stoppen() => _server.close(force: true);

  String _seite(String body) =>
      '<html><body><script>M.cfg = {"sesskey":"$sesskey","courseId":12,"contextid":"55"};</script>$body</body></html>';

  Future<void> _antworte(HttpRequest r) async {
    final sitzung = r.cookies.where((c) => c.name == 'MoodleSession');
    final id = sitzung.isEmpty ? null : sitzung.first.value;
    final eingeloggt = id != null && _angemeldet.contains(id);
    final pfad = r.uri.path;

    if (pfad == '/login/index.php' && r.method == 'GET') {
      if (r.uri.queryParameters.containsKey('testsession')) {
        return _umleiten(r, eingeloggt ? '/my/' : '/login/index.php');
      }
      r.response.cookies.add(Cookie('MoodleSession', 's${_zaehler++}'));
      return _text(r, '<form><input name="logintoken" value="tok"></form>');
    }
    if (pfad == '/login/index.php' && r.method == 'POST') {
      final f = Uri.splitQueryString(await utf8.decoder.bind(r).join());
      if (id != null &&
          f['username'] == benutzer &&
          f['password'] == passwort &&
          f['logintoken'] == 'tok') {
        _angemeldet.add(id);
        return _umleiten(r, '/login/index.php?testsession=1');
      }
      return _umleiten(r, '/login/index.php');
    }
    if (!eingeloggt) return _umleiten(r, '/login/index.php');
    if (pfad == '/course/modedit.php' && r.method == 'POST') {
      speichern.add(r.uri.query);
      return _text(r, _seite('<p>gespeichert</p>'));
    }
    if (pfad == '/course/modedit.php' && r.method == 'GET') {
      final ziel = r.uri.queryParameters['update'];
      if (ziel == '31') return _text(r, _seite(karte));
      if (ziel == '101') return _text(r, _seite(seite));
      return _text(r, 'nicht gefunden', status: HttpStatus.notFound);
    }
    return _text(r, 'nicht gefunden', status: HttpStatus.notFound);
  }

  Future<void> _umleiten(HttpRequest r, String ziel) async {
    r.response.redirect(Uri.parse(ziel), status: HttpStatus.seeOther);
    await r.response.close();
  }

  Future<void> _text(
    HttpRequest r,
    String body, {
    int status = HttpStatus.ok,
  }) async {
    r.response
      ..statusCode = status
      ..headers.contentType = ContentType.html
      ..write(body);
    await r.response.close();
  }
}

void main() {
  late _Doppel doppel;
  late Directory arbeitsordner;
  late MoodleZugang zugang;

  setUp(() async {
    doppel = _Doppel();
    await doppel.starten();
    arbeitsordner = Directory.systemTemp.createTempSync('ticket23-');
    zugang = await MoodleZugang.fuerTest(
      Protokoll(),
      doppel.basis,
      benutzer: _Doppel.benutzer,
      passwort: _Doppel.passwort,
    );
  });

  tearDown(() async {
    await doppel.stoppen();
    if (arbeitsordner.existsSync()) arbeitsordner.deleteSync(recursive: true);
  });

  test('Lernlandkarte: Orte, Wege und vorhandene Verknüpfungen werden lesbar ausgewertet', () async {
    final g = await formularLesen(
      zugang,
      Formularziel.aktivitaet(31),
      arbeitsordner.path,
    );
    final text = g.zusammenfassung();

    // Erhaltenes Ziel im Kurs: mit Titel geprüft.
    expect(text, contains('cm 101'));
    expect(text, contains('ZZ Seite'));
    // Nicht abrufbares Ziel: ausdrücklich nicht geprüft, kein stiller Erfolg.
    expect(text, contains('Titel nicht geprüft für Verweise auf cm 404'));
    expect(text, contains('Lernlandkarte'));
    expect(text, contains('Ort p1'));
    expect(text, contains('Aktivität 101'));
    expect(text, contains('Startort'));
    expect(text, contains('Titel nicht geprüft für Verweise auf cm 404'));
    final karte = jsonDecode(
      File(p.join(arbeitsordner.path, 'cm-31', 'lernlandkarte.json'))
          .readAsStringSync(),
    ) as Map;
    expect(karte['svgcode'], contains('<circle id="p1"/>'));
    expect((karte['orte'] as List).single['linkedActivity'], 101);
  });

  test('Lernlandkarte: ein als Text gespeichertes Ortsziel wird wie eine Zahl gelesen', () async {
    doppel.zielAlsText = true;
    final g = await formularLesen(
      zugang,
      Formularziel.aktivitaet(31),
      arbeitsordner.path,
    );
    final text = g.zusammenfassung();
    expect(text, contains('Aktivität 101'));
    expect(text, contains('ZZ Seite'));
    expect(ortsziel('101'), 101);
    expect(ortsziel(' 101 '), 101);
    expect(ortsziel(101), 101);
    expect(ortsziel(101.0), 101);
    expect(ortsziel(''), isNull);
    expect(ortsziel(null), isNull);
    expect(ortsziel({'id': 1}), isNull);
  });

  test('Lesen eines schreibbaren Typs: keine Prüflücke', () async {
    final g = await formularLesen(
      zugang,
      Formularziel.aktivitaet(101),
      arbeitsordner.path,
    );
    expect(g.zusammenfassung(), isNot(contains('Prüflücke')));
  });

  test('unbekanntes placestore-Format meldet nur seine Struktur', () {
    final form = html_parser.parse('''<form>
      <textarea name="svgcode">svg</textarea>
      <input name="placestore" value='{"map":{"places":[]},"version":2}'>
    </form>''').querySelector('form')!;

    expect(
      () => lernlandkarteLesen(form),
      throwsA(
        isA<MoodleFehler>()
            .having(
              (e) => e.meldung,
              'Meldung',
              contains('map:Objekt, version:int'),
            )
            .having((e) => e.meldung, 'Meldung', isNot(contains('[]'))),
      ),
    );
  });

  test('native neue Karte ohne Orte und Wege ist lesbar', () {
    final form = html_parser.parse('''<form>
      <textarea name="svgcode">&lt;svg/&gt;</textarea>
      <input name="placestore" value='{"editmode":true,"mapid":"native-id"}'>
    </form>''').querySelector('form')!;

    final karte = lernlandkarteLesen(form)!;

    expect(karte['orte'], isEmpty);
    expect(karte['wege'], isEmpty);
    expect(karte['startorte'], isEmpty);
    expect(karte['zielorte'], isEmpty);
    expect((karte['placestore'] as Map)['places'], isEmpty);
    expect((karte['placestore'] as Map)['paths'], isEmpty);
    expect(karte['svgcode'], '<svg/>');
  });

  test('native Kartenvorlage erzeugt sichere Orte, Wege und SVG', () {
    final entwurf = lernlandkarteEntwurfErzeugen(
      {
        'orte': [
          {'id': 'p1', 'x': 120, 'y': 280, 'titel': 'Start <eins>'},
          {'id': 'p2', 'x': 880, 'y': 280, 'titel': 'Ziel & Rückblick'},
        ],
        'wege': [
          {'von': 'p1', 'nach': 'p2'},
        ],
      },
      '{"editmode":true,"mapid":"native-id","hidepaths":false}',
    );

    final store = jsonDecode(entwurf.placestore) as Map<String, dynamic>;
    expect(store['mapid'], 'native-id');
    expect(store['editmode'], true);
    expect(store['hidepaths'], false);
    expect(store['startingplaces'], ['p1']);
    expect(store['targetplaces'], isEmpty);
    expect(store['places'], [
      {
        'id': 'p1',
        'linkId': 'a1',
        'linkedActivity': null,
        'placecolor': null,
        'visitedcolor': null,
      },
      {
        'id': 'p2',
        'linkId': 'a2',
        'linkedActivity': null,
        'placecolor': null,
        'visitedcolor': null,
      },
    ]);
    expect(store['paths'], [
      {'id': 'p1_2', 'from': 'p1', 'to': 'p2'},
    ]);
    expect(entwurf.svgcode, contains('id="pathsGroup"'));
    expect(entwurf.svgcode, contains('id="placesGroup"'));
    expect(entwurf.svgcode, contains('Start &lt;eins&gt;'));
    expect(entwurf.svgcode, contains('Ziel &amp; Rückblick'));
    expect(entwurf.svgcode, isNot(contains('<script')));
    expect(
      lernlandkarteSvgVergleichswert(
        '<svg>\n  <g>\n    <circle/>\n  </g>\n</svg>',
      ),
      '<svg><g><circle/></g></svg>',
    );
    expect(
      lernlandkarteSvgVergleichswert('<svg><g id="a"></g><g></g></svg>'),
      lernlandkarteSvgVergleichswert('<svg><g id="a"/><g/></svg>'),
    );
    expect(
      lernlandkarteSvgVergleichswert('<svg><text>a</text></svg>'),
      '<svg><text>a</text></svg>',
    );
  });

  test('Kartenvorlage lehnt fremde IDs und ungültige Wege vor dem Schreiben ab', () {
    expect(
      () => lernlandkarteEntwurfErzeugen(
        {
          'orte': [
            {'id': 'p1', 'x': 100, 'y': 100},
            {'id': 'p2', 'x': 900, 'y': 100},
          ],
          'wege': [
            {'von': 'p1', 'nach': 'other'},
          ],
        },
        '{"editmode":true,"mapid":"native-id"}',
      ),
      throwsA(isA<MoodleFehler>()),
    );
    expect(
      () => lernlandkarteEntwurfErzeugen(
        {
          'orte': [
            {
              'id': 'p1',
              'x': 100,
              'y': 100,
              'linkedActivity': 99,
            },
          ],
          'wege': [],
        },
        '{"editmode":true,"mapid":"native-id"}',
      ),
      throwsA(isA<MoodleFehler>()),
    );
  });

  test('Ortsbeschriftung im SVG zählt beim Verknüpfen nicht, Geometrie schon', () {
    const vorher = '<svg><g><circle id="p1" cx="200"/>'
        '<title id="titlep1">ZZ Ort 1</title>'
        '<text id="textp1" x="200">ZZ Ort 1</text></g></svg>';
    const nachher = '<svg><g><circle id="p1" cx="200"/>'
        '<title id="titlep1">ZZ #31 Ziel Probe</title>'
        '<text id="textp1" x="200">ZZ #31 Ziel Probe</text></g></svg>';
    const verschoben = '<svg><g><circle id="p1" cx="300"/>'
        '<title id="titlep1">ZZ #31 Ziel Probe</title>'
        '<text id="textp1" x="200">ZZ #31 Ziel Probe</text></g></svg>';

    expect(ohneOrtsbeschriftung(nachher), ohneOrtsbeschriftung(vorher));
    expect(ohneOrtsbeschriftung(verschoben), isNot(ohneOrtsbeschriftung(vorher)));
    expect(ohneOrtsbeschriftung(null), isNull);
  });

  test('ungültiges placestore meldet nur Parserposition und Zeichensignatur', () {
    final form = html_parser.parse('''<form>
      <textarea name="svgcode">svg</textarea>
      <input name="placestore" value="private-course-content">
    </form>''').querySelector('form')!;

    expect(
      () => lernlandkarteLesen(form),
      throwsA(
        isA<MoodleFehler>()
            .having((e) => e.meldung, 'Meldung', contains('Parserposition'))
            .having(
              (e) => e.meldung,
              'Meldung',
              isNot(contains('private-course-content')),
            ),
      ),
    );
  });

  test('Ändern eines nicht schreibbaren Typs: nichts wird an Moodle geschickt, der Typ wird genannt', () async {
    await formularLesen(
      zugang,
      Formularziel.aktivitaet(31),
      arbeitsordner.path,
    );
    final datei = File(p.join(arbeitsordner.path, 'cm-31', 'introeditor.html'));
    datei.writeAsStringSync('${datei.readAsStringSync()}<p>ZZ Zusatz</p>');

    await expectLater(
      aendern(
        zugang,
        Freigaben(Protokoll()),
        ordner: 'cm-31',
        arbeitsordner: arbeitsordner.path,
      ),
      throwsA(
        isA<MoodleFehler>().having(
          (e) => e.meldung,
          'Meldung',
          contains('Lernlandkarte'),
        ),
      ),
    );
    expect(doppel.speichern, isEmpty);
  });
}
