// Offline prüfbar: was der Browser des Werkzeugs bildschirmfoto anfragen
// darf. Die Sperrliste gilt zuerst, auch hier.
import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/bildschirmfoto.dart';
import 'package:moocp/moodle/browserliste.dart';
import 'package:moocp/moodle/moodle_zugang.dart';

final _basis = Uri.parse('https://moodle.schule.example');

/// [seiten]: ohne Angabe die angefragte Adresse selbst -- dann zählt nur,
/// ob sie eine erlaubte Ansicht ist.
BrowserWeg weg(
  String methode,
  String adresse, {
  bool dokument = false,
  String? rumpf,
  String? mathjax,
  Set<String>? seiten,
}) {
  final uri = adresse.startsWith('http')
      ? Uri.parse(adresse)
      : _basis.resolve(adresse);
  return browserPruefen(
    methode,
    uri,
    basis: _basis,
    seiten: seiten ?? {uri.toString()},
    dokument: dokument,
    rumpf: rumpf,
    mathjax: mathjax,
  ).$1;
}

void main() {
  test('Seiten: nur die Ansichten ohne Personen', () {
    for (final a in [
      '/mod/page/view.php?id=15730',
      '/mod/book/view.php?id=2047',
      '/mod/book/view.php?id=2047&chapterid=12',
      '/mod/wiki/view.php?pageid=88',
      '/mod/learningmap/view.php?id=15731',
      '/question/bank/previewquestion/preview.php?id=5010&cmid=5002',
      '/question/bank/previewquestion/preview.php?id=5010&cmid=5002&previewid=9',
    ]) {
      expect(weg('GET', a, dokument: true), BrowserWeg.ueberApp, reason: a);
    }
    for (final a in [
      '/course/view.php?id=43',
      '/mod/assign/view.php?id=4703',
      '/mod/assign/view.php?id=4703&action=grading',
      '/mod/page/view.php?id=15730&foo=1',
      '/mod/learningmap/view.php?id=15731&foo=1',
      // Ein Wiki nur über die geprüfte Seite (wiki.dart, wikiAnsicht).
      '/mod/wiki/view.php?id=15397',
      '/mod/wiki/view.php?wid=22&title=Startseite&groupanduser=3-45',
      '/mod/quiz/review.php?attempt=88',
      '/user/profile.php?id=5',
      '/my/',
      '/login/logout.php?sesskey=abc',
    ]) {
      expect(weg('GET', a, dokument: true), BrowserWeg.gesperrt, reason: a);
    }
    expect(
      weg('POST', '/mod/page/view.php?id=15730', dokument: true),
      BrowserWeg.gesperrt,
    );
  });

  test('Rahmen: interaktive Elemente aus dem Dateibereich eines Felds, sonst nichts', () {
    final seiten = {'https://moodle.schule.example/mod/page/view.php?id=15961'};
    for (final a in [
      '/pluginfile.php/26822/mod_page/content/1/wuerfel.html',
      '/pluginfile.php/26823/mod_label/intro/wuerfel.html',
      '/pluginfile.php/26824/mod_book/chapter/228/wuerfel.htm',
      '/pluginfile.php/26825/course/section/4883/wuerfel.html',
    ]) {
      expect(
        weg('GET', a, dokument: true, seiten: seiten),
        BrowserWeg.ueberApp,
        reason: a,
      );
    }
    for (final a in [
      '/pluginfile.php/26822/mod_page/content/1/bild.png',
      '/pluginfile.php/5/user/icon/boost/f1.html',
      '/mod/page/view.php?id=15962',
    ]) {
      expect(
        weg('GET', a, dokument: true, seiten: seiten),
        BrowserWeg.gesperrt,
        reason: a,
      );
    }
    expect(
      weg(
        'POST',
        '/pluginfile.php/26822/mod_page/content/1/wuerfel.html',
        dokument: true,
        seiten: seiten,
      ),
      BrowserWeg.gesperrt,
    );
  });

  test('Seiten: nur die aufgenommene und ihre Umleitung, auch nicht im Rahmen', () {
    const vorschau =
        'https://moodle.schule.example/question/bank/previewquestion/preview.php?id=5010&cmid=5002';
    final seiten = {vorschau};
    expect(
      weg('GET', vorschau, dokument: true, seiten: seiten),
      BrowserWeg.ueberApp,
    );
    // Ein iframe in der Seite ist auch ein Dokument -- eine andere erlaubte
    // Ansicht kommt so nicht ins Bild.
    expect(
      weg(
        'GET',
        '/mod/wiki/view.php?pageid=88',
        dokument: true,
        seiten: seiten,
      ),
      BrowserWeg.gesperrt,
    );
    expect(
      weg('GET', '$vorschau&previewid=9', dokument: true, seiten: seiten),
      BrowserWeg.gesperrt,
    );
    seiten.add(
      '$vorschau&previewid=9',
    ); // die Umleitung, die Moodle geschickt hat
    expect(
      weg('GET', '$vorschau&previewid=9', dokument: true, seiten: seiten),
      BrowserWeg.ueberApp,
    );
    // Dateien der Seite hängen nicht an dieser Grenze.
    expect(
      weg('GET', '/theme/styles.php/boost/1/all', seiten: seiten),
      BrowserWeg.ueberApp,
    );
  });

  test('Dateien: Theme, Skripte, Kursdateien -- keine Profilbilder', () {
    for (final a in [
      '/theme/styles.php/boost/1700000000_1/all',
      '/theme/yui_combo.php?rollup/3.18.1/yui-moodlesimple-min.js',
      '/theme/image.php/boost/core/1700000000/f/pdf',
      '/theme/font.php/boost/core/1700000000/fontawesome-webfont.woff2',
      '/lib/javascript.php/1700000000/lib/babel-polyfill/polyfill.min.js',
      '/lib/requirejs.php/1700000000/core/first.js',
      '/pluginfile.php/7000/mod_page/content/3/zeichnung.svg',
    ]) {
      expect(weg('GET', a), BrowserWeg.ueberApp, reason: a);
    }
    for (final a in [
      '/pluginfile.php/2393/user/icon/boost/f2',
      '/pluginfile.php/4703/assignsubmission_file/submission_files/88/abgabe.pdf',
      '/user/pix.php/5/f1.jpg',
      '/message/index.php',
      '/course/view.php?id=43',
    ]) {
      expect(weg('GET', a), BrowserWeg.gesperrt, reason: a);
    }
  });

  test('Dienste: nur Vorlagen, Sprachtexte und Symbole', () {
    const vorlage =
        '[{"index":0,"methodname":"core_output_load_template_with_dependencies","args":{}}]';
    const gemischt =
        '[{"index":0,"methodname":"core_get_string","args":{}},'
        '{"index":1,"methodname":"core_message_get_unread_conversation_counts","args":{}}]';
    expect(
      weg(
        'POST',
        '/lib/ajax/service.php?sesskey=abc&info=core_output_load_template_with_dependencies',
        rumpf: vorlage,
      ),
      BrowserWeg.ueberApp,
    );
    expect(
      weg('POST', '/lib/ajax/service.php?sesskey=abc&info=x', rumpf: gemischt),
      BrowserWeg.gesperrt,
    );
    expect(
      weg(
        'POST',
        '/lib/ajax/service.php?sesskey=abc&info=core_fetch_notifications',
        rumpf:
            '[{"index":0,"methodname":"core_fetch_notifications","args":{}}]',
      ),
      BrowserWeg.gesperrt,
    );
    expect(
      weg(
        'GET',
        '/lib/ajax/service-nologin.php?info=core_output_load_template_with_dependencies&args=x',
      ),
      BrowserWeg.ueberApp,
    );
    expect(
      weg('GET', '/lib/ajax/service-nologin.php?info=core_course_get_courses'),
      BrowserWeg.gesperrt,
    );
  });

  test('MathJax: nur von der Adresse, die die Seite einstellt', () {
    const seite =
        r'M.util.js_pending("filter_mathjaxloader/loader"); require(["filter_mathjaxloader/loader"], '
        r'function(amd) {amd.configure({"mathjaxurl":"https:\/\/cdn.jsdelivr.net\/npm\/mathjax@3.2.2\/es5\/tex-mml-chtml.js"});});';
    final quelle = mathjaxQuelle(seite);
    expect(quelle, 'https://cdn.jsdelivr.net/npm/mathjax@3.2.2/');
    expect(
      weg(
        'GET',
        'https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/output/chtml/fonts/woff-v2/MathJax_Main-Regular.woff',
        mathjax: quelle,
      ),
      BrowserWeg.direkt,
    );
    expect(
      weg(
        'GET',
        'https://cdn.jsdelivr.net/npm/anderes@1/x.js',
        mathjax: quelle,
      ),
      BrowserWeg.gesperrt,
    );
    expect(
      weg(
        'GET',
        'https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/tex-mml-chtml.js',
      ),
      BrowserWeg.gesperrt,
      reason: 'ohne Adresse aus der Seite nichts von fremden Rechnern',
    );
    expect(
      weg(
        'GET',
        'https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/tex-mml-chtml.js',
        mathjax: quelle,
        dokument: true,
      ),
      BrowserWeg.gesperrt,
    );
    expect(mathjaxQuelle('<p>keine Formeln</p>'), isNull);
  });

  test('Nur https auf der eigenen Instanz', () {
    expect(
      weg('GET', 'http://moodle.schule.example/theme/styles.php/boost/1/all'),
      BrowserWeg.gesperrt,
    );
    expect(
      weg('GET', 'https://andere.schule.example/theme/styles.php/boost/1/all'),
      BrowserWeg.gesperrt,
    );
  });

  test('Was nicht geladen ist, zählt nur, wenn es das Bild verändern kann', () {
    expect(veraendertBild('Datenschutz-Sperre (Regel 3)', 'Script'), isTrue);
    expect(
      veraendertBild('fremder Rechner', 'Stylesheet'),
      isTrue,
      reason: 'Schriften, fremde Bilder',
    );
    expect(
      veraendertBild('nicht die aufgenommene Seite', 'Document'),
      isTrue,
      reason: 'ein Rahmen im Inhalt',
    );
    for (final art in ['Stylesheet', 'Image', 'Font', 'Media']) {
      expect(veraendertBild(nichtAufDerListe, art), isTrue, reason: art);
    }
    for (final art in ['Script', 'XHR', 'Fetch', 'Other', null]) {
      expect(
        veraendertBild(nichtAufDerListe, art),
        isFalse,
        reason: '$art: Kopfzeile und Plugins',
      );
    }
    final (_, grund) = browserPruefen(
      'GET',
      Uri.parse('https://moodle.schule.example/local/beispiel/build/app.js'),
      basis: Uri.parse('https://moodle.schule.example/'),
      seiten: const {},
    );
    expect(grund, nichtAufDerListe);
  });

  test('STACK-Zeichnungen: Skripte aus corsscripts, nur Dateinamen', () {
    const ordner = '/question/type/stack/corsscripts';
    for (final a in [
      '$ordner/cors.php?name=jsxgraphcore.min.js',
      '$ordner/cors.php?name=stackjsiframe.min.js',
      '$ordner/cors.php?name=jsxgraph.min.css',
      '$ordner/cors.php?name=jsxgraphstyles%2Fempty.css',
      '$ordner/stackjsxgraph.min.js',
    ]) {
      expect(
        browserPruefen(
          'GET',
          _basis.resolve(a),
          basis: _basis,
          seiten: const {},
        ),
        (BrowserWeg.ueberApp, stackSkript),
        reason: a,
      );
    }
    for (final a in [
      '$ordner/cors.php?name=..%2F..%2F..%2Fconfig.php',
      '$ordner/cors.php?name=..%2Fversion.js',
      '$ordner/cors.php?name=x.php',
      '$ordner/cors.php',
      '$ordner/cors.php?name=a.js&x=1',
      '$ordner/README',
      '$ordner/a.js?x=1',
      '/question/type/stack/adminui/index.php',
    ]) {
      expect(weg('GET', a), BrowserWeg.gesperrt, reason: a);
    }
    expect(
      weg('POST', '$ordner/cors.php?name=jsxgraphcore.min.js'),
      BrowserWeg.gesperrt,
    );
    expect(
      weg('GET', '$ordner/cors.php?name=jsxgraphcore.min.js', dokument: true),
      BrowserWeg.gesperrt,
    );
  });

  test('Grund: Pflicht, ein Satz', () {
    expect(
      grundPruefen(
        '  Prüfen, ob die Formeln\n auf Infoblatt 2 gesetzt werden  ',
      ),
      'Prüfen, ob die Formeln auf Infoblatt 2 gesetzt werden',
    );
    for (final g in [null, '', '   ', 'Formeln', 'x' * 201]) {
      expect(() => grundPruefen(g), throwsA(isA<MoodleFehler>()), reason: '$g');
    }
    String meldung(String? g) {
      try {
        grundPruefen(g);
      } on MoodleFehler catch (f) {
        return f.toString();
      }
      return '';
    }

    expect(meldung('  '), contains('Ohne Grund'));
    expect(
      meldung('Testlauf'),
      allOf(contains('„Testlauf" ist zu knapp'), isNot(contains('Ohne Grund'))),
    );
  });
}
