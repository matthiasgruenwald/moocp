// Ticket #21 (Spec #17, E2, E3): Bilder und Anhänge importierter Aktivitäten
// zurücklesen und mit der Quellaufnahme im Archiv vergleichen.
//
// Die Moodle-Grenze ist ein Doppel (MoodleZugang mit vorgegebenen Antworten für
// Formulare und Dateiadressen). Geprüft wird über die öffentlichen Funktionen:
// die Regeln ohne Netz und der Statusaufruf, der nach der Verbergung den Bericht
// schreibt und später wieder ausgibt.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/moodle/sicherung.dart';
import 'package:moocp/moodle/wiederherstellung.dart';
import 'package:moocp/moodle/wiederherstellung_anhaenge.dart';
import 'package:moocp/moodle/wiederherstellung_regeln.dart';
import 'package:moocp/protokoll.dart';

String _sha(List<int> bytes) => sha1.convert(bytes).toString();

Uint8List _mbz(Map<String, List<int>> dateien) {
  final archiv = Archive();
  dateien.forEach((name, inhalt) => archiv.addFile(ArchiveFile.bytes(name, inhalt)));
  final tar = TarEncoder().encodeBytes(archiv);
  return Uint8List.fromList(GZipEncoder().encodeBytes(tar));
}

Antwort _antwort(int status, List<int> bytes) =>
    Antwort(status, Uri.parse('http://127.0.0.1/'), Uint8List.fromList(bytes), 'text/html');

/// Eine Sicherung mit einer Seite „Infoblatt" und einem Bild in ihrer Quellaufnahme.
Uint8List _archiv({required List<int> bild, bool mitNutzerdatei = false}) {
  const backup = '<moodle_backup><activities><activity><modulename>page</modulename>'
      '<title>Infoblatt</title><directory>activities/page_7</directory></activity></activities></moodle_backup>';
  final files = StringBuffer('<files>'
      '<file><id>1</id><contenthash>${_sha(bild)}</contenthash><filename>bild.png</filename>'
      '<filepath>/</filepath><component>mod_page</component><filearea>content</filearea></file>'
      '<file><id>2</id><contenthash>${_sha(const [1])}</contenthash><filename>eigen.png</filename>'
      '<filepath>/</filepath><component>user</component><filearea>draft</filearea></file>'
      '<file><id>3</id><contenthash>x</contenthash><filename>.</filename>'
      '<filepath>/</filepath><component>mod_page</component><filearea>content</filearea></file>'
      '</files>');
  return _mbz({
    'moodle_backup.xml': utf8.encode(backup),
    'activities/page_7/inforef.xml': utf8.encode(mitNutzerdatei
        ? '<inforef><fileref><file><id>1</id></file><file><id>2</id></file></fileref></inforef>'
        : '<inforef><fileref><file><id>1</id></file></fileref></inforef>'),
    'files.xml': utf8.encode(files.toString()),
  });
}

/// Moodle-Doppel: Fortschritt, Kursstruktur, Formulare und Dateiadressen.
class _Moodle extends MoodleZugang {
  _Moodle(this.seiten, {required this.neueCmids}) : super(Protokoll());

  /// Pfad (mit Query) -> Antwort. Fehlt ein Pfad, antwortet der Server mit 404.
  final Map<String, Antwort> seiten;

  /// Zusätzliche neue Aktivitäten im Kurs (cmid, modul, titel).
  final List<(int, String, String)> neueCmids;
  final Map<int, bool> sichtbar = {1: true};
  final Map<int, String> namen = {1: 'Alt'};

  @override
  Future<Object?> dienst(String name, Map<String, Object?> args) async {
    if (name == 'core_backup_get_async_backup_progress') {
      return [
        {'backupid': 'r-1', 'progress': 1, 'status': 1000},
      ];
    }
    if (name == 'core_courseformat_update_course') {
      for (final id in (args['ids'] as List).cast<int>()) {
        sichtbar[id] = false;
      }
      return null;
    }
    if (name == 'core_courseformat_get_state') {
      for (final (cmid, _, titel) in neueCmids) {
        sichtbar.putIfAbsent(cmid, () => true);
        namen[cmid] = titel;
      }
      final cms = <Map<String, Object?>>[];
      for (final id in sichtbar.keys) {
        final neu = neueCmids.where((c) => c.$1 == id).firstOrNull;
        cms.add({
          'id': id,
          'visible': sichtbar[id]! ? 1 : 0,
          'module': neu?.$2 ?? 'label',
          'name': namen[id],
          'sectionid': 1,
        });
      }
      return {
        'cm': cms,
        'section': [
          {'id': 1, 'cmlist': sichtbar.keys.toList()},
        ],
      };
    }
    throw MoodleFehler('Unerwarteter Dienst im Test: $name');
  }

  @override
  Future<Antwort> lesen(String pfadMitQuery) async =>
      seiten[pfadMitQuery] ?? _antwort(404, utf8.encode('nicht gefunden'));
}

void main() {
  final bild = utf8.encode('PNG-Testinhalt');

  group('Quelldateien aus dem Archiv', () {
    test('nennt die Datei der Aktivität mit Prüfsumme; Nutzerdateien bleiben außen', () {
      final mbz = _archiv(bild: bild, mitNutzerdatei: true);

      final dateien = quelldateienAus(mbz, modul: 'page', titel: 'Infoblatt');

      expect(dateien, [(name: 'bild.png', sha1: _sha(bild), dateimanager: false)]);
    });

    test('Dateien einer Datei-Aktivität liegen im Dateimanager', () {
      final mbz = _mbz({
        'moodle_backup.xml': utf8.encode('<moodle_backup><activities><activity><modulename>resource</modulename>'
            '<title>Blatt</title><directory>activities/resource_3</directory></activity></activities></moodle_backup>'),
        'activities/resource_3/inforef.xml': utf8.encode('<inforef><fileref><file><id>1</id></file></fileref></inforef>'),
        'files.xml': utf8.encode('<files><file><id>1</id><contenthash>abc</contenthash><filename>blatt.pdf</filename>'
            '<component>mod_resource</component><filearea>content</filearea></file></files>'),
      });
      expect(quelldateienAus(mbz, modul: 'resource', titel: 'Blatt'),
          [(name: 'blatt.pdf', sha1: 'abc', dateimanager: true)]);
    });

    test('fehlende Quellaufnahme ist null, nicht leer', () {
      final ohneInforef = _mbz({
        'moodle_backup.xml': utf8.encode('<moodle_backup><activities><activity><modulename>page</modulename>'
            '<title>Infoblatt</title><directory>activities/page_7</directory></activity></activities></moodle_backup>'),
        'files.xml': utf8.encode('<files/>'),
      });

      expect(quelldateienAus(ohneInforef, modul: 'page', titel: 'Infoblatt'), isNull);
      expect(quelldateienAus(_archiv(bild: bild), modul: 'page', titel: 'Unbekannt'), isNull);
      expect(quelldateienAus(Uint8List.fromList([1, 2, 3]), modul: 'page', titel: 'Infoblatt'), isNull);
    });
  });

  group('Verweise im Formular', () {
    test('escapetes HTML: Adresse ohne Query, Entwurf erkannt, Host verworfen', () {
      const html = '<textarea>&lt;img src=&quot;https://m.example/draftfile.php/12/user/draft/77/bild.png?x=1&quot;'
          '&gt; &lt;a href=&quot;https://fremd.example/pluginfile.php/9/mod_page/content/1/z.pdf&quot;&gt;</textarea>';

      final v = verweiseAus(html);

      expect(v, [
        (entwurf: true, pfad: '/draftfile.php/12/user/draft/77/bild.png', name: 'bild.png'),
        (entwurf: false, pfad: '/pluginfile.php/9/mod_page/content/1/z.pdf', name: 'z.pdf'),
      ]);
    });
  });

  group('Vergleich', () {
    const quelle = [(name: 'bild.png', sha1: 'aaa', dateimanager: false)];
    ZielAbruf ok(String name, String sha) => (name: name, entwurf: false, status: 200, sha1: sha);

    test('identische Datei: vollständig, nichts zu melden', () {
      final p = vergleicheAnhaenge(quelle: quelle, ziel: [ok('bild.png', 'aaa')]);
      expect(p.vollstaendig, isTrue);
      expect(p.befunde, isEmpty);
    });

    test('Datei im Dateimanager ist nicht lesbar: Prüflücke, kein „fehlend im Ziel"', () {
      final p = vergleicheAnhaenge(
          quelle: [(name: 'blatt.pdf', sha1: 'bbb', dateimanager: true)], ziel: []);
      expect(p.vollstaendig, isFalse);
      expect(p.text, contains('Prüflücke'));
      expect(p.text, contains('blatt.pdf'));
      expect(p.text, contains('nicht lesbar'));
      expect(p.text, isNot(contains('fehlend')));
    });

    test('fehlende Datei: nicht vollständig', () {
      final p = vergleicheAnhaenge(quelle: quelle, ziel: []);
      expect(p.vollstaendig, isFalse);
      expect(p.text, contains('fehlend'));
    });

    test('geänderte Datei (anderer Inhalt bei gleichem Namen)', () {
      final p = vergleicheAnhaenge(quelle: quelle, ziel: [ok('bild.png', 'bbb')]);
      expect(p.vollstaendig, isFalse);
      expect(p.text, contains('geändert'));
    });

    test('HTTP 500 auf eine Datei verhindert die Verifikation', () {
      final p = vergleicheAnhaenge(quelle: quelle,
          ziel: [(name: 'bild.png', entwurf: false, status: 500, sha1: null)]);
      expect(p.vollstaendig, isFalse);
      expect(p.text, contains('HTTP 500'));
    });

    test('Entwurfsadresse, die ins Leere zeigt, ist verwaist', () {
      final p = vergleicheAnhaenge(quelle: quelle,
          ziel: [(name: 'bild.png', entwurf: true, status: 404, sha1: null)]);
      expect(p.vollstaendig, isFalse);
      expect(p.text, contains('verwaiste Entwurfsadresse'));
    });

    test('fremde Referenz, die die Quelle nicht kennt', () {
      final p = vergleicheAnhaenge(quelle: quelle, ziel: [ok('bild.png', 'aaa'), ok('fremd.png', 'ccc')]);
      expect(p.vollstaendig, isFalse);
      expect(p.text, contains('fremd'));
    });

    test('fehlende Quellaufnahme ist ausdrücklich genannt', () {
      final p = vergleicheAnhaenge(quelle: null, ziel: [ok('bild.png', 'aaa')]);
      expect(p.vollstaendig, isFalse);
      expect(p.text, contains('Quellaufnahme fehlt'));
    });
  });

  group('Statusaufruf mit Anhangsprüfung', () {
    late Directory ordner;
    late DateTime nun;

    setUp(() {
      nun = DateTime(2026, 10, 18, 10, 0);
      ordner = Directory.systemTemp.createTempSync('anhaenge');
      jetzt = () => nun;
      schlafe = (d) async => nun = nun.add(d);
    });

    tearDown(() {
      jetzt = DateTime.now;
      schlafe = (d) => Future<void>.delayed(d);
      ordner.deleteSync(recursive: true);
    });

    /// Ein fertiger Wiederherstellungsvorgang; das Archiv liegt im Sicherungsordner.
    Future<Vorgang> fertigerVorgang(Vorgaenge vg, {Uint8List? archiv}) async {
      final bytes = archiv ?? _archiv(bild: bild);
      File('${ordner.path}/b.mbz').writeAsBytesSync(bytes);
      final v = await vg.neuWiederherstellung(kurs: 12, datei: 'b.mbz',
          fingerabdruck: fingerabdruck(bytes, instanz: 'Test', kurs: 12, weg: Zielweg.aktuellerKursVerschmelzen));
      await vg.aktualisieren(v,
          wiederherstellung: WiederherstellungStand.laufend,
          backupid: 'r-1',
          kontext: 77,
          vorherCmids: [1],
          wiederherstellungAktivitaeten: [(modul: 'page', titel: 'Infoblatt')]);
      return v;
    }

    Antwort formular(int cmid) => _antwort(200, utf8.encode(
        '<textarea>&lt;img src=&quot;/draftfile.php/12/user/draft/77/bild.png&quot;&gt;</textarea>'));

    test('identische Datei: verborgen und verified, Bericht im Status', () async {
      final vg = Vorgaenge(ordner.path);
      final v = await fertigerVorgang(vg);
      final moodle = _Moodle({
        '/course/modedit.php?update=2': formular(2),
        '/draftfile.php/12/user/draft/77/bild.png': _antwort(200, bild),
      }, neueCmids: [(2, 'page', 'Infoblatt')]);

      final text = await wiederherstellungStatus(moodle, vg, id: v.id);
      final nachher = await vg.finde(v.id);

      expect(text, contains('verglichen'));
      expect(nachher!.verified, isTrue);
      expect(nachher.text, contains('verglichen'));
    });

    test('HTTP-Fehler beim Lesen einer Datei: nicht verified, Status nennt den Fehler', () async {
      final vg = Vorgaenge(ordner.path);
      final v = await fertigerVorgang(vg);
      final moodle = _Moodle({
        '/course/modedit.php?update=2': formular(2),
        '/draftfile.php/12/user/draft/77/bild.png': _antwort(500, const []),
      }, neueCmids: [(2, 'page', 'Infoblatt')]);

      await wiederherstellungStatus(moodle, vg, id: v.id);
      final nachher = await vg.finde(v.id);

      expect(nachher!.verified, isFalse);
      final spaeter = await wiederherstellungStatus(moodle, vg, id: v.id);
      expect(spaeter, contains('HTTP 500'));
    });

    test('fehlende Quellaufnahme (Sicherung weg): nicht verified und ausdrücklich genannt', () async {
      final vg = Vorgaenge(ordner.path);
      final v = await fertigerVorgang(vg);
      File('${ordner.path}/b.mbz').deleteSync();
      final moodle = _Moodle({
        '/course/modedit.php?update=2': formular(2),
        '/draftfile.php/12/user/draft/77/bild.png': _antwort(200, bild),
      }, neueCmids: [(2, 'page', 'Infoblatt')]);

      await wiederherstellungStatus(moodle, vg, id: v.id);
      final nachher = await vg.finde(v.id);

      expect(nachher!.verified, isFalse);
      expect(nachher.text, contains('Quellaufnahme fehlt'));
    });

    test('unlesbares Archiv mit passendem Hash: Prüflücke „Quellaufnahme fehlt", nie verified', () async {
      final vg = Vorgaenge(ordner.path);
      final v = await fertigerVorgang(vg, archiv: Uint8List.fromList([1, 2, 3]));
      final moodle = _Moodle({
        '/course/modedit.php?update=2': formular(2),
        '/draftfile.php/12/user/draft/77/bild.png': _antwort(200, bild),
      }, neueCmids: [(2, 'page', 'Infoblatt')]);

      await wiederherstellungStatus(moodle, vg, id: v.id);
      final nachher = await vg.finde(v.id);

      expect(nachher!.verified, isFalse);
      expect(nachher.text, contains('Quellaufnahme fehlt'));
    });

    test('konkurrierende neue Aktivitäten: keine Zuordnung, keine Anhangsprüfung, nichts verborgen', () async {
      final vg = Vorgaenge(ordner.path);
      final v = await fertigerVorgang(vg);
      final moodle = _Moodle({
        '/course/modedit.php?update=2': formular(2),
      }, neueCmids: [(2, 'page', 'Infoblatt'), (3, 'page', 'Infoblatt')]);

      await wiederherstellungStatus(moodle, vg, id: v.id);
      final nachher = await vg.finde(v.id);

      expect(nachher!.verified, isFalse);
      expect(nachher.text, contains('nicht eindeutig'));
      expect(nachher.text, isNot(contains('verglichen')));
      expect(moodle.sichtbar[2], isTrue);
      expect(moodle.sichtbar[3], isTrue);
    });
  });
}
