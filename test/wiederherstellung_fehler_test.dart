// Moodle meldet bei der Wiederherstellung einen Fehler: Die App entscheidet nicht aus dem
// Fehlerfeld, sondern prüft den Zielkurs. Hier die reinen Regeln: Beleg für „Prozess beendet",
// die Fehlerart ohne Inhalte und der Nachfragetext an die Verwaltung (E11, A9).
import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/sicherung_regeln.dart';
import 'package:moocp/moodle/wiederherstellung_regeln.dart';

Map<String, Object?> _e({Object? error, Object? errorcode, Object? status, double progress = 0.4}) => {
      'backupid': 'r-1',
      'progress': progress,
      'status': ?status,
      'error': ?error,
      'errorcode': ?errorcode,
    };

void main() {
  group('Prozess beendet', () {
    test('Status 800 (Moodle: beendet mit Fehler) belegt das Ende', () {
      expect(fehlerBeendet([_e(error: 'x', status: 800)], 'r-1'), isTrue);
    });
    test('ein Fehlerfeld allein belegt das Ende nicht', () {
      expect(fehlerBeendet([_e(error: 'x')], 'r-1'), isFalse);
      expect(fehlerBeendet([_e(error: 'x', status: 200)], 'r-1'), isFalse);
      expect(fehlerBeendet('kaputt', 'r-1'), isFalse);
    });
  });

  group('Fehlerart', () {
    test('Fehlercode hat Vorrang und wird nur als kurzer Bezeichner übernommen', () {
      expect(fehlerArt([_e(error: 'boom', errorcode: 'backup_exception')], 'r-1'), 'backup_exception');
      expect(fehlerArt([_e(error: 'failed')], 'r-1'), 'failed');
    });
    test('Freitext mit Inhalten wird nicht weitergegeben (E11)', () {
      expect(fehlerArt([_e(error: 'Kurs "Mathe 9b" von Erika Mustermann kaputt')], 'r-1'), 'nicht benannt');
      expect(fehlerArt([_e(error: true)], 'r-1'), 'nicht benannt');
    });
  });

  group('Nachfrage an die Verwaltung', () {
    final text = verwaltungsNachfrage(
      nummer: 'abc123',
      start: DateTime(2026, 10, 19, 9, 5),
      letzteBeobachtung: DateTime(2026, 10, 19, 9, 40),
      zielkurs: 12,
      fehlerart: 'backup_exception',
      fortschritt: 0.4,
    );
    test('nennt Nummer, beide Uhrzeiten, Zielkurs, Fehlerart und Fortschritt', () {
      expect(text, contains('abc123'));
      expect(text, contains('09:05'));
      expect(text, contains('09:40'));
      expect(text, contains('Kurs 12'));
      expect(text, contains('backup_exception'));
      expect(text, contains('40 %'));
    });
    test('sagt, dass angestoßen wurde, nicht wiederholt werden soll, und fragt nach dem Hintergrundauftrag', () {
      expect(text, contains('angestoßen'));
      expect(text, contains('nicht wiederholt'));
      expect(text, contains('Hintergrundauftrag'));
      expect(text, contains('?'));
    });
    test('ohne Zielkurs-Nummer steht neuer Kurs, ohne Fortschritt unbekannt', () {
      final t = verwaltungsNachfrage(
        nummer: 'x', start: DateTime(2026, 10, 19, 9), letzteBeobachtung: null, zielkurs: null,
        fehlerart: 'nicht benannt', fortschritt: null);
      expect(t, contains('neuen Kurs'));
      expect(t, contains('unbekannt'));
    });
  });
}
