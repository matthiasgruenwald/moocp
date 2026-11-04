// Ein Schutzdienst vor der Instanz, der schon die Anmeldung anhält, ist kein
// Fehlversuch: Das Passwort kam nie bei Moodle an. Der Zugang meldet es als
// „nicht erreichbar", damit eine Neuanmeldung die Zugangsdaten behält
// (_neuAnmelden), und das Protokoll nennt die Ray-ID, aber keine Werte (A4).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/protokoll.dart';

void main() {
  late HttpServer server;
  late Uri basis;

  /// [pruefungBei]: bei welcher Methode die Prüfung des Schutzdienstes kommt.
  Future<void> starten(String pruefungBei) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    basis = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((req) async {
      await req.drain<void>();
      if (req.method == pruefungBei) {
        req.response
          ..statusCode = 403
          ..headers.set('cf-mitigated', 'challenge')
          ..headers.set('cf-ray', 'abc123-FRA')
          ..headers.contentType = ContentType.html
          ..write('<html>Just a moment...</html>');
      } else {
        req.response
          ..headers.contentType = ContentType.html
          ..write('<html><input name="logintoken" value="t"></html>');
      }
      await req.response.close();
    });
  }

  tearDown(() => server.close(force: true));

  for (final bei in ['GET', 'POST']) {
    test('Prüfung des Schutzdienstes bei $bei der Anmeldung: nicht erreichbar, nicht „falsches Passwort"', () async {
      await starten(bei);
      final protokoll = Protokoll();
      await expectLater(
        MoodleZugang.fuerTest(protokoll, basis, benutzer: 'e.mustermann', passwort: 'geheim'),
        throwsA(isA<MoodleNichtErreichbar>()),
      );
      final text = protokoll.eintraege.map((e) => e.text).join('\n');
      expect(text, contains('Ray-ID abc123-FRA'));
      expect(text, isNot(contains('geheim')));
      expect(text, isNot(contains('e.mustermann')));
    });
  }
}
