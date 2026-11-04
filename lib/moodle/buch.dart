// Bücher (mod_book): Werkzeuge buch_lesen, buchkapitel_anlegen,
// buchkapitel_loeschen, buchkapitel_verschieben, buch_ordnen. Ein Kapitel
// ändert das allgemeine aendern (formular_schreiben.dart), denn jedes
// Kapitel hat ein eigenes Bearbeitungsformular (/mod/book/edit.php).
//
// Die Kapitelliste kommt aus der Druckansicht (/mod/book/tool/print/): Sie
// zeigt alle Kapitel mit ihrer chapterid auf einer Seite. Die normale
// Ansichtsseite verlinkt das gerade angezeigte Kapitel nicht, seine id fehlt
// dort. Unterkapitel erkennt man an der Überschriftenebene (Kapitel h2,
// Unterkapitel h3), nicht an der Nummerierung -- die lässt sich am Buch
// abschalten.
//
// Umsortieren (/mod/book/move.php, ein Schritt hoch oder runter), gemessen
// am 10.09.2026 an einem Probebuch:
//   Hauptkapitel  bewegt sich als BLOCK mit seinen Unterkapiteln und springt
//                 über den ganzen Nachbarblock. Die Hierarchie bleibt.
//   Unterkapitel  bewegt sich um EINE Position und wechselt dabei
//                 stillschweigend den Elternteil. An erster Stelle macht
//                 Moodle ein Hauptkapitel daraus -- ohne Rückfrage.
// Deshalb ordnet buch_ordnen nur Hauptkapitel, und buchkapitel_verschieben
// bricht ab, bevor ein Unterkapitel den Elternteil oder die Ebene wechselt,
// es sei denn, das ist ausdrücklich gewollt. Die Rückleseprobe prüft
// Reihenfolge UND Hierarchie: Die Reihenfolge kann stimmen, während die
// Hierarchie zerfallen ist.
//
// Löschen (/mod/book/delete.php) braucht confirm=1: Ohne antwortet Moodle
// mit einer Umleitung auf die Buchseite und löscht nichts. Ein Hauptkapitel
// nimmt seine Unterkapitel mit.

import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

import '../freigabe.dart';
import 'formular.dart';
import 'elemente.dart';
import 'formular_lesen.dart';
import 'formular_schreiben.dart';
import 'kurs.dart';
import 'moodle_zugang.dart';

class Kapitel {
  Kapitel(this.id, this.titel, this.unterkapitel);
  final int id;
  final String titel;
  final bool unterkapitel;

  Map<String, Object?> toJson() => {'id': id, 'titel': titel, 'unterkapitel': unterkapitel};
}

/// Die Kapitel eines Buchs, in ihrer Reihenfolge.
Future<List<Kapitel>> kapitelLesen(MoodleZugang moodle, int cmid) async {
  final r = await moodle.lesen('/mod/book/tool/print/index.php?id=$cmid');
  if (r.status != 200) {
    throw MoodleFehler('Die Druckansicht des Buchs cmid $cmid ist nicht abrufbar (HTTP ${r.status}). '
        'Ohne sie fehlen die Kapitelnummern; sie kann von der Administration abgeschaltet sein.');
  }
  final d = html_parser.parse(r.text);
  final roh = [
    for (final el in d.querySelectorAll('.book_chapter'))
      (el, el.querySelector('h1, h2, h3, h4, h5'))
  ];
  final stufen = [for (final (_, h) in roh) if (h != null) int.parse(h.localName!.substring(1))];
  final oben = stufen.isEmpty ? 2 : stufen.reduce((a, b) => a < b ? a : b);
  return [
    for (final (el, h) in roh)
      if (int.tryParse(el.id.replaceFirst('ch', '')) != null)
        Kapitel(
          int.parse(el.id.replaceFirst('ch', '')),
          // Die vorangestellte Nummer („1.2.") gehört nicht zum Titel.
          (h?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim().replaceFirst(RegExp(r'^(\d+\.)+\s*'), ''),
          h != null && int.parse(h.localName!.substring(1)) > oben,
        )
  ];
}

String _liste(List<Kapitel> k) =>
    [for (final (i, x) in k.indexed) '${i + 1}. ${x.unterkapitel ? '  ' : ''}${x.titel} [id ${x.id}]'].join('\n');

// ---------------------------------------------------------------------------
// buch_lesen
// ---------------------------------------------------------------------------

Future<String> buchLesen(MoodleZugang moodle, int cmid, String arbeitsordner) async {
  final kapitel = await kapitelLesen(moodle, cmid);
  final ordner = Directory(p.join(arbeitsordner, 'buch-$cmid'));
  if (await ordner.exists()) await ordner.delete(recursive: true);
  await ordner.create(recursive: true);
  await File(p.join(ordner.path, 'kapitel.json'))
      .writeAsString(const JsonEncoder.withIndent('  ').convert([for (final k in kapitel) k.toJson()]));
  final b = StringBuffer()
    ..writeln('Buch cmid $cmid: ${kapitel.length} Kapitel, gelesen nach ${ordner.path}')
    ..writeln(_liste(kapitel))
    ..writeln();
  for (final k in kapitel) {
    final g = await formularLesen(moodle, Formularziel.buchkapitel(cmid, k.id), arbeitsordner);
    // Je Kapitel die Übersicht, ohne den Hinweistext am Ende (steht unten einmal).
    final z = g.zusammenfassung();
    b.writeln('━━ ${k.unterkapitel ? 'Unterkapitel' : 'Kapitel'} „${k.titel}" ━━');
    b.writeln(z.substring(0, z.lastIndexOf('\nQuelltext unverändert')).trim());
    b.writeln();
  }
  b.writeln('Je Kapitel ein Ordner kapitel-<id> mit content_editor.html, dateien/ und einstellungen.json. '
      'Ändern: dort bearbeiten, dann aendern(ordner des Kapitels). Einstellungen des Buchs selbst: '
      'aktivitaet_lesen($cmid).');
  return b.toString();
}

// ---------------------------------------------------------------------------
// buchkapitel_anlegen
// ---------------------------------------------------------------------------

Future<String> buchkapitelAnlegen(MoodleZugang moodle, Freigaben freigaben,
    {required int cmid,
    required String titel,
    required String arbeitsordner,
    int? nachKapitelId,
    bool unterkapitel = false,
    String? ordner}) async {
  final quelle = ordner == null ? null : imArbeitsordner(ordner, arbeitsordner);
  final inhalt = quelleLesen(quelle, kopf: elementKopfFuer(moodle));
  final vorher = await kapitelLesen(moodle, cmid);
  // pagenum ist die Stelle, HINTER der eingefügt wird; 0 = an den Anfang.
  var pagenum = vorher.length;
  if (nachKapitelId != null) {
    final i = vorher.indexWhere((k) => k.id == nachKapitelId);
    if (i < 0) throw MoodleFehler('Kapitel $nachKapitelId gibt es in diesem Buch nicht.\n${_liste(vorher)}');
    pagenum = i + 1;
  }
  if (unterkapitel && pagenum == 0) {
    throw MoodleFehler('Das erste Kapitel eines Buchs kann kein Unterkapitel sein.');
  }
  // Ein neues Kapitel in einem Buch, das Lernende sehen, ist sofort sichtbar:
  // Dann fragt die App ab „mittel", sonst erst bei „alle".
  final probe0 = await formularHolen(moodle, '/mod/book/edit.php?cmid=$cmid&pagenum=$pagenum');
  final kurs = probe0.kurs;
  final buch = kurs == null ? null : (await kursLesen(moodle, kurs)).nachCmid[cmid];
  final sofort = buch != null && buch.sichtbarkeit != Sichtbarkeit.verborgen;
  final wo = 'Buch „${buch?.name ?? probe0.name}" (cmid $cmid'
      '${kurs == null ? '' : ', ${await kursBezeichnung(moodle, kurs)}'})';
  final ja = await freigaben.anfragen(FreigabeAnfrage(
    titel: sofort ? 'Kapitel in sichtbarem Buch anlegen?' : 'Buchkapitel anlegen?',
    punkte: [
      '${unterkapitel ? 'Unterkapitel' : 'Kapitel'} „$titel" im $wo',
      sofort
          ? 'Das Buch ist für Lernende ${buch.sichtbarkeit.text} -- das Kapitel erscheint SOFORT.'
          : buch == null
              ? 'Ob das Buch für Lernende sichtbar ist, ließ sich nicht ermitteln.'
              : 'Das Buch ist für Lernende verborgen -- das Kapitel sieht niemand außer der Lehrkraft.',
    ],
    vergleich: const [],
    knopf: 'Anlegen',
    ohneEntscheidung: 'wird nichts angelegt',
    ab: sofort ? Bestaetigungen.mittel : Bestaetigungen.alle,
  ));
  if (!ja) return 'Nicht angelegt: in der App abgelehnt oder nicht rechtzeitig freigegeben.';

  Future<(Map<String, String>, List<Gesetzt>)> versuch(Map<String, String> felder) async {
    final f = await formularHolen(moodle, '/mod/book/edit.php?cmid=$cmid&pagenum=$pagenum');
    final e = await formularFuellen(moodle, f,
        quelle: quelle, felder: felder, bereiche: inhalt.bereiche, name: titel, was: 'einem Buchkapitel');
    // Ob Unterkapitel, entscheidet das Feld subchapter -- nicht die Adresse.
    f.felder
      ..removeWhere((x) => x.key == 'subchapter')
      ..add(MapEntry('subchapter', unterkapitel ? '1' : '0'));
    await absenden(moodle, f, knoepfe: const ['submitbutton']);
    return e;
  }

  Future<(Map<String, String>, List<Gesetzt>)> mitNeuanmeldung(Map<String, String> felder) async {
    try {
      return await versuch(felder);
    } on SitzungAbgelaufen {
      return await versuch(felder);
    }
  }

  // Hält der Schutzdienst das Anlegen an, mit Platzhalter anlegen und den
  // Inhalt danach übergeben (inhaltUebergeben, formular_schreiben.dart).
  SchutzPruefung? angehalten;
  (Map<String, String>, List<Gesetzt>) e;
  try {
    e = await mitNeuanmeldung(inhalt.felder);
  } on SchutzPruefung catch (x) {
    angehalten = x;
    e = await mitNeuanmeldung(platzhalterFelder(inhalt.felder));
  }
  final nachher = await kapitelLesen(moodle, cmid);
  final neu = nachher.where((k) => !vorher.any((v) => v.id == k.id)).toList();
  if (neu.length != 1) {
    throw MoodleFehler('Gespeichert, aber das neue Kapitel ist nicht eindeutig zu finden '
        '(${neu.length} neue).\n${_liste(nachher)}');
  }
  final k = neu.single;
  final g = await formularLesen(moodle, Formularziel.buchkapitel(cmid, k.id), arbeitsordner);
  final probe = await zuruecklesen(g,
      felder: e.$1, dateien: inhalt.dateien, bereiche: inhalt.bereiche, einstellungen: e.$2, name: titel);
  final stelle = nachher.indexWhere((x) => x.id == k.id);
  probe.pruefe(stelle == pagenum, 'Position (erwartet ${pagenum + 1}, ist ${stelle + 1})');
  probe.pruefe(k.unterkapitel == unterkapitel, 'Ebene (${k.unterkapitel ? "Unterkapitel" : "Kapitel"})');
  if (angehalten != null) {
    return inhaltUebergeben(moodle, freigaben,
        ziel: Formularziel.buchkapitel(cmid, k.id),
        felder: inhalt.felder,
        arbeitsordner: arbeitsordner,
        fehler: angehalten,
        angelegt: 'Angelegt: ${unterkapitel ? 'Unterkapitel' : 'Kapitel'} „${k.titel}" (id ${k.id}) im Buch '
            'cmid $cmid, an Stelle ${stelle + 1}.\n${probe.text}');
  }
  return [
    'Angelegt: ${unterkapitel ? 'Unterkapitel' : 'Kapitel'} „${k.titel}" (id ${k.id}) im Buch cmid $cmid, '
        'an Stelle ${stelle + 1}.',
    probe.text,
    _liste(nachher),
    'Zurückgelesen nach: ${g.ordner}',
  ].join('\n');
}

// ---------------------------------------------------------------------------
// buchkapitel_loeschen
// ---------------------------------------------------------------------------

Future<String> buchkapitelLoeschen(MoodleZugang moodle, Freigaben freigaben,
    {required int cmid, required int kapitelId, required String titel}) async {
  final vorher = await kapitelLesen(moodle, cmid);
  final i = vorher.indexWhere((k) => k.id == kapitelId);
  if (i < 0) throw MoodleFehler('Kapitel $kapitelId gibt es in diesem Buch nicht.\n${_liste(vorher)}');
  final k = vorher[i];
  nameBestaetigen(titel, k.titel, 'Kapitel $kapitelId');
  final mit = <Kapitel>[];
  if (!k.unterkapitel) {
    for (var j = i + 1; j < vorher.length && vorher[j].unterkapitel; j++) {
      mit.add(vorher[j]);
    }
  }
  final ja = await freigaben.anfragen(FreigabeAnfrage(
    titel: 'Buchkapitel endgültig löschen?',
    punkte: [
      '${k.unterkapitel ? 'Unterkapitel' : 'Kapitel'} „${k.titel}" im Buch cmid $cmid',
      if (mit.isNotEmpty) 'Mit seinen Unterkapiteln: ${mit.map((x) => '„${x.titel}"').join(', ')}',
      'Mit Inhalt und Bildern; nicht über den Papierkorb zurückzuholen.',
    ],
    vergleich: const [],
    knopf: 'Löschen',
  ));
  if (!ja) return 'Nicht gelöscht: in der App abgelehnt oder nicht rechtzeitig freigegeben.';
  final s = await moodle.sesskey();
  await moodle.aufrufen('/mod/book/delete.php?id=$cmid&chapterid=$kapitelId&confirm=1&sesskey=$s');
  final nachher = await kapitelLesen(moodle, cmid);
  final weg = ![k, ...mit].any((x) => nachher.any((n) => n.id == x.id));
  return '${weg ? 'Gelöscht' : 'NICHT gelöscht'}: „${k.titel}"${mit.isEmpty ? '' : ' samt ${mit.length} Unterkapitel(n)'}. '
      'verified: $weg\n${_liste(nachher)}';
}

// ---------------------------------------------------------------------------
// Umsortieren
// ---------------------------------------------------------------------------

Future<void> _schritt(MoodleZugang moodle, int cmid, int kapitelId, bool hoch) async {
  final s = await moodle.sesskey();
  await moodle.aufrufen('/mod/book/move.php?id=$cmid&chapterid=$kapitelId&up=${hoch ? 1 : 0}&sesskey=$s');
}

Kapitel? _elternVon(List<Kapitel> liste, int index) {
  for (var x = index - 1; x >= 0; x--) {
    if (!liste[x].unterkapitel) return liste[x];
  }
  return null;
}

/// Hauptkapitel -> seine Unterkapitel (ids), zur Prüfung der Hierarchie.
Map<int, String> _hierarchie(List<Kapitel> k) {
  final aus = <int, String>{};
  int? kopf;
  for (final x in k) {
    if (!x.unterkapitel) {
      kopf = x.id;
      aus[kopf] = '';
    } else if (kopf != null) {
      aus[kopf] = '${aus[kopf]},${x.id}';
    }
  }
  return aus;
}

Future<String> buchkapitelVerschieben(MoodleZugang moodle, Freigaben freigaben,
    {required int cmid,
    required int kapitelId,
    required String titel,
    required bool hoch,
    int schritte = 1,
    bool elternwechselOk = false,
    bool zuHauptkapitelOk = false}) async {
  final vorher = await kapitelLesen(moodle, cmid);
  final i = vorher.indexWhere((k) => k.id == kapitelId);
  if (i < 0) throw MoodleFehler('Kapitel $kapitelId gibt es in diesem Buch nicht.\n${_liste(vorher)}');
  final k = vorher[i];
  nameBestaetigen(titel, k.titel, 'Kapitel $kapitelId');
  if (schritte < 1 || schritte > vorher.length) throw MoodleFehler('schritte: 1 bis ${vorher.length}.');

  // Nur Unterkapitel können dabei die Hierarchie verlieren; Hauptkapitel
  // nehmen ihre Unterkapitel mit. Vorher durchrechnen, was die Schritte
  // bewirken würden.
  if (k.unterkapitel) {
    final sim = [...vorher];
    var pos = i;
    for (var n = 0; n < schritte; n++) {
      final ziel = hoch ? pos - 1 : pos + 1;
      if (ziel < 0 || ziel >= sim.length) break;
      final x = sim[pos];
      sim[pos] = sim[ziel];
      sim[ziel] = x;
      pos = ziel;
    }
    if (pos == 0 && !zuHauptkapitelOk) {
      throw MoodleFehler('Abgebrochen: Das Unterkapitel „${k.titel}" käme an die erste Stelle -- und Moodle '
          'macht daraus ohne Rückfrage ein Hauptkapitel. Wenn genau das gewollt ist: zu_hauptkapitel_ok.');
    }
    final alt = _elternVon(vorher, i), neu = _elternVon(sim, pos);
    if (alt != null && neu != null && alt.id != neu.id && !elternwechselOk) {
      throw MoodleFehler('Abgebrochen: Das Unterkapitel „${k.titel}" wanderte damit von „${alt.titel}" unter '
          '„${neu.titel}". Moodle sagt dazu nichts. Wenn das gewollt ist: elternwechsel_ok.');
    }
  }
  final ja = await freigaben.anfragen(FreigabeAnfrage(
    titel: 'Buchkapitel verschieben?',
    punkte: [
      '${k.unterkapitel ? 'Unterkapitel' : 'Kapitel'} „${k.titel}" im Buch cmid $cmid',
      '$schritte Schritt(e) ${hoch ? 'nach oben' : 'nach unten'}'
          '${k.unterkapitel ? '' : ' -- als Block mit seinen Unterkapiteln'}',
    ],
    vergleich: const [],
    knopf: 'Verschieben',
  ));
  if (!ja) return 'Nicht verschoben: in der App abgelehnt oder nicht rechtzeitig freigegeben.';
  for (var n = 0; n < schritte; n++) {
    await _schritt(moodle, cmid, kapitelId, hoch);
  }
  final nachher = await kapitelLesen(moodle, cmid);
  final iNeu = nachher.indexWhere((x) => x.id == kapitelId);
  return '„${k.titel}" stand an Stelle ${i + 1}, jetzt an ${iNeu + 1}. verified: ${iNeu != i}\n${_liste(nachher)}';
}

Future<String> buchOrdnen(MoodleZugang moodle, Freigaben freigaben,
    {required int cmid, required List<int> reihenfolge}) async {
  final vorher = await kapitelLesen(moodle, cmid);
  final koepfe = [for (final k in vorher) if (!k.unterkapitel) k.id];
  final fehlt = koepfe.where((id) => !reihenfolge.contains(id)).toList();
  final fremd = reihenfolge.where((id) => !koepfe.contains(id)).toList();
  if (fehlt.isNotEmpty || fremd.isNotEmpty || reihenfolge.length != koepfe.length) {
    throw MoodleFehler('Die Reihenfolge muss genau die HAUPTkapitel enthalten, jedes einmal. '
        '${fehlt.isEmpty ? '' : 'Es fehlt: ${fehlt.join(", ")}. '}'
        '${fremd.isEmpty ? '' : 'Unbekannt oder Unterkapitel: ${fremd.join(", ")}. '}'
        'Unterkapitel wandern mit ihrem Hauptkapitel.\n${_liste(vorher)}');
  }
  if (koepfe.join(',') == reihenfolge.join(',')) return 'Die Reihenfolge stimmt schon -- nichts geändert.';
  final titel = {for (final k in vorher) k.id: k.titel};
  final ja = await freigaben.anfragen(FreigabeAnfrage(
    titel: 'Buch neu ordnen?',
    punkte: [
      'Buch cmid $cmid, Hauptkapitel mit ihren Unterkapiteln',
      'vorher: ${koepfe.map((id) => titel[id]).join(' · ')}',
      'nachher: ${reihenfolge.map((id) => titel[id]).join(' · ')}',
    ],
    vergleich: const [],
    knopf: 'Neu ordnen',
  ));
  if (!ja) return 'Nicht geändert: in der App abgelehnt oder nicht rechtzeitig freigegeben.';
  final ist = [...koepfe];
  var schritte = 0;
  final grenze = reihenfolge.length * reihenfolge.length + 10;
  for (var ziel = 0; ziel < reihenfolge.length; ziel++) {
    final id = reihenfolge[ziel];
    var jetzt = ist.indexOf(id);
    while (jetzt > ziel) {
      await _schritt(moodle, cmid, id, true);
      ist
        ..removeAt(jetzt)
        ..insert(jetzt - 1, id);
      jetzt--;
      if (++schritte > grenze) {
        throw MoodleFehler('Nach $schritte Schritten stimmt die Reihenfolge nicht; abgebrochen. Stand mit buch_lesen ansehen.');
      }
    }
  }
  final nachher = await kapitelLesen(moodle, cmid);
  final reihenfolgeOk = [for (final k in nachher) if (!k.unterkapitel) k.id].join(',') == reihenfolge.join(',');
  final alt = _hierarchie(vorher), neu = _hierarchie(nachher);
  final hierarchieOk = koepfe.every((id) => alt[id] == neu[id]);
  return 'Neu geordnet in $schritte Schritt(en). Reihenfolge stimmt: $reihenfolgeOk; an jedem Hauptkapitel '
      'hängt noch dasselbe: $hierarchieOk. verified: ${reihenfolgeOk && hierarchieOk}\n${_liste(nachher)}';
}
