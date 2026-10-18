// Ein Moodle-Bearbeitungsformular vollständig in einen Ordner lesen: eine
// Aktivität, einen Abschnitt, ein Buchkapitel, eine Frage. Werkzeuge
// aktivitaet_lesen, abschnitt_lesen, buch_lesen, frage_lesen.
//
// Gelesen wird das Bearbeitungsformular, nicht die Ansichtsseite. Nur dort
// steht der GESPEICHERTE Quelltext -- genau der, der beim Bearbeiten
// zurückgeschrieben wird. Die Ansichtsseite zeigt die aufbereitete Version
// (Filter angewendet, Adressen umgeschrieben); wer die zurückspeichert,
// verändert die Seite unbemerkt.
//
// Ergebnis im Arbeitsordner, Unterordner je nach Ziel (cm-<cmid>,
// abschnitt-<id>, buch-<cmid>/kapitel-<id>, frage-<id>):
//   <feld>.html           der gespeicherte Quelltext, unverändert
//   dateien/<name>        jede referenzierte Datei, Byte für Byte
//   bereiche/<feld>/      die Dateien jedes Dateibereichs, mit Unterordnern
//                         (Zusätzliche Dateien einer Aufgabe, Inhalt eines
//                         Verzeichnisses, Datei einer Dateiressource)
//   einstellungen.json    alle Einstellungen des Formulars, lesbar
//                         (formular.dart); die wichtigen stehen in der Übersicht
//   uebersicht.json       was wo liegt, dazu die Auswertung (auswertung.dart)
//   .stand/               dasselbe noch einmal, unangetastet: der Stand beim
//                         Lesen. Bearbeitet wird <feld>.html und dateien/;
//                         aendern vergleicht gegen .stand, um zu erkennen, was
//                         sich geändert hat -- und ob Moodle seit dem Lesen
//                         von jemand anderem geändert wurde.
//   .stand/ziel.json      welches Formular das ist; daran erkennt aendern,
//                         wohin zurückgeschrieben wird
//   .stand/formular.html  das Formular selbst (ohne Kopfzeile; sesskey
//                         unkenntlich)
//   .stand/dateibereiche.json  die Dateibereiche des Formulars, ohne
//                         Personenfelder
//
// Die Adressen im Quelltext zeigen auf einen Entwurfsbereich, den Moodle bei
// jedem Abruf des Formulars neu anlegt. Beim Zurückschreiben werden die
// Dateien deshalb über ihren NAMEN zugeordnet, nicht über die Adresse.
//
// Zurück ans Modell geht nicht nur, was wo liegt, sondern eine Übersicht
// dessen, was darauf steht: Gliederung, Bilder mit Alternativtext und
// Beschriftungen, Verweise mit dem Titel des Ziels, Befunde nach den Regeln
// der Skills. So muss für einen Auftrag nur geöffnet werden, was er betrifft.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

import 'auswertung.dart';
import 'formular.dart';
import 'kurs.dart';
import 'moodle_zugang.dart';
import 'sperrliste.dart';

/// Welche Art Formular.
enum Zielart { aktivitaet, abschnitt, buchkapitel, frage }

/// Ein Moodle-Formular, das die App lesen und zurückschreiben kann.
class Formularziel {
  const Formularziel(this.art, this.id, {this.cmid});

  final Zielart art;

  /// cmid, sectionid, chapterid oder questionid.
  final int id;

  /// Das Buch bzw. die Fragensammlung, zu der ein Kapitel bzw. eine Frage gehört.
  final int? cmid;

  factory Formularziel.aktivitaet(int cmid) => Formularziel(Zielart.aktivitaet, cmid);
  factory Formularziel.abschnitt(int sectionid) => Formularziel(Zielart.abschnitt, sectionid);
  factory Formularziel.buchkapitel(int buch, int kapitel) => Formularziel(Zielart.buchkapitel, kapitel, cmid: buch);
  factory Formularziel.frage(int sammlung, int frage) => Formularziel(Zielart.frage, frage, cmid: sammlung);

  /// Wo das Formular abgerufen wird.
  String get adresse => switch (art) {
        Zielart.aktivitaet => '/course/modedit.php?update=$id',
        Zielart.abschnitt => '/course/editsection.php?id=$id',
        Zielart.buchkapitel => '/mod/book/edit.php?cmid=$cmid&id=$id',
        Zielart.frage => '/question/bank/editquestion/question.php?cmid=$cmid&id=$id',
      };

  /// Unterordner im Arbeitsordner.
  String get ordnerName => switch (art) {
        Zielart.aktivitaet => 'cm-$id',
        Zielart.abschnitt => 'abschnitt-$id',
        Zielart.buchkapitel => p.join('buch-$cmid', 'kapitel-$id'),
        Zielart.frage => 'frage-$id',
      };

  String get bezeichnung => switch (art) {
        Zielart.aktivitaet => 'cmid $id',
        Zielart.abschnitt => 'Abschnitt (id $id)',
        Zielart.buchkapitel => 'Kapitel $id im Buch cmid $cmid',
        Zielart.frage => 'Frage $id (Sammlung cmid $cmid)',
      };

  Map<String, Object?> toJson() => {'art': art.name, 'id': id, if (cmid != null) 'cmid': cmid};

  static Formularziel ausJson(Map j) {
    final art = Zielart.values.byName('${j['art']}');
    final id = (j['id'] as num).toInt();
    final cmid = (j['cmid'] as num?)?.toInt();
    return Formularziel(art, id, cmid: cmid);
  }

  /// Liest .stand/ziel.json eines gelesenen Ordners.
  static Formularziel ausOrdner(String ordner) {
    final f = File(p.join(ordner, '.stand', 'ziel.json'));
    if (!f.existsSync()) {
      throw MoodleFehler('In $ordner fehlt .stand/ziel.json -- ist das ein Ordner, den die App '
          'gelesen hat? Erst lesen, dann ändern.');
    }
    return ausJson(jsonDecode(f.readAsStringSync()) as Map);
  }
}

class GelesenesFeld {
  GelesenesFeld(this.feld, this.html);
  final String feld;
  final String html;
}

class GeleseneDatei {
  GeleseneDatei(this.name, this.bytes, this.typ, this.felder);
  final String name;
  final int bytes;
  final String? typ;
  final Set<String> felder;
}

/// Ein Dateibereich des Formulars (Dateimanager), gelesen nach `bereiche/<feld>/`.
class Dateibereich {
  Dateibereich(this.feld, this.label);
  final String feld;
  final String label;

  /// Pfad im Bereich (etwa „/unterordner/a.pdf") -> Auswertung der Datei.
  final Map<String, Dateiinfo> dateien = {};
  final List<String> nichtGelesen = [];
}

/// Was aus der Seite eines Formulars stammt und kein Feld ist.
class Seitenangaben {
  Seitenangaben(this.kurs, this.kontext, this.upload);
  final int? kurs;
  final String? kontext;

  /// Nummer der Dateiquelle „Datei hochladen" (repository_ajax, repo_id).
  final String? upload;

  static Seitenangaben aus(String seite) {
    final cfg = RegExp(r'M\.cfg\s*=\s*(\{.*?\});', dotAll: true).firstMatch(seite);
    Map? m;
    try {
      m = cfg == null ? null : jsonDecode(cfg.group(1)!) as Map;
    } catch (_) {
      m = null;
    }
    final kurs = (m?['courseId'] as num?)?.toInt();
    final repo = RegExp(r'"id":"?(\d+)"?,[^{}]{0,400}?"type":"upload"').firstMatch(seite)?.group(1);
    return Seitenangaben(kurs != null && kurs > 1 ? kurs : null, m?['contextid']?.toString(), repo);
  }
}

class FormularGelesen {
  FormularGelesen(this.ziel, this.kurs, this.name, this.modul, this.ordner, this.felder, this.dateien,
      this.fehlend, this.auswertungen, this.dateiinfo, this.hinweise,
      {this.einstellungen = const [], this.bereiche = const []});
  final Formularziel ziel;
  final List<Einstellung> einstellungen;
  final List<Dateibereich> bereiche;
  final int? kurs;
  final String? name;

  /// Aktivitätstyp (page, assign …), bei Fragen der Fragetyp; sonst null.
  final String? modul;
  final String ordner;
  final List<GelesenesFeld> felder;
  final List<GeleseneDatei> dateien;
  final List<String> fehlend;
  final List<Feldauswertung> auswertungen;
  final Map<String, Dateiinfo> dateiinfo;

  /// Was bei der Auswertung nicht geklappt hat (etwa: Titel verlinkter
  /// Aktivitäten nicht abrufbar). Kein Fehler des Lesens.
  final List<String> hinweise;

  String zusammenfassung() {
    final b = StringBuffer()
      ..writeln('Gelesen: ${name ?? "(ohne Namen)"} (${[
        if (modul != null) modul,
        ziel.bezeichnung,
        if (kurs != null) 'Kurs $kurs'
      ].join(', ')})')
      ..writeln('Ordner: $ordner');
    // Ticket #23, E3: Ein Typ außerhalb der Positivliste wird gelesen, aber nicht
    // geändert. Die Lücke steht im Ergebnis, damit eine Auswertung ohne Verweise
    // nicht wie ein stiller Erfolg aussieht.
    if (ziel.art == Zielart.aktivitaet &&
        modul != null &&
        !MoodleZugang.schreibbareModule.contains(modul)) {
      b.writeln('Prüflücke: Typ „$modul" ist nicht schreibbar -- gelesen, nicht geändert (aendern lehnt ab). '
          'Die Verweisprüfung erfasst nur Textfelder; Auswahlfelder werden nicht geprüft.');
    }
    if (fehlend.isNotEmpty) {
      b.writeln('NICHT gelesen (${fehlend.length}): ${fehlend.join(", ")}');
    }
    b.write(uebersichtText(auswertungen, dateiinfo));
    final zeigen = [...?wichtigeEinstellungen[modul], ...immerZeigen];
    final wichtig = [
      for (final k in zeigen) ...einstellungen.where((e) => e.schluessel == k)
    ];
    if (einstellungen.isNotEmpty) {
      b.writeln('\nEinstellungen (${einstellungen.length}, alle in einstellungen.json):');
      for (final e in wichtig) {
        b.writeln('  ${e.label}: ${e.wert}');
      }
    }
    for (final d in bereiche) {
      b.writeln('\nDateibereich ${d.feld} „${d.label}": ${d.dateien.length} Datei(en) in bereiche/${d.feld}/');
      for (final e in d.dateien.entries) {
        final i = e.value;
        b.writeln('  ${e.key.substring(1)} · ${i.bytes} Bytes · ${i.format ?? "?"}'
            '${i.breite == null ? '' : ' ${i.breite}×${i.hoehe}'}'
            '${i.titel == null ? '' : ' · SVG-Titel „${i.titel}"'}');
      }
      for (final n in d.nichtGelesen) {
        b.writeln('  NICHT gelesen: $n');
      }
    }
    for (final h in hinweise) {
      b.writeln('Hinweis: $h');
    }
    b.writeln('\nQuelltext unverändert in <feld>.html. '
        'Zum Ändern <feld>.html, dateien/ und bereiche/ bearbeiten -- neue Bilder in dateien/ '
        'ablegen und als src="@@PLUGINFILE@@/<name>" einbinden --, dann aendern(ordner). '
        '.stand/ nicht anfassen.');
    return b.toString();
  }
}

/// Größere Dateien eines Dateibereichs werden nicht geladen, nur genannt.
const int bereichGrenze = 25 * 1024 * 1024;

/// Liest die Dateibereiche des Formulars nach `bereiche/<feld>/` (und .stand/).
/// Die Wurzel jedes Bereichs steht schon in der Seite; Unterordner fragt die
/// App einzeln ab.
Future<List<Dateibereich>> _bereicheLesen(MoodleZugang moodle, dom.Element form,
    List<Map<String, Object?>> roh, String ziel, String? sesskey) async {
  final aus = <Dateibereich>[];
  for (final b in roh) {
    final feld = '${b['target'] ?? ''}'.replaceFirst('id_', '');
    final itemid = '${b['itemid'] ?? ''}';
    if (feld.isEmpty || itemid.isEmpty) continue;
    final label = (form.querySelector('#fitem_id_$feld .col-form-label')?.text ?? feld)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final bereich = Dateibereich(feld, label);
    aus.add(bereich);
    await Directory(p.join(ziel, 'bereiche', feld)).create(recursive: true);
    await Directory(p.join(ziel, '.stand', 'bereiche', feld)).create(recursive: true);
    final offen = <List<Object?>>[(b['list'] as List?) ?? const []];
    var runden = 0;
    while (offen.isNotEmpty && runden++ < 200) {
      for (final e in offen.removeAt(0)) {
        if (e is! Map) continue;
        final pfad = '${e['filepath'] ?? '/'}';
        final name = '${e['filename'] ?? ''}';
        if (e['type'] == 'folder') {
          if (sesskey == null) {
            bereich.nichtGelesen.add('$pfad$name/ (Unterordner, kein sesskey)');
            continue;
          }
          final unter = await moodle.senden('/repository/draftfiles_ajax.php?action=list', [
            MapEntry('itemid', itemid),
            MapEntry('filepath', '$pfad$name/'.replaceAll('//', '/')),
            MapEntry('client_id', '${b['client_id'] ?? ''}'),
            MapEntry('sesskey', sesskey),
          ]);
          try {
            offen.add(((jsonDecode(unter.text) as Map)['list'] as List?) ?? const []);
          } catch (_) {
            bereich.nichtGelesen.add('$pfad$name/ (Unterordner nicht lesbar)');
          }
          continue;
        }
        final groesse = int.tryParse('${e['size'] ?? ''}') ?? 0;
        final url = '${e['url'] ?? ''}';
        if (groesse > bereichGrenze) {
          bereich.nichtGelesen.add('$pfad$name (${(groesse / 1048576).toStringAsFixed(0)} MB, zu groß)');
          continue;
        }
        try {
          final d = await moodle.lesen(url);
          if (d.status != 200) {
            bereich.nichtGelesen.add('$pfad$name (HTTP ${d.status})');
            continue;
          }
          for (final wurzel in [ziel, p.join(ziel, '.stand')]) {
            final f = File(p.joinAll([wurzel, 'bereiche', feld, ...pfad.split('/').where((s) => s.isNotEmpty), name]));
            await f.parent.create(recursive: true);
            await f.writeAsBytes(d.bytes);
          }
          bereich.dateien['$pfad$name'] = dateiAuswerten(name, d.bytes);
        } on MoodleFehler catch (x) {
          bereich.nichtGelesen.add('$pfad$name (${x.meldung})');
        }
      }
    }
  }
  return aus;
}

/// Titel und Typ der verlinkten Aktivitäten: zuerst aus der Struktur des
/// eigenen Kurses (eine Anfrage), was dort fehlt, aus dem jeweiligen
/// Bearbeitungsformular -- höchstens [grenze] Stück.
Future<Map<int, (String, String)>> _zielTitel(
    MoodleZugang moodle, int? kurs, Set<int> cmids, List<String> hinweise,
    {int grenze = 10}) async {
  final titel = <int, (String, String)>{};
  if (cmids.isEmpty) return titel;
  if (kurs != null) {
    try {
      final k = await kursLesen(moodle, kurs);
      for (final c in k.nachCmid.values) {
        if (cmids.contains(c.cmid)) titel[c.cmid] = (c.name, c.modul);
      }
    } on MoodleFehler catch (x) {
      hinweise.add('Kursstruktur nicht abrufbar (${x.meldung}).');
    }
  }
  final rest = cmids.where((c) => !titel.containsKey(c)).take(grenze).toList();
  for (final c in rest) {
    try {
      final r = await moodle.lesen('/course/modedit.php?update=$c');
      final form = html_parser.parse(r.text).querySelector('form.mform');
      String? wert(String n) => form
          ?.querySelectorAll('input')
          .where((e) => e.attributes['name'] == n)
          .firstOrNull
          ?.attributes['value'];
      final name = wert('name');
      if (name != null) titel[c] = (name, wert('modulename') ?? '?');
    } on MoodleFehler {
      // nicht prüfbar, etwa ohne Bearbeitungsrecht im anderen Kurs
    }
  }
  final offen = cmids.where((c) => !titel.containsKey(c)).toList();
  if (offen.isNotEmpty) {
    hinweise.add('Titel nicht geprüft für Verweise auf cm ${offen.join(", ")} '
        '(nicht abrufbar oder mehr als $grenze außerhalb des Kurses).');
  }
  return titel;
}

/// Die Einstellungen der Dateibereiche einer Seite, wie Moodle sie dem
/// Dateimanager mitgibt (M.form_filemanager.init). Personenfelder -- etwa der
/// Autor, der volle Name der angemeldeten Person -- werden entfernt.
List<Map<String, Object?>> dateibereiche(String seite) {
  final aus = <Map<String, Object?>>[];
  const marke = 'M.form_filemanager.init(Y, ';
  var i = seite.indexOf(marke);
  while (i >= 0) {
    final start = i + marke.length;
    final ende = _jsonEnde(seite, start);
    if (ende > start) {
      try {
        final j = ohnePersonenfelder(jsonDecode(seite.substring(start, ende)));
        if (j is Map<String, Object?>) aus.add(j);
      } catch (_) {
        // kein gültiges JSON: übergehen
      }
    }
    i = seite.indexOf(marke, start);
  }
  return aus;
}

/// Ende eines JSON-Objekts ab [start] (öffnende Klammer), Zeichenketten beachtet.
int _jsonEnde(String s, int start) {
  if (start >= s.length || s[start] != '{') return -1;
  var tiefe = 0;
  var inText = false;
  for (var i = start; i < s.length; i++) {
    final c = s[i];
    if (inText) {
      if (c == r'\') {
        i++;
      } else if (c == '"') {
        inText = false;
      }
    } else if (c == '"') {
      inText = true;
    } else if (c == '{') {
      tiefe++;
    } else if (c == '}') {
      tiefe--;
      if (tiefe == 0) return i + 1;
    }
  }
  return -1;
}

/// Das Moodle-Formular einer Seite. Einzeln in dieser Reihenfolge suchen: Ein
/// Selektor mit Komma liefert das erste Formular im Dokument, das irgendeinen
/// trifft -- und das ist auf Moodle-Seiten oft die Suche in der Kopfzeile.
dom.Element? hauptformular(dom.Document d) =>
    d.querySelector('form.mform') ?? d.querySelector('form#mform1') ?? d.querySelector('form[action*="edit"]');

/// Name, der im Formular steht: das Feld name, sonst ein Titel- oder
/// Fragenname-Feld.
String? _nameIn(dom.Element form) {
  for (final n in ['name', 'title', 'questiontext_name']) {
    final e = form.querySelectorAll('input').where((e) => e.attributes['name'] == n).firstOrNull;
    final v = e?.attributes['value'];
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

/// Ticket #22: Je Zielordner läuft im Prozess höchstens ein Lesen gleichzeitig.
/// Ohne das löscht ein Lesen den Ordner, während ein anderes ihn gerade füllt;
/// dann schlägt das Löschen oder Schreiben fehl. Die Sperre gilt je Pfad, nicht
/// global: verschiedene Fragen lesen weiter parallel.
final _ordnerSperren = <String, Future<void>>{};

/// Der Schlüssel der Sperre: der absolute Ordner des Ziels im Arbeitsordner.
String ordnerSchluessel(Formularziel ziel, String arbeitsordner) =>
    p.normalize(p.absolute(p.join(arbeitsordner, ziel.ordnerName)));

Future<T> ordnerSperre<T>(String pfad, Future<T> Function() tu) {
  final vorher = _ordnerSperren[pfad] ?? Future<void>.value();
  final fertig = Completer<void>();
  final ende = fertig.future;
  _ordnerSperren[pfad] = ende;
  return vorher.then((_) => tu()).whenComplete(() {
    fertig.complete();
    if (identical(_ordnerSperren[pfad], ende)) _ordnerSperren.remove(pfad);
  });
}

Future<FormularGelesen> formularLesen(MoodleZugang moodle, Formularziel ziel, String arbeitsordner) {
  return ordnerSperre(ordnerSchluessel(ziel, arbeitsordner),
      () => formularLesenOhneSperre(moodle, ziel, arbeitsordner));
}

/// Nur innerhalb einer [ordnerSperre] aufrufen, sonst wartet der Aufruf auf sich selbst.
Future<FormularGelesen> formularLesenOhneSperre(
    MoodleZugang moodle, Formularziel ziel, String arbeitsordner) async {
  final r = await moodle.lesen(ziel.adresse);
  if (r.status != 200) {
    throw MoodleFehler('Das Bearbeitungsformular von ${ziel.bezeichnung} ist nicht abrufbar (HTTP ${r.status}).');
  }
  final doc = html_parser.parse(r.text);
  final form = hauptformular(doc);
  if (form == null) {
    throw MoodleFehler('In der Antwort steht kein Bearbeitungsformular. Entweder gibt es '
        '${ziel.bezeichnung} nicht, oder diese Sitzung darf es nicht bearbeiten.');
  }
  String? wert(String n) =>
      form.querySelectorAll('input').where((e) => e.attributes['name'] == n).firstOrNull?.attributes['value'];
  final seite = Seitenangaben.aus(r.text);

  final felder = <GelesenesFeld>[];
  for (final ta in form.querySelectorAll('textarea')) {
    final n = ta.attributes['name'] ?? '';
    if (!n.endsWith('[text]')) continue;
    // Textarea ist RCDATA: .text liefert den Quelltext so, wie der Editor
    // ihn bekäme -- Entities aufgelöst, sonst unverändert.
    felder.add(GelesenesFeld(n.substring(0, n.length - '[text]'.length), ta.text));
  }

  final ziel0 = Directory(p.join(arbeitsordner, ziel.ordnerName));
  if (await ziel0.exists()) await ziel0.delete(recursive: true);
  await Directory(p.join(ziel0.path, 'dateien')).create(recursive: true);
  await Directory(p.join(ziel0.path, '.stand', 'dateien')).create(recursive: true);
  await File(p.join(ziel0.path, '.stand', 'ziel.json')).writeAsString(jsonEncode(ziel.toJson()));

  // Das Formular selbst, für Einstellungen und Fehlersuche -- ohne sesskey.
  final kopie = form.clone(true);
  for (final e in kopie.querySelectorAll('input[name="sesskey"]')) {
    e.attributes['value'] = '…';
  }
  await File(p.join(ziel0.path, '.stand', 'formular.html')).writeAsString(kopie.outerHtml, encoding: utf8);
  final bereicheRoh = dateibereiche(r.text);
  await File(p.join(ziel0.path, '.stand', 'dateibereiche.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(bereicheRoh),
      encoding: utf8);
  final einstellungen = einstellungenLesen(form);
  final einstellungenJson =
      const JsonEncoder.withIndent('  ').convert([for (final e in einstellungen) e.toJson()]);
  // Oben zum Lesen; in .stand für den Vergleich beim Ändern (hat jemand anderes
  // eine Einstellung geändert, die jetzt geändert werden soll?).
  await File(p.join(ziel0.path, 'einstellungen.json')).writeAsString(einstellungenJson, encoding: utf8);
  await File(p.join(ziel0.path, '.stand', 'einstellungen.json')).writeAsString(einstellungenJson, encoding: utf8);
  final sesskey = wert('sesskey');
  final bereiche = await _bereicheLesen(moodle, form, bereicheRoh, ziel0.path, sesskey);

  // Referenzierte Dateien einsammeln: src und href, die auf Datei-Adressen
  // dieser Moodle-Instanz zeigen.
  final basis = moodle.basis!;
  final attr = RegExp(r'''(?:src|href)\s*=\s*(["'])(.*?)\1''', dotAll: true);
  final adressen = <String, Set<String>>{}; // Adresse -> Felder
  for (final f in felder) {
    for (final m in attr.allMatches(f.html)) {
      final roh = m.group(2)!.replaceAll('&amp;', '&');
      final u = Uri.tryParse(roh);
      if (u == null || u.host != basis.host) continue;
      if (!u.path.startsWith('/draftfile.php/') && !u.path.startsWith('/pluginfile.php/')) continue;
      adressen.putIfAbsent(roh, () => <String>{}).add(f.feld);
    }
  }

  final dateien = <GeleseneDatei>[];
  final dateiinfo = <String, Dateiinfo>{};
  final fehlend = <String>[];
  final namenFuer = <String, String>{}; // Adresse -> lokaler Name
  final vergeben = <String>{};
  for (final e in adressen.entries) {
    var name = dateiname(e.key);
    if (vergeben.contains(name)) {
      final ext = p.extension(name);
      var i = 2;
      while (vergeben.contains('${p.basenameWithoutExtension(name)}-$i$ext')) {
        i++;
      }
      name = '${p.basenameWithoutExtension(name)}-$i$ext';
    }
    try {
      final d = await moodle.lesen(e.key);
      if (d.status != 200) {
        fehlend.add('$name (HTTP ${d.status})');
        continue;
      }
      await File(p.join(ziel0.path, 'dateien', name)).writeAsBytes(d.bytes);
      await File(p.join(ziel0.path, '.stand', 'dateien', name)).writeAsBytes(d.bytes);
      vergeben.add(name);
      namenFuer[e.key] = name;
      dateien.add(GeleseneDatei(name, d.bytes.length, d.inhaltstyp, e.value));
      dateiinfo[name] = dateiAuswerten(name, d.bytes);
    } on MoodleFehler catch (x) {
      fehlend.add('$name (${x.meldung})');
    }
  }

  for (final f in felder) {
    await File(p.join(ziel0.path, '${f.feld}.html')).writeAsString(f.html, encoding: utf8);
    await File(p.join(ziel0.path, '.stand', '${f.feld}.html')).writeAsString(f.html, encoding: utf8);
  }

  // Auswerten: Quelltext jedes Felds, Titel der verlinkten Aktivitäten.
  final kurs = int.tryParse(wert('course') ?? '') ?? seite.kurs;
  final auswertungen = [
    for (final f in felder) feldAuswerten(f.feld, f.html, host: basis.host, lokalerName: namenFuer)
  ];
  final hinweise = <String>[];
  final eigene = ziel.art == Zielart.aktivitaet ? ziel.id : ziel.cmid;
  final verlinkt = {
    for (final a in auswertungen)
      for (final v in a.verweise)
        if (v.art == VerweisArt.aktivitaet && v.cmid != eigene) v.cmid!
  };
  final titel = await _zielTitel(moodle, kurs, verlinkt, hinweise);
  for (final a in auswertungen) {
    verweiseAbgleichen(a, titel);
  }

  final modul = wert('modulename') ?? wert('qtype');
  final ergebnis = FormularGelesen(ziel, kurs, _nameIn(form), modul, ziel0.path, felder,
      dateien, fehlend, auswertungen, dateiinfo, hinweise,
      einstellungen: einstellungen, bereiche: bereiche);
  await File(p.join(ziel0.path, 'uebersicht.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'ziel': ziel.toJson(),
        'kurs': kurs,
        'name': ergebnis.name,
        'modul': ergebnis.modul,
        'gelesen': DateTime.now().toIso8601String(),
        'felder': [
          for (final f in felder) {'feld': f.feld, 'zeichen': f.html.length, 'datei': '${f.feld}.html'}
        ],
        'dateien': [
          for (final d in dateien)
            {'name': d.name, 'bytes': d.bytes, 'typ': d.typ, 'felder': d.felder.toList()}
        ],
        'nichtGelesen': fehlend,
        'bereiche': [
          for (final b in bereiche)
            {
              'feld': b.feld,
              'label': b.label,
              'dateien': [for (final e in b.dateien.entries) {'pfad': e.key, ...e.value.toJson()}],
              'nichtGelesen': b.nichtGelesen,
            }
        ],
        'auswertung': {
          'felder': [for (final a in auswertungen) a.toJson()],
          'dateien': [for (final d in dateiinfo.values) d.toJson()],
          'hinweise': hinweise,
        },
      }),
      encoding: utf8);
  return ergebnis;
}
