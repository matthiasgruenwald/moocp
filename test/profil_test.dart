// Offline prüfbar: Instanzprofile (Issue #4). Altbestand-Migration der
// Einstellungen, Auflösung des Parameters `instanz` und die Registry der
// Zugänge. Die Gegenstellen mit identischen Kurs-IDs fehlen noch (siehe TODO.md
// zu E31 und zur Entscheidung über https in Tests).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/einstellungen.dart';
import 'package:moocp/moodle/instanzen.dart';
import 'package:moocp/profil.dart';
import 'package:moocp/protokoll.dart';

Einstellungen _standard() =>
    Einstellungen(port: 47831, schluessel: 'x');

const _a = Profil(kennung: 'a1b2c3d4', name: 'Schule A', adresse: 'https://a.schule.example');
const _b = Profil(kennung: 'e5f6a7b8', name: 'Schule B', adresse: 'https://b.schule.example');

void main() {
  group('Altbestand und Einstellungen', () {
    test('nur moodleAdresse wird zum Standardprofil', () {
      final e = Einstellungen.aus({'moodleAdresse': 'https://moodle.schule.example'}, _standard());
      expect(e.profile, hasLength(1));
      expect(e.profile.first.kennung, Profil.standardKennung);
      expect(e.profile.first.adresse, 'https://moodle.schule.example');
      expect(e.moodleAdresse, 'https://moodle.schule.example');
    });

    test('ohne Adresse und ohne Profile gibt es kein Profil', () {
      final e = Einstellungen.aus({}, _standard());
      expect(e.profile, isEmpty);
      expect(e.moodleAdresse, '');
    });

    test('eine vorhandene Profilliste gewinnt über moodleAdresse', () {
      final e = Einstellungen.aus({
        'moodleAdresse': 'https://alt.schule.example',
        'profile': [_a.toJson(), _b.toJson()],
      }, _standard());
      expect(e.profile.map((p) => p.kennung), ['a1b2c3d4', 'e5f6a7b8']);
      expect(e.moodleAdresse, 'https://a.schule.example');
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

    test('speichern schreibt Profile und moodleAdresse, Rückführung ist verlustfrei', () {
      final e = Einstellungen.aus({'moodleAdresse': 'https://moodle.schule.example'}, _standard());
      final j = e.zuJson();
      expect(j['moodleAdresse'], 'https://moodle.schule.example');
      final zurueck = Einstellungen.aus(j, _standard());
      expect(zurueck.profile.single.kennung, Profil.standardKennung);
      expect(zurueck.profile.single.adresse, 'https://moodle.schule.example');
    });

    test('Setzen der Adresse ändert das erste Profil und behält die Kennung', () {
      final e = Einstellungen.aus({'profile': [_a.toJson(), _b.toJson()]}, _standard());
      e.moodleAdresse = 'https://neu.schule.example';
      expect(e.profile.first.adresse, 'https://neu.schule.example');
      expect(e.profile.first.kennung, 'a1b2c3d4');
      expect(e.profile.last.adresse, 'https://b.schule.example');
    });

    test('Setzen einer Adresse ohne Profil legt das Standardprofil an', () {
      final e = _standard();
      e.moodleAdresse = 'https://moodle.schule.example';
      expect(e.profile.single.kennung, Profil.standardKennung);
      e.moodleAdresse = '';
      expect(e.profile.single.adresse, '');
    });
  });

  group('profilAufloesen', () {
    test('ein einziges Profil ist der Standard, auch ohne Angabe', () {
      expect(profilAufloesen([_a], null).kennung, 'a1b2c3d4');
      expect(profilAufloesen([_a], '').kennung, 'a1b2c3d4');
    });

    test('ohne Profil ist das ein Fehler', () {
      expect(() => profilAufloesen([], null), throwsA(isA<ProfilFehler>()));
    });

    test('mehrere Profile ohne Angabe: Fehler mit Profilliste', () {
      final f = _fehler(() => profilAufloesen([_a, _b], null));
      expect(f, contains('instanz'));
      expect(f, contains('Schule A (a1b2c3d4)'));
      expect(f, contains('Schule B (e5f6a7b8)'));
      expect(f, isNot(contains('https://')), reason: 'Adressen stehen nicht in der Meldung');
    });

    test('Kennung und Name, Name ohne Groß- und Kleinschreibung', () {
      expect(profilAufloesen([_a, _b], 'e5f6a7b8').name, 'Schule B');
      expect(profilAufloesen([_a, _b], 'schule a').kennung, 'a1b2c3d4');
    });

    test('unbekannte Angabe ist ein Fehler', () {
      expect(_fehler(() => profilAufloesen([_a, _b], 'gibtsnicht')), contains('gibtsnicht'));
    });

    test('doppelter Name ist ein Fehler, keine Wahl', () {
      const c = Profil(kennung: '11112222', name: 'schule a', adresse: 'https://c.schule.example');
      expect(_fehler(() => profilAufloesen([_a, c], 'Schule A')), contains('Kennung angeben'));
    });
  });

  group('Registry', () {
    test('je Kennung ein eigener Zugang, bei gleicher Kennung derselbe', () {
      final r = MoodleInstanzen(Protokoll());
      final a = r.zugang(_a.kennung);
      final b = r.zugang(_b.kennung);
      expect(identical(a, b), isFalse);
      expect(identical(a, r.zugang(_a.kennung)), isTrue);
      expect(r.hat(_b.kennung), isTrue);
    });

    test('entfernen vergisst nur den einen Zugang', () {
      final r = MoodleInstanzen(Protokoll());
      final a = r.zugang(_a.kennung);
      r.zugang(_b.kennung);
      r.entfernen(_b.kennung);
      expect(r.hat(_b.kennung), isFalse);
      expect(r.hat(_a.kennung), isTrue);
      expect(identical(a, r.zugang(_a.kennung)), isTrue);
    });
  });

  test('neue Kennungen sind acht Hexziffern und ändern sich nicht', () {
    final k = Profil.neueKennung(Random(7));
    expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(k), isTrue);
    expect(Profil.neueKennung(Random(7)), k);
  });
}

String _fehler(void Function() f) {
  try {
    f();
  } on ProfilFehler catch (e) {
    return e.meldung;
  }
  fail('kein ProfilFehler');
}
