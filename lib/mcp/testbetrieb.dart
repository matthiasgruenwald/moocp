// Die begrenzte Testfreigabe sitzt vor dem echten Werkzeugablauf (E18/E20).
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../freigabe.dart';
import '../moodle/formular_lesen.dart';
import '../moodle/formular_schreiben.dart';
import '../moodle/kurs.dart';
import '../moodle/lernlandkarte.dart';
import '../moodle/moodle_zugang.dart';
import '../moodle/sicherung.dart';
import '../moodle/sicherung_regeln.dart';
import '../moodle/wiederherstellung_regeln.dart';
import '../profil.dart';
import '../testzugang.dart';

part 'testkopien.dart';

typedef _Probe = ({int kurs, String name, String modul, String hash});

class Testbetrieb {
  Testbetrieb(
    this.moodle,
    this.freigaben,
    this.arbeitsordner,
    this.sicherungsordner,
  );
  final MoodleZugang moodle;
  final Freigaben freigaben;
  final String arbeitsordner;
  final String sicherungsordner;
  final _proben = <int, _Probe>{};
  final _uebernommeneVorgaenge = <String>{};
  final _kopierteProben = <int>{};
  bool _aktiv = true;

  Future<String?> _hash(Formular f, int cmid) =>
      _mitProbe(cmid, (gelesen) async {
        final dateien = await _dateienStand(gelesen);
        if (dateien == null) return null;
        return sha256
            .convert(
              utf8.encode(
                jsonEncode({
                  'felder': [
                    for (final e in f.felder)
                      if (!const {
                            'sesskey',
                            'submitbutton',
                            'cancel',
                          }.contains(e.key) &&
                          !istEntwurfsId(e.key) &&
                          !_ausgeschalteterTermin(f, e.key))
                        [e.key, normalisiert(e.value)],
                  ],
                  'dateien': dateien,
                }),
              ),
            )
            .toString();
      });

  // Besitzprüfungen dürfen den bearbeiteten Benutzerentwurf niemals neu lesen
  // oder löschen. Jede Probe bekommt einen eigenen, kurzlebigen Leseordner.
  Future<T> _mitProbe<T>(
    int cmid,
    Future<T> Function(FormularGelesen) pruefen,
  ) async {
    final temp = await Directory.systemTemp.createTemp('moocp-testprobe-');
    try {
      return await pruefen(
        await formularLesen(moodle, Formularziel.aktivitaet(cmid), temp.path),
      );
    } finally {
      await temp.delete(recursive: true);
    }
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
    if (aktivitaet?.sichtbar != false ||
        aktivitaet?.modul != f.modul ||
        aktivitaet?.name != f.name) {
      return null;
    }
    final hash = await _hash(f, cmid);
    if (hash == null) return null;
    return (kurs: f.kurs!, name: f.name, modul: f.modul!, hash: hash);
  }

  bool _bindungPasst(Profil profil, Testzugang? zugang) =>
      zugang != null &&
      zugang.passt(profil) &&
      moodle.angemeldet &&
      Testzugang.adresseSchluessel(moodle.basis.toString()) ==
          Testzugang.adresseSchluessel(zugang.adresse);

  Future<String> ausfuehren(
    Profil profil,
    Testzugang? zugang,
    String werkzeug,
    Map<String, dynamic> args,
    Future<String> Function() aufruf,
  ) async {
    if (!_bindungPasst(profil, zugang) || zugang == null) {
      _proben.clear();
      _kopierteProben.clear();
      _uebernommeneVorgaenge.clear();
      _eigeneSicherungen.removeWhere((_, e) => identical(e.quelle, this));
      return aufruf();
    }
    if (werkzeug == 'uebertragen' &&
        await _eigenerTransfer(profil, zugang, args)) {
      return freigaben.imTest(
        aufruf,
        pruefen: () => _eigenerTransfer(profil, zugang, args),
      );
    }
    if (werkzeug == 'wiederherstellen_datei' &&
        await _eigeneWiederherstellung(profil, zugang, args)) {
      return freigaben.imTest(
        aufruf,
        pruefen: () => _eigeneWiederherstellung(profil, zugang, args),
      );
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
      final text = await freigaben.imTest(
        aufruf,
        pruefen: () async =>
            _bindungPasst(profil, zugang) &&
            zugang.kurse.contains(args['kurs']),
      );
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
        !(moodle.selbstAngelegt.contains(cmid) ||
            _kopierteProben.contains(cmid)) ||
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
    final text = await freigaben.imTest(
      aufruf,
      pruefen: () async =>
          _bindungPasst(profil, zugang) &&
          _proben[cmid] == eigene &&
          (moodle.selbstAngelegt.contains(cmid) ||
              _kopierteProben.contains(cmid)) &&
          zugang.kurse.contains(eigene.kurs) &&
          await _probe(cmid!) == eigene,
    );
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

// Moodle füllt die deaktivierte Terminerinnerung bei jedem GET mit „jetzt“.
// Ihr Schalter bleibt Teil des Standes; nur unwirksame Datumswerte entfallen.
bool _ausgeschalteterTermin(Formular f, String key) =>
    key.startsWith('completionexpected[') &&
    key != 'completionexpected[enabled]' &&
    !f.felder.any(
      (e) =>
          e.key == 'completionexpected[enabled]' &&
          const {'1', 'on'}.contains(e.value),
    );

Future<Map<String, String>?> _dateienStand(FormularGelesen gelesen) async {
  if (gelesen.fehlend.isNotEmpty ||
      gelesen.bereiche.any((b) => b.nichtGelesen.isNotEmpty)) {
    return null;
  }
  final dateien = <String, String>{};
  for (final name in ['dateien', 'bereiche']) {
    final wurzel = Directory(p.join(gelesen.ordner, name));
    if (!wurzel.existsSync()) continue;
    for (final file in wurzel.listSync(recursive: true).whereType<File>()) {
      dateien[p
          .relative(file.path, from: gelesen.ordner)
          .replaceAll(r'\', '/')] = sha256
          .convert(await file.readAsBytes())
          .toString();
    }
  }
  return {
    for (final name in dateien.keys.toList()..sort()) name: dateien[name]!,
  };
}
