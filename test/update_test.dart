// Die Update-Prüfung ohne Netz: Tag lesen, Versionen vergleichen, die
// Datei im Release finden, und die Grenzen, innerhalb derer überhaupt
// geprüft wird.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/einstellungen.dart';
import 'package:moocp/update/update.dart';

void main() {
  group('Tag eines Releases', () {
    test('das Schema von publish_tag_to_github.sh', () {
      expect(versionAusTag('v0.9.4'), '0.9.4');
      expect(versionAusTag('0.9.4'), '0.9.4');
      expect(versionAusTag(' v1.2.3 '), '1.2.3');
      expect(versionAusTag('v1.0'), '1.0');
    });

    test('die alte Form der ersten Versionen wird geduldet', () {
      expect(versionAusTag('github-v0.9.2'), '0.9.2');
    });

    test('was nicht passt, wird nicht geraten', () {
      expect(versionAusTag('Release 2'), isNull);
      expect(versionAusTag('v0.9.4-beta'), isNull);
      expect(versionAusTag(''), isNull);
    });
  });

  group('Versionen vergleichen', () {
    test('kleiner, gleich, größer', () {
      expect(versionVergleich('0.9.4', '0.9.5'), -1);
      expect(versionVergleich('0.9.5', '0.9.4'), 1);
      expect(versionVergleich('0.9.4', '0.9.4'), 0);
    });

    test('zählt Zahlen, nicht Zeichen', () {
      expect(versionVergleich('0.10.0', '0.9.9'), 1);
      expect(versionVergleich('1.0.0', '0.99.99'), 1);
    });

    test('fehlende Stellen sind 0, die Buildnummer zählt nicht', () {
      expect(versionVergleich('1.0', '1.0.0'), 0);
      expect(versionVergleich('1.0.1', '1.0'), 1);
      expect(versionVergleich('0.9.4+7', '0.9.4+1'), 0);
    });
  });

  group('Datei im Release', () {
    Map<String, dynamic> anhang(String name) => {'name': name, 'browser_download_url': 'https://x/$name'};

    test('die zur Version passende Datei', () {
      final gefunden = releaseDatei([
        anhang('quelltext.zip'),
        anhang('moocp_setup_0.9.4.exe'),
        anhang('moocp_setup_0.9.5.exe'),
      ], '0.9.5');
      expect(gefunden?['name'], 'moocp_setup_0.9.5.exe');
      expect(installerName('0.9.5'), 'moocp_setup_0.9.5.exe');
    });

    test('heißt sie anders, wird die erste Setup-Datei genommen', () {
      final gefunden = releaseDatei([anhang('moocp_setup0.9.5+1.exe')], '0.9.5');
      expect(gefunden?['name'], 'moocp_setup0.9.5+1.exe');
    });

    test('ohne Installer kein Treffer', () {
      expect(releaseDatei([anhang('quelltext.zip'), anhang('moocp.txt')], '0.9.5'), isNull);
      expect(releaseDatei([], '0.9.5'), isNull);
    });
  });

  group('Wann überhaupt geprüft wird', () {
    test('der Schalter schaltet ab', () {
      expect(updateMoeglich([keinUpdateSchalter], {'LOCALAPPDATA': r'C:\x'}), isFalse);
    });

    test('nur aus dem Installationsverzeichnis', () {
      // Hier läuft der Test, nicht die installierte App: Ein Update ersetzte
      // diese Datei nicht, also wird nicht geprüft.
      expect(updateMoeglich([], {'LOCALAPPDATA': r'C:\irgendwo\anders'}), isFalse);
      expect(updateMoeglich([], {}), isFalse);
    });
  });

  group('Einmal am Tag', () {
    test('Datum als Text', () {
      expect(tagesdatum(DateTime(2026, 10, 3)), '2026-10-03');
      expect(tagesdatum(DateTime(2026, 1, 1)), '2026-01-01');
    });

    test('heute schon geprüft', () {
      final e = Einstellungen(schluessel: 'x');
      final jetzt = DateTime(2026, 10, 3, 18);
      expect(heuteSchonGeprueft(e, jetzt), isFalse);
      e.updateZuletzt = '2026-10-03';
      expect(heuteSchonGeprueft(e, jetzt), isTrue);
      expect(heuteSchonGeprueft(e, DateTime(2026, 10, 4)), isFalse);
    });
  });

  group('Die Prüfung bleibt von Moodle getrennt', () {
    // A2/A1: Die Update-Prüfung hat ihre eigene Verbindung. Käme sie je an
    // MoodleZugang, ginge das Sitzungscookie an GitHub -- deshalb hält der
    // Test die Datei darauf fest, so wie sperrliste_test.dart die Listen
    // gegeneinander hält.
    test('update.dart kennt weder MoodleZugang noch Cookies', () {
      // Ohne die Kommentare: Die erklären gerade, dass es beides nicht gibt.
      final code = File('lib/update/update.dart')
          .readAsLinesSync()
          .where((z) => !z.trimLeft().startsWith('//'))
          .join('\n')
          .toLowerCase();
      expect(code.contains('moodle'), isFalse, reason: 'kein Bezug auf Moodle');
      expect(code.contains('cookie'), isFalse, reason: 'keine Cookies an GitHub');
    });
  });
}
