// Gruppierungen eines Kurses: lesen, anlegen, Gruppen zuordnen (E33).
//
// Gelesen werden nur Namen. Die Gruppierung steht in ihrem Formular
// (grouping.php), die Gruppen darin auf der Zuordnungsseite (assign.php).
// Die Seiten index, members und overview zeigen Mitglieder und bleiben
// gesperrt (A1); diese Datei braucht sie nicht.
//
// Anlegen geht in drei Schritten, jeder als Formular wie im Browser: die
// Gruppierung, fehlende Gruppen, dann die Zuordnung. Gruppen und Gruppierungen
// haben keine Sichtbarkeit; Lernende sehen sie nur über Aktivitäten, die sie
// verwenden. Löschen und Umbenennen gibt es hier nicht.

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../freigabe.dart';
import 'formular.dart';
import 'kurs.dart';
import 'moodle_zugang.dart';

class Gruppierung {
  Gruppierung(this.id, this.name, this.gruppen);
  final int id;
  final String name;
  final List<String> gruppen;
}

/// Eine Gruppierung, die im Kurs fehlt. Kein stilles Abbrechen: Die Meldung
/// ist die Rückfrage an die Lehrkraft und nennt den Weg weiter.
class GruppierungFehlt extends MoodleFehler {
  GruppierungFehlt(String name, int? kurs, List<String> vorhanden)
    : super(
        'Rückfrage an die Lehrkraft, bevor es weitergeht: Die Gruppierung „$name" gibt es '
        '${kurs == null ? 'im Kurs' : 'in Kurs $kurs'} nicht '
        '(vorhanden: ${vorhanden.isEmpty ? 'keine' : vorhanden.join(', ')}). Nichts gespeichert. '
        'Frage, ob sie angelegt werden soll -- mit den Gruppen darin. Welche Gruppen zur Gruppierung '
        'der Quelle gehören, zeigt gruppierungen_lesen für den Quellkurs. Nach dem Ja: '
        'gruppierung_anlegen(kurs, name, gruppen), danach diesen Aufruf wiederholen. Ohne Ja bleibt '
        'die Gruppierung leer; sag der Lehrkraft ausdrücklich, dass sie fehlt.',
      );
}

/// Ob der Optionstext zum Gruppennamen gehört. Manche Auswahllisten hängen
/// die Zahl der Mitglieder an („Name (3)"); die Zahl ist hier ohne Bedeutung.
bool optionPasst(String text, String name) {
  final t = text.trim().toLowerCase();
  final n = name.trim().toLowerCase();
  return t == n || RegExp('^${RegExp.escape(n)} \\(\\d+\\)\$').hasMatch(t);
}

/// Prüft vor dem Schreiben, ob die gewünschte Gruppierung im Formular zur
/// Auswahl steht (Name oder Nummer). Sonst die Rückfrage [GruppierungFehlt].
void gruppierungPruefen(dom.Element form, Object? wunsch, int? kurs) {
  if (wunsch == null) return;
  final auswahl = form.querySelectorAll('select').where((s) => s.attributes['name'] == 'groupingid').firstOrNull;
  if (auswahl == null) return;
  final text = '$wunsch'.trim();
  final optionen = auswahl.querySelectorAll('option');
  if (optionen.any((o) => optionPasst(_optionsText(o), text) || o.attributes['value'] == text)) return;
  throw GruppierungFehlt(text, kurs, [
    for (final o in optionen)
      if (o.attributes['value'] != '0') _optionsText(o),
  ]);
}

dom.Element _formular(String html, String auswahl) {
  final f = html_parser.parse(html).querySelector(auswahl);
  if (f == null) throw MoodleFehler('Moodle zeigt das erwartete Formular nicht ($auswahl).');
  return f;
}

/// Wohin ein Browser das Formular schickt: an seine `action`, bei leerer
/// `action` an die Adresse der Seite -- mit Query. (Uri.resolve('') verlöre sie;
/// die Zuordnungsseite hat eine leere `action`.)
Uri formularZiel(dom.Element form, Uri seite) {
  final a = form.attributes['action'];
  return a == null || a.isEmpty ? seite : seite.resolve(a);
}

String _pfadMitQuery(Uri u) => u.hasQuery ? '${u.path}?${u.query}' : u.path;

/// Die Nummern aller Gruppierungen eines Kurses, aus den Verweisen der Übersicht.
Future<List<int>> gruppierungsIds(MoodleZugang moodle, int kurs) async {
  final r = await moodle.lesen('/group/groupings.php?id=$kurs');
  final ids = <int>{};
  for (final a in html_parser.parse(r.text).querySelectorAll('a[href]')) {
    final m = RegExp(r'/group/(?:grouping|assign)\.php\?(?:[^"#]*&)?id=(\d+)').firstMatch(a.attributes['href']!);
    if (m != null) ids.add(int.parse(m.group(1)!));
  }
  return ids.toList()..sort();
}

String _optionsText(dom.Element o) => o.text.trim();

/// Optionen einer Auswahlliste der Zuordnungsseite: (Wert, Text).
List<(String, String)> _optionen(dom.Element form, String name) => [
  for (final s in form.querySelectorAll('select'))
    if (s.attributes['name'] == name)
      for (final o in s.querySelectorAll('option'))
        if ((o.attributes['value'] ?? '').isNotEmpty) (o.attributes['value']!, _optionsText(o)),
];

Future<(dom.Element, Uri)> _zuordnung(MoodleZugang moodle, int gruppierung) async {
  final r = await moodle.lesen('/group/assign.php?id=$gruppierung');
  return (_formular(r.text, '#assignform'), r.adresse);
}

/// Alle Gruppierungen des Kurses mit ihren Gruppen (nur Namen).
Future<List<Gruppierung>> gruppierungenLesen(MoodleZugang moodle, int kurs) async {
  final aus = <Gruppierung>[];
  for (final id in await gruppierungsIds(moodle, kurs)) {
    final f = _formular((await moodle.lesen('/group/grouping.php?id=$id')).text, 'form.mform');
    final name = formularFelder(f).where((e) => e.key == 'name').map((e) => e.value).firstOrNull ?? '';
    final (zuordnung, _) = await _zuordnung(moodle, id);
    aus.add(Gruppierung(id, name.trim(), [for (final o in _optionen(zuordnung, 'removeselect[]')) o.$2]));
  }
  return aus;
}

/// Die Gruppen, die es im Kurs gibt -- soweit sich das ohne die gesperrte
/// Gruppenübersicht feststellen lässt: Auf der Zuordnungsseite jeder
/// Gruppierung stehen alle Gruppen des Kurses, die einen in der Auswahl
/// „in der Gruppierung", die anderen daneben. Ohne Gruppierung unbekannt (null).
Future<List<String>?> kursGruppen(MoodleZugang moodle, List<Gruppierung> vorhandene) async {
  if (vorhandene.isEmpty) return null;
  final (f, _) = await _zuordnung(moodle, vorhandene.first.id);
  return [
    ..._optionen(f, 'removeselect[]').map((o) => o.$2),
    ..._optionen(f, 'addselect[]').map((o) => o.$2),
  ];
}

String gruppierungenText(int kurs, String kursname, List<Gruppierung> gs) {
  final b = StringBuffer()..writeln('Gruppierungen in $kursname: ${gs.length}');
  for (final g in gs) {
    b.writeln('  „${g.name}" (id ${g.id}): ${g.gruppen.isEmpty ? 'keine Gruppen' : g.gruppen.join(', ')}');
  }
  b.write('Nur Namen; Mitglieder liest die App nicht. Gruppennamen können Namen von Lernenden enthalten: '
      'nicht an Dritte weitergeben und nicht in erzeugte Inhalte übernehmen.');
  return b.toString();
}

Future<String> gruppierungenLesenText(MoodleZugang moodle, int kurs) async =>
    gruppierungenText(kurs, await kursBezeichnung(moodle, kurs), await gruppierungenLesen(moodle, kurs));

String _fehlerAus(String html) =>
    html_parser
        .parse(html)
        .querySelectorAll('.error, .invalid-feedback, .alert-danger')
        .map((e) => e.text.trim())
        .where((t) => t.isNotEmpty)
        .join(' | ');

Future<void> _speichern(MoodleZugang moodle, dom.Element form, String adresse, Felder felder, String was) async {
  final knopf = form.querySelectorAll('input[type=submit], button[type=submit]').firstOrNull;
  final knopfName = knopf?.attributes['name'];
  if (knopfName != null && knopfName.isNotEmpty) felder.add(MapEntry(knopfName, knopf!.attributes['value'] ?? '1'));
  final ziel = formularZiel(form, Uri.parse(adresse));
  final a = await moodle.senden(_pfadMitQuery(ziel), felder);
  if (moodle.umleitungsziel(a) == null) {
    final meldung = _fehlerAus(a.text);
    throw MoodleFehler('Moodle hat $was nicht angenommen${meldung.isEmpty ? '' : ': $meldung'}.');
  }
}

Future<void> _gruppeAnlegen(MoodleZugang moodle, int kurs, String name) async {
  final adresse = '/group/group.php?courseid=$kurs';
  final r = await moodle.lesen(adresse);
  final f = _formular(r.text, 'form.mform');
  final felder = formularFelder(f);
  setze(felder, 'name', name);
  await _speichern(moodle, f, r.adresse.toString(), felder, 'die Gruppe „$name"');
}

/// Legt eine Gruppierung samt Gruppen an und ordnet die Gruppen zu. Gruppen,
/// die es im Kurs schon gibt, werden nur zugeordnet, fehlende werden angelegt.
/// Gibt es die Gruppierung schon (etwa nach einem Abbruch mitten im Anlegen),
/// werden ihr nur fehlende Gruppen hinzugefügt: nie entfernt, nie umbenannt.
/// Rückgelesen wird zum Schluss die Gruppierung mit ihren Gruppen.
Future<String> gruppierungAnlegen(
  MoodleZugang moodle,
  Freigaben freigaben, {
  required int kurs,
  required String name,
  List<String> gruppen = const [],
}) async {
  final wunsch = name.trim();
  if (wunsch.isEmpty) throw MoodleFehler('Der Name der Gruppierung ist leer.');
  final namen = <String>[];
  for (final g in gruppen.map((g) => g.trim())) {
    if (g.isEmpty) throw MoodleFehler('Ein Gruppenname ist leer.');
    if (!namen.any((n) => n.toLowerCase() == g.toLowerCase())) namen.add(g);
  }
  final vorhanden = await gruppierungenLesen(moodle, kurs);
  final bestehende = vorhanden.where((g) => g.name.toLowerCase() == wunsch.toLowerCase()).firstOrNull;
  // Was der Gruppierung noch fehlt; bei einer neuen alle.
  final zuordnen = [
    for (final g in namen)
      if (bestehende == null || !bestehende.gruppen.any((o) => optionPasst(o, g))) g,
  ];
  if (bestehende != null && zuordnen.isEmpty) {
    return 'Unverändert: Die Gruppierung „${bestehende.name}" (id ${bestehende.id}) gibt es in Kurs $kurs schon, '
        'mit ${namen.isEmpty ? 'allen gewünschten' : 'diesen'} Gruppen: ${bestehende.gruppen.join(', ')}. verified: true';
  }
  final imKurs = await kursGruppen(moodle, vorhanden);
  final fehlen = [
    for (final g in zuordnen)
      if (imKurs == null || !imKurs.any((o) => optionPasst(o, g))) g,
  ];
  final ja = await freigaben.anfragen(FreigabeAnfrage(
    titel: bestehende == null ? 'Gruppierung anlegen?' : 'Gruppen einer Gruppierung ergänzen?',
    punkte: [
      '${bestehende == null ? 'Gruppierung' : 'Bestehende Gruppierung'} „$wunsch" in ${await kursBezeichnung(moodle, kurs)}',
      if (zuordnen.isNotEmpty) '${bestehende == null ? 'Gruppen darin' : 'Gruppen, die hinzukommen'}: ${zuordnen.join(', ')}',
      if (imKurs == null && zuordnen.isNotEmpty)
        'Welche dieser Gruppen es im Kurs schon gibt, ist vorab nicht festzustellen; vorhandene werden nur zugeordnet, '
            'fehlende angelegt.'
      else if (fehlen.isNotEmpty)
        'Neu angelegt werden die Gruppen: ${fehlen.join(', ')}',
      'Gruppen und Gruppierungen haben keine Mitglieder aus dieser Aktion; Lernende werden nicht hinzugefügt.',
    ],
    vergleich: const [],
    knopf: 'Anlegen',
    ohneEntscheidung: 'wird nichts angelegt',
    ab: Bestaetigungen.alle,
  ));
  if (!ja) {
    return 'Nicht angelegt: in der App abgelehnt oder nicht innerhalb von '
        '${freigaben.frist.inMinutes} Minuten freigegeben.';
  }

  // 1. die Gruppierung
  int id;
  if (bestehende != null) {
    id = bestehende.id;
  } else {
    final leer = await moodle.lesen('/group/grouping.php?courseid=$kurs');
    final gf = _formular(leer.text, 'form.mform');
    final gfelder = formularFelder(gf);
    setze(gfelder, 'name', wunsch);
    await _speichern(moodle, gf, leer.adresse.toString(), gfelder, 'die Gruppierung „$wunsch"');
    final neu = (await gruppierungenLesen(moodle, kurs)).where((g) => g.name.toLowerCase() == wunsch.toLowerCase());
    if (neu.length != 1) {
      throw MoodleFehler('Die Gruppierung „$wunsch" war nach dem Speichern nicht eindeutig zu finden '
          '(${neu.length} Treffer). Nichts weiter angelegt.');
    }
    id = neu.single.id;
  }

  // 2. fehlende Gruppen anlegen, 3. alle zuordnen
  final angelegt = <String>[];
  var (zf, zadresse) = await _zuordnung(moodle, id);
  for (final g in zuordnen) {
    if (!_optionen(zf, 'addselect[]').any((o) => optionPasst(o.$2, g))) {
      await _gruppeAnlegen(moodle, kurs, g);
      angelegt.add(g);
      (zf, zadresse) = await _zuordnung(moodle, id);
    }
  }
  final waehlen = <String>[];
  final nichtGefunden = <String>[];
  for (final g in zuordnen) {
    final o = _optionen(zf, 'addselect[]').where((o) => optionPasst(o.$2, g)).firstOrNull;
    if (o == null) {
      nichtGefunden.add(g);
    } else {
      waehlen.add(o.$1);
    }
  }
  if (waehlen.isNotEmpty) {
    final felder = formularFelder(zf)..removeWhere((e) => e.key == 'addselect[]' || e.key == 'removeselect[]');
    for (final w in waehlen) {
      felder.add(MapEntry('addselect[]', w));
    }
    final knopf = zf.querySelector('input[name=add]');
    felder.add(MapEntry('add', knopf?.attributes['value'] ?? '1'));
    // Die Nummer der Gruppierung steht in der Adresse des Formulars, nicht in einem Feld.
    final ziel = formularZiel(zf, zadresse);
    final a = await moodle.senden(_pfadMitQuery(ziel), felder);
    if (moodle.umleitungsziel(a) == null && a.status >= 400) {
      throw MoodleFehler('Moodle hat die Zuordnung der Gruppen nicht angenommen (Status ${a.status}).');
    }
  }

  // Rückleseprobe: die Gruppierung mit genau den gewünschten Gruppen
  final danach = (await gruppierungenLesen(moodle, kurs)).where((g) => g.id == id).firstOrNull;
  final fehlt = [
    for (final g in namen)
      if (danach == null || !danach.gruppen.any((o) => optionPasst(o, g))) g,
  ];
  final ok = danach != null && fehlt.isEmpty && nichtGefunden.isEmpty;
  return '${ok ? (bestehende == null ? 'Angelegt' : 'Ergänzt') : 'NICHT vollständig angelegt'}: Gruppierung „$wunsch" (id $id) in Kurs $kurs '
      'mit Gruppen: ${danach == null || danach.gruppen.isEmpty ? 'keine' : danach.gruppen.join(', ')}. '
      '${angelegt.isEmpty ? '' : 'Neu angelegte Gruppen: ${angelegt.join(', ')}. '}'
      '${fehlt.isEmpty ? '' : 'In der Gruppierung fehlen: ${fehlt.join(', ')}. '}verified: $ok';
}
