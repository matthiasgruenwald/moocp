// Die Auswertung der STACK-Testseite (stackTestBericht in
// lib/moodle/stack.dart): Eine Testeingabe gilt nur als verworfen, wenn im
// selben Testfall kein Baum etwas geliefert hat.
import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/stack.dart';

/// Ein Testfall, wie questiontestrun.php ihn zeigt: Überschrift, Tabelle der
/// Eingaben (sechs Spalten), Tabelle der Bäume (sieben Spalten).
String fall(String titel,
        {required String uebernommen, required String punkte, required String hinweis, String kennung = ''}) =>
    '''
<h3${kennung.isEmpty ? '' : ' id="$kennung"'}>$titel</h3>
<table class="stacktestsuite"><thead><tr><th>1</th><th>2</th><th>3</th><th>4</th><th>5</th><th>6</th></tr></thead>
<tbody><tr><td>ans1</td><td>matrix([1,2],[3,4])</td><td>$uebernommen</td><td></td><td></td><td></td></tr></tbody></table>
<table class="stacktestsuite"><thead><tr><th>1</th><th>2</th><th>3</th><th>4</th><th>5</th><th>6</th><th>7</th></tr></thead>
<tbody><tr class="${punkte == '1' ? 'pass' : 'fail'}"><td>prt1</td><td>$punkte</td><td>1</td><td></td><td></td><td>$hinweis</td><td>prt1-1-T</td></tr></tbody></table>
''';

String seite(List<String> faelle) =>
    '<div id="region-main">${faelle.join()}<div class="overallresult pass">ok</div></div>';

void main() {
  test('Wert nicht als Text angezeigt, aber der Baum hat gerechnet: kein Fehlalarm', () {
    final b = stackTestBericht(seite([fall('Testfall 1', uebernommen: '', punkte: '1', hinweis: 'prt1-1-T')]), frage: 7);
    expect(b, contains('alle 1 Testfälle bestanden'));
    expect(b, isNot(contains('nicht übernommen')));
  });

  test('Eingabe verworfen und kein Baum gerechnet: gemeldet', () {
    final b = stackTestBericht(
        seite([
          fall('Testfall 1', uebernommen: 'matrix([1,2],[3,4])', punkte: '1', hinweis: 'prt1-1-T'),
          fall('Testfall 2', uebernommen: '', punkte: '', hinweis: ''),
        ]),
        frage: 7);
    expect(b, contains('Mindestens eine Testeingabe hat STACK nicht übernommen'));
    expect(RegExp('nicht übernommen').allMatches(b).length, 2, reason: 'der Hinweis oben und Testfall 2');
    expect(b.indexOf('! Eingabe ans1'), greaterThan(b.indexOf('Testfall 2:')));
  });

  // So zeigt questiontestrun.php eine Frage ohne Fragetests: zwischen zwei
  // <hr> ein Beispiel mit den Musterantworten, kein Gesamtergebnis, nur den
  // Hinweis, dass Tests fehlen.
  String ohneTests({required String punkte}) => '<div id="region-main"><h2>Stack Test</h2>'
      '<hr/>If you add the test, its output will look like this:'
      '${fall('Testfall Beispiel', uebernommen: 'x', punkte: punkte, hinweis: 'prt1-1-T')}<hr/>'
      '<h2>Fragetests für Variante 1</h2><p>Question is missing tests or variants. No test cases have been added yet.</p></div>';

  test('Ohne Fragetests: das Beispiel von STACK zählt nicht als Testfall', () {
    final b = stackTestBericht(ohneTests(punkte: '1'), frage: 995);
    expect(b, contains('KEINE Testfälle -- nicht überprüfbar. verified: false'));
    expect(b, isNot(contains('NICHT bestanden')));
    expect(b, isNot(contains('Testfall Beispiel')));
    expect(b, contains('Musterantworten eingesetzt: volle Punkte'));
  });

  test('Ohne Fragetests und das Beispiel scheitert: gesagt, aber weiter keine Testfälle', () {
    final b = stackTestBericht(ohneTests(punkte: '0'), frage: 995);
    expect(b, contains('KEINE Testfälle'));
    expect(b, contains('NICHT volle Punkte'));
  });

  // So zeigt die STACK-Version der Testinstanz die Testfälle (gemessen): vor
  // jedem ein <hr>, die Überschrift mit Kennung testcase-<Nummer>-<Frage>.
  String mitTrennern(List<String> nummern) => '<div id="region-main">${[
        for (final n in nummern)
          '<br><hr class="bg-dark">'
              '${fall('Testfall $n', uebernommen: 'x', punkte: '1', hinweis: 'prt1-1-T', kennung: 'testcase-$n-7')}'
      ].join()}<p class="overallresult pass">ok</p></div>';

  test('Ein <hr> vor jedem Testfall: alle gezählt, keiner als Beispiel verworfen', () {
    final b = stackTestBericht(mitTrennern(['1', '2', '3', '4']), frage: 7);
    expect(b, contains('alle 4 Testfälle bestanden'));
    for (final n in ['1', '2', '3', '4']) {
      expect(b, contains('Testfall $n:'));
    }
  });

  test('Beispiel mit Kennung und <hr> davor: zählt nicht als Testfall', () {
    final b = stackTestBericht(
        '<div id="region-main"><p class="test-pane-fail">Es fehlen Tests.</p><br><hr class="bg-dark">'
        '${fall('Testfall Beispiel', uebernommen: 'x', punkte: '1', hinweis: 'prt1-1-T', kennung: 'testcase-Beispiel-995')}'
        '</div>',
        frage: 995);
    expect(b, contains('KEINE Testfälle -- nicht überprüfbar. verified: false'));
    expect(b, isNot(contains('Testfall Beispiel')));
    expect(b, contains('Musterantworten eingesetzt: volle Punkte'));
  });
}
