// Fragensammlungen und Fragen: Werkzeuge fragensammlungen, fragen_lesen,
// frage_lesen, fragen_importieren, kategorie_anlegen, fragetypen,
// stack_xml, coderunner_xml. Eine Frage ändert das allgemeine aendern
// (formular_schreiben.dart) über ihr Bearbeitungsformular.
//
// Anlegen per Moodle-XML-Import, ändern über das Formular: Der Import legt
// IMMER neu an -- es gibt keinen Weg, ein XML als neue Version einer
// vorhandenen Frage einzuspielen. Speichern im Formular erzeugt eine neue
// Version mit NEUER questionid; die alte Nummer zeigt danach auf die alte
// Version. Stabil ist die Sachnummer (idnumber): Sie hängt am
// Fragenbank-Eintrag, nicht an der Version. Tests ziehen standardmäßig die
// neueste Version -- eine Änderung wirkt sofort in jedem Test, der die Frage
// benutzt.
//
// Gelesen wird über den Moodle-XML-Export: vollständig und ohne
// Personendaten (nachgemessen: kein createdby, kein Name). Die Fragenübersicht
// der Sammlung (question/edit.php) zeigt dagegen „Erstellt von" und „Geändert
// von" mit Klarnamen -- die ruft die App nicht auf.

import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

import '../freigabe.dart';
import 'formular.dart';
import 'formular_lesen.dart';
import 'formular_schreiben.dart';
import 'fragen_xml.dart';
import 'moodle_zugang.dart';

class Kategorie {
  Kategorie(this.wert, this.name, this.anzahl, this.tiefe);

  /// `<kategorieid>,<kontextid>` -- so will es das Import- und Exportformular.
  final String wert;
  final String name;
  final int anzahl;
  final int tiefe;
  int get id => int.parse(wert.split(',').first);
  int? get kontext => int.tryParse(wert.split(',').last);
}

/// Kategorien einer Sammlung. Die Auswahlliste des Importformulars ist die
/// zuverlässigste Quelle: Sie führt die Fragenanzahl mit.
Future<List<Kategorie>> kategorienLesen(MoodleZugang moodle, int sammlung) async {
  final r = await moodle.lesen('/question/bank/importquestions/import.php?cmid=$sammlung');
  final sel = html_parser.parse(r.text).querySelector('select[name="category"]');
  if (sel == null) throw MoodleFehler('Keine Kategorieliste -- ist cmid $sammlung eine Fragensammlung?');
  return [
    for (final o in sel.querySelectorAll('option'))
      () {
        final roh = o.text.replaceAll(' ', ' ');
        final tiefe = (roh.length - roh.trimLeft().length) ~/ 3;
        final text = roh.replaceAll(RegExp(r'\s+'), ' ').trim();
        final m = RegExp(r'^(.*?)\s*\((\d+)\)$').firstMatch(text);
        return Kategorie(o.attributes['value'] ?? '', m?.group(1) ?? text, int.tryParse(m?.group(2) ?? '') ?? 0, tiefe);
      }()
  ];
}

Kategorie _kategorie(List<Kategorie> alle, String? wunsch) {
  if (wunsch == null || wunsch.isEmpty) return alle.first;
  final k = alle.where((k) => k.wert == wunsch || '${k.id}' == wunsch || k.name == wunsch).toList();
  if (k.length != 1) {
    throw MoodleFehler('Kategorie „$wunsch" ${k.isEmpty ? 'gibt es nicht' : 'ist mehrdeutig'}. Vorhanden:\n'
        '${alle.map((k) => '  ${k.id} „${k.name}" (${k.anzahl})').join('\n')}');
  }
  return k.single;
}

/// Eine Kategorie als Moodle-XML exportieren.
Future<String> exportieren(MoodleZugang moodle, int sammlung, Kategorie k) async {
  final f = await formularHolen(moodle, '/question/bank/exportquestions/export.php?cmid=$sammlung');
  setze(f.felder, 'format', 'xml');
  setze(f.felder, 'category', k.wert);
  // Kategorie und Kontext NICHT in die Datei: Beim Import soll die Zielkategorie gelten.
  f.felder.removeWhere((e) => e.key == 'cattofile' || e.key == 'contexttofile');
  final felder = [...f.felder, const MapEntry('submitbutton', '1')];
  final antwort = await moodle.senden(f.aktion, felder);
  final ziel = moodle.umleitungsziel(antwort);
  String? link;
  if (ziel != null && ziel.path.contains('/pluginfile.php/')) {
    link = ziel.toString();
  } else {
    link = html_parser.parse(antwort.text).querySelector('a[href*="pluginfile.php"]')?.attributes['href'];
  }
  if (link == null) throw MoodleFehler('Kein Download in der Exportantwort -- Kategorie leer oder Recht fehlt?');
  final x = await moodle.lesen(link);
  if (!x.text.trimLeft().startsWith('<?xml')) throw MoodleFehler('Der Export lieferte kein XML.');
  return x.text;
}

String _sammlungsOrdner(String arbeitsordner, int sammlung) => p.join(arbeitsordner, 'fragen-$sammlung');

// ---------------------------------------------------------------------------
// fragen_lesen
// ---------------------------------------------------------------------------

Future<String> fragenLesen(MoodleZugang moodle, String arbeitsordner,
    {required int sammlung, String? kategorie, bool alle = false, String? idnummer}) async {
  final kats = await kategorienLesen(moodle, sammlung);
  final ordner = _sammlungsOrdner(arbeitsordner, sammlung);
  await Directory(ordner).create(recursive: true);
  final b = StringBuffer('Sammlung cmid $sammlung, Kategorien (id „Name" (Anzahl)):\n');
  for (final k in kats) {
    b.writeln('  ${'  ' * k.tiefe}${k.id} „${k.name}" (${k.anzahl})');
  }
  final ziel = alle ? kats.where((k) => k.anzahl > 0).toList() : [_kategorie(kats, kategorie)];
  final treffer = <(Kategorie, FrageKurz)>[];
  for (final k in ziel) {
    if (k.anzahl == 0) {
      b.writeln('\nKategorie „${k.name}" ist leer.');
      continue;
    }
    final xml = await exportieren(moodle, sammlung, k);
    final datei = File(p.join(ordner, 'kategorie-${k.id}.xml'));
    await datei.writeAsString(xml, encoding: utf8);
    final fragen = fragenAusXml(xml);
    if (idnummer != null) {
      treffer.addAll([for (final f in fragen) if (f.idnummer == idnummer) (k, f)]);
      continue;
    }
    b.writeln('\nKategorie „${k.name}" (${fragen.length} Fragen) -> ${datei.path}');
    for (final f in fragen) {
      b.writeln('  ${f.zeile()}');
    }
  }
  if (idnummer != null) {
    if (treffer.isEmpty) {
      b.writeln('\nSachnummer $idnummer: nicht gefunden${alle ? '' : ' in dieser Kategorie (alle: true sucht überall)'}.');
    } else if (treffer.length > 1) {
      // Mehrdeutigkeit wird gemeldet, nicht aufgelöst: Die falsche Frage zu
      // ändern ist teurer als eine Rückfrage.
      b.writeln('\nSachnummer $idnummer: MEHRDEUTIG, ${treffer.length} Fragen -- nicht raten, nachfragen:');
      for (final (k, f) in treffer) {
        b.writeln('  in „${k.name}": ${f.zeile()}');
      }
    } else {
      final (k, f) = treffer.single;
      b.writeln('\nSachnummer $idnummer: in „${k.name}", aktuelle questionid ${f.id}\n  ${f.zeile()}\n'
          'Nach einer Änderung ist die questionid eine andere, die Sachnummer nicht.');
    }
  }
  b.writeln('\nEine Frage bearbeiten: frage_lesen(sammlung, frage_id), dann aendern.');
  return b.toString();
}

// ---------------------------------------------------------------------------
// frage_lesen
// ---------------------------------------------------------------------------

/// Die Sperre des Ordners umfasst das Lesen, das frage.xml-Schreiben (Befund 6) und
/// damit auch die Zeit bis zum Ende des Lesens; sonst lösche ein Parallelaufruf den Ordner.
Future<String> frageLesen(MoodleZugang moodle, String arbeitsordner, {required int sammlung, required int frage}) {
  final ziel = Formularziel.frage(sammlung, frage);
  return ordnerSperre(ordnerSchluessel(ziel, arbeitsordner), () => _frageLesenOhneSperre(moodle, arbeitsordner, ziel, sammlung, frage));
}

Future<String> _frageLesenOhneSperre(
    MoodleZugang moodle, String arbeitsordner, Formularziel ziel, int sammlung, int frage) async {
  final g = await formularLesenOhneSperre(moodle, ziel, arbeitsordner);
  // Dazu die Frage als XML: vollständig, auch für Typen mit vielen Feldern.
  var xmlHinweis = '';
  try {
    final s = await moodle.sesskey();
    final r = await moodle.lesen('/question/bank/exporttoxml/exportone.php?id=$frage&cmid=$sammlung&sesskey=$s');
    var xml = r.text;
    if (!xml.trimLeft().startsWith('<?xml')) {
      final link = html_parser.parse(xml).querySelector('a[href*="pluginfile.php"]')?.attributes['href'];
      xml = link == null ? '' : (await moodle.lesen(link)).text;
    }
    if (xml.trimLeft().startsWith('<?xml')) {
      await File(p.join(g.ordner, 'frage.xml')).writeAsString(xml, encoding: utf8);
      // Der Einzelexport lässt die Datensätze einer berechneten Frage weg
      // (gemessen: calculated mit geteilten Datensätzen); vollständig stehen
      // sie im Export ihrer Kategorie.
      xmlHinweis = 'Die Frage als Moodle-XML (nur zum Lesen): frage.xml'
          '${g.modul == 'calculated' ? ' -- ohne ihre Datensätze; vollständig im Export ihrer Kategorie (fragen_lesen)' : ''}\n';
    }
  } on MoodleFehler catch (x) {
    xmlHinweis = 'Einzelexport nicht möglich (${x.meldung}).\n';
  }
  final z = g.zusammenfassung();
  return '$z\n${xmlHinweis}Speichern erzeugt eine NEUE Version mit neuer questionid; Tests mit '
      '„neueste Version" nutzen sie sofort. Strukturänderungen (andere Antwortzahl, anderer Typ) gehen so '
      'nicht -- dafür neu anlegen.';
}

// ---------------------------------------------------------------------------
// fragen_importieren
// ---------------------------------------------------------------------------

/// Ergebnis eines Imports, für die Nachweise danach (STACK, CodeRunner).
class Importiert {
  Importiert(this.text, this.neu);
  final String text;
  final List<FrageKurz> neu;
}

Future<Importiert> fragenImportieren(MoodleZugang moodle, Freigaben freigaben, String arbeitsordner,
    {required int sammlung, required String kategorie, required String datei}) async {
  final pfad = imArbeitsordner(datei, arbeitsordner);
  final f0 = File(pfad);
  if (!f0.existsSync()) throw MoodleFehler('Datei $pfad gibt es nicht.');
  final (xml, fragen) =
      fragenXmlPruefen(await f0.readAsString(encoding: utf8), dateiordner: p.join(p.dirname(pfad), 'dateien'));

  final kats = await kategorienLesen(moodle, sammlung);
  final k = _kategorie(kats, kategorie);

  // Eine Freigabe für die ganze Datei, nicht je Frage: Der Import ist ein
  // Vorgang, und er bricht beim ersten Fehler als Ganzes ab. Erst bei
  // Bestätigungen „alle" -- Lernende sehen eine Frage erst in einem Test.
  final ja = await freigaben.anfragen(FreigabeAnfrage(
    titel: '${fragen.length} Frage(n) anlegen?',
    punkte: [
      'In Kategorie „${k.name}" der Fragensammlung cmid $sammlung',
      'Aus ${p.basename(pfad)}; die Fragen sind neu, vorhandene werden nicht ersetzt.',
      for (final f in fragen.take(20)) '${f.typ}: „${f.name}"',
      if (fragen.length > 20) '… und ${fragen.length - 20} weitere',
      'Lernende sehen eine Frage erst, wenn sie in einem Test steht.',
    ],
    vergleich: const [],
    knopf: 'Anlegen',
    ohneEntscheidung: 'wird nichts angelegt',
    ab: Bestaetigungen.alle,
  ));
  if (!ja) {
    throw MoodleFehler('Der Import wurde in der App abgelehnt oder nicht innerhalb von '
        '${freigaben.frist.inMinutes} Minuten freigegeben. Nichts angelegt.');
  }

  final vorherIds = k.anzahl == 0 ? <int>{} : {for (final f in fragenAusXml(await exportieren(moodle, sammlung, k))) f.id};

  Future<String> versuch() async {
    final f = await formularHolen(moodle, '/question/bank/importquestions/import.php?cmid=$sammlung');
    final itemid = wertIn(f.felder, 'newfile');
    if (itemid == null) throw MoodleFehler('Im Importformular fehlt der Entwurfsbereich (newfile).');
    await hochladen(moodle, f, itemid, '/', p.basename(pfad), utf8.encode(xml));
    setze(f.felder, 'format', 'xml');
    setze(f.felder, 'category', k.wert);
    // Kategorie aus dem Formular, nicht aus der Datei; bei unpassenden
    // Punkten abbrechen statt runden; beim ersten Fehler aufhören.
    setze(f.felder, 'catfromfile', '0');
    setze(f.felder, 'contextfromfile', '0');
    setze(f.felder, 'matchgrades', 'error');
    setze(f.felder, 'stoponerror', '1');
    final a = await moodle.senden(f.aktion, [...f.felder, const MapEntry('submitbutton', '1')]);
    final d = html_parser.parse(a.text);
    return d
        .querySelectorAll('.alert-danger, .notifyproblem, .errorbox, .error')
        .map((e) => e.text.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((t) => t.isNotEmpty)
        .join(' | ');
  }

  String probleme;
  try {
    probleme = await versuch();
  } on SitzungAbgelaufen {
    probleme = await versuch();
  }
  // Nachzählen ist der eigentliche Nachweis: Moodle meldet Erfolge, die keine sind.
  final nachher = fragenAusXml(await exportieren(moodle, sammlung, k));
  final neu = nachher.where((f) => !vorherIds.contains(f.id)).toList();
  final ok = neu.length == fragen.length && probleme.isEmpty;
  final b = StringBuffer()
    ..writeln('${ok ? 'Importiert' : 'Import UNVOLLSTÄNDIG'}: ${neu.length} von ${fragen.length} Fragen in '
        '„${k.name}" (Sammlung cmid $sammlung). verified: $ok')
    ..writeln([for (final f in neu) '  ${f.zeile()}'].join('\n'));
  if (probleme.isNotEmpty) b.writeln('Moodle meldet: $probleme');
  return Importiert(b.toString(), neu);
}

// ---------------------------------------------------------------------------
// kategorie_anlegen
// ---------------------------------------------------------------------------

const String kategorieFormular = r'qbank_managecategories\form\question_category_edit_form';

/// Legt eine Kategorie IN einer Sammlung an -- nicht die Sammlung selbst; die
/// ist eine Aktivität (`aktivitaet_anlegen`, Typ `qbank`). Die Meldung nennt
/// deshalb die Sammlung mit: Wer „Fragensammlung" sagte und eine Kategorie
/// bekommt, erkennt die Verwechslung nur, wenn das Ziel dabeisteht.
Future<String> kategorieAnlegen(MoodleZugang moodle, Freigaben freigaben,
    {required int sammlung, required String name, String? eltern, String? beschreibung}) async {
  final kats = await kategorienLesen(moodle, sammlung);
  final kontext = kats.first.kontext;
  final elternK = eltern == null ? null : _kategorie(kats, eltern);
  if (kats.any((k) => k.name == name)) {
    throw MoodleFehler('Eine Kategorie „$name" gibt es in dieser Sammlung schon.');
  }
  // Eine Kategorie ist Gliederung in der Fragensammlung; Lernende sehen sie
  // nie. Freigabe deshalb erst bei Bestätigungen „alle".
  final ja = await freigaben.anfragen(FreigabeAnfrage(
    titel: 'Kategorie anlegen?',
    punkte: [
      'Kategorie „$name" in der Fragensammlung cmid $sammlung'
          '${elternK == null ? '' : ', unter „${elternK.name}"'}',
      'Gliederung der Fragensammlung; Lernende sehen Kategorien nicht.',
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
  final leer = await moodle.dienst('core_form_dynamic_form',
      {'form': kategorieFormular, 'formdata': 'cmid=$sammlung&contextid=$kontext&courseid=0&actiontype=add'});
  final html = (leer is Map ? leer['html'] : null) as String? ?? '';
  final form = html_parser.parse(html).querySelector('form') ?? html_parser.parse(html).body!;
  final felder = formularFelder(form);
  setze(felder, 'name', name);
  if (beschreibung != null) setze(felder, 'info[text]', beschreibung);
  if (elternK != null) setze(felder, 'parent', elternK.wert);
  setze(felder, '_qf__qbank_managecategories_form_question_category_edit_form', '1');
  final daten = felder.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');
  final r = await moodle.dienst('core_form_dynamic_form', {'form': kategorieFormular, 'formdata': daten});
  final nachher = await kategorienLesen(moodle, sammlung);
  final neu = nachher.where((k) => k.name == name).toList();
  final ok = r is Map && r['submitted'] == true && neu.length == 1;
  return '${ok ? 'Angelegt' : 'NICHT angelegt'}: Kategorie „$name"${neu.isEmpty ? '' : ' (id ${neu.single.id})'}'
      '${elternK == null ? '' : ' unter „${elternK.name}"'} in Sammlung cmid $sammlung. verified: $ok';
}

// ---------------------------------------------------------------------------
// fragetypen: STACK-Version und CodeRunner-Prototypen der Instanz
// ---------------------------------------------------------------------------

/// Die STACK-Version der Instanz, aus dem Formular einer neuen STACK-Frage --
/// die einzige Quelle ohne Administrationsrechte. Sie gehört in jede neue
/// Frage: Eine ältere Nummer markiert die Frage in STACK dauerhaft als
/// nachbesserungsbedürftig.
Future<String?> stackVersion(MoodleZugang moodle, int sammlung) async {
  final k = (await kategorienLesen(moodle, sammlung)).first;
  final r = await moodle.lesen('/question/bank/editquestion/question.php?cmid=$sammlung&qtype=stack'
      '&category=${Uri.encodeQueryComponent(k.wert)}');
  return RegExp(r'name="stackversion"[^>]*value="(\d+)"').firstMatch(r.text)?.group(1) ??
      RegExp(r'value="(\d+)"[^>]*name="stackversion"').firstMatch(r.text)?.group(1);
}

Future<String> fragetypen(MoodleZugang moodle, int sammlung) async {
  final b = StringBuffer()
    ..writeln('Anlegbar (XML gemessen): ${[...kernAnlegbar.where((t) => t != 'matching' && t != 'cloze'), ...zusatzAnlegbar].join(", ")}.')
    ..writeln('Nur lesbar: ${nurLesen.join(", ")} und alle übrigen Zusatztypen.');
  try {
    final v = await stackVersion(moodle, sammlung);
    b.writeln('STACK: ${v == null ? 'nicht gefunden (nicht installiert?)' : 'Version $v'}');
  } on MoodleFehler catch (x) {
    b.writeln('STACK: nicht abrufbar (${x.meldung})');
  }
  try {
    final k = (await kategorienLesen(moodle, sammlung)).first;
    final r = await moodle.lesen('/question/bank/editquestion/question.php?cmid=$sammlung&qtype=coderunner'
        '&category=${Uri.encodeQueryComponent(k.wert)}');
    final sel = html_parser.parse(r.text).querySelector('[name="coderunnertype"]');
    if (sel == null) {
      b.writeln('CodeRunner: nicht installiert.');
    } else {
      final alle = [
        for (final o in sel.querySelectorAll('option'))
          if ((o.attributes['value'] ?? '').isNotEmpty && o.attributes['value'] != 'Undefined') o.attributes['value']!
      ];
      b.writeln('CodeRunner-Prototypen: gemessen ${alle.where(coderunnerGemessen.contains).join(", ")}; '
          'ungemessen ${alle.where((x) => !coderunnerGemessen.contains(x)).join(", ")} '
          '(gehen wahrscheinlich genauso, sind aber nicht nachgesehen).');
    }
  } on MoodleFehler catch (x) {
    b.writeln('CodeRunner: nicht abrufbar (${x.meldung})');
  }
  return b.toString();
}

// ---------------------------------------------------------------------------
// stack_xml und coderunner_xml: bauen, als Datei ablegen
// ---------------------------------------------------------------------------

Map<String, List<int>> _dateienIn(String ordner) {
  final d = Directory(p.join(ordner, 'dateien'));
  if (!d.existsSync()) return const {};
  return {for (final f in d.listSync().whereType<File>()) p.basename(f.path): f.readAsBytesSync()};
}

Future<String> xmlBauen(MoodleZugang moodle, String arbeitsordner,
    {required String art, required List<Map<String, Object?>> fragen, required String datei, int? sammlung}) async {
  final pfad = imArbeitsordner(datei, arbeitsordner);
  if (!pfad.toLowerCase().endsWith('.xml')) throw MoodleFehler('datei muss auf .xml enden.');
  final dateien = _dateienIn(p.dirname(pfad));
  final teile = <String>[];
  if (art == 'stack') {
    if (sammlung == null) throw MoodleFehler('sammlung fehlt: Die STACK-Version kommt aus der Instanz.');
    final v = await stackVersion(moodle, sammlung);
    if (v == null) throw MoodleFehler('STACK-Version nicht gefunden -- ist STACK installiert?');
    for (final f in fragen) {
      teile.add(stackXml(f, version: v, dateien: dateien));
    }
  } else {
    for (final f in fragen) {
      teile.add(coderunnerXml(f, dateien: dateien));
    }
  }
  final xml = quizXml(teile);
  fragenXmlPruefen(xml, dateiordner: p.join(p.dirname(pfad), 'dateien'));
  await File(pfad).parent.create(recursive: true);
  await File(pfad).writeAsString(xml, encoding: utf8);
  return 'Gebaut und geprüft: ${fragen.length} ${art == 'stack' ? 'STACK' : 'CodeRunner'}-Frage(n) in $pfad. '
      'Anlegen mit fragen_importieren(sammlung, kategorie, datei).';
}

// ---------------------------------------------------------------------------
// Nachweise nach dem Import
// ---------------------------------------------------------------------------

/// STACK-Fragen: Fragetests laufen lassen. CodeRunner-Fragen: einmal über das
/// Formular speichern -- nur dort schickt Moodle die Musterlösung durch die
/// Sandbox (gemessen am 10.09.2026: Der Import nahm eine falsche Musterlösung
/// klaglos an, erst das Speichern meldete „Erwartet 5, Erhalten -1").
Future<String> importNachweise(MoodleZugang moodle, int sammlung, List<FrageKurz> neu,
    Future<String> Function(int frage) stackTesten) async {
  final b = StringBuffer();
  for (final f in neu.where((f) => f.typ == 'stack' && f.id != null)) {
    b.writeln('\nNachweis STACK „${f.name}":\n${await stackTesten(f.id!)}');
  }
  for (final f in neu.where((f) => f.typ == 'coderunner' && f.id != null)) {
    try {
      final form = await formularHolen(moodle, '/question/bank/editquestion/question.php?cmid=$sammlung&id=${f.id}');
      await absenden(moodle, form, knoepfe: const ['submitbutton']);
      b.writeln('\nNachweis CodeRunner „${f.name}": Musterlösung besteht alle Testfälle (über das Formular '
          'gespeichert, neue Version). geprueft: true');
    } on MoodleFehler catch (x) {
      b.writeln('\nNachweis CodeRunner „${f.name}": NICHT bestanden -- ${x.meldung}. geprueft: false. '
          'Musterlösung oder erwartete Ausgabe nachbessern (frage_lesen, aendern).');
    }
  }
  return b.toString();
}

// ---------------------------------------------------------------------------
// fragen_loeschen
// ---------------------------------------------------------------------------

/// Eine Frage einzeln als Moodle-XML, oder die Fehlerseite, mit der Moodle
/// den Export ablehnt.
Future<({String? xml, String? fehlercode, String meldung})> _frageExport(
    MoodleZugang moodle, int sammlung, int frage) async {
  final s = await moodle.sesskey();
  final r = await moodle.lesen('/question/bank/exporttoxml/exportone.php?id=$frage&cmid=$sammlung&sesskey=$s');
  var text = r.text;
  if (!text.trimLeft().startsWith('<?xml')) {
    final link = html_parser.parse(text).querySelector('a[href*="pluginfile.php"]')?.attributes['href'];
    if (link != null) text = (await moodle.lesen(link)).text;
  }
  if (text.trimLeft().startsWith('<?xml')) return (xml: text, fehlercode: null, meldung: '');
  // Moodles Fehlerseite: die Meldung und, im Verweis auf die Doku
  // (…/error/<komponente>/<code>), der Fehlercode.
  final d = html_parser.parse(text);
  final meldung = (d.querySelector('.errormessage') ?? d.querySelector('#region-main .alert'))?.text.trim() ?? '';
  final doku = d.querySelectorAll('a[href*="/error/"]').map((a) => a.attributes['href'] ?? '').firstOrNull;
  final code = doku == null ? null : Uri.tryParse(doku)?.pathSegments.lastOrNull;
  return (xml: null, fehlercode: code, meldung: meldung.replaceAll(RegExp(r'\s+'), ' '));
}

/// Die Fehlercodes, mit denen Moodle den Export einer Frage ablehnt, die es
/// nicht mehr gibt. Nur sie zählen beim Zurücklesen als „gelöscht"; jede
/// andere Ablehnung (etwa ein fehlendes Recht) heißt: unklar.
const _frageFehlt = {'invalidrecord', 'invalidrecordunknown', 'questiondoesnotexist'};

/// Löscht Fragen einer Sammlung mit allen Versionen, so wie die
/// Fragensammlung es anbietet: Rückfrage von delete.php holen, ihr Formular
/// nach der Freigabe absenden, wie es dasteht. Steckt eine Frage in einem
/// Test, löscht Moodle sie nicht, sondern verbirgt sie nur; das Zurücklesen
/// meldet das.
///
/// Vor allem anderen wird jede Frage einzeln exportiert und ihr Name gegen
/// den genannten geprüft -- eine vertauschte Nummer löscht so nichts.
Future<String> fragenLoeschen(MoodleZugang moodle, Freigaben freigaben, String arbeitsordner,
    {required int sammlung, required List<(int, String)> fragen}) async {
  if (fragen.isEmpty) throw MoodleFehler('Keine Fragen genannt.');
  final ids = [for (final (id, _) in fragen) id];
  if (ids.toSet().length != ids.length) throw MoodleFehler('Eine Frage ist doppelt genannt.');

  final gefunden = <FrageKurz>[];
  for (final (id, name) in fragen) {
    final e = await _frageExport(moodle, sammlung, id);
    final f = e.xml == null ? null : fragenAusXml(e.xml!).where((x) => x.id == id).firstOrNull;
    if (f == null) {
      throw MoodleFehler('Abgebrochen, nichts gelöscht: Frage $id ist in Sammlung $sammlung nicht zu finden'
          '${e.meldung.isEmpty ? '' : ' (Moodle: ${e.meldung})'}. Nummern mit fragen_lesen prüfen.');
    }
    nameBestaetigen(name, f.name, 'Frage $id');
    gefunden.add(f);
  }

  // Die Rückfrage ändert nichts; sie liegt danach im Arbeitsordner, damit
  // sich nachsehen lässt, was Moodle gefragt hat.
  final ordner = _sammlungsOrdner(arbeitsordner, sammlung);
  await Directory(ordner).create(recursive: true);
  // Die Auswahl wie das Formular der Sammlung: q<id>=1 je Frage. returnurl
  // ist Pflicht, sonst bricht Moodle 5.1 die Rückfrage mit einem Fehler ab;
  // aufgerufen wird sie nicht (moodle_zugang.dart, _loeschRueckfrage).
  final zurueck = Uri.encodeQueryComponent('/question/edit.php?cmid=$sammlung');
  final r = await moodle.lesen('/question/bank/deletequestion/delete.php?cmid=$sammlung&deleteselected=1'
      '&deleteall=1&returnurl=$zurueck&${ids.map((i) => 'q$i=1').join('&')}');
  final seite = File(p.join(ordner, 'loeschen-rueckfrage.html'));
  await seite.writeAsString(r.text, encoding: utf8);
  final doc = html_parser.parse(r.text);
  final form = doc
      .querySelectorAll('form')
      .where((f) => f.querySelector('input[name="confirm"]') != null)
      .firstOrNull;
  final link = doc
      .querySelectorAll('a[href*="deletequestion/delete.php"]')
      .map((a) => r.adresse.resolve(a.attributes['href'] ?? ''))
      .where((u) => u.queryParameters.containsKey('confirm'))
      .firstOrNull;
  if (form == null && link == null) {
    throw MoodleFehler('Moodle hat nicht nach einer Bestätigung gefragt, nichts gelöscht. Fehlt das Recht? '
        'Die Antwort liegt unter ${seite.path}.');
  }
  // Was die Bestätigung löschen würde, muss genau das Genannte sein.
  final bestaetigt = form != null
      ? form.querySelector('input[name="deleteselected"]')?.attributes['value']
      : link!.queryParameters['deleteselected'];
  final bestaetigtIds = (bestaetigt ?? '').split(',').map((x) => int.tryParse(x.trim())).toSet();
  if (bestaetigtIds.length != ids.length || !bestaetigtIds.containsAll(ids)) {
    throw MoodleFehler('Abgebrochen, nichts gelöscht: Moodles Bestätigung nennt andere Fragen ($bestaetigt) als '
        'die genannten (${ids.join(',')}). Die Rückfrage liegt unter ${seite.path}.');
  }
  // Was Moodle zur Auswahl sagt, etwa zu Fragen in Tests, mit in die Freigabe.
  final hinweis = (doc.querySelector('#modal-body') ?? doc.querySelector('.confirmation-message') ??
          doc.querySelector('#region-main .box'))
      ?.text
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  final ja = await freigaben.anfragen(FreigabeAnfrage(
    titel: fragen.length == 1 ? 'Frage endgültig löschen?' : '${fragen.length} Fragen endgültig löschen?',
    punkte: [
      'Aus der Fragensammlung cmid $sammlung, jeweils mit allen Versionen:',
      for (final f in gefunden) '„${f.name}" (${f.typ}, questionid ${f.id}${f.idnummer == null ? '' : ', ${f.idnummer}'})',
      'Steckt eine Frage in einem Test, löscht Moodle sie nicht, sondern verbirgt sie nur.',
      if (hinweis != null && hinweis.isNotEmpty) 'Moodle fragt: $hinweis',
    ],
    vergleich: const [],
    knopf: 'Löschen',
  ));
  if (!ja) {
    return 'Nicht gelöscht: in der App abgelehnt oder nicht rechtzeitig freigegeben. '
        'Die Rückfrage von Moodle liegt unter ${seite.path}.';
  }

  // Absenden, wie Moodle es anbietet. Der Umleitung danach (auf die
  // Fragenübersicht, die Klarnamen zeigt) folgt die App nicht.
  if (form != null) {
    final felder = <MapEntry<String, String>>[
      for (final i in form.querySelectorAll('input[type="hidden"]'))
        if ((i.attributes['name'] ?? '').isNotEmpty) MapEntry(i.attributes['name']!, i.attributes['value'] ?? ''),
    ];
    final ziel = r.adresse.resolve(form.attributes['action'] ?? '');
    if ((form.attributes['method'] ?? 'get').toLowerCase() == 'post') {
      await moodle.senden(ziel.hasQuery ? '${ziel.path}?${ziel.query}' : ziel.path, felder);
    } else {
      await moodle.aufrufen(ziel.replace(queryParameters: {for (final e in felder) e.key: e.value}).toString());
    }
  } else {
    await moodle.aufrufen('${link!.path}?${link.query}');
  }

  final b = StringBuffer();
  var alleWeg = true;
  for (final f in gefunden) {
    final e = await _frageExport(moodle, sammlung, f.id!);
    if (e.xml == null && _frageFehlt.contains(e.fehlercode)) {
      b.writeln('  gelöscht: „${f.name}" (${f.id})');
    } else if (e.xml != null) {
      alleWeg = false;
      b.writeln('  NOCH DA: „${f.name}" (${f.id}) -- steckt vermutlich in einem Test; Moodle hat sie dann nur verborgen.');
    } else {
      alleWeg = false;
      b.writeln('  UNKLAR: „${f.name}" (${f.id}) -- Export abgelehnt mit ${e.fehlercode ?? 'unbekanntem Fehler'}'
          '${e.meldung.isEmpty ? '' : ' (${e.meldung})'}');
    }
  }
  return '${alleWeg ? 'Gelöscht' : 'Nicht alles gelöscht'}: ${fragen.length} Frage(n) aus Sammlung $sammlung. '
      'verified: $alleWeg\n$b';
}
