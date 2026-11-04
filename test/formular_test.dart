// Offline prüfbar: Einstellungen aus einem Moodle-Formular lesen und setzen,
// an einem nachgebauten Formular im Aufbau von Moodle 4.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:moocp/moodle/formular.dart';
import 'package:moocp/moodle/formular_lesen.dart';
import 'package:moocp/moodle/formular_schreiben.dart';
import 'package:moocp/moodle/moodle_zugang.dart';

String optionen(int von, int bis, int gewaehlt) =>
    [for (var i = von; i <= bis; i++) '<option value="$i"${i == gewaehlt ? ' selected' : ''}>$i</option>'].join();

final formular = '''<form class="mform">
<input type="hidden" name="sesskey" value="x">
<div id="fitem_id_name" class="mb-3 row fitem"><div class="col-md-3 col-form-label"><label for="id_name">Name der Aufgabe</label></div>
<div class="col-md-9 felement" data-fieldtype="text"><input type="text" name="name" id="id_name" value="ZZ Probe"></div></div>
<div id="fitem_id_duedate" class="mb-3 row fitem" data-groupname="duedate"><div class="col-md-3 col-form-label"><p>Fälligkeitsdatum</p></div>
<div class="col-md-9 felement" data-fieldtype="date_time_selector"><fieldset>
<label class="form-check fitem"><input type="checkbox" name="duedate[enabled]" id="id_duedate_enabled" value="1"> Aktivieren</label>
<select name="duedate[day]">${optionen(1, 31, 1)}</select><select name="duedate[month]">${optionen(1, 12, 10)}</select>
<select name="duedate[year]">${optionen(2025, 2030, 2026)}</select><select name="duedate[hour]">${optionen(0, 23, 0)}</select>
<select name="duedate[minute]">${optionen(0, 59, 0)}</select></fieldset></div></div>
<div id="fgroup_id_submissionplugins" class="mb-3 row fitem" data-groupname="submissionplugins"><div class="col-md-3 col-form-label"><p>Abgabetypen</p></div>
<div class="col-md-9 felement" data-fieldtype="group"><fieldset>
<input type="hidden" name="assignsubmission_onlinetext_enabled" value="0">
<label class="form-check"><input type="checkbox" name="assignsubmission_onlinetext_enabled" id="id_ot" value="1"> Texteingabe online</label>
<input type="hidden" name="assignsubmission_file_enabled" value="0">
<label class="form-check"><input type="checkbox" name="assignsubmission_file_enabled" id="id_fi" value="1" checked> Dateiabgabe</label>
</fieldset></div></div>
<div id="fitem_id_teamsubmission" class="mb-3 row fitem"><div class="col-md-3 col-form-label"><label for="id_team">Gruppenabgabe</label></div>
<div class="col-md-9 felement" data-fieldtype="selectyesno"><select name="teamsubmission" id="id_team"><option value="0" selected>Nein</option><option value="1">Ja</option></select></div></div>
</form>''';

void main() {
  group('Schutzdienst vor der Instanz erkennen', () {
    const moodleSeite = '<html><script>M.cfg = {"wwwroot":"x"};</script><p>Fehlendes Recht</p></html>';
    const sperrSeite = '<html><title>Attention Required! | Cloudflare</title><p>Sorry, you have been blocked</p></html>';
    test('Prüfung an cf-mitigated, gleich welcher Status', () {
      expect(schutzErkennen(403, server: 'cloudflare', mitigated: 'challenge', text: sperrSeite), Schutz.pruefung);
    });
    test('Sperre: 403 von Cloudflare ohne Moodle-Seite', () {
      expect(schutzErkennen(403, server: 'cloudflare', text: sperrSeite), Schutz.sperre);
      expect(schutzErkennen(403, server: 'Cloudflare', text: ''), Schutz.sperre);
    });
    test('Ein 403 von Moodle, durch Cloudflare gereicht, ist keine Sperre', () {
      expect(schutzErkennen(403, server: 'cloudflare', text: moodleSeite), isNull);
    });
    test('Ohne Cloudflare oder ohne 403 nichts', () {
      expect(schutzErkennen(403, server: 'nginx', text: sperrSeite), isNull);
      expect(schutzErkennen(403, text: sperrSeite), isNull);
      expect(schutzErkennen(200, server: 'cloudflare', text: sperrSeite), isNull);
      expect(schutzErkennen(303, server: 'cloudflare', text: ''), isNull);
    });
  });

  String radios({String name = 'completion', String selected = '0', String disabled = ''}) => '''<form>
    <fieldset><legend>Abschlussverfolgung</legend>
    ${['Keine', 'Manuell markieren', 'Automatisch abschließen'].asMap().entries.map((e) => '''
    <div class="row fitem" id="fitem_id_$name"><div class="col-form-label"></div>
    <div class="felement" data-fieldtype="radio"><label for="${name}_${e.key}">${e.value}</label>
    <input type="radio" id="${name}_${e.key}" name="$name" value="${e.key}"
      ${selected == '${e.key}' ? 'checked' : ''} ${disabled == '${e.key}' ? 'disabled' : ''}></div></div>''').join()}
    </fieldset></form>''';

  test('Optionsfelder werden nach Namen als Auswahl statt als erstes ja gelesen', () {
    final form = html_parser.parse(radios(selected: '1')).querySelector('form')!;
    final gelesen = einstellungenLesen(form);
    expect(gelesen, hasLength(1));
    expect(gelesen.single.schluessel, 'completion');
    expect(gelesen.single.wert, 'Manuell markieren');
    expect(gelesen.single.toJson()['optionen'], hasLength(3));
  });

  test('jede Radioauswahl wird eindeutig geschrieben und zurückgelesen', () {
    for (final name in ['completion', 'anderes_feld']) {
      for (final value in ['0', '1', '2']) {
        final form = html_parser.parse(radios(name: name)).querySelector('form')!;
        final felder = formularFelder(form);
        final gesetzt = einstellungenSetzen(form, felder, {name: value}).single;
        expect(felder.where((e) => e.key == name).map((e) => e.value), [value]);
        final rueck = html_parser.parse(radios(name: name, selected: value)).querySelector('form')!;
        expect(einstellungenLesen(rueck).single.wert, gesetzt.nachher);
        expect(gesetzt.erwartet, [gesetzt.nachher]);
      }
    }
    final form = html_parser.parse(radios(disabled: '2')).querySelector('form')!;
    final felder = formularFelder(form);
    einstellungenSetzen(form, felder, {'completion': 'Manuell markieren'});
    expect(wertIn(felder, 'completion'), '1');
    expect(() => einstellungenSetzen(form, felder, {'completion': '2'}), throwsA(isA<MoodleFehler>()));
    expect(() => einstellungenSetzen(form, felder, {'completion': 'unbekannt'}), throwsA(isA<MoodleFehler>()));
    expect(wertIn(felder, 'completion'), '1');
  });

  test('Rückleseprobe akzeptiert bei Optionsfeldern keine bloße Teilgleichheit', () async {
    final form = html_parser.parse(radios(selected: '2').replaceAll('Automatisch abschließen', 'Keine manuelle Markierung'))
        .querySelector('form')!;
    final gelesen = FormularGelesen(Formularziel.aktivitaet(5), 12, 'ZZ Probe', 'assign', '',
        [], [], [], [], {}, [], einstellungen: einstellungenLesen(form));
    final probe = await zuruecklesen(gelesen, felder: {}, dateien: {}, bereiche: {},
        einstellungen: [Gesetzt('completion', 'Abschlussverfolgung', '', 'Keine', ['Keine'])]);
    expect(probe.ok, isFalse);
  });

  test('Rückleseprobe unterscheidet gleiche Radiobeschriftungen anhand des technischen Werts', () async {
    final quelle = radios().replaceAll('Manuell markieren', 'Keine');
    final form = html_parser.parse(quelle).querySelector('form')!;
    final gesetzt = einstellungenSetzen(form, formularFelder(form), {'completion': '1'});
    FormularGelesen gelesen(String selected) => FormularGelesen(
        Formularziel.aktivitaet(5), 12, 'ZZ Probe', 'assign', '', [], [], [], [], {}, [],
        einstellungen: einstellungenLesen(html_parser.parse(radios(selected: selected)
            .replaceAll('Manuell markieren', 'Keine')).querySelector('form')!));
    final falsch = await zuruecklesen(gelesen('0'), felder: {}, dateien: {}, bereiche: {}, einstellungen: gesetzt);
    final richtig = await zuruecklesen(gelesen('1'), felder: {}, dateien: {}, bereiche: {}, einstellungen: gesetzt);
    expect(falsch.ok, isFalse);
    expect(richtig.ok, isTrue);
    expect(() => einstellungenSetzen(form, formularFelder(form), {'completion': 'Keine'}),
        throwsA(isA<MoodleFehler>()));
  });

  test('Einstellungen lesen: Datum, Gruppe, Auswahl', () {
    final form = html_parser.parse(formular).querySelector('form')!;
    expect({for (final e in einstellungenLesen(form)) e.schluessel: e.wert}, {
      'name': 'ZZ Probe',
      'duedate': 'aus',
      'submissionplugins': 'Texteingabe online: nein · Dateiabgabe: ja',
      'teamsubmission': 'Nein',
    });
  });

  test('Einstellungen setzen: wie ein Browser, mit Rückleseangaben', () {
    final form = html_parser.parse(formular).querySelector('form')!;
    final f = formularFelder(form);
    final g = einstellungenSetzen(form, f, {
      'duedate': '2026-10-05 08:30',
      'submissionplugins': {'Texteingabe online': 'ja', 'Dateiabgabe': 'nein'},
      'teamsubmission': 'Ja',
      'name': 'ZZ Neu',
    });
    expect(g.map((s) => '$s').toList(), [
      'Fälligkeitsdatum: aus → 2026-10-05 08:30',
      'Abgabetypen: Texteingabe online: nein · Dateiabgabe: ja → Texteingabe online: ja · Dateiabgabe: nein',
      'Gruppenabgabe: Nein → Ja',
      'Name der Aufgabe: ZZ Probe → ZZ Neu',
    ]);
    expect(wertIn(f, 'duedate[enabled]'), '1');
    expect(wertIn(f, 'duedate[day]'), '5');
    expect(wertIn(f, 'duedate[month]'), '10');
    expect(wertIn(f, 'duedate[hour]'), '8');
    expect(wertIn(f, 'duedate[minute]'), '30');
    // PHP nimmt den letzten gleichnamigen Wert.
    expect(f.where((e) => e.key == 'assignsubmission_onlinetext_enabled').last.value, '1');
    expect(f.where((e) => e.key == 'assignsubmission_file_enabled').last.value, '0');
    expect(wertIn(f, 'teamsubmission'), '1');

    final aus = formularFelder(form);
    einstellungenSetzen(form, aus, {'duedate': '2026-10-05 08:30'});
    einstellungenSetzen(form, aus, {'duedate': 'aus'});
    expect(aus.any((e) => e.key == 'duedate[enabled]'), isFalse);
  });

  test('Einstellungen setzen: ein leerer Wert steht in der Freigabe als (leer)', () {
    final form = html_parser.parse(formular).querySelector('form')!;
    final g = einstellungenSetzen(form, formularFelder(form), {'name': ''});
    expect('${g.single}', 'Name der Aufgabe: ZZ Probe → (leer)');
  });

  test('Einstellungen setzen: Unbekanntes bricht ab, mit Hinweis', () {
    final form = html_parser.parse(formular).querySelector('form')!;
    final f = formularFelder(form);
    expect(() => einstellungenSetzen(form, f, {'gibtsnicht': '1'}), throwsA(isA<MoodleFehler>()));
    expect(
        () => einstellungenSetzen(form, f, {'teamsubmission': 'Vielleicht'}),
        throwsA(predicate((e) => e is MoodleFehler && e.meldung.contains('Nein | Ja'))));
    expect(() => einstellungenSetzen(form, f, {'duedate': '5.10.2026'}), throwsA(isA<MoodleFehler>()));
    expect(() => einstellungenSetzen(form, f, {'submissionplugins': 'ja'}), throwsA(isA<MoodleFehler>()));
  });

  group('Welche Datei eines Dateibereichs zeilenweise verglichen wird', () {
    // Die Freigabe zeigt bei einer geänderten Textdatei die Zeilen, bei allem
    // anderen Name und Größe. Falsch entschieden heißt: eine Lehrkraft sieht
    // Kauderwelsch statt eines Vergleichs -- oder gar nichts, wo sie etwas
    // sehen müsste.
    test('UTF-8 mit Umlauten ist Text, Zeilenenden werden angeglichen', () {
      expect(alsText(utf8.encode('# Größen\r\nzwei Zeilen\n')), '# Größen\nzwei Zeilen\n');
    });
    test('Eine PNG-Datei ist kein Text (Nullbyte im Kopf)', () {
      expect(alsText(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D]), isNull);
    });
    test('Kein gültiges UTF-8 ist kein Text', () {
      expect(alsText(const [0xFF, 0xFE, 0x41, 0x42]), isNull);
    });
    test('Zu groß wird nicht verglichen', () {
      expect(alsText(utf8.encode('x' * (256 * 1024 + 1))), isNull);
      expect(alsText(utf8.encode('x' * (256 * 1024))), isNotNull);
    });
  });

  test('Für die Zwischenablage der Übergabe werden eigene Dateien zu @@PLUGINFILE@@, fremde bleiben', () {
    // Im Browser hat das Formular einen eigenen Entwurfsbereich; die Adresse
    // aus dem der App gälte dort nicht (_uebergeben).
    const html = '<p><img src="https://moodle.schule.example/draftfile.php/2996/user/draft/689622855/zz.png?time=1" '
        'alt="Probe"> <a href="https://moodle.schule.example/pluginfile.php/7/mod_resource/content/1/plan.pdf">Plan</a> '
        '<a href="https://moodle.schule.example/mod/page/view.php?id=12">Seite</a></p>';
    expect(
        fuerBrowser(html),
        '<p><img src="@@PLUGINFILE@@/zz.png" alt="Probe"> '
        '<a href="https://moodle.schule.example/pluginfile.php/7/mod_resource/content/1/plan.pdf">Plan</a> '
        '<a href="https://moodle.schule.example/mod/page/view.php?id=12">Seite</a></p>');
  });

  test('Nach der Übergabe zählt, was der Editor im Browser gleichwertig schreibt, nicht wie', () {
    // Gemessen am Abschnitt: TinyMCE sortiert Attribute um und setzt
    // Zeilenumbrüche zwischen Absätze; der Entwurfsbereich hat eine andere Nummer.
    const app = '<p>Probeabschnitt.</p><p><img src="https://moodle.schule.example/draftfile.php/2996/user/draft/1/zz.png" '
        'alt="Probe" class="img-fluid"></p><pre class="language-html"><code>&lt;b&gt;\n  x\n</code></pre>';
    const browser = '<p>Probeabschnitt.</p>\n<p><img class="img-fluid" '
        'src="https://moodle.schule.example/draftfile.php/2996/user/draft/2/zz.png" alt="Probe"></p>\n'
        '<pre class="language-html"><code>&lt;b&gt;\n  x\n</code></pre>';
    expect(wieImEditor(browser), wieImEditor(app));
    // Nach dem Anlegen mit Platzhalter steht im Ordner @@PLUGINFILE@@, zurück
    // kommt die Entwurfsadresse.
    expect(wieImEditor(browser), wieImEditor(app.replaceFirst(RegExp(r'https://[^"]*/zz\.png'), '@@PLUGINFILE@@/zz.png')));
    expect(platzhalterFelder({'page': app, 'leer': ''}), {
      'page': '<p>Inhalt folgt.</p><p><a href="@@PLUGINFILE@@/zz.png">zz.png</a></p>',
      'leer': '',
    });
    expect(normalisiert(browser), isNot(normalisiert(app)), reason: 'Zeichen für Zeichen sind sie verschieden');
    // Echte Unterschiede fallen weiter auf: Text, Leerraum im Code, ein Attributwert.
    expect(wieImEditor(app.replaceFirst('Probeabschnitt', 'Probe')), isNot(wieImEditor(app)));
    expect(wieImEditor(app.replaceFirst('\n  x', '\n x')), isNot(wieImEditor(app)));
    expect(wieImEditor(app.replaceFirst('alt="Probe"', 'alt="Bild"')), isNot(wieImEditor(app)));
  });

  test('Gemessen am Buchkapitel: der übergebene Text und was Moodle danach zeigt, gelten als gleich', () {
    const uebergeben = '<h3>ZZ Kapitel</h3><p><img src="@@PLUGINFILE@@/zz.png" alt="Probe" class="img-fluid"></p>'
        '<pre class="language-html"><code>&lt;button onclick="berechne()"&gt;Berechnen&lt;/button&gt;\n'
        '&lt;script&gt;\nfunction berechne() {\n  x = 2.5;\n}\n&lt;/script&gt;</code></pre>';
    const moodle = '<h3>ZZ Kapitel</h3>\n<p><img class="img-fluid" '
        'src="https://moodle.schule.example/draftfile.php/2996/user/draft/231118294/zz.png" alt="Probe"></p>\n'
        '<pre class="language-html"><code>&lt;button onclick="berechne()"&gt;Berechnen&lt;/button&gt;\n'
        '&lt;script&gt;\nfunction berechne() {\n  x = 2.5;\n}\n&lt;/script&gt;</code></pre>';
    expect(wieImEditor(moodle), wieImEditor(uebergeben));
    // Der Platzhalter ist etwas anderes.
    expect(wieImEditor(platzhalterFelder({'f': uebergeben})['f']!), isNot(wieImEditor(uebergeben)));
  });
}
