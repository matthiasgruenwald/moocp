// Die begrenzte Testfreigabe sitzt vor dem echten Werkzeugablauf (E18/E20).
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../freigabe.dart';
import '../moodle/formular_lesen.dart';
import '../moodle/formular_schreiben.dart';
import '../moodle/kurs.dart';
import '../moodle/moodle_zugang.dart';
import '../profil.dart';
import '../testzugang.dart';

typedef _Probe = ({int kurs, String name, String modul, String hash});

class Testbetrieb {
  Testbetrieb(this.moodle, this.freigaben, this.arbeitsordner);
  final MoodleZugang moodle;
  final Freigaben freigaben;
  final String arbeitsordner;
  final _proben = <int, _Probe>{};

  Future<String> _hash(Formular f, int cmid) async {
    final inhalt = <String, Object?>{
      'felder': [
        for (final e in f.felder)
          if (!const {'sesskey', 'submitbutton', 'cancel'}.contains(e.key) &&
              !istEntwurfsId(e.key))
            [e.key, e.value],
      ],
    };
    if (f.modul == 'learningmap') {
      // Die Karte enthält auch eine Datei außerhalb von placestore/svgcode.
      // Nur ihren Namen zu binden ließe einen Austausch des Hintergrunds
      // unbemerkt; die Bytes liest ausschließlich der normale Moodle-Zugang.
      final gelesen = await formularLesen(
        moodle,
        Formularziel.aktivitaet(cmid),
        arbeitsordner,
      );
      final wurzel = p.join(gelesen.ordner, 'bereiche', 'backgroundfile');
      final dateien = Directory(wurzel).existsSync()
          ? Directory(wurzel).listSync(recursive: true).whereType<File>().toList()
          : <File>[];
      dateien.sort((a, b) => a.path.compareTo(b.path));
      final nativeListe = f.bereiche['backgroundfile']?['list'];
      inhalt['backgroundfile'] = {
        'formular': [
          for (final e in (nativeListe as List? ?? const []).whereType<Map>())
            {
              'filepath': e['filepath'],
              'filename': e['filename'],
              'size': e['size'],
              'datemodified': e['datemodified'],
            },
        ],
        'dateien': [
          for (final datei in dateien)
            [
              p.relative(datei.path, from: wurzel).replaceAll(r'\\', '/'),
              sha256.convert(datei.readAsBytesSync()).toString(),
            ],
        ],
        'nichtGelesen': [
          for (final b in gelesen.bereiche.where((b) => b.feld == 'backgroundfile'))
            ...b.nichtGelesen,
        ],
      };
    }
    return sha256.convert(utf8.encode(jsonEncode(inhalt))).toString();
  }

  Future<_Probe?> _probe(int cmid) async {
    final f = await formularHolen(moodle, '/course/modedit.php?update=$cmid');
    if (!const {'page', 'learningmap'}.contains(f.modul) ||
        f.kurs == null ||
        !f.name.startsWith('ZZ')) {
      return null;
    }
    final struktur = await kursLesen(moodle, f.kurs!);
    final aktivitaet = struktur.nachCmid[cmid];
    if (aktivitaet?.sichtbar != false || aktivitaet?.modul != f.modul ||
        aktivitaet?.name != f.name) {
      return null;
    }
    return (
      kurs: f.kurs!,
      name: f.name,
      modul: f.modul!,
      hash: await _hash(f, cmid),
    );
  }

  bool _bindungPasst(Profil profil, Testzugang? zugang) =>
      zugang != null && zugang.passt(profil) && moodle.angemeldet &&
      Testzugang.adresseSchluessel(moodle.basis.toString()) == Testzugang.adresseSchluessel(zugang.adresse);

  Future<String> ausfuehren(
    Profil profil,
    Testzugang? zugang,
    String werkzeug,
    Map<String, dynamic> args,
    Future<String> Function() aufruf,
  ) async {
    if (!_bindungPasst(profil, zugang) || zugang == null) {
      _proben.clear();
      return aufruf();
    }
    if (werkzeug == 'aktivitaet_anlegen' &&
        const {'page', 'learningmap'}.contains(args['typ']) &&
        args['name'] is String &&
        (args['name'] as String).startsWith('ZZ') &&
        args['sichtbar'] != true &&
        zugang.kurse.contains(args['kurs']) &&
        (args['einstellungen'] == null ||
            (args['einstellungen'] as Map).isEmpty)) {
      final vorher = (await kursLesen(
        moodle,
        args['kurs'] as int,
      )).nachCmid.keys.toSet();
      final text = await freigaben.imTest(aufruf, pruefen: () async =>
        _bindungPasst(profil, zugang) && zugang.kurse.contains(args['kurs']));
      if (text.contains('verified: true')) {
        final neu = (await kursLesen(moodle, args['kurs'] as int))
            .nachCmid
            .values
            .where(
              (c) =>
                  !vorher.contains(c.cmid) &&
                  c.modul == args['typ'] &&
                  c.name == args['name'] &&
                  !c.sichtbar,
            )
            .toList();
        if (neu.length == 1) {
          final id = neu.single.cmid;
          final probe = await _probe(id);
          if (probe != null && probe.kurs == args['kurs']) _proben[id] = probe;
        }
      }
      return text;
    }
    int? cmid;
    if (werkzeug == 'aendern' &&
        args['ordner'] is String &&
        (args['einstellungen'] == null ||
            (args['einstellungen'] as Map).isEmpty)) {
      final ziel = Formularziel.ausOrdner(
        imArbeitsordner(args['ordner'] as String, arbeitsordner),
      );
      if (ziel.art == Zielart.aktivitaet) cmid = ziel.id;
    } else if (werkzeug == 'loeschen' && args['abschnitt_id'] == null) {
      cmid = args['cmid'] as int?;
    } else if (werkzeug == 'bildschirmfoto' &&
        zugang.bilder &&
        args['frage'] == null &&
        args['sammlung'] == null &&
        args['kapitel'] == null &&
        args['wikiseite'] == null) {
      cmid = args['cmid'] as int?;
    } else if (werkzeug == 'lernlandkarte_verknuepfungen_setzen') {
      cmid = args['cmid'] as int?;
    }
    final eigene = _proben[cmid];
    if (cmid == null ||
        eigene == null ||
        !moodle.selbstAngelegt.contains(cmid) ||
        !zugang.kurse.contains(eigene.kurs) ||
        ((werkzeug == 'loeschen' &&
                (args['kurs'] != eigene.kurs || args['name'] != eigene.name)) ||
            (werkzeug == 'lernlandkarte_verknuepfungen_setzen' &&
                (eigene.modul != 'learningmap' ||
                    args['name'] != eigene.name)))) {
      return aufruf();
    }
    final frisch = await _probe(cmid);
    if (frisch != eigene) return aufruf();
    final text = await freigaben.imTest(aufruf, pruefen: () async =>
      _bindungPasst(profil, zugang) && _proben[cmid] == eigene &&
      moodle.selbstAngelegt.contains(cmid) && zugang.kurse.contains(eigene.kurs) &&
      await _probe(cmid!) == eigene);
    if (text.contains('verified: true')) {
      if (werkzeug == 'loeschen') {
        _proben.remove(cmid);
      } else if (werkzeug == 'aendern' ||
          werkzeug == 'lernlandkarte_verknuepfungen_setzen') {
        final probe = await _probe(cmid);
        if (probe != null && probe.kurs == eigene.kurs) _proben[cmid] = probe;
      }
    }
    return text;
  }
}
