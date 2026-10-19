// Bilder und Anhänge importierter Aktivitäten zurücklesen und vergleichen (Ticket #21,
// Spec #17, E2, E3, E17).
//
// Quelle: die Sicherungsdatei im Sicherungsordner (vorgaenge.ordner/datei). Je
// eindeutig zugeordneter Aktivität nennt inforef.xml die Dateien, files.xml gibt Name
// und contenthash (SHA-1 des Inhalts). Nutzerdateien (component „user…") bleiben
// außen (A1); ihre Inhalte werden nie gelesen.
//
// Ziel: das Bearbeitungsformular der Aktivität (GET /course/modedit.php?update=cmid,
// Positivliste). Seine Verweise auf /pluginfile.php und /draftfile.php werden nur
// über den Pfad abgerufen, nie über einen anderen Host. Verglichen wird der Inhalt
// (SHA-1), nicht die Adresse: URLs allein beweisen keine Gleichheit.
//
// Die Prüfung repariert nichts. Eine Reparatur über aktivitaet_aendern wäre ein
// eigener Schritt mit Freigabe und hier nicht enthalten.
//
// Lücke: Dateien, die nur im Dateimanager einer Aktivität liegen (etwa mod_resource),
// erscheinen nicht im Formular als Verweis. Sie gelten darum als nicht verifiziert
// („fehlend"), bis eine erlaubte Leseseite dafür in der Positivliste steht.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'moodle_zugang.dart';
import 'sicherung.dart';
import 'wiederherstellung_regeln.dart' show WiederhergestellteAktivitaet;

/// Eine Datei der Quellaufnahme.
typedef QuellDatei = ({String name, String sha1});

/// Ein abgerufener Verweis aus dem Formular. [status] null: keine Antwort (Netzfehler).
/// [sha1] nur bei HTTP 200.
typedef ZielAbruf = ({String name, bool entwurf, int? status, String? sha1});

/// Ergebnis für eine Aktivität oder für alle zusammen.
class AnhangPruefung {
  AnhangPruefung(this.befunde, {required this.vollstaendig});

  /// Leer, wenn alles übereinstimmt. Sonst je Fund ein Satz mit dem Namen.
  final List<String> befunde;

  /// Nur wahr, wenn jede Datei mit der Quellaufnahme übereinstimmt und nichts fehlt.
  final bool vollstaendig;

  String get text => vollstaendig
      ? 'Anhänge und Bilder: verglichen, übereinstimmend.'
      : 'Anhänge und Bilder nicht vollständig verifiziert: ${befunde.join('; ')}. '
          'Nichts wurde repariert.';
}

final RegExp _verweis = RegExp(r'/(pluginfile|draftfile)\.php/[^\s"\x27<>]+');

String? _text(XmlElement e, String name) => e.getElement(name)?.innerText.trim();

/// Die Dateien einer Aktivität aus der Quellaufnahme. null, wenn es keine gibt, weil
/// das Archiv unlesbar ist, die Aktivität nicht eindeutig darin vorkommt oder ihre
/// Dateiliste fehlt. Dann ist die Quelle „fehlend", nicht „leer".
List<QuellDatei>? quelldateienAus(Uint8List mbz, {required String modul, required String titel}) {
  final Map<String, Uint8List> dateien;
  try {
    final tar = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(mbz));
    dateien = {
      for (final f in tar.files)
        if (f.isFile) f.name: Uint8List.fromList(f.content as List<int>),
    };
  } catch (_) {
    // Jeder Fehler beim Entpacken heißt: keine Quellaufnahme. Der Aufrufer meldet null
    // als Prüflücke („Quellaufnahme fehlt"), nie als leere Dateiliste.
    return null;
  }

  final backup = dateien['moodle_backup.xml'];
  final filesXml = dateien['files.xml'];
  if (backup == null || filesXml == null) return null;
  try {
    final doc = XmlDocument.parse(utf8.decode(backup, allowMalformed: true));
    final verzeichnisse = [
      for (final a in doc.findAllElements('activity'))
        if (_text(a, 'modulename') == modul && _text(a, 'title') == titel) _text(a, 'directory') ?? '',
    ];
    if (verzeichnisse.length != 1) return null;
    final verz = verzeichnisse.single;
    if (verz.isEmpty || verz.startsWith('/') || verz.contains('..')) return null;
    final inforef = dateien['$verz/inforef.xml'];
    if (inforef == null) return null;

    final ids = {
      for (final f in XmlDocument.parse(utf8.decode(inforef, allowMalformed: true)).findAllElements('file'))
        if ((_text(f, 'id') ?? '').isNotEmpty) _text(f, 'id')!,
    };
    final liste = <QuellDatei>[];
    for (final f in XmlDocument.parse(utf8.decode(filesXml, allowMalformed: true)).findAllElements('file')) {
      if (!ids.contains(_text(f, 'id'))) continue;
      if ((_text(f, 'component') ?? '').startsWith('user')) continue; // A1: Nutzerdateien nie
      final name = _text(f, 'filename') ?? '';
      if (name.isEmpty || name == '.') continue; // Verzeichniseinträge
      liste.add((name: name, sha1: _text(f, 'contenthash') ?? ''));
    }
    return liste;
  } on XmlException {
    return null;
  }
}

/// Die Verweise auf Dateien im Formular. Escapetes HTML wird zuerst aufgelöst. Nur der
/// Pfad zählt: Ein fremder Host wird nie angefragt. Gleiche Pfade einmal.
List<({bool entwurf, String pfad, String name})> verweiseAus(String html) {
  final text = html
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
  final gesehen = <String>{};
  final liste = <({bool entwurf, String pfad, String name})>[];
  for (final m in _verweis.allMatches(text)) {
    var roh = m.group(0)!;
    final ende = roh.indexOf(RegExp(r'[?#]'));
    if (ende > 0) roh = roh.substring(0, ende);
    if (!gesehen.add(roh)) continue;
    String name;
    try {
      name = Uri.decodeComponent(roh.split('/').last);
    } on FormatException {
      name = roh.split('/').last;
    }
    liste.add((entwurf: m.group(1) == 'draftfile', pfad: roh, name: name));
  }
  return liste;
}

/// Liest das Formular einer Aktivität und ruft jeden Verweis ab. [fehler] nennt den
/// Grund, wenn das Formular selbst nicht lesbar ist.
Future<({String? fehler, List<ZielAbruf> abrufe})> zielLesen(MoodleZugang moodle, int cmid) async {
  final Antwort form;
  try {
    form = await moodle.lesen('/course/modedit.php?update=$cmid');
  } on MoodleFehler {
    return (fehler: 'Bearbeitungsformular nicht lesbar', abrufe: const <ZielAbruf>[]);
  }
  if (form.status != 200) {
    return (fehler: 'Bearbeitungsformular nicht lesbar (HTTP ${form.status})', abrufe: const <ZielAbruf>[]);
  }
  final abrufe = <ZielAbruf>[];
  for (final v in verweiseAus(form.text)) {
    int? status;
    String? sha;
    try {
      final r = await moodle.lesen(v.pfad);
      status = r.status;
      if (r.status == 200) sha = sha1.convert(r.bytes).toString();
    } on MoodleFehler {
      status = null;
    }
    abrufe.add((name: v.name, entwurf: v.entwurf, status: status, sha1: sha));
  }
  return (fehler: null, abrufe: abrufe);
}

/// Vergleicht Quelle und Ziel einer Aktivität. [quelle] null heißt: Quellaufnahme fehlt.
AnhangPruefung vergleicheAnhaenge({required List<QuellDatei>? quelle, required List<ZielAbruf> ziel,
    String? formularFehler}) {
  final befunde = <String>[];
  if (formularFehler != null) befunde.add(formularFehler);
  if (quelle == null) {
    befunde.add('Quellaufnahme fehlt: Vergleich nicht möglich');
    return AnhangPruefung(befunde, vollstaendig: false);
  }

  final namen = <String, Set<String>>{};
  for (final q in quelle) {
    namen.putIfAbsent(q.name, () => {}).add(q.sha1);
  }
  final gelesen = <String>{};
  for (final z in ziel) {
    if (z.status == null) {
      befunde.add('„${z.name}": Abruf fehlgeschlagen');
      continue;
    }
    if (z.status != 200) {
      if (z.entwurf) {
        befunde.add('„${z.name}": verwaiste Entwurfsadresse (HTTP ${z.status})');
      } else {
        befunde.add('„${z.name}": HTTP ${z.status}');
      }
      continue;
    }
    final erwartet = namen[z.name];
    if (erwartet == null) {
      befunde.add('„${z.name}": fremd, die Quellaufnahme kennt die Datei nicht');
      continue;
    }
    if (erwartet.length > 1) {
      befunde.add('„${z.name}": mehrdeutig, gleicher Name mit verschiedenem Inhalt in der Quelle');
      continue;
    }
    if (z.sha1 != erwartet.single) {
      befunde.add('„${z.name}": geändert, Inhalt weicht von der Quelle ab');
      continue;
    }
    gelesen.add(z.name);
  }
  for (final name in namen.keys) {
    if (!gelesen.contains(name) && !ziel.any((z) => z.name == name)) {
      befunde.add('„$name": fehlend im Ziel');
    }
  }
  return AnhangPruefung(befunde, vollstaendig: befunde.isEmpty);
}

/// Prüft die Anhänge der eindeutig zugeordneten Aktivitäten. Liest nur Quelle und
/// Formulare; schreibt nie.
Future<AnhangPruefung> anhaengePruefen(MoodleZugang moodle, Vorgaenge vorgaenge, Vorgang vg,
    List<WiederhergestellteAktivitaet> aktivitaeten) async {
  final Uint8List mbz;
  try {
    mbz = await File(p.join(vorgaenge.ordner, vg.datei)).readAsBytes();
  } on FileSystemException {
    return AnhangPruefung(['Prüflücke: Quellaufnahme fehlt; die Sicherungsdatei ist nicht mehr vorhanden'],
        vollstaendig: false);
  }

  // Der Dateiname ist veränderlich, die vor dem Hochladen aufgenommene Quelle
  // hingegen nicht. Ein später ersetztes Archiv kann keinen Vergleich belegen.
  final startHash = vg.fingerabdruck?.split('|').first;
  if (startHash == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(startHash)) {
    return AnhangPruefung(['Prüflücke: Quellaufnahme ist nicht an den Start-Inhalt gebunden (Inhalts-Hash fehlt)'],
        vollstaendig: false);
  }
  if (sha256.convert(mbz).toString() != startHash) {
    return AnhangPruefung(['Prüflücke: Quellaufnahme hat seit dem Start einen anderen Inhalt; Anhänge nicht verglichen'],
        vollstaendig: false);
  }

  final befunde = <String>[];
  var vollstaendig = true;
  for (final a in aktivitaeten) {
    final quelle = quelldateienAus(mbz, modul: a.modul, titel: a.titel);
    vorgaenge.pruefeBindung(vg);
    final ziel = await zielLesen(moodle, a.cmid);
    final pruefung = vergleicheAnhaenge(quelle: quelle, ziel: ziel.abrufe, formularFehler: ziel.fehler);
    if (!pruefung.vollstaendig) {
      vollstaendig = false;
      befunde.add('„${a.titel}": ${pruefung.befunde.join('; ')}');
    }
  }
  return AnhangPruefung(befunde, vollstaendig: vollstaendig && aktivitaeten.isNotEmpty);
}
