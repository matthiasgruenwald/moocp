// Offline prüfbar: Fragen-XML bauen und prüfen, Export lesen, Test auswerten.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/fragen_xml.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/moodle/test.dart';
import 'package:path/path.dart' as p;

const _svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><title>Probe</title>'
    '<desc>Ein Punkt</desc><circle cx="5" cy="5" r="2"/></svg>';

Map<String, Object?> _stackFrage() => {
      'name': 'ZZ Ohmsches Gesetz',
      'fragetext': '<p>R = 100 Ω, U = 5 V. I in mA? [[input:ans1]] [[validation:ans1]]</p>',
      'variablen': 'R:100; U:5; I:U/R*1000;',
      'eingaben': [
        {'name': 'ans1', 'typ': 'numerical', 'tans': 'I'}
      ],
      'prts': [
        {
          'name': 'prt1',
          'knoten': [
            {
              'test': 'NumRelative',
              'sans': 'ans1',
              'tans': 'I',
              'optionen': '0.01',
              'wahr': {'punkte': 1},
              'falsch': {'punkte': 0, 'feedback': '<p>Einheiten prüfen.</p>'},
            }
          ]
        }
      ],
      'tests': [
        {
          'beschreibung': 'richtig',
          'eingaben': {'ans1': '50'},
          'erwartet': {
            'prt1': {'punkte': 1, 'abzug': 0, 'hinweis': 'prt1-1-T'}
          }
        }
      ],
    };

void main() {
  test('STACK bauen: Pflichtelemente, Knoten 0-basiert, besteht die Prüfung', () {
    final xml = quizXml([stackXml(_stackFrage(), version: '2026010500')]);
    expect(xml, contains('<stackversion><text>2026010500</text></stackversion>'));
    expect(xml, contains('<forbidfloat>0</forbidfloat>'));
    expect(xml, contains('<name>0</name>'), reason: 'sichtbarer Knoten 1 ist im XML 0');
    expect(xml, contains('<truenextnode>-1</truenextnode>'));
    expect(xml, contains('<trueanswernote>prt1-1-T</trueanswernote>'));
    final (_, fragen) = fragenXmlPruefen(xml);
    expect(fragen.single.typ, 'stack');
  });

  test('STACK bauen verweigert: ohne Tests, ohne Platzhalter, Knoten 0', () {
    expect(() => stackXml({..._stackFrage(), 'tests': []}, version: '1'), throwsA(isA<MoodleFehler>()));
    expect(() => stackXml({..._stackFrage(), 'fragetext': '<p>ohne Feld</p>'}, version: '1'),
        throwsA(predicate((e) => e is MoodleFehler && e.meldung.contains('[[input:ans1]]'))));
    final f = _stackFrage();
    ((f['prts'] as List).first as Map)['knoten'] = [
      {'nr': 0, 'sans': 'ans1', 'tans': 'I'}
    ];
    expect(() => stackXml(f, version: '1'), throwsA(isA<MoodleFehler>()));
  });

  test('STACK bauen verweigert eine Testeingabe, die keine Option der Auswahlliste ist', () {
    Map<String, Object?> auswahl(String testwert, {String tans = '[[4,true],[2,false]]'}) => {
          ..._stackFrage(),
          'fragetext': '<p>Welche Zahl? [[input:ans1]] [[validation:ans1]]</p>',
          'eingaben': [
            {'name': 'ans1', 'typ': 'dropdown', 'tans': tans}
          ],
          'tests': [
            {
              'eingaben': {'ans1': testwert},
              'erwartet': {
                'prt1': {'punkte': 1, 'hinweis': 'prt1-1-T'}
              }
            }
          ],
        };
    // Gemessen: STACK wertet den Testwert nicht aus; zur Option 4 fällt 3+1 durch.
    expect(() => stackXml(auswahl('3+1'), version: '1'),
        throwsA(predicate((e) => e is MoodleFehler && e.meldung.contains('keine der Optionen'))));
    expect(stackXml(auswahl('4'), version: '1'), contains('<value>4</value>'));
    // Steht in tans keine wörtliche Liste, lässt sich nichts prüfen.
    expect(stackXml(auswahl('kb+1', tans: 'optionen'), version: '1'), contains('<value>kb+1</value>'));
  });

  test('STACK: [[validation:…]] für jede Eingabe, Auswahllisten ohne Anzeige der Validierung', () {
    final auswahl = {
      ..._stackFrage(),
      'fragetext': '<p>[[input:ans1]] [[validation:ans1]] [[input:ans2]] [[validation:ans2]]</p>',
      'eingaben': [
        {'name': 'ans1', 'typ': 'numerical', 'tans': 'I'},
        {'name': 'ans2', 'typ': 'dropdown', 'tans': '[[4,true],[2,false]]'},
      ],
    };
    final xml = quizXml([stackXml(auswahl, version: '1')]);
    expect(RegExp('<showvalidation>(.)</showvalidation>').allMatches(xml).map((m) => m[1]), ['1', '0']);
    fragenXmlPruefen(xml);
    // Eine ausdrückliche Angabe gilt weiter.
    final eingaben = [
      for (final e in auswahl['eingaben'] as List) {...e as Map, 'showvalidation': 2}
    ];
    expect(stackXml({...auswahl, 'eingaben': eingaben}, version: '1'), isNot(contains('<showvalidation>0')));

    // Gemessen: Ohne den Platzhalter importiert Moodle, aber das Formular
    // lehnt jede spätere Änderung ab -- auch bei Auswahllisten und showvalidation 0.
    for (final ohne in ['[[validation:ans1]]', '[[validation:ans2]]']) {
      final f = {...auswahl, 'fragetext': (auswahl['fragetext'] as String).replaceFirst(ohne, '')};
      expect(() => fragenXmlPruefen(quizXml([stackXml(f, version: '1')])),
          throwsA(predicate((e) => e is MoodleFehler && e.meldung.contains(ohne))));
    }
  });

  test('STACK mit Zeichnung: gebundene Eingabe verborgen, ohne Prüfanzeige, Musterantwort nicht angezeigt', () {
    Map<String, Object?> frage({String attribute = ' input-ref-ans2="ans2Ref"', Map<String, Object?> ans2 = const {}}) => {
          ..._stackFrage(),
          'fragetext': '<p>I in mA? [[input:ans1]] [[validation:ans1]]</p><p>Ziehe P auf den Arbeitspunkt.</p>'
              '[[jsxgraph$attribute]]\nvar board = JXG.JSXGraph.initBoard(divid, {axis: true});\n'
              "var p = board.create('point', [1, 1]);\nstack_jxg.bind_point(ans2Ref, p);\n[[/jsxgraph]]",
          'eingaben': [
            {'name': 'ans1', 'typ': 'numerical', 'tans': 'I'},
            {'name': 'ans2', 'typ': 'algebraic', 'tans': '[5,50]', 'gebunden': true, ...ans2},
          ],
        };
    final xml = quizXml([stackXml(frage(), version: '1')]);
    expect(xml, contains('<div class="d-none">[[input:ans2]] [[validation:ans2]]</div>'));
    expect(RegExp('<showvalidation>(.)</showvalidation>').allMatches(xml).map((m) => m[1]), ['1', '0']);
    expect(RegExp('<options>([^<]*)</options>').allMatches(xml).map((m) => m[1]), ['', 'hideanswer,allowempty']);
    expect(xml, isNot(contains('<mustverify>1')));
    fragenXmlPruefen(xml);
    // Eine ausdrückliche Angabe gilt weiter.
    expect(stackXml(frage(ans2: {'options': 'allowempty'}), version: '1'), contains('<options>allowempty</options>'));

    void verweigert(Map<String, Object?> f, String text) => expect(() => stackXml(f, version: '1'),
        throwsA(predicate((e) => e is MoodleFehler && e.meldung.contains(text))), reason: text);
    verweigert(frage(attribute: ''), 'kein [[jsxgraph input-ref-ans2');
    verweigert(frage(attribute: ' input-ref-ans3="x"'), 'input-ref-ans3');
    verweigert(frage(ans2: {'typ': 'numerical'}), 'braucht typ algebraic');
    final mitPlatzhalter = frage();
    mitPlatzhalter['fragetext'] = '${mitPlatzhalter['fragetext']}<p>[[input:ans2]] [[validation:ans2]]</p>';
    verweigert(mitPlatzhalter, 'setzt stack_xml die Platzhalter selbst');

    // Was von außen lädt, kommt nicht durch die Prüfung vor dem Import.
    expect(() => fragenXmlPruefen(quizXml([stackXml(frage(attribute: ' input-ref-ans2="r" version="cdn"'), version: '1')])),
        throwsA(predicate((e) => e is MoodleFehler && e.meldung.contains('fremden Rechner'))));
    final xmlHand = xml.replaceFirst('input-ref-ans2="ans2Ref"', 'input-ref-ans2="ans2Ref" input-ref-ans9="x"');
    expect(() => fragenXmlPruefen(xmlHand),
        throwsA(predicate((e) => e is MoodleFehler && e.meldung.contains('input-ref-ans9'))));

    // Eingabenamen mit Großbuchstaben bindet STACK wie geschrieben.
    final gross = quizXml([stackXml(frage(attribute: ' input-ref-ansG="ans2Ref"', ans2: {'name': 'ansG'}), version: '1')]);
    expect(gross, contains('<div class="d-none">[[input:ansG]] [[validation:ansG]]</div>'));
    fragenXmlPruefen(gross);
    verweigert(frage(attribute: ' input-ref-ansg="ans2Ref"', ans2: {'name': 'ansG'}), 'input-ref-ansg');
  });

  test('STACK: Teile ohne Antwort -- allowempty nur mit Knoten für EMPTYANSWER, Abzug je Zweig', () {
    Map<String, Object?> frage(List<Map<String, Object?>> knoten, {String optionen = 'allowempty'}) => {
          ..._stackFrage(),
          'eingaben': [
            {'name': 'ans1', 'typ': 'numerical', 'tans': 'I', 'options': optionen}
          ],
          'prts': [
            {'name': 'prt1', 'knoten': knoten}
          ],
        };
    final leer = {
      'test': 'AlgEquiv',
      'sans': 'ans1',
      'tans': 'EMPTYANSWER',
      'wahr': {'punkte': 0, 'abzug': 0, 'feedback': '<p>Nicht bearbeitet.</p>'},
      'falsch': {'weiter': 2},
    };
    final rechnen = {'nr': 2, 'test': 'NumRelative', 'sans': 'ans1', 'tans': 'I', 'optionen': '0.01'};
    final xml = stackXml(frage([leer, rechnen]), version: '1');
    expect(xml, contains('<truepenalty>0</truepenalty>'));
    // Der Leer-Knoten ist immer leise, der Rechenknoten nicht.
    expect(RegExp('<quiet>(.)</quiet>').allMatches(xml).map((m) => m[1]), ['1', '0']);
    expect(xml, contains('<falsepenalty></falsepenalty>'), reason: 'ohne Angabe der Abzug der Frage');
    fragenXmlPruefen(quizXml([xml]));
    // Ohne den Knoten liefe der Baum mit EMPTYANSWER in den Rechentest.
    expect(() => stackXml(frage([rechnen..remove('nr')]), version: '1'),
        throwsA(predicate((e) => e is MoodleFehler && e.meldung.contains('prt1 prüft das nicht'))));
    // Ohne allowempty braucht es ihn nicht.
    stackXml(frage([rechnen], optionen: ''), version: '1');
  });

  test('STACK: Einheiten tippt man mit Leerzeichen -- units setzt Sterne selbst', () {
    final f = {
      ..._stackFrage(),
      'eingaben': [
        {'name': 'ans1', 'typ': 'units', 'tans': 'ta'}
      ],
    };
    expect(stackXml(f, version: '1'), contains('<insertstars>4</insertstars>'));
    expect(stackXml(_stackFrage(), version: '1'), contains('<insertstars>0</insertstars>'));
  });

  test('CodeRunner bauen verweigert, was still danebenginge', () {
    final gut = {
      'name': 'ZZ Summe',
      'fragetext': '<p>Schreibe summe(a, b).</p>',
      'typ': 'python3',
      'musterloesung': 'def summe(a, b):\n    return a + b',
      'tests': [
        {'code': 'print(summe(2, 3))', 'erwartet': '5'}
      ],
    };
    final xml = quizXml([coderunnerXml(gut)]);
    expect(xml, contains('<prototypetype>0</prototypetype>'));
    expect(xml, contains('<validateonsave>1</validateonsave>'));
    fragenXmlPruefen(xml);
    expect(() => coderunnerXml({...gut, 'musterloesung': ''}), throwsA(isA<MoodleFehler>()));
    expect(() => coderunnerXml({...gut, 'tests': []}), throwsA(isA<MoodleFehler>()));
    expect(
        () => coderunnerXml({
              ...gut,
              'tests': [
                {'code': 'print(1)'}
              ]
            }),
        throwsA(isA<MoodleFehler>()));
    expect(() => coderunnerXml({...gut, 'typ': 'sql'}), throwsA(predicate((e) => '$e'.contains('.db'))));
  });

  test('Prüfung vor dem Import: Typen, ordering, doppelte Sachnummern', () {
    String q(String typ, String inhalt, {String name = 'ZZ Frage', String idn = ''}) =>
        '<question type="$typ"><name><text>$name</text></name><questiontext format="html"><text>x</text>'
        '</questiontext><idnumber>$idn</idnumber>$inhalt</question>';
    expect(() => fragenXmlPruefen(quizXml([q('ddmarker', '')])),
        throwsA(predicate((e) => '$e'.contains('Koordinaten'))));
    expect(() => fragenXmlPruefen(quizXml([q('formulas', '')])), throwsA(predicate((e) => '$e'.contains('nicht anlegbar'))));
    expect(() => fragenXmlPruefen(quizXml([q('ordering', '<layouttype>1</layouttype>')])),
        throwsA(predicate((e) => '$e'.contains('shownumcorrect') && '$e'.contains('Namen'))));
    expect(() => fragenXmlPruefen(quizXml([q('truefalse', '', idn: 'A1'), q('truefalse', '', name: 'ZZ B', idn: 'A1')])),
        throwsA(predicate((e) => '$e'.contains('mehrfach'))));
    final (_, ok) = fragenXmlPruefen(quizXml(['<question type="category"><category><text>x</text></category></question>',
      q('truefalse', '', idn: 'A1')]));
    expect(ok.single.idnummer, 'A1');
  });

  test('Zeichnung aus dateien/ wird eingebettet und geprüft', () {
    final ordner = Directory.systemTemp.createTempSync('moocp');
    try {
      File(p.join(ordner.path, 'zz-punkt.svg')).writeAsStringSync(_svg);
      final xml = quizXml([
        '<question type="description"><name><text>ZZ Bild</text></name><questiontext format="html">'
            '<text><![CDATA[<p><img src="@@PLUGINFILE@@/zz-punkt.svg" alt="Ein Punkt"></p>]]></text></questiontext></question>'
      ]);
      final (fertig, _) = fragenXmlPruefen(xml, dateiordner: ordner.path);
      expect(fertig, contains('<file name="zz-punkt.svg" path="/" encoding="base64">'));
      expect(() => fragenXmlPruefen(xml.replaceAll('zz-punkt', 'fehlt'), dateiordner: ordner.path),
          throwsA(predicate((e) => '$e'.contains('fehlt'))));
    } finally {
      ordner.deleteSync(recursive: true);
    }
  });

  test('Export lesen: questionid aus dem Kommentar, Typnamen, Antworten', () {
    final fragen = fragenAusXml('''<?xml version="1.0" encoding="UTF-8"?>
<quiz>
<!-- question: 0  -->
  <question type="category"><category><text>\$course\$/Standard</text></category></question>
<!-- question: 5011  -->
  <question type="matching"><name><text>ZZ Zuordnen</text></name>
    <questiontext format="html"><text><![CDATA[<p>Ordne zu.</p>]]></text></questiontext>
    <defaultgrade>2.0000000</defaultgrade><idnumber>LS2-A1</idnumber><hidden>0</hidden></question>
<!-- question: 5012  -->
  <question type="multichoice"><name><text>ZZ Wahl</text></name>
    <questiontext format="html"><text>Welche?</text></questiontext><defaultgrade>1</defaultgrade>
    <answer fraction="100"><text>a</text></answer><answer fraction="0"><text>b</text></answer></question>
</quiz>''');
    expect(fragen.map((f) => '${f.id} ${f.typ} ${f.idnummer} ${f.antworten}/${f.richtig}').toList(),
        ['5011 match LS2-A1 0/0', '5012 multichoice null 2/1']);
  });

  test('Test auswerten: Seiten, Plätze, Summe, Beste Bewertung, Befunde', () {
    const seite = '''<html><body><script>M.cfg = {"courseId":43,"contextid":7};</script>
<div data-quizid="9"><script>var x = {"quizid":"77"};</script>
<ul><li class="pagenumber" id="page-1">Seite 1</li>
<li class="activity slot qtype_multichoice" id="slot-501"><span class="activityname">ZZ Wahl</span>
<a href="/question/bank/editquestion/question.php?cmid=5002&id=5012">bearbeiten</a><span class="instancemaxmark">1,00</span></li>
<li class="activity slot qtype_truefalse" id="slot-502"><span class="activityname">ZZ Ja/Nein</span><span class="instancemaxmark">0,00</span></li>
<li class="pagenumber" id="page-2">Seite 2</li>
<li class="activity slot qtype_description" id="slot-503"><span class="activityname">ZZ Hinweis</span><span class="instancemaxmark">0,00</span></li>
</ul><p>Summe der Punkte: 1,00</p><input name="maxgrade" value="10,00"></div></body></html>''';
    final t = testAuswerten(9532, seite);
    expect(t.quizid, 77);
    expect(t.kurs, 43);
    expect(t.seiten, 2);
    expect([for (final x in t.plaetze) '${x.slotid}:${x.seite}:${x.punkte}:${x.frage}'],
        ['501:1:1.0:5012', '502:1:0.0:null', '503:2:0.0:null']);
    expect(t.proSeite, 2);
    expect(t.befunde().join('\n'), allOf(contains('weicht'), contains('1 Frage(n) mit 0 Punkten')));
  });
}
