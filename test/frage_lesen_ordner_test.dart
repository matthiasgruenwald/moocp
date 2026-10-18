// Ticket #22 (Spec #17): wiederholtes und gleichzeitiges Fragenlesen über den
// Weg des Werkzeugs frage_lesen (frageLesen -> formularLesen). Die Moodle-Grenze
// ist ein lokales Test-Doppel auf 127.0.0.1; der Arbeitsordner ist ein
// Temp-Verzeichnis. Es geht um den Arbeitsordner frage-<id>, der beim Lesen
// neu angelegt wird.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/fragen.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/protokoll.dart';
import 'package:path/path.dart' as p;

/// Ein Moodle-Doppel mit Anmeldung, Bearbeitungsformular einer Frage, einer
/// eingebetteten Bilddatei und dem Einzelexport als XML.
class _Doppel {
  late HttpServer _server;
  final Set<String> _angemeldet = {};
  int _zaehler = 0;

  /// Wie oft die Frage-Seite abgerufen wurde.
  int formulare = 0;

  static const benutzer = 'e.mustermann';
  static const passwort = 'test-geheim-47';
  static const sesskey = 'sk1';
  static final bild = Uint8List.fromList(List<int>.generate(64, (i) => i));

  Uri get basis => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> starten() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_antworte);
  }

  Future<void> stoppen() => _server.close(force: true);

  String _seite(String body) =>
      '<html><body><script>M.cfg = {"sesskey":"$sesskey","courseId":12,"contextid":"55"};</script>$body</body></html>';

  Future<void> _antworte(HttpRequest r) async {
    final id = r.cookies.where((c) => c.name == 'MoodleSession').map((c) => c.value).firstOrNull;
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
      if (id != null && f['username'] == benutzer && f['password'] == passwort && f['logintoken'] == 'tok') {
        _angemeldet.add(id);
        return _umleiten(r, '/login/index.php?testsession=1');
      }
      return _umleiten(r, '/login/index.php');
    }
    if (!eingeloggt) return _umleiten(r, '/login/index.php');
    if (pfad == '/my/') return _text(r, _seite('<p>Startseite</p>'));
    if (pfad == '/question/bank/editquestion/question.php') {
      formulare++;
      return _text(r, _seite('''<form class="mform" method="post">
<input type="hidden" name="sesskey" value="$sesskey">
<div id="fitem_id_name"><label for="id_name">Fragenname</label><input type="text" name="name" id="id_name" value="ZZ Frage"></div>
<input type="hidden" name="qtype" value="multichoice">
<textarea name="questiontext[text]"><p>ZZ Text</p><img src="${basis.resolve('/draftfile.php/55/user/draft/9/bild.png')}" alt="ZZ Bild"></textarea>
</form>'''));
    }
    if (pfad == '/draftfile.php/55/user/draft/9/bild.png') {
      r.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('image', 'png')
        ..add(bild);
      return r.response.close();
    }
    if (pfad == '/question/bank/exporttoxml/exportone.php') {
      return _text(r, '<?xml version="1.0" encoding="UTF-8"?><quiz><question type="multichoice"/></quiz>');
    }
    return _text(r, 'nicht gefunden', status: HttpStatus.notFound);
  }

  Future<void> _umleiten(HttpRequest r, String ziel) async {
    r.response.redirect(Uri.parse(ziel), status: HttpStatus.seeOther);
    await r.response.close();
  }

  Future<void> _text(HttpRequest r, String body, {int status = HttpStatus.ok}) async {
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
    arbeitsordner = Directory.systemTemp.createTempSync('ticket22-');
    zugang = await MoodleZugang.fuerTest(Protokoll(), doppel.basis,
        benutzer: _Doppel.benutzer, passwort: _Doppel.passwort);
  });

  tearDown(() async {
    await doppel.stoppen();
    if (arbeitsordner.existsSync()) arbeitsordner.deleteSync(recursive: true);
  });

  /// Der vollständige Stand einer gelesenen Frage: Quelltext, Bild, XML, Übersicht.
  void erwarteStand(String ordner) {
    expect(File(p.join(ordner, 'questiontext.html')).readAsStringSync(), contains('ZZ Text'));
    expect(File(p.join(ordner, 'dateien', 'bild.png')).readAsBytesSync(), _Doppel.bild);
    expect(File(p.join(ordner, 'frage.xml')).existsSync(), isTrue);
    expect(File(p.join(ordner, '.stand', 'ziel.json')).existsSync(), isTrue);
    expect(File(p.join(ordner, 'uebersicht.json')).existsSync(), isTrue);
    expect(File(p.join(ordner, '.stand', 'dateien', 'bild.png')).existsSync(), isTrue);
  }

  test('Wiederholtes Lesen derselben Frage ergibt jedes Mal den vollständigen Stand', () async {
    for (var i = 0; i < 3; i++) {
      final g = await frageLesen(zugang, arbeitsordner.path, sammlung: 12, frage: 34);
      expect(g, contains('frage.xml'));
      erwarteStand(p.join(arbeitsordner.path, 'frage-34'));
    }
  });

  test('Gleichzeitiges Lesen derselben Frage: alle Aufrufe liefern einen vollständigen Stand', () async {
    final ergebnisse = await Future.wait([
      for (var i = 0; i < 30; i++) frageLesen(zugang, arbeitsordner.path, sammlung: 12, frage: 34),
    ]);
    expect(ergebnisse, hasLength(30));
    erwarteStand(p.join(arbeitsordner.path, 'frage-34'));
  });

  test('Gleichzeitiges Lesen unterschiedlicher Fragen: jede Frage bekommt ihren Ordner', () async {
    await Future.wait([
      for (final f in [34, 35, 36, 37])
        frageLesen(zugang, arbeitsordner.path, sammlung: 12, frage: f),
    ]);
    for (final f in [34, 35, 36, 37]) {
      erwarteStand(p.join(arbeitsordner.path, 'frage-$f'));
    }
  });
}
