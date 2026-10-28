// Zwei Moodle-Instanzen mit denselben Nummern: Kurs 12 und
// Aktivität 34 gibt es auf beiden. Die Instanzen sind lokale Test-Doppel auf
// 127.0.0.1 und laufen über den Testzugang MoodleZugang.fuerTest.
//
// Geprüft wird: Anfragen landen bei der Instanz, zu der sie gehören, und der
// Ablauf der Sitzung bei A berührt B nicht (eigene Cookies, eigene Anmeldung).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/protokoll.dart';

/// Ein Moodle-Doppel: Anmeldeseite, Sitzung als Cookie, eine Aktivitätsseite.
class _FakeMoodle {
  _FakeMoodle(this.name);

  final String name;
  late HttpServer _server;

  /// Sitzungen, die sich angemeldet haben.
  final Set<String> _angemeldet = {};
  int _zaehler = 0;

  /// Wie oft sich jemand bei diesem Doppel anmeldet (Formular gesendet).
  int anmeldungen = 0;

  static const benutzer = 'e.mustermann';
  static const passwort = 'test-geheim-47';

  Uri get basis => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> starten() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_antworte);
  }

  Future<void> stoppen() => _server.close(force: true);

  /// Läßt die Sitzungen ablaufen, wie es Moodle nach einer Weile tut.
  void sitzungenBeenden() => _angemeldet.clear();

  Future<void> _antworte(HttpRequest r) async {
    final id = r.cookies.where((c) => c.name == 'MoodleSession').map((c) => c.value).firstOrNull;
    final eingeloggt = id != null && _angemeldet.contains(id);
    final pfad = r.uri.path;

    if (pfad == '/login/index.php' && r.method == 'GET') {
      if (r.uri.queryParameters.containsKey('testsession')) {
        return _umleiten(r, eingeloggt ? '/my/' : '/login/index.php');
      }
      // Neue, noch nicht angemeldete Sitzung, dazu der logintoken.
      final neu = 's${name.hashCode.abs()}-${_zaehler++}';
      r.response.cookies.add(Cookie('MoodleSession', neu));
      return _text(r, '<form><input name="logintoken" value="tok"></form>');
    }
    if (pfad == '/login/index.php' && r.method == 'POST') {
      anmeldungen++;
      final f = Uri.splitQueryString(await utf8.decoder.bind(r).join());
      if (id != null && f['username'] == benutzer && f['password'] == passwort && f['logintoken'] == 'tok') {
        _angemeldet.add(id);
        return _umleiten(r, '/login/index.php?testsession=1');
      }
      return _umleiten(r, '/login/index.php');
    }
    if (!eingeloggt) return _umleiten(r, '/login/index.php');
    if (pfad == '/course/modedit.php' && r.uri.queryParameters['update'] == '34') {
      return _text(r, 'Instanz $name: Kurs 12, Aktivität 34');
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
  late _FakeMoodle a;
  late _FakeMoodle b;

  setUp(() async {
    a = _FakeMoodle('Testinstanz A');
    b = _FakeMoodle('Testinstanz B');
    await a.starten();
    await b.starten();
  });

  tearDown(() async {
    await a.stoppen();
    await b.stoppen();
  });

  test('Anfragen landen bei der Instanz, zu der sie gehören', () async {
    final protokoll = Protokoll();
    final za = await MoodleZugang.fuerTest(protokoll.fuer('Testinstanz A'), a.basis,
        benutzer: _FakeMoodle.benutzer, passwort: _FakeMoodle.passwort);
    final zb = await MoodleZugang.fuerTest(protokoll.fuer('Testinstanz B'), b.basis,
        benutzer: _FakeMoodle.benutzer, passwort: _FakeMoodle.passwort);

    final ra = await za.lesen('/course/modedit.php?update=34');
    final rb = await zb.lesen('/course/modedit.php?update=34');

    expect(utf8.decode(ra.bytes), contains('Instanz Testinstanz A'));
    expect(utf8.decode(rb.bytes), contains('Instanz Testinstanz B'));
  });

  test('Ablauf der Sitzung bei A berührt B nicht', () async {
    final protokoll = Protokoll();
    final za = await MoodleZugang.fuerTest(protokoll.fuer('Testinstanz A'), a.basis,
        benutzer: _FakeMoodle.benutzer, passwort: _FakeMoodle.passwort);
    final zb = await MoodleZugang.fuerTest(protokoll.fuer('Testinstanz B'), b.basis,
        benutzer: _FakeMoodle.benutzer, passwort: _FakeMoodle.passwort);
    expect(a.anmeldungen, 1);
    expect(b.anmeldungen, 1);

    a.sitzungenBeenden();
    final ra = await za.lesen('/course/modedit.php?update=34');
    expect(utf8.decode(ra.bytes), contains('Instanz Testinstanz A'));
    expect(a.anmeldungen, 2, reason: 'A meldet genau einmal neu an');

    final rb = await zb.lesen('/course/modedit.php?update=34');
    expect(utf8.decode(rb.bytes), contains('Instanz Testinstanz B'));
    expect(b.anmeldungen, 1, reason: 'B bleibt unberührt');

    final ablauf = protokoll.eintraege.where((e) => e.text.contains('Sitzung abgelaufen')).toList();
    expect(ablauf, hasLength(1));
    expect(ablauf.single.text, startsWith('[Testinstanz A]'));
    expect(protokoll.eintraege.any((e) => e.text.contains(_FakeMoodle.passwort)), isFalse,
        reason: 'das Passwort steht nie im Protokoll');
  });

  test('der Testzugang nimmt nur lokale http-Adressen', () async {
    await expectLater(
      MoodleZugang.fuerTest(Protokoll(), Uri.parse('https://moodle.schule.example'),
          benutzer: 'x', passwort: 'y'),
      throwsArgumentError,
    );
  });
}
