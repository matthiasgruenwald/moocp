// Offline prüfbar: Instanzprofile (Issue #4, E31). Altbestand-Migration der
// Einstellungen, Port und Servername je Profil, und die Registry der Zugänge.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/einstellungen.dart';
import 'package:moocp/einstellungen_ort.dart';
import 'package:moocp/moodle/instanzen.dart';
import 'package:moocp/profil.dart';
import 'package:moocp/protokoll.dart';

Einstellungen _standard() => Einstellungen(schluessel: 'x');

final _a = Profil(
    kennung: 'a1b2c3d4', name: 'Schule A', adresse: 'https://a.schule.example', port: 47811, mcpName: 'schule-a');
final _b = Profil(
    kennung: 'e5f6a7b8', name: 'Schule B', adresse: 'https://b.schule.example', port: 47812, mcpName: 'schule-b');

void main() {
  group('Altbestand und Einstellungen', () {
    test('nur moodleAdresse wird zum Standardprofil mit Port 47811 und Servername moodle', () {
      final e = Einstellungen.aus({'moodleAdresse': 'https://moodle.schule.example'}, _standard());
      expect(e.profile, hasLength(1));
      expect(e.profile.first.kennung, Profil.standardKennung);
      expect(e.profile.first.adresse, 'https://moodle.schule.example');
      expect(e.profile.first.port, standardPort);
      expect(e.profile.first.mcpName, 'moodle');
      expect(e.port, standardPort);
      expect(e.moodleAdresse, 'https://moodle.schule.example');
    });

    test('ein alter Port aus der Datei bleibt beim Standardprofil', () {
      final e = Einstellungen.aus({'moodleAdresse': 'https://moodle.schule.example', 'port': 47831}, _standard());
      expect(e.profile.first.port, 47831);
      expect(e.port, 47831);
    });

    test('ohne Adresse und ohne Profile gibt es kein Profil', () {
      final e = Einstellungen.aus({}, _standard());
      expect(e.profile, isEmpty);
      expect(e.moodleAdresse, '');
      expect(e.port, standardPort);
    });

    test('eine vorhandene Profilliste gewinnt über moodleAdresse', () {
      final e = Einstellungen.aus({
        'moodleAdresse': 'https://alt.schule.example',
        'profile': [_a.toJson(), _b.toJson()],
      }, _standard());
      expect(e.profile.map((p) => p.kennung), ['a1b2c3d4', 'e5f6a7b8']);
      expect(e.moodleAdresse, 'https://a.schule.example');
      expect(e.profile.map((p) => p.port), [47811, 47812]);
    });

    test('ein unbrauchbares Profil fällt weg, die anderen bleiben', () {
      final e = Einstellungen.aus({
        'profile': [
          {'kennung': '', 'name': 'kaputt', 'adresse': 'https://x.schule.example'},
          _b.toJson(),
        ],
      }, _standard());
      expect(e.profile.map((p) => p.kennung), ['e5f6a7b8']);
    });

    test('fehlender Port und Servername werden vergeben, Namen bleiben eindeutig', () {
      final e = Einstellungen.aus({
        'profile': [
          {'kennung': 'k1', 'name': 'Test', 'adresse': 'https://t.schule.example'},
          {'kennung': 'k2', 'name': 'test', 'adresse': 'https://u.schule.example'},
        ],
      }, _standard());
      expect(e.profile.map((p) => p.port), [standardPort, standardPort + 1]);
      expect(e.profile.map((p) => p.mcpName), ['test', 'test-2']);
    });

    test('gleiche Ports werden auseinandergezogen, das erste behält seinen', () {
      final e = Einstellungen(profile: [
        Profil(kennung: 'k1', name: 'Eins', adresse: 'https://e.schule.example', port: 47900, mcpName: 'eins'),
        Profil(kennung: 'k2', name: 'Zwei', adresse: 'https://z.schule.example', port: 47900, mcpName: 'zwei'),
      ], schluessel: 'x');
      expect(e.profile.map((p) => p.port), [47900, 47811]);
    });

    test('speichern schreibt Profile und moodleAdresse, Rückführung ist verlustfrei', () {
      final e = Einstellungen.aus({'moodleAdresse': 'https://moodle.schule.example'}, _standard());
      final j = e.zuJson();
      expect(j['moodleAdresse'], 'https://moodle.schule.example');
      expect(j['port'], standardPort, reason: 'ältere Versionen lesen den Port oben');
      final zurueck = Einstellungen.aus(j, _standard());
      expect(zurueck.profile.single.kennung, Profil.standardKennung);
      expect(zurueck.profile.single.adresse, 'https://moodle.schule.example');
      expect(zurueck.profile.single.mcpName, 'moodle');
    });

    test('Setzen der Adresse ändert das erste Profil und behält die Kennung', () {
      final e = Einstellungen.aus({'profile': [_a.toJson(), _b.toJson()]}, _standard());
      e.moodleAdresse = 'https://neu.schule.example';
      expect(e.profile.first.adresse, 'https://neu.schule.example');
      expect(e.profile.first.kennung, 'a1b2c3d4');
      expect(e.profile.first.mcpName, 'schule-a');
      expect(e.profile.last.adresse, 'https://b.schule.example');
    });

    test('Setzen einer Adresse ohne Profil legt das Standardprofil an', () {
      final e = _standard();
      e.moodleAdresse = 'https://moodle.schule.example';
      expect(e.profile.single.kennung, Profil.standardKennung);
      expect(e.profile.single.port, standardPort);
      e.moodleAdresse = '';
      expect(e.profile.single.adresse, '');
    });
  });

  group('Servername', () {
    test('aus dem Anzeigenamen: Kleinbuchstaben, Bindestriche, keine Leerzeichen', () {
      expect(Profil.mcpNameAus('Moodle Test'), 'moodle-test');
      expect(Profil.mcpNameAus('  Schule (Süd) 2 '), 'schule-s-d-2');
      expect(Profil.mcpNameAus('Ä Ö'), '');
    });

    test('gültig nur nach dem Muster, das mcpNameAus liefert', () {
      expect(Profil.mcpNameGueltig('moodle-test'), isTrue);
      expect(Profil.mcpNameGueltig('Moodle Test'), isFalse);
      expect(Profil.mcpNameGueltig('-x'), isFalse);
    });

    test('ohne brauchbaren Namen zählt die Kennung', () {
      expect(Profil.mcpNameFuer('Ä', 'k9'), 'moodle-k9');
    });
  });

  group('Registry', () {
    test('je Kennung ein eigener Zugang, bei gleicher Kennung derselbe', () {
      final r = MoodleInstanzen(Protokoll());
      final a = r.zugang(_a);
      final b = r.zugang(_b);
      expect(identical(a, b), isFalse);
      expect(identical(a, r.zugang(_a)), isTrue);
      expect(r.hat(_b.kennung), isTrue);
    });

    test('entfernen vergisst nur den einen Zugang', () {
      final r = MoodleInstanzen(Protokoll());
      final a = r.zugang(_a);
      r.zugang(_b);
      r.entfernen(_b.kennung);
      expect(r.hat(_b.kennung), isFalse);
      expect(r.hat(_a.kennung), isTrue);
      expect(identical(a, r.zugang(_a)), isTrue);
    });
  });

  test('neue Kennungen sind acht Hexziffern und ändern sich nicht', () {
    final k = Profil.neueKennung(Random(7));
    expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(k), isTrue);
    expect(Profil.neueKennung(Random(7)), k);
  });
}
