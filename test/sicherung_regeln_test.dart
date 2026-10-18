// Offline prüfbar: die Regeln der Aktivitätssicherung (moodle/sicherung_regeln.dart),
// die Positivliste für die Sicherung, die Ausnahme der Sperrliste und der
// Vorgangsspeicher (moodle/sicherung.dart). Die Formularwerte sind Nachbildungen
// der gemessenen Felder; der Ablauf gegen Moodle ist nicht geprüft.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/moodle/sicherung.dart';
import 'package:moocp/moodle/sicherung_regeln.dart';
import 'package:moocp/moodle/sperrliste.dart';
import 'package:moocp/protokoll.dart';

MapEntry<String, String> e(String k, String v) => MapEntry(k, v);

/// Die Bestätigungsseite (Schritt 4) mit genau einer eingeschalteten Aktivität.
Felder bestaetigung({String stage = '4', String users = '0', String andere = '0'}) => [
      e('_qf__backup_confirmation_form', '1'),
      e('sesskey', 'abc'),
      e('stage', stage),
      e('setting_root_users', users),
      e('setting_root_enrolments', '0'),
      e('setting_activity_page_1002_included', '1'),
      e('setting_activity_page_1002_userinfo', '0'),
      e('setting_activity_label_1003_included', andere),
    ];

void main() {
  group('Bestätigungsseite', () {
    test('genau die gewählte Aktivität, keine Nutzerdaten: in Ordnung', () {
      expect(bestaetigungFehler(bestaetigung(), cmid: 1002), isNull);
    });

    test('eine weitere Aktivität eingeschaltet: Abbruch', () {
      expect(bestaetigungFehler(bestaetigung(andere: '1'), cmid: 1002), contains('1003'));
    });

    test('Nutzerdaten eingeschaltet: Abbruch', () {
      expect(bestaetigungFehler(bestaetigung(users: '1'), cmid: 1002), contains('Nutzerdaten'));
    });

    test('falsche Stufe: Abbruch', () {
      expect(bestaetigungFehler(bestaetigung(stage: '2'), cmid: 1002), isNotNull);
    });

    test('andere cmid als bestellt: Abbruch', () {
      expect(bestaetigungFehler(bestaetigung(), cmid: 999), isNotNull);
    });
  });

  test('Nutzerdaten aus: vorhandene Felder auf 0, fehlende bleiben fehlend', () {
    final vorher = [e('stage', '1'), e('setting_root_users', '1'), e('setting_activity_page_1002_userinfo', '1')];
    final nachher = nutzerdatenAus(vorher);
    expect(letzteWerte(nachher)['setting_root_users'], '0');
    expect(letzteWerte(nachher)['setting_activity_page_1002_userinfo'], '0');
    expect(letzteWerte(nachher).containsKey('setting_root_logs'), isFalse);
    expect(ohneNutzerdaten(nachher), isTrue);
    expect(ohneNutzerdaten(vorher), isFalse);
  });

  test('Schema-Auswahl: genau die Aktivität ein, alle anderen aus, Nutzerdaten aus', () {
    final seite = [
      e('stage', '2'),
      e('setting_activity_page_1002_included', '0'),
      e('setting_activity_label_1003_included', '1'),
      e('setting_root_users', '1'),
    ];
    final neu = schemaAuswahl(seite, cmid: 1002)!;
    final w = letzteWerte(neu);
    expect(w['setting_activity_page_1002_included'], '1');
    expect(w['setting_activity_label_1003_included'], '0');
    expect(w['setting_root_users'], '0');
    expect(schemaAuswahl(seite, cmid: 1), isNull);
  });

  test('Nutzerdaten-Optionen: fehlende Felder zählen als aus, eingeschaltete nicht', () {
    expect(ohneNutzerdaten([e('setting_root_users', '0')]), isTrue);
    expect(ohneNutzerdaten([e('setting_root_logs', '1')]), isFalse);
    expect(ohneNutzerdaten([e('setting_activity_page_1002_userinfo', '1')]), isFalse);
    // Der letzte Wert zählt: Moodle setzt vor jedes Kontrollkästchen eine 0.
    expect(ohneNutzerdaten([e('setting_root_users', '0'), e('setting_root_users', '1')]), isFalse);
  });

  group('Fortschritt', () {
    test('Ende: progress 1 und status 1000', () {
      expect(bewerteFortschritt([{'backupid': '42', 'progress': 1, 'status': 1000}], '42'), SicherungStand.fertig);
    });
    test('läuft: progress unter 1', () {
      expect(bewerteFortschritt([{'backupid': '42', 'progress': 0.5, 'status': 0}], '42'), SicherungStand.laufend);
    });
    test('Fehlerfeld: fehlgeschlagen', () {
      expect(bewerteFortschritt([{'backupid': '42', 'errorcode': 'x'}], '42'), SicherungStand.fehlgeschlagen);
    });
    test('unbekanntes Muster oder andere Nummer: unklar', () {
      expect(bewerteFortschritt([{'backupid': '42', 'progress': 1, 'status': 500}], '42'), SicherungStand.unklar);
      expect(bewerteFortschritt([{'backupid': '7', 'progress': 1, 'status': 1000}], '42'), SicherungStand.unklar);
      expect(bewerteFortschritt(null, '42'), SicherungStand.unklar);
    });
  });

  group('Downloadlink auf der Seite Wiederherstellen (Fixturen)', () {
    const eigene = 'sicherung-cm1002-2026-10-18_090507.mbz';
    const andere = 'sicherung-cm1-2026-10-17_120000.mbz';
    String zeile(String datei, {String id = '7'}) =>
        '<li><a href="https://m.example/pluginfile.php/$id/user/backup/$datei?forcedownload=1">Herunterladen</a></li>';

    test('genau ein Treffer des eigenen Namens, in &amp;-Schreibweise der Seite', () {
      final html = '<ul>${zeile(andere)}<a href="https://m.example/pluginfile.php/7/user/backup/$eigene?forcedownload=1" title="a&amp;b">x</a></ul>';
      expect(sicherungsLinks(html, eigene), ['/pluginfile.php/7/user/backup/$eigene?forcedownload=1']);
    });

    test('Zusatzparameter nach dem Link: kein Treffer, die Positivliste ließe ihn nicht zu', () {
      final html = '<a href="https://m.example/pluginfile.php/7/user/backup/$eigene?forcedownload=1&amp;x=1">x</a>';
      expect(sicherungsLinks(html, eigene), isEmpty);
    });

    test('kein Treffer: leer, auch wenn nur ein fremder Name da ist', () {
      expect(sicherungsLinks('<ul>${zeile(andere)}</ul>', eigene), isEmpty);
    });

    test('zwei Treffer mit dem eigenen Namen: beide, der Aufrufer bricht ab', () {
      final html = zeile(eigene) + zeile(eigene, id: '9');
      expect(sicherungsLinks(html, eigene), hasLength(2));
    });

    test('Namensteil ist kein Treffer: nur ganze Dateinamen zählen', () {
      expect(sicherungsLinks(zeile('x-$eigene'), eigene), isEmpty);
    });

    test('gemessene Form: Link ohne itemid, daneben choosebackupfile-Link, nur der Downloadlink zählt', () {
      const gemessen = 'sicherung-moodle2-activity-1202-page1202-20261018-0532-nu.mbz';
      final html = '<a href="https://m.example/pluginfile.php/75/user/backup/$gemessen?forcedownload=1">Herunterladen</a>'
          '<a href="https://m.example/backup/restorefile.php?action=choosebackupfile&amp;filename=$gemessen&amp;contextid=75">Wiederherstellen</a>';
      expect(sicherungsLinks(html, gemessen), ['/pluginfile.php/75/user/backup/$gemessen?forcedownload=1']);
    });

    test('Punkte im Namen sind wörtlich, nicht als Muster', () {
      expect(sicherungsLinks(zeile('sicherungXcm1.mbz'), 'sicherung.cm1.mbz'), isEmpty);
    });
  });

  test('Dateiname: Modul, cmid und Zeit, sonst nichts', () {
    expect(sicherungsName('page', 1002, DateTime(2026, 10, 18, 9, 5, 7)), 'page-cm1002-2026-10-18_090507.mbz');
  });

  test('Zielordner: nur einfache relative Namen', () {
    expect(zielOrdnerPruefen(null), '');
    expect(zielOrdnerPruefen('Unterricht/2026'), 'Unterricht/2026');
    expect(zielOrdnerPruefen('../x'), isNull);
    expect(zielOrdnerPruefen('/abs'), isNull);
    expect(zielOrdnerPruefen('C:x'), isNull);
    expect(zielOrdnerPruefen('x*y'), isNull);
  });

  group('Sperrliste und Positivliste für die Sicherung', () {
    final z = MoodleZugang(Protokoll());

    test('Sicherungsdatei mit forcedownload=1: durch die Sperrliste, nur sie', () {
      final u = Uri.parse('https://m.example/pluginfile.php/7/user/backup/page-cm1002-x.mbz?forcedownload=1');
      expect(gesperrt(u), isFalse);
      expect(z.erlaubt('GET', u), isTrue);
    });

    test('Sicherungsdatei mit itemid-Segment (Zahl vor dem Namen): ebenfalls durch', () {
      final u = Uri.parse('https://m.example/pluginfile.php/7/user/backup/0/page-cm1002-x.mbz?forcedownload=1');
      expect(gesperrt(u), isFalse);
      expect(z.erlaubt('GET', u), isTrue);
    });

    test('Nutzerdatei ohne Sicherungs-Muster bleibt gesperrt', () {
      for (final a in [
        '/pluginfile.php/7/user/backup/page-cm1002-x.mbz',
        '/pluginfile.php/7/user/private/notizen.pdf?forcedownload=1',
        '/pluginfile.php/7/user/icon/f1.png?forcedownload=1',
      ]) {
        expect(gesperrt(Uri.parse('https://m.example$a')), isTrue, reason: a);
      }
    });

    test('Seite Wiederherstellen: nur contextid, sonst nichts', () {
      expect(z.erlaubt('GET', Uri.parse('https://m.example/backup/restorefile.php?contextid=2010')), isTrue);
      expect(z.erlaubt('GET', Uri.parse('https://m.example/backup/restorefile.php?contextid=2010&x=1')), isFalse);
      expect(z.erlaubt('GET', Uri.parse('https://m.example/backup/restorefile.php?contextid=abc')), isFalse);
      expect(z.erlaubt('GET', Uri.parse('https://m.example/backup/restorefile.php')), isFalse);
    });

    test('Einstieg der Sicherung: id und cm, sonst nichts', () {
      expect(z.erlaubt('GET', Uri.parse('https://m.example/backup/backup.php?id=12&cm=1002')), isTrue);
      expect(z.erlaubt('GET', Uri.parse('https://m.example/backup/backup.php?id=12&cm=1002&userdata=1')), isFalse);
    });

    test('Absenden: nur mit Marke der Sicherungsseite, sesskey und ohne Nutzerdaten', () {
      final url = Uri.parse('https://m.example/backup/backup.php');
      expect(z.erlaubt('POST', url, bestaetigung()), isTrue);
      expect(z.erlaubt('POST', url, bestaetigung(users: '1')), isFalse);
      expect(z.erlaubt('POST', url, [e('stage', '4'), e('sesskey', 'abc')]), isFalse);
    });
  });

  group('Vorgänge', () {
    late Directory ordner;
    setUp(() => ordner = Directory.systemTemp.createTempSync('sicherung_test'));
    tearDown(() => ordner.deleteSync(recursive: true));

    test('Stand überlebt einen neuen Lesevorgang (Client-Abbruch)', () async {
      final v = Vorgaenge(ordner.path);
      final vg = await v.neu(kurs: 12, cmid: 1002, datei: 'Unterricht/page-cm1002-x.mbz');
      await v.aktualisieren(vg, stand: SicherungStand.laufend, backupid: '42', kontext: 99);

      final neu = await Vorgaenge(ordner.path).finde(vg.id);
      expect(neu, isNotNull);
      expect(neu!.stand, SicherungStand.laufend);
      expect(neu.backupid, '42');
      expect(neu.kontext, 99);
      expect(File('${ordner.path}/vorgaenge.json.tmp').existsSync(), isFalse);
    });

    test('beschädigte Datei: Fehler, nichts überschrieben', () async {
      File('${ordner.path}/vorgaenge.json').writeAsStringSync('{kaputt');
      await expectLater(Vorgaenge(ordner.path).alle(), throwsA(isA<MoodleFehler>()));
      expect(File('${ordner.path}/vorgaenge.json').readAsStringSync(), '{kaputt');
    });

    test('freierName: nie ein vorhandener Name, auch nicht ein laufender', () async {
      expect(await freierName(ordner.path, 'x.mbz'), 'x.mbz');
      File('${ordner.path}/x.mbz').writeAsStringSync('');
      expect(await freierName(ordner.path, 'x.mbz'), 'x-2.mbz');
      File('${ordner.path}/x-2.mbz.teil').writeAsStringSync('');
      expect(await freierName(ordner.path, 'x.mbz'), 'x-3.mbz');
    });
  });
}
