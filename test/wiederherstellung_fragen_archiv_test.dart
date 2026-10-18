// Offline prüfbar: die Fragen eines Quiz im Sicherungsarchiv (activities/quiz_*/quiz.xml
// und questions.xml) und ihre Abbildung auf die Herkunftsprüfung. Alle Namen sind erfunden
// (ZZ-Präfix). Das echte Moodle-Format ist nicht gemessen (UNGEMESSEN, TODO.md): die Tests
// prüfen nur die hier festgelegte Lesart.
import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/wiederherstellung_fragen.dart';
import 'package:moocp/moodle/wiederherstellung_regeln.dart';

List<int> _eintrag(String name, List<int> inhalt) {
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
  kopf[156] = 0x30;
  schreibe(257, 'ustar\u000000');
  kopf.fillRange(148, 156, 0x20);
  var summe = 0;
  for (final b in kopf) {
    summe += b;
  }
  schreibe(148, '${summe.toRadixString(8).padLeft(6, '0')}\u0000 ');
  final daten = [...inhalt, ...List<int>.filled((512 - inhalt.length % 512) % 512, 0)];
  return [...kopf, ...daten];
}

Uint8List _mbz(List<List<int>> eintraege) => Uint8List.fromList(gzip.encode(Uint8List.fromList([
      ...eintraege.expand((e) => e),
      ...List<int>.filled(1024, 0),
    ])));

List<int> _xml(String s) => utf8.encode(s);

const _sicherungXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<moodle_backup>
  <information>
    <moodle_version>2024100700</moodle_version>
    <format>moodle2</format>
    <type>activity</type>
    <activities>
      <activity>
        <modulename>quiz</modulename>
        <title>ZZ Testtest</title>
      </activity>
    </activities>
    <settings>
      <setting><name>users</name><value>0</value></setting>
    </settings>
  </information>
</moodle_backup>
''';

/// Zwei Fragen aus der Sammlung (mit Sachnummer), eine fremde ohne Sachnummer, dazu
/// eine Zufallsfrage im Quiz.
const _questionsXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<question_categories>
  <question_bank_entries>
    <question_bank_entry id="11">
      <idnumber>ZZ-0001</idnumber>
      <question_version><version>1</version><question><name>ZZ Frage Eins</name></question></question_version>
    </question_bank_entry>
    <question_bank_entry id="12">
      <idnumber>ZZ-0002</idnumber>
      <question_version><version>1</version><question><name>ZZ Frage Zwei</name></question></question_version>
    </question_bank_entry>
    <question_bank_entry id="13">
      <idnumber></idnumber>
      <question_version><version>1</version><question><name>ZZ Frage Fremd</name></question></question_version>
    </question_bank_entry>
  </question_bank_entries>
</question_categories>
''';

const _quizXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<activity>
  <quiz id="21">
    <question_instances>
      <question_instance id="1">
        <slot>1</slot>
        <question_reference><questionbankentryid>11</questionbankentryid><version>1</version></question_reference>
      </question_instance>
      <question_instance id="2">
        <slot>2</slot>
        <question_reference><questionbankentryid>12</questionbankentryid><version>1</version></question_reference>
      </question_instance>
      <question_instance id="3">
        <slot>3</slot>
        <question_reference><questionbankentryid>13</questionbankentryid><version>1</version></question_reference>
      </question_instance>
      <question_instance id="4">
        <slot>4</slot>
        <question_set_reference><filtercondition>{}</filtercondition></question_set_reference>
      </question_instance>
    </question_instances>
  </quiz>
</activity>
''';

void main() {
  group('Quizfragen aus dem Archiv lesen (UNGEMESSEN: Lesart festgelegt)', () {
    test('Sachnummer aus der Fragenbank, Zufallsfrage als zufall, fremde Frage ohne Sachnummer', () {
      final f = quizFragenAusXml(_quizXml, _questionsXml);
      expect(f.map((q) => q.name).toList(), ['ZZ Frage Eins', 'ZZ Frage Zwei', 'ZZ Frage Fremd', 'Zufallsfrage']);
      expect(f[0].sachnummer, 'ZZ-0001');
      expect(f[1].sachnummer, 'ZZ-0002');
      expect(f[2].sachnummer, isNull, reason: 'leere Sachnummer zählt als fehlend');
      expect(f[3].zufall, isTrue);
      expect(f[0].zufall, isFalse);
    });

    test('referenzierte Version statt des ersten Namens; fehlende Version bleibt Prüflücke', () {
      const bank = '<question_bank_entry id="11"><idnumber>ZZ-1</idnumber>'
          '<question_version><version>1</version><question><name>Alt</name></question></question_version>'
          '<question_version><version>2</version><question><name>Neu</name></question></question_version>'
          '</question_bank_entry>';
      String quiz(String version) => '<question_instance><question_reference>'
          '<questionbankentryid>11</questionbankentryid><version>$version</version>'
          '</question_reference></question_instance>';
      expect(quizFragenAusXml(quiz('2'), bank).single.name, 'Neu');
      for (final version in ['3', '', '0']) {
        final quelle = quizFragenAusXml(quiz(version), bank);
        expect(quelle.single.sachnummer, isNull);
        expect(herkunftPruefen(verwendet: quelle, eigeneSachnummern: {'ZZ-1'}, eigeneAnzahl: 1).art,
            HerkunftArt.pruefluecke);
        expect(quizVerifiziert(fragenVergleichen(quelle: quelle,
            ziel: [(name: quelle.single.name, zufall: false)])), isFalse);
      }
    });

    test('Eintrag ohne Fragenbank: Sachnummer fehlt, Name nennt die Nummer', () {
      final f = quizFragenAusXml(_quizXml, null);
      expect(f.first.sachnummer, isNull);
      expect(f.first.name, contains('11'));
    });

    test('Quiz ohne Fragen liefert eine leere Liste', () {
      expect(quizFragenAusXml('<activity><quiz id="1"></quiz></activity>', _questionsXml), isEmpty);
    });

    test('kaputtes quiz.xml wirft XmlException', () {
      expect(() => quizFragenAusXml('<activity><quiz>', _questionsXml), throwsA(isA<Exception>()));
    });
  });

  group('Archivprüfung liefert die Quizfragen', () {
    Uint8List archiv({String quizPfad = 'activities/quiz_21/quiz.xml'}) => _mbz([
          _eintrag('moodle_backup.xml', _xml(_sicherungXml)),
          _eintrag('questions.xml', _xml(_questionsXml)),
          _eintrag(quizPfad, _xml(_quizXml)),
        ]);

    test('quiz.xml und questions.xml werden gelesen und je Quiz gespeichert', () async {
      final b = await archivPruefen(archiv());
      expect(b.ok, isTrue, reason: b.grund);
      expect(b.quizFragen.keys.toList(), ['quiz_21']);
      expect(b.quizFragen['quiz_21']!.length, 4);
      expect(b.quizFragen['quiz_21']!.first.sachnummer, 'ZZ-0001');
    });

    test('ohne questions.xml sind alle Sachnummern leer (Prüflücke, kein Nachweis)', () async {
      final b = await archivPruefen(_mbz([
        _eintrag('moodle_backup.xml', _xml(_sicherungXml)),
        _eintrag('activities/quiz_21/quiz.xml', _xml(_quizXml)),
      ]));
      expect(b.ok, isTrue, reason: b.grund);
      expect(b.quizFragen['quiz_21']!.every((f) => f.sachnummer == null), isTrue);
      expect(b.quizFragen['quiz_21']!.length, 4);
    });

    test('Archiv ohne Quiz hat keine Quizfragen', () async {
      final b = await archivPruefen(_mbz([_eintrag('moodle_backup.xml', _xml(_sicherungXml))]));
      expect(b.quizFragen, isEmpty);
    });

    test('kaputtes quiz.xml: das Archiv bleibt gültig, das Quiz ist unlesbar (Prüflücke, Befund 7)', () async {
      final b = await archivPruefen(_mbz([
        _eintrag('moodle_backup.xml', _xml(_sicherungXml)),
        _eintrag('activities/quiz_21/quiz.xml', _xml('<activity><quiz>')),
      ]));
      expect(b.ok, isTrue, reason: b.grund);
      expect(b.quizUnlesbar, {'quiz_21'});
      expect(b.quizFragen, isNot(contains('quiz_21')));
    });

    test('lesbares Quiz: nicht als unlesbar markiert', () async {
      final b = await archivPruefen(archiv());
      expect(b.quizUnlesbar, isEmpty);
    });
  });
}
