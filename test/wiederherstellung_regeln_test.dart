// Offline prüfbar: die Archivprüfung der Wiederherstellung (moodle/wiederherstellung_regeln.dart),
// die Positivliste für Upload, Kurs und Assistenten und die erlaubten Übergänge.
// Die Archive sind hier nachgebaut (gzip + ustar); der Ablauf gegen Moodle ist nicht geprüft.
import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/moodle/wiederherstellung_regeln.dart';
import 'package:moocp/protokoll.dart';

/// Ein Tar-Eintrag mit 512-Byte-Kopf (ustar), Daten auf 512 Byte aufgefüllt.
List<int> _eintrag(String name, List<int> inhalt, {int typ = 0x30, bool falscheSumme = false}) {
  final kopf = Uint8List(512);
  void schreibe(int von, String s) {
    final b = latin1.encode(s);
    kopf.setRange(von, von + b.length, b);
  }

  schreibe(0, name);
  schreibe(100, '0000644\u0000');
  schreibe(108, '0000000\u0000');
  schreibe(116, '0000000\u0000');
  schreibe(124, '${inhalt.length.toRadixString(8).padLeft(11, '0')}\u0000');
  schreibe(136, '00000000000\u0000');
  kopf[156] = typ;
  schreibe(257, 'ustar\u000000');
  // Prüfsumme: mit Leerzeichen im Feld berechnen, dann eintragen.
  kopf.fillRange(148, 156, 0x20);
  var summe = 0;
  for (final b in kopf) {
    summe += b;
  }
  if (falscheSumme) summe += 1;
  schreibe(148, '${summe.toRadixString(8).padLeft(6, '0')}\u0000 ');
  final daten = [...inhalt, ...List<int>.filled((512 - inhalt.length % 512) % 512, 0)];
  return [...kopf, ...daten];
}

/// Ein Tar-Archiv aus Einträgen, mit dem üblichen Abschluss aus Nullblöcken.
Uint8List _tar(List<List<int>> eintraege) =>
    Uint8List.fromList([...eintraege.expand((e) => e), ...List<int>.filled(1024, 0)]);

String _sicherungXml({String typ = 'activity', String nutzer = '0', String titel = 'ZZ Testseite'}) => '''
<?xml version="1.0" encoding="UTF-8"?>
<moodle_backup>
  <information>
    <moodle_version>2024100700</moodle_version>
    <format>moodle2</format>
    <type>$typ</type>
    <activities>
      <activity>
        <modulename>page</modulename>
        <title>$titel</title>
      </activity>
    </activities>
    <settings>
      <setting><name>users</name><value>$nutzer</value></setting>
    </settings>
  </information>
</moodle_backup>
''';

List<int> _xml(String s) => utf8.encode(s);

Uint8List _mbz(List<List<int>> eintraege) => Uint8List.fromList(gzip.encode(_tar(eintraege)));

Uint8List _gueltig({String nutzer = '0', String titel = 'ZZ Testseite'}) => _mbz([
      _eintrag('moodle_backup.xml', _xml(_sicherungXml(nutzer: nutzer, titel: titel))),
      _eintrag('activities/page_1/page.xml', _xml('<activity/>')),
    ]);

void main() {
  group('Archivprüfung', () {
    test('gültige Aktivitätssicherung wird angenommen und nennt Art und Titel', () async {
      final b = await archivPruefen(_gueltig());
      expect(b.ok, isTrue, reason: b.grund);
      expect(b.typ, 'activity');
      expect(b.moodleVersion, '2024100700');
      expect(b.aktivitaeten.single.modul, 'page');
      expect(b.aktivitaeten.single.titel, 'ZZ Testseite');
    });

    test('gültiger Kurs ohne Nutzerdaten wird angenommen', () async {
      final b = await archivPruefen(_mbz([
        _eintrag('moodle_backup.xml', _xml(_sicherungXml(typ: 'course'))),
      ]));
      expect(b.ok, isTrue, reason: b.grund);
      expect(b.typ, 'course');
    });

    test('keine gepackte Datei: abgelehnt, ohne zu entpacken', () async {
      final b = await archivPruefen(Uint8List.fromList(List.filled(64, 7)));
      expect(b.ok, isFalse);
    });

    test('beschädigte gzip-Datei wird abgelehnt', () async {
      final b = await archivPruefen(Uint8List.fromList([0x1f, 0x8b, 8, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]));
      expect(b.ok, isFalse);
    });

    test('abgeschnittene Sicherung wird abgelehnt', () async {
      final voll = _gueltig();
      final b = await archivPruefen(Uint8List.sublistView(voll, 0, voll.length ~/ 2));
      expect(b.ok, isFalse);
    });

    test('Pfad mit „..“ im Archiv wird abgelehnt', () async {
      final b = await archivPruefen(_mbz([
        _eintrag('moodle_backup.xml', _xml(_sicherungXml())),
        _eintrag('../../etc/evil.txt', _xml('x')),
      ]));
      expect(b.ok, isFalse);
      expect(b.grund, contains('Pfad'));
    });

    test('absoluter Pfad im Archiv wird abgelehnt', () async {
      final b = await archivPruefen(_mbz([
        _eintrag('moodle_backup.xml', _xml(_sicherungXml())),
        _eintrag('/tmp/x.txt', _xml('x')),
      ]));
      expect(b.ok, isFalse);
    });

    test('Link im Archiv wird abgelehnt', () async {
      final b = await archivPruefen(_mbz([
        _eintrag('moodle_backup.xml', _xml(_sicherungXml())),
        _eintrag('link', const [], typ: 0x32),
      ]));
      expect(b.ok, isFalse);
    });

    test('falsche Prüfsumme im Tar-Kopf wird abgelehnt', () async {
      final b = await archivPruefen(_mbz([
        _eintrag('moodle_backup.xml', _xml(_sicherungXml()), falscheSumme: true),
      ]));
      expect(b.ok, isFalse);
    });

    test('Nutzerdaten im Archiv (Einstellung users = 1) werden abgelehnt', () async {
      final b = await archivPruefen(_gueltig(nutzer: '1'));
      expect(b.ok, isFalse);
      expect(b.grund, contains('Nutzerdaten'));
    });

    test('Nutzerdatei im Archiv (users.xml) wird abgelehnt', () async {
      final b = await archivPruefen(_mbz([
        _eintrag('moodle_backup.xml', _xml(_sicherungXml())),
        _eintrag('users.xml', _xml('<users/>')),
      ]));
      expect(b.ok, isFalse);
      expect(b.grund, contains('Nutzerdaten'));
    });

    test('Bewertungen einer Person in grades.xml werden abgelehnt', () async {
      final b = await archivPruefen(_mbz([
        _eintrag('moodle_backup.xml', _xml(_sicherungXml())),
        _eintrag('grades.xml', _xml('<grade_grades><grade_grade><userid>5</userid></grade_grade></grade_grades>')),
      ]));
      expect(b.ok, isFalse);
    });

    test('Archiv ohne moodle_backup.xml wird abgelehnt', () async {
      final b = await archivPruefen(_mbz([_eintrag('andere.xml', _xml('<x/>'))]));
      expect(b.ok, isFalse);
    });

    test('Sicherung über der Größe (gepackt) wird vor dem Lesen abgelehnt', () async {
      final b = await archivPruefen(_gueltig(), maxBytes: 50);
      expect(b.ok, isFalse);
      expect(b.grund, contains('größer'));
    });

    test('entpackter Inhalt über der Grenze wird abgelehnt', () async {
      final b = await archivPruefen(_gueltig(), maxEntpackt: 100);
      expect(b.ok, isFalse);
    });

    test('zu viele Einträge werden abgelehnt', () async {
      final b = await archivPruefen(_gueltig(), maxEintraege: 1);
      expect(b.ok, isFalse);
    });

    test('leere Bewertungs- und Rollendateien einer Sicherung ohne Nutzerdaten werden angenommen (Regression Live-Messung #8)', () async {
      // Form wie in der gemessenen Sicherung: das Wurzelelement grade_history ist kein Eintrag zu einer Person.
      final b = await archivPruefen(_mbz([
        _eintrag('moodle_backup.xml', _xml(_sicherungXml())),
        _eintrag('grades.xml', _xml('<grade_grades>\n</grade_grades>\n')),
        _eintrag('grade_history.xml', _xml('<grade_history>\n  <grade_grades>\n  </grade_grades>\n</grade_history>\n')),
        _eintrag('roles.xml', _xml('<roles>\n  <role_assignments>\n  </role_assignments>\n</roles>\n')),
        _eintrag('activities/page_1/page.xml', _xml('<activity/>')),
      ]));
      expect(b.ok, isTrue, reason: b.grund);
    });

    test('Format, das kein Moodle-2-Archiv ist, wird abgelehnt', () async {
      final xml = _sicherungXml().replaceAll('moodle2', 'moodle1');
      final b = await archivPruefen(_mbz([_eintrag('moodle_backup.xml', _xml(xml))]));
      expect(b.ok, isFalse);
    });
  });

  group('Pfade und Nutzerdaten', () {
    test('pfadFehler', () {
      expect(pfadFehler('a/b.txt'), isNull);
      expect(pfadFehler('../x'), isNotNull);
      expect(pfadFehler('a/../../x'), isNotNull);
      expect(pfadFehler('/etc/x'), isNotNull);
      expect(pfadFehler(r'C:\x'), isNotNull);
      expect(pfadFehler(''), isNotNull);
    });

    test('nutzerdatenPfad', () {
      expect(nutzerdatenPfad('users.xml'), isTrue);
      expect(nutzerdatenPfad('activities/page_1/userdata/x.xml'), isTrue);
      expect(nutzerdatenPfad('user/files.xml'), isTrue);
      expect(nutzerdatenPfad('activities/page_1/page.xml'), isFalse);
    });

  });

  group('Archividentität beim Gegenlesen', () {
    const erwartet = [(modul: 'page', titel: 'Infoblatt')];

    test('ordnet die einzelne passende neue Aktivität zu', () {
      expect(importierteCmidsEindeutig(erwartet: erwartet, vorher: {4}, aktuell: const [
        (cmid: 4, modul: 'page', titel: 'Alt'),
        (cmid: 9, modul: 'page', titel: 'Infoblatt'),
      ]), [9]);
    });

    test('lässt parallele und mehrdeutige Neuanlagen unzugeordnet', () {
      expect(importierteCmidsEindeutig(erwartet: erwartet, vorher: {4}, aktuell: const [
        (cmid: 9, modul: 'page', titel: 'Infoblatt'),
        (cmid: 10, modul: 'forum', titel: 'Lehrkraft-Beitrag'),
      ]), isNull);
      expect(importierteCmidsEindeutig(erwartet: erwartet, vorher: {}, aktuell: const [
        (cmid: 9, modul: 'page', titel: 'Infoblatt'),
        (cmid: 10, modul: 'page', titel: 'Infoblatt'),
      ]), isNull);
      expect(importierteCmidsEindeutig(erwartet: const [
        (modul: 'page', titel: 'Infoblatt'), (modul: 'page', titel: 'Infoblatt')
      ], vorher: {}, aktuell: const [
        (cmid: 9, modul: 'page', titel: 'Infoblatt'),
        (cmid: 10, modul: 'page', titel: 'Infoblatt'),
      ]), isNull);
    });
  });

  group('Zustandsfolge', () {
    test('der gemessene Weg ist erlaubt', () {
      const folge = [
        WiederherstellungStand.anstehend,
        WiederherstellungStand.hochgeladen,
        WiederherstellungStand.laufend,
        WiederherstellungStand.fertig,
      ];
      for (var i = 0; i < folge.length - 1; i++) {
        expect(erlaubterUebergang(folge[i], folge[i + 1]), isTrue, reason: '${folge[i]} -> ${folge[i + 1]}');
      }
    });

    test('vor dem Start abbrechen ist erlaubt, nach dem Start nicht stillschweigend', () {
      expect(erlaubterUebergang(WiederherstellungStand.anstehend, WiederherstellungStand.fehlgeschlagen), isTrue);
      expect(erlaubterUebergang(WiederherstellungStand.hochgeladen, WiederherstellungStand.fehlgeschlagen), isTrue);
      expect(erlaubterUebergang(WiederherstellungStand.laufend, WiederherstellungStand.unklar), isTrue);
      expect(erlaubterUebergang(WiederherstellungStand.unklar, WiederherstellungStand.fertig), isTrue);
    });

    test('ohne Start nie laufend, und nie direkt von anstehend nach fertig', () {
      expect(erlaubterUebergang(WiederherstellungStand.anstehend, WiederherstellungStand.laufend), isFalse);
      expect(erlaubterUebergang(WiederherstellungStand.anstehend, WiederherstellungStand.fertig), isFalse);
      expect(erlaubterUebergang(WiederherstellungStand.hochgeladen, WiederherstellungStand.fertig), isFalse);
    });

    test('fertig und fehlgeschlagen bewegen sich nicht mehr', () {
      for (final nach in WiederherstellungStand.values) {
        expect(erlaubterUebergang(WiederherstellungStand.fertig, nach), isFalse);
        expect(erlaubterUebergang(WiederherstellungStand.fehlgeschlagen, nach), isFalse);
      }
    });

    test('unklar löst sich nie zurück nach anstehend oder hochgeladen', () {
      expect(erlaubterUebergang(WiederherstellungStand.unklar, WiederherstellungStand.anstehend), isFalse);
      expect(erlaubterUebergang(WiederherstellungStand.unklar, WiederherstellungStand.laufend), isFalse);
    });

    test('Stand aus Text: unbekannt wird null', () {
      expect(WiederherstellungStand.aus('laufend'), WiederherstellungStand.laufend);
      expect(WiederherstellungStand.aus('quatsch'), isNull);
      expect(WiederherstellungStand.aus(null), isNull);
    });
  });

  group('Positivliste für die Wiederherstellung', () {
    final z = MoodleZugang(Protokoll());
    bool post(String a, [List<MapEntry<String, String>>? f, Anhang? anhang]) =>
        z.erlaubt('POST', Uri.parse(a), f, null, anhang);
    bool get(String a) => z.erlaubt('GET', Uri.parse(a));
    const kurs = <MapEntry<String, String>>[];

    Anhang mbz({String mime = 'application/octet-stream', String name = 'kurs-12.mbz'}) =>
        Anhang('repo_upload_file', name, [1, 2, 3], mime);

    test('Kursseite nur mit id', () {
      expect(get('https://m.example/course/view.php?id=42'), isTrue);
      expect(get('https://m.example/course/view.php?id=42&edit=on'), isFalse);
      expect(kurs, isEmpty);
    });

    test('Upload einer .mbz nur mit Entwurfsbereich, Sitzung und passendem Namen und MIME', () {
      const formular = [MapEntry('itemid', '7'), MapEntry('sesskey', 'abc')];
      const up = 'https://m.example/repository/repository_ajax.php?action=upload';
      expect(post(up, formular, mbz()), isTrue);
      expect(post(up, formular, mbz(mime: 'text/plain')), isFalse);
      expect(post(up, formular, mbz(name: '../evil.mbz')), isFalse);
      expect(post(up, const [MapEntry('sesskey', 'abc')], mbz()), isFalse);
    });

    test('andere Dateien laufen nicht über den .mbz-Pfad, und ohne Datei gibt es keinen Upload', () {
      const up = 'https://m.example/repository/repository_ajax.php?action=upload';
      expect(post(up, null, Anhang('repo_upload_file', 'bild.png', [1], 'image/png')), isTrue);
      expect(post(up, null, mbz()), isFalse);
      expect(post(up), isFalse);
    });

    test('Formular „Wiederherstellen" nur mit der Marke und Kurs-ID', () {
      const ziel = 'https://m.example/backup/restorefile.php?contextid=5';
      const gut = [
        MapEntry('_qf__course_restore_form', '1'),
        MapEntry('sesskey', 'abc'),
        MapEntry('backupfile', '99'),
      ];
      expect(post(ziel, gut), isTrue);
      expect(post(ziel, [...gut, const MapEntry('submitbutton', 'Weiter')]), isTrue);
      expect(post(ziel, [...gut, const MapEntry('contextid', '5')]), isTrue);
      expect(post('https://m.example/backup/restorefile.php?contextid=5&x=1', gut), isFalse);
      expect(post(ziel, const [MapEntry('sesskey', 'abc'), MapEntry('backupfile', '99')]), isFalse);
      // Jedes weitere Feld lehnt die Regel ab, auch wenn Marke, Sitzung und Itemid stimmen.
      expect(post(ziel, [...gut, const MapEntry('name', 'x')]), isFalse);
      expect(post(ziel, [...gut, const MapEntry('contextid', 'abc')]), isFalse);
      expect(post(ziel, [...gut]..[2] = const MapEntry('backupfile', 'abc')), isFalse);
    });

    test('Weiterleitung nach dem Hochladen nur mit Dateiablagen-Hash und den erlaubten Schlüsseln', () {
      const hash = 'da39a3ee5e6b4b0d3255bfef95601890afd80709';
      expect(get('https://m.example/backup/restore.php?contextid=5&pathnamehash=$hash'), isTrue);
      expect(get('https://m.example/backup/restore.php?contextid=5&pathnamehash=$hash&component=backup&filearea=draft'),
          isTrue);
      expect(get('https://m.example/backup/restore.php?contextid=5&pathnamehash=xyz'), isFalse);
      expect(get('https://m.example/backup/restore.php?contextid=5&pathnamehash=$hash&extra=1'), isFalse);
      expect(get('https://m.example/backup/restore.php?contextid=5'), isFalse);
    });

    test('Sicherungsdetails (stage 2) nur mit den gemessenen Feldern', () {
      const ziel = 'https://m.example/backup/restore.php?contextid=5&filename=kurs.mbz';
      const gut = [
        MapEntry('contextid', '5'),
        MapEntry('filepath', '/'),
        MapEntry('filename', 'kurs.mbz'),
        MapEntry('stage', '2'),
        MapEntry('sesskey', 'abc'),
      ];
      expect(post(ziel, gut), isTrue);
      expect(post(ziel, [...gut, const MapEntry('name', 'x')]), isFalse);
      expect(post(ziel, [...gut]..[3] = const MapEntry('stage', '4')), isFalse);
      expect(post(ziel, [...gut, const MapEntry('_qf__restore_target_form', '1')]), isFalse);
    });

    test('Zielwahl (Formular mit stage 4) nur mit target 4, Kurs-ID und den gemessenen Feldern', () {
      const ziel = 'https://m.example/backup/restore.php?contextid=5&filename=kurs.mbz';
      const gut = [
        MapEntry('contextid', '5'),
        MapEntry('filepath', '/'),
        MapEntry('filename', 'kurs.mbz'),
        MapEntry('stage', '4'),
        MapEntry('target', '4'),
        MapEntry('targetid', '42'),
        MapEntry('search', ''),
        MapEntry('sesskey', 'abc'),
      ];
      expect(post(ziel, gut), isTrue);
      expect(post(ziel, [...gut]..[4] = const MapEntry('target', '2')), isFalse);
      expect(post(ziel, [...gut]..[5] = const MapEntry('targetid', 'x')), isFalse);
      expect(post(ziel, [...gut, const MapEntry('_qf__restore_target_form', '1')]), isFalse);
      expect(post(ziel, [...gut, const MapEntry('setting_root_users', '1')]), isFalse);
    });

    test('Schritte 4, 8, 16 nur ohne Nutzerdaten und mit dem Schalter restore', () {
      const ziel = 'https://m.example/backup/restore.php?contextid=5&filename=kurs.mbz';
      const schritte = [('4', 'settings'), ('8', 'schema'), ('16', 'review')];
      for (final (schritt, form) in schritte) {
        final gut = [
          MapEntry('stage', schritt),
          MapEntry('_qf__restore_${form}_form', '1'),
          const MapEntry('restore', 'Weiter'),
          const MapEntry('sesskey', 'abc'),
        ];
        expect(post(ziel, gut), isTrue, reason: 'Schritt $schritt');
        expect(post(ziel, gut.where((e) => e.key != 'restore').toList()), isFalse, reason: 'ohne restore, $schritt');
        expect(post(ziel, [...gut, const MapEntry('setting_root_users', '1')]), isFalse, reason: 'Nutzer, $schritt');
      }
    });

    test('der Assistent-Aufruf nimmt nur contextid und filename, mit sicheren Zeichen', () {
      expect(get('https://m.example/backup/restore.php?contextid=5&filename=kurs-12.mbz'), isTrue);
      expect(get('https://m.example/backup/restore.php?contextid=5&filename=../x'), isFalse);
      expect(get('https://m.example/backup/restore.php?contextid=5&filename=k.mbz&extra=1'), isFalse);
    });
  });

  // Befund 8: ein nicht schreibbarer Typ darf nie verifiziert werden.
  group('nichtSchreibbarePruefluecke', () {
    test('nur schreibbare Typen: keine Prüflücke', () {
      expect(nichtSchreibbarePruefluecke(['page', 'quiz', 'resource']), isNull);
    });

    test('nicht schreibbarer Typ: Prüflücke nennt den Typ', () {
      final t = nichtSchreibbarePruefluecke(['page', 'lernlandkarte']);
      expect(t, isNotNull);
      expect(t, contains('lernlandkarte'));
    });
  });
}
