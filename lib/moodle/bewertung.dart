// Bewertungsschema einer Aufgabe: Werkzeuge bewertungsschema_lesen und
// bewertungsschema_setzen -- Rubrik (rubric) und Bewertungsrichtlinie
// (guide). Die Methode selbst stellt aendern um (Einstellung
// advancedgradingmethod_submissions der Aufgabe).
//
// Datenschutz: Der ganze Notenbereich (/grade/) ist gesperrt. Ausgenommen
// sind genau manage.php, pick.php und form/<methode>/edit.php, und zwar nur
// von der Regel /grade/ (sperrliste.dart): Eine Rubrik ist das Raster, nicht
// die Bewertung. Ausgefüllte Rubriken einzelner Personen liegen unter
// action=grading und bleiben gesperrt.
//
// Den Verwaltungslink baut die App aus dem Kontext des Moduls (M.cfg.contextid
// des Bearbeitungsformulars) -- die Ansichtsseite der Aufgabe mit ihrer
// Abgabeübersicht braucht sie dafür nicht.
//
// Die Feldnamen tragen die Struktur (gemessen): <m>[criteria][<kid>][feld]
// und <m>[criteria][<kid>][levels][<lid>][feld]. Bestehende ids sind Zahlen,
// neue heißen NEWID1, NEWID2 … -- die Nummern laufen über alle Kriterien und
// Level hinweg. Punktzahlen stehen je nach Sprache mit Komma oder Punkt.
//
// Die Optionen stehen im selben Formular als <m>[options][<name>] (gemessen):
// bei der Rubrik neun, davon sortlevelsasc als Auswahl, die übrigen als
// Kontrollkästchen (nicht angehakt = aus, wie im Browser); bei der Richtlinie
// zwei Kontrollkästchen, die sich auch beide abschalten lassen. alwaysshowdefinition ist die Vorschau für
// Lernende („Nutzer/innen eine Vorschau auf die Rubrik erlauben" bzw.
// „Beschreibung für Teilnehmer/innen anzeigen"). Ein neues Schema hat alle an.
// Welche es gibt, liest die App aus dem Formular statt aus einer festen Liste.
// Die Stufen stehen im Formular in der Reihenfolge nach sortlevelsasc.

import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

import '../freigabe.dart';
import 'formular.dart';
import 'formular_lesen.dart' show hauptformular;
import 'formular_schreiben.dart';
import 'kurs.dart';
import 'moodle_zugang.dart';
import 'zeilenvergleich.dart';

class Schema {
  Schema(this.methode, this.areaid, this.adresse, this.form, this.felder, this.kriterien, this.name, this.beschreibung);
  final String methode;
  final int areaid;
  final String adresse;
  final dom.Element form;
  final Felder felder;

  /// id -> {feld: wert, 'level': {lid: {feld: wert}}}
  final Map<String, Map<String, Object?>> kriterien;
  final String name;
  final String beschreibung;

  late final Map<String, dom.Element> optionen = schemaOptionen(form);

  /// Name -> lesbarer Wert („ja", „nein", Text der Auswahl).
  Map<String, String> get optionenWerte => {for (final o in optionen.entries) o.key: steuerWert(o.value)};

  /// Name -> Beschriftung; eine Auswahl bringt ihren Doppelpunkt mit
  /// („Sortierfolge für Level:").
  Map<String, String> get optionenLabels => {
        for (final o in optionen.entries) o.key: beschriftung(o.value, form).replaceFirst(RegExp(r':\s*$'), '')
      };

  List<Map<String, Object?>> alsJson() => [
        for (final e in kriterien.entries)
          {
            'id': e.key,
            for (final f in e.value.entries.where((f) => f.key != 'level' && f.key != 'sortorder')) f.key: f.value,
            if ((e.value['level'] as Map).isNotEmpty)
              'level': [
                for (final l in (e.value['level'] as Map).entries)
                  {'id': l.key, 'definition': (l.value as Map)['definition'], 'punkte': (l.value as Map)['score']}
              ],
          }
      ];

  String text() => _schemaText(name, methode, alsJson(), optionenWerte, optionenLabels);

  /// Für die Antwort an die KI: die Kriterien mit den Punkten ihrer Stufen und
  /// die Optionen. Die Texte der Stufen stehen nur in `bewertung-<cmid>.json` --
  /// wer etwas ändert, öffnet die Datei ohnehin (E5), und sie zweimal zu
  /// schicken kostete Kontext.
  String uebersicht() {
    final ks = alsJson();
    String kurz(Object? s) {
      final t = '${s ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
      return t.length <= 100 ? t : '${t.substring(0, 99)}…';
    }

    return [
      '„$name" ($methode), ${ks.length} ${ks.length == 1 ? 'Kriterium' : 'Kriterien'}:',
      for (final k in ks)
        '  Kriterium ${k['id']}: ${kurz(k['shortname'] ?? k['description'])}'
            '${k['maxscore'] == null ? '' : ' (höchstens ${k['maxscore']} P.)'}'
            '${k['level'] == null ? '' : ' -- Stufen: ${[for (final l in (k['level'] as List).cast<Map>()) l['punkte']].join(', ')} P.'}',
      if (optionenWerte.isNotEmpty) 'Optionen:',
      for (final o in optionenWerte.entries) '    ${optionenLabels[o.key] ?? o.key}: ${o.value} (${o.key})',
    ].join('\n');
  }
}

/// Die lesbare Version für Übersicht und Freigabe; [kriterien] im Aufbau von
/// `bewertung-<cmid>.json`, neue ohne id.
String _schemaText(String name, String methode, List<Map> kriterien, Map<String, String> optionen,
        Map<String, String> labels) =>
    [
      '„$name" ($methode)',
      for (final k in kriterien) ...[
        'Kriterium ${'${k['id'] ?? ''}'.isEmpty ? 'neu' : k['id']}: ${k['description'] ?? k['shortname'] ?? ''}'
            '${k['maxscore'] == null ? '' : ' (höchstens ${k['maxscore']} P.)'}',
        for (final l in (k['level'] as List? ?? const []).cast<Map>()) '    ${l['punkte']} P.: ${l['definition']}',
      ],
      if (optionen.isNotEmpty) 'Optionen:',
      for (final o in optionen.entries) '    ${labels[o.key] ?? o.key}: ${o.value} (${o.key})',
    ].join('\n');

final _feldMuster = RegExp(r'^([a-z]+)\[criteria\]\[([^\]]+)\](?:\[levels\]\[([^\]]+)\])?\[([a-z]+)\]$');
final _optionMuster = RegExp(r'^[a-z]+\[options\]\[([a-z]+)\]$');

/// Die Optionen eines Definitionsformulars: Name -> Steuerelement
/// (Kontrollkästchen oder Auswahl). Versteckte und deaktivierte Felder
/// gleichen Namens sind keine Optionen, die sich setzen lassen; beim Senden
/// gehen sie trotzdem mit, wie im Browser.
Map<String, dom.Element> schemaOptionen(dom.Element form) => {
      for (final e in form.querySelectorAll('input, select'))
        if (_optionMuster.firstMatch(e.attributes['name'] ?? '') case final m?
            when (e.attributes['type'] ?? '').toLowerCase() != 'hidden' && !e.attributes.containsKey('disabled'))
          m.group(1)!: e
    };

/// Setzt die gewünschten Optionen ({name: wert}) in [f] und gibt die Werte
/// aller Optionen danach zurück, lesbar wie [steuerWert]. Nicht genannte
/// bleiben, wie sie sind -- anders als bei Kriterien soll eine vergessene
/// Zeile nichts abschalten. Unbekanntes bricht ab, bevor etwas geschrieben
/// wird.
Map<String, String> optionenSetzen(dom.Element form, Felder f, Map<Object?, Object?> wuensche) {
  final optionen = schemaOptionen(form);
  final aus = {for (final o in optionen.entries) o.key: steuerWert(o.value)};
  for (final w in wuensche.entries) {
    final e = optionen['${w.key}'];
    if (e == null) {
      throw MoodleFehler('Option „${w.key}" gibt es in diesem Schema nicht; möglich: ${optionen.keys.join(', ')}.');
    }
    aus['${w.key}'] = steuerSetzen(form, f, e, w.value, 'Option ${w.key}');
  }
  return aus;
}

String _norm(Object? x) => '${x ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();

String _punkte(Object? x) {
  final d = double.tryParse(_zahl(x).trim());
  return d == null ? _norm(x) : '$d';
}

/// Was die zurückgelesenen Kriterien ([ist], aus Schema.alsJson) anders haben
/// als die geschriebenen ([soll], aus der Datei). Kriterien nach Position,
/// weil Moodle sie nach sortorder zeigt und neue erst beim Speichern ids
/// bekommen; Stufen als Menge, weil das Formular sie nach Punkten ordnet;
/// Punkte als Zahl („2,00" = „2").
List<String> kriterienAbweichungen(List<Map> soll, List<Map> ist) {
  final aus = <String>[];
  if (soll.length != ist.length) aus.add('${ist.length} Kriterien statt ${soll.length}');
  List<String> stufen(Map k) => [
        for (final l in (k['level'] as List? ?? const []).cast<Map>())
          '${_punkte(l['punkte'])} P.: ${_norm(l['definition'])}'
      ]..sort();
  for (var i = 0; i < soll.length && i < ist.length; i++) {
    final (s, x) = (soll[i], ist[i]);
    for (final f in const ['description', 'shortname', 'descriptionmarkers', 'maxscore']) {
      if (s[f] == null) continue;
      final gleich = f == 'maxscore' ? _punkte(s[f]) == _punkte(x[f]) : _norm(s[f]) == _norm(x[f]);
      if (!gleich) aus.add('Kriterium ${i + 1}, $f: „${_norm(x[f])}" statt „${_norm(s[f])}"');
    }
    final (a, b) = (stufen(s), stufen(x));
    if (a.join('\n') != b.join('\n')) {
      aus.add('Kriterium ${i + 1}, Stufen: ${b.join(' | ')} statt ${a.join(' | ')}');
    }
  }
  return aus;
}

Future<(String?, String?)> _methodeUndBereich(MoodleZugang moodle, int cmid) async {
  final f = await formularHolen(moodle, '/course/modedit.php?update=$cmid');
  if (f.modul != 'assign') throw MoodleFehler('cmid $cmid ist keine Aufgabe (${f.modul}).');
  final methode = wertIn(f.felder, 'advancedgradingmethod_submissions');
  return (methode == null || methode.isEmpty ? null : methode, f.seite.kontext);
}

Future<Schema?> _schema(MoodleZugang moodle, int cmid) async {
  final (methode, kontext) = await _methodeUndBereich(moodle, cmid);
  if (methode == null) return null;
  final m = html_parser.parse((await moodle.lesen(
          '/grade/grading/manage.php?contextid=$kontext&component=mod_assign&area=submissions'))
      .text);
  final link = m.querySelector('#region-main a[href*="/grade/grading/form/"]')?.attributes['href'];
  final u = link == null ? null : Uri.parse(link);
  final areaid = int.tryParse(u?.queryParameters['areaid'] ?? '');
  if (u == null || areaid == null) {
    throw MoodleFehler('Kein Definitionsformular für die Methode $methode gefunden (manage.php).');
  }
  final adresse = '${u.path}?areaid=$areaid';
  final r = await moodle.lesen(adresse);
  final form = hauptformular(html_parser.parse(r.text));
  if (form == null) throw MoodleFehler('Definitionsformular nicht lesbar ($adresse).');
  final felder = formularFelder(form);
  final kriterien = <String, Map<String, Object?>>{};
  for (final e in felder) {
    final x = _feldMuster.firstMatch(e.key);
    if (x == null) continue;
    final k = kriterien.putIfAbsent(x.group(2)!, () => {'level': <String, Map<String, String>>{}});
    if (x.group(3) != null) {
      ((k['level'] as Map).putIfAbsent(x.group(3)!, () => <String, String>{}) as Map)[x.group(4)!] = e.value;
    } else {
      k[x.group(4)!] = e.value;
    }
  }
  return Schema(methode, areaid, adresse, form, felder, kriterien, wertIn(felder, 'name') ?? '',
      wertIn(felder, 'description_editor[text]') ?? '');
}

Future<String> bewertungsschemaLesen(MoodleZugang moodle, int cmid, String arbeitsordner) async {
  final s = await _schema(moodle, cmid);
  if (s == null) {
    return 'Aufgabe cmid $cmid: einfache direkte Bewertung (keine Rubrik, keine Richtlinie). Umstellen: aendern mit '
        'Einstellung advancedgradingmethod_submissions ("Bewertungsraster" bzw. "Bewertungsrichtlinie").';
  }
  final datei = File(p.join(arbeitsordner, 'bewertung-$cmid.json'));
  await datei.parent.create(recursive: true);
  await datei.writeAsString(const JsonEncoder.withIndent('  ').convert({
    'methode': s.methode,
    'name': s.name,
    'beschreibung': s.beschreibung,
    'kriterien': s.alsJson(),
    'optionen': s.optionenWerte,
  }));
  return 'Bewertungsschema der Aufgabe cmid $cmid -- nur die DEFINITION, keine Bewertung:\n${s.uebersicht()}\n'
      'Vollständig, mit den Texten der Stufen: ${datei.path}. Ändern: die Datei bearbeiten (bestehende ids behalten, neue Kriterien und Level ohne '
      'id; weggelassene Kriterien werden gelöscht; optionen: ja/nein bzw. Text der Auswahl, weggelassene bleiben), '
      'dann bewertungsschema_setzen.';
}

String _zahl(Object? x) => '${x ?? ''}'.replaceAll(',', '.');

Future<String> bewertungsschemaSetzen(MoodleZugang moodle, Freigaben freigaben,
    {required int cmid, required String name, required String datei, required String arbeitsordner}) async {
  final neu = jsonDecode(await dateiAusArbeitsordner(datei, arbeitsordner)) as Map;
  final s = await _schema(moodle, cmid);
  if (s == null) {
    throw MoodleFehler('Die Aufgabe hat keine Rubrik oder Richtlinie. Erst die Methode umstellen (aendern, '
        'advancedgradingmethod_submissions), dann setzen.');
  }
  final f0 = await formularHolen(moodle, '/course/modedit.php?update=$cmid');
  nameBestaetigen(name, f0.name, 'cmid $cmid');
  final m = s.methode;
  // Neue Felder: alles Übrige des Formulars bleibt; die Kriterien werden
  // vollständig aus der Datei gebaut.
  final felder = [for (final e in s.felder) if (!_feldMuster.hasMatch(e.key)) e];
  // Neue Kriterien und Level heißen NEWID<n>, eindeutig über alles hinweg --
  // auch über NEWIDs, die schon in der Datei stehen.
  final vergeben = <String>{
    for (final k in (neu['kriterien'] as List? ?? const []).cast<Map>()) ...[
      '${k['id'] ?? ''}',
      for (final l in (k['level'] as List? ?? const []).cast<Map>()) '${l['id'] ?? ''}',
    ]
  };
  var neuId = 0;
  String id(Object? x) {
    if (x != null && '$x'.isNotEmpty) return '$x';
    while (vergeben.contains('NEWID${++neuId}')) {}
    return 'NEWID$neuId';
  }
  final kriterien = (neu['kriterien'] as List? ?? const []).cast<Map>();
  if (kriterien.isEmpty) throw MoodleFehler('Das Schema braucht mindestens ein Kriterium.');
  for (final (i, k) in kriterien.indexed) {
    final kid = id(k['id']);
    if (!kid.startsWith('NEWID') && !s.kriterien.containsKey(kid)) {
      throw MoodleFehler('Kriterium $kid gibt es nicht -- neue Kriterien ohne id angeben.');
    }
    final b = '$m[criteria][$kid]';
    felder.add(MapEntry('$b[sortorder]', '${i + 1}'));
    for (final f in ['description', 'shortname', 'descriptionmarkers', 'maxscore']) {
      if (k[f] != null) felder.add(MapEntry('$b[$f]', f == 'maxscore' ? _zahl(k[f]) : '${k[f]}'));
    }
    for (final l in (k['level'] as List? ?? const []).cast<Map>()) {
      final lid = id(l['id']);
      felder.add(MapEntry('$b[levels][$lid][definition]', '${l['definition'] ?? ''}'));
      felder.add(MapEntry('$b[levels][$lid][score]', _zahl(l['punkte'])));
    }
  }
  if (neu['name'] != null) setze(felder, 'name', '${neu['name']}');
  if (neu['beschreibung'] != null) setze(felder, 'description_editor[text]', '${neu['beschreibung']}');
  final wuensche = neu['optionen'] ?? const {};
  if (wuensche is! Map) {
    throw MoodleFehler('„optionen" ist ein Objekt {name: wert}, etwa {"alwaysshowdefinition": "ja"}.');
  }
  final optionen = optionenSetzen(s.form, felder, wuensche);
  final nameNeu = '${neu['name'] ?? s.name}';

  final vorher = s.text();
  final nachherText = _schemaText(nameNeu, m, kriterien, optionen, s.optionenLabels);
  final ja = await freigaben.anfragen(FreigabeAnfrage(
    titel: 'Bewertungsschema ändern?',
    ab: await fuellenAb(moodle, f0.kurs, [cmid]),
    punkte: [
      '${m == 'rubric' ? 'Bewertungsraster' : 'Bewertungsrichtlinie'} der Aufgabe „${f0.name}" (cmid $cmid'
          '${f0.kurs == null ? '' : ', ${await kursBezeichnung(moodle, f0.kurs!)}'})',
      'Ist das Schema schon zum Bewerten benutzt worden, kann eine Änderung Neubewertungen nötig machen; Moodle weist '
          'dann darauf hin.',
    ],
    vergleich: zeilenVergleich(vorher, nachherText).zeilen,
  ));
  if (!ja) return 'Nicht geändert: in der App abgelehnt oder nicht rechtzeitig freigegeben.';
  final knopf = s.form.querySelectorAll('input, button').where((e) => e.attributes['name'] == 'save$m').firstOrNull;
  felder.add(MapEntry('save$m', knopf?.attributes['value'] ?? '1'));
  final ziel = Uri.parse(s.adresse).resolve(s.form.attributes['action'] ?? s.adresse);
  final a = await moodle.senden(ziel.hasQuery ? '${ziel.path}?${ziel.query}' : ziel.path, felder);
  if (moodle.umleitungsziel(a) == null) {
    final meldung = html_parser
        .parse(a.text)
        .querySelectorAll('.error, .invalid-feedback, .alert-danger')
        .map((e) => e.text.trim())
        .where((t) => t.isNotEmpty)
        .join(' | ');
    throw MoodleFehler('Moodle hat das Schema nicht angenommen${meldung.isEmpty ? '' : ': $meldung'}.');
  }
  // Rückleseprobe über alles, was geschrieben wurde: Moodle leitet auch dann
  // weiter, wenn es Teile still verwirft.
  final danach = await _schema(moodle, cmid);
  final abweichungen = danach == null
      ? ['Die Aufgabe hat keine Rubrik oder Richtlinie mehr.']
      : [
          if (_norm(danach.name) != _norm(nameNeu)) 'Name: „${danach.name}" statt „$nameNeu"',
          if (neu['beschreibung'] != null && _norm(danach.beschreibung) != _norm(neu['beschreibung']))
            'Beschreibung weicht ab',
          ...kriterienAbweichungen(kriterien, danach.alsJson()),
          for (final o in optionen.entries)
            if (danach.optionenWerte[o.key] != o.value)
              'Option ${o.key}: ${danach.optionenWerte[o.key] ?? 'fehlt'} statt ${o.value}',
        ];
  final ok = abweichungen.isEmpty;
  return 'Gespeichert. Zurückgelesen: ${danach?.kriterien.length} Kriterien (erwartet ${kriterien.length}). '
      'verified: $ok\n'
      '${ok ? '' : 'Abweichungen: ${abweichungen.join('; ')}\n'}'
      '${danach?.text() ?? ''}';
}
