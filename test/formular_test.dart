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
}
