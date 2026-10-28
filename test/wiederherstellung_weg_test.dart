// Zielwege der Wiederherstellung Zuordnung, Rückfragen und die enge
// Positivliste je Weg. Ohne Netz; die Positivliste wird ohne Versand geprüft.

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/moodle/wiederherstellung_regeln.dart';
import 'package:moocp/protokoll.dart';

void main() {
  group('Zielwege: Zuordnung', () {
    test('die fünf Wege mit den gemessenen Moodle-Werten', () {
      final werte = {for (final z in Zielweg.values) z.nennung: z.moodle};
      expect(werte, {
        'neuer_kurs': 2,
        'aktueller_kurs_verschmelzen': 1,
        'aktueller_kurs_ersetzen': 0,
        'anderer_kurs_verschmelzen': 4,
        'anderer_kurs_ersetzen': 3,
      });
    });

    test('nur die Ersetzen-Wege löschen', () {
      expect({for (final z in Zielweg.values) if (z.loescht) z.nennung},
          {'aktueller_kurs_ersetzen', 'anderer_kurs_ersetzen'});
    });

    test('neuer_kurs braucht keinen Kurs, alle anderen schon', () {
      expect(Zielweg.neuerKurs.brauchtKurs, isFalse);
      for (final z in Zielweg.values.where((z) => z != Zielweg.neuerKurs)) {
        expect(z.brauchtKurs, isTrue, reason: z.nennung);
      }
    });

    test('aus() kennt nur die fünf Namen', () {
      expect(Zielweg.aus('anderer_kurs_ersetzen'), Zielweg.anderKursErsetzen);
      expect(Zielweg.aus('verschmelzen'), isNull);
    });
  });

  group('zielwegPruefen', () {
    test('ohne weg: Rückfrage mit allen Optionen, nichts wird geraten', () {
      for (final kurs in [42, null]) {
        final r = zielwegPruefen(weg: null, loeschend: false, kurs: kurs, neuerKursName: null, kurzname: null);
        expect(r.weg, isNull);
        expect(r.rueckfrage, endsWith('Nichts geändert.'));
        for (final z in Zielweg.values) {
          expect(r.rueckfrage, contains(z.nennung));
        }
      }
    });

    test('ohne weg bleibt auch dann eine Rückfrage, wenn alles andere passt', () {
      final r = zielwegPruefen(weg: null, loeschend: false, kurs: 42, neuerKursName: null, kurzname: null);
      expect(r.weg, isNull);
      expect(r.rueckfrage, isNotNull);
    });

    test('unbekannter Weg: Rückfrage mit allen Optionen', () {
      final r = zielwegPruefen(weg: 'verschmelzen', loeschend: false, kurs: 42, neuerKursName: null, kurzname: null);
      expect(r.weg, isNull);
      for (final z in Zielweg.values) {
        expect(r.rueckfrage, contains(z.nennung));
      }
    });

    test('löschende Wege verlangen loeschend: true', () {
      for (final w in ['aktueller_kurs_ersetzen', 'anderer_kurs_ersetzen']) {
        final ohne = zielwegPruefen(weg: w, loeschend: false, kurs: 42, neuerKursName: null, kurzname: null);
        expect(ohne.weg, isNull, reason: w);
        expect(ohne.rueckfrage, isNotNull, reason: w);
        final mit = zielwegPruefen(weg: w, loeschend: true, kurs: 42, neuerKursName: null, kurzname: null);
        expect(mit.weg, isNotNull, reason: w);
        expect(mit.rueckfrage, isNull, reason: w);
      }
    });

    test('loeschend bei nicht löschenden Wegen wird abgelehnt', () {
      final r = zielwegPruefen(
          weg: 'aktueller_kurs_verschmelzen', loeschend: true, kurs: 42, neuerKursName: null, kurzname: null);
      expect(r.weg, isNull);
      expect(r.rueckfrage, isNotNull);
    });

    test('Kurs-Wege ohne kurs: Rückfrage', () {
      final r = zielwegPruefen(
          weg: 'aktueller_kurs_verschmelzen', loeschend: false, kurs: null, neuerKursName: null, kurzname: null);
      expect(r.weg, isNull);
      expect(r.rueckfrage, isNotNull);
    });

    test('neuer_kurs: Name und Kurzname sind Pflicht, kurs ist verboten', () {
      final ohneName = zielwegPruefen(
          weg: 'neuer_kurs', loeschend: false, kurs: null, neuerKursName: null, kurzname: 'ZZ-Kurz');
      expect(ohneName.weg, isNull);
      expect(ohneName.rueckfrage, isNotNull);

      final ohneKurzname = zielwegPruefen(
          weg: 'neuer_kurs', loeschend: false, kurs: null, neuerKursName: 'ZZ Kurs', kurzname: null);
      expect(ohneKurzname.weg, isNull);

      final mitKurs = zielwegPruefen(
          weg: 'neuer_kurs', loeschend: false, kurs: 42, neuerKursName: 'ZZ Kurs', kurzname: 'ZZ-Kurz');
      expect(mitKurs.weg, isNull);

      final gut = zielwegPruefen(
          weg: 'neuer_kurs', loeschend: false, kurs: null, neuerKursName: 'ZZ Kurs', kurzname: 'ZZ-Kurz');
      expect(gut.weg, Zielweg.neuerKurs);
      expect(gut.rueckfrage, isNull);
    });

    test('bei bestehenden Kursen sind neuer_kurs_name und kurzname verboten', () {
      final r = zielwegPruefen(
          weg: 'anderer_kurs_verschmelzen', loeschend: false, kurs: 42, neuerKursName: 'ZZ Kurs', kurzname: null);
      expect(r.weg, isNull);
      expect(r.rueckfrage, isNotNull);
    });
  });

  group('Positivliste je Zielweg', () {
    final z = MoodleZugang(Protokoll());
    bool post(String a, List<MapEntry<String, String>> f) => z.erlaubt('POST', Uri.parse(a), f, null, null);
    bool get(String a) => z.erlaubt('GET', Uri.parse(a));
    const ziel = 'https://m.example/backup/restore.php?contextid=5&filename=kurs.mbz';

    List<MapEntry<String, String>> formular(int target, {String? targetid, Map<String, String> extra = const {}}) => [
          const MapEntry('contextid', '5'),
          const MapEntry('filepath', '/'),
          const MapEntry('filename', 'kurs.mbz'),
          const MapEntry('stage', '4'),
          MapEntry('target', '$target'),
          MapEntry('targetid', targetid ?? '42'),
          const MapEntry('sesskey', 'abc'),
          ...extra.entries,
        ];

    test('jeder Weg mit seinem Wert und seiner Schlüsselmenge ist erlaubt', () {
      expect(post(ziel, formular(4, extra: {'search': ''})), isTrue);
      expect(post(ziel, formular(3, extra: {'search': ''})), isTrue);
      expect(post(ziel, formular(1)), isTrue);
      expect(post(ziel, formular(0)), isTrue);
      expect(post(ziel, formular(2, targetid: '7', extra: {'catsearch': ''})), isTrue);
    });

    test('Feld des falschen Weges wird abgelehnt', () {
      // target 2 mit dem Feld search: gehört nicht zu neuer_kurs.
      expect(post(ziel, formular(2, targetid: '7', extra: {'search': ''})), isFalse);
      // target 1 mit dem Feld search: gehört nicht zu aktueller_kurs_verschmelzen.
      expect(post(ziel, formular(1, extra: {'search': ''})), isFalse);
      // target 0 mit dem Feld catsearch: gehört nicht zu aktueller_kurs_ersetzen.
      expect(post(ziel, formular(0, extra: {'catsearch': ''})), isFalse);
    });

    test('target außerhalb der fünf gemessenen Werte wird abgelehnt', () {
      expect(post(ziel, formular(5)), isFalse);
    });

    test('targetid muss eine Zahl sein', () {
      expect(post(ziel, formular(1, targetid: 'x')), isFalse);
    });

    test('Kursformular und Kursverwaltung nur mit ihrer Kennung', () {
      expect(get('https://m.example/course/edit.php'), isTrue);
      expect(get('https://m.example/course/edit.php?category=3'), isTrue);
      expect(get('https://m.example/course/edit.php?category=x'), isFalse);
      expect(get('https://m.example/course/edit.php?id=42'), isFalse);
      expect(get('https://m.example/course/management.php?categoryid=3'), isTrue);
      expect(get('https://m.example/course/management.php?categoryid=x'), isFalse);
      expect(get('https://m.example/course/management.php?categoryid=3&search=x'), isFalse);
    });
  });
}
