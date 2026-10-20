part of 'testbetrieb.dart';

// Nur im Speicher dieser App-Sitzung. Ein Dateiname und ein ZZ-Präfix allein
// beweisen keinen Testbesitz; der Hash gehört zu einer eigenen Quellauswahl.
final _eigeneSicherungen =
    <
      String,
      ({
        Testbetrieb quelle,
        bool Function() gueltig,
        List<ArchivAktivitaet> inhalt,
        Map<ArchivAktivitaet, String> staende,
      })
    >{};

extension Testkopien on Testbetrieb {
  void beginnen() => _aktiv = true;

  void beenden() {
    _aktiv = false;
    _proben.clear();
    _uebernommeneVorgaenge.clear();
    _kopierteProben.clear();
    _eigeneSicherungen.removeWhere((_, e) => identical(e.quelle, this));
  }

  Future<List<ArchivAktivitaet>?> _eigeneQuellen(
    Profil profil,
    Testzugang zugang,
    Map<String, dynamic> args,
  ) async {
    if (!_aktiv ||
        !_bindungPasst(profil, zugang) ||
        !zugang.kurse.contains(args['kurs']) ||
        args['datei'] != null ||
        args['ganzer_kurs'] == true ||
        ((args['abschnitte'] as List?)?.isNotEmpty ?? false)) {
      return null;
    }
    final auswahl = args['aktivitaeten'];
    if (auswahl is! List || auswahl.isEmpty) return null;
    final gesehen = <int>{};
    final inhalt = <ArchivAktivitaet>[];
    for (final x in auswahl) {
      if (x is! Map || x['cmid'] is! int) return null;
      final id = x['cmid'] as int;
      final eigen = _proben[id];
      if (!gesehen.add(id) ||
          eigen == null ||
          !(moodle.selbstAngelegt.contains(id) ||
              _kopierteProben.contains(id)) ||
          eigen.kurs != args['kurs'] ||
          eigen.name != x['name'] ||
          await _probe(id) != eigen) {
        return null;
      }
      inhalt.add((modul: eigen.modul, titel: eigen.name));
    }
    return _bindungPasst(profil, zugang) ? inhalt : null;
  }

  Future<bool> _eigenerTransfer(
    Profil profil,
    Testzugang zugang,
    Map<String, dynamic> args,
  ) async {
    final ziele = args['ziele'];
    if (ziele is! List ||
        ziele.isEmpty ||
        ziele.any(
          (z) =>
              z is! Map ||
              !zugang.kurse.contains(z['kurs']) ||
              z['loeschend'] == true ||
              !const {
                'aktueller_kurs_verschmelzen',
                'anderer_kurs_verschmelzen',
              }.contains(z['weg']),
        )) {
      return false;
    }
    return await _eigeneQuellen(profil, zugang, args) != null;
  }

  Future<void> sicherungMerken(
    Profil profil,
    Testzugang? zugang,
    Vorgaenge vorgaenge,
    Vorgang v,
    Map<String, dynamic> args,
  ) async {
    if (zugang == null ||
        v.stand != SicherungStand.fertig ||
        !v.verified ||
        v.kurs != args['kurs']) {
      return;
    }
    final eigen = await _eigeneQuellen(profil, zugang, args);
    if (eigen == null || pfadFehler(v.datei) != null) return;
    vorgaenge.pruefeBindung(v);
    final datei = await _sicherungsDatei(vorgaenge.ordner, v.datei);
    if (datei == null) return;
    if (!await datei.exists() || await datei.length() > archivGrenzeStandard) {
      return;
    }
    final bytes = await datei.readAsBytes();
    final archiv = await archivPruefen(bytes);
    if (!archiv.ok ||
        !_gleicherInhalt(eigen, archiv.aktivitaeten) ||
        !_aktiv ||
        !_bindungPasst(profil, zugang)) {
      return;
    }
    final ids = <int, ArchivAktivitaet>{
      for (final x in args['aktivitaeten'] as List)
        x['cmid'] as int: (
          modul: _proben[x['cmid']]!.modul,
          titel: x['name'] as String,
        ),
    };
    final staende = <ArchivAktivitaet, String>{};
    for (final e in ids.entries) {
      final stand = await _kopierInhalt(e.key, ids);
      if (stand == null) return;
      staende[e.value] = stand;
    }
    if (!_aktiv ||
        !_bindungPasst(profil, zugang) ||
        await _eigeneQuellen(profil, zugang, args) == null) {
      return;
    }
    _eigeneSicherungen[sha256.convert(bytes).toString()] = (
      quelle: this,
      gueltig: () => _aktiv && _bindungPasst(profil, zugang),
      inhalt: List.unmodifiable(eigen),
      staende: Map.unmodifiable(staende),
    );
  }

  Future<bool> _eigeneWiederherstellung(
    Profil profil,
    Testzugang zugang,
    Map<String, dynamic> args,
  ) async {
    if (!_aktiv ||
        !_bindungPasst(profil, zugang) ||
        !zugang.kurse.contains(args['kurs']) ||
        args['loeschend'] == true ||
        args['wiederholung_von'] != null ||
        !const {
          'aktueller_kurs_verschmelzen',
          'anderer_kurs_verschmelzen',
        }.contains(args['weg'])) {
      return false;
    }
    final datei = args['datei'];
    if (datei is! String || pfadFehler(datei) != null) return false;
    final file = await _sicherungsDatei(sicherungsordner, datei);
    if (file == null) return false;
    if (!await file.exists() || await file.length() > archivGrenzeStandard) {
      return false;
    }
    final eigen =
        _eigeneSicherungen[sha256.convert(await file.readAsBytes()).toString()];
    return eigen != null && eigen.gueltig() && _bindungPasst(profil, zugang);
  }

  Future<bool> kopienErfassen(
    Profil profil,
    Testzugang? zugang,
    Vorgaenge vorgaenge,
    String? id,
  ) async {
    if (!_aktiv ||
        zugang == null ||
        !_bindungPasst(profil, zugang) ||
        id == null ||
        _uebernommeneVorgaenge.contains(id)) {
      return false;
    }
    final v = await vorgaenge.finde(id);
    if (v == null ||
        v.wiederherstellung != WiederherstellungStand.fertig ||
        !zugang.kurse.contains(v.kurs) ||
        v.vorherCmids == null ||
        v.wiederherstellungAktivitaeten == null) {
      return false;
    }
    vorgaenge.pruefeBindung(v);
    final eigen = _eigeneSicherungen[v.fingerabdruck?.split('|').first];
    if (eigen == null ||
        !eigen.gueltig() ||
        !_gleicherInhalt(eigen.inhalt, v.wiederherstellungAktivitaeten!)) {
      return false;
    }
    final struktur = await kursLesen(moodle, v.kurs);
    final cmids = importierteCmidsEindeutig(
      erwartet: eigen.inhalt,
      vorher: v.vorherCmids!.toSet(),
      aktuell: [
        for (final x in struktur.nachCmid.values)
          (cmid: x.cmid, modul: x.modul, titel: x.name),
      ],
    );
    if (cmids == null) return false;
    final ids = <int, ArchivAktivitaet>{
      for (final cmid in cmids)
        cmid: (
          modul: struktur.nachCmid[cmid]!.modul,
          titel: struktur.nachCmid[cmid]!.name,
        ),
    };
    final proben = <int, _Probe>{};
    for (final e in ids.entries) {
      final probe = await _probe(e.key);
      if (probe == null || probe.kurs != v.kurs) return false;
      // Vollständiger eigener Inhaltsnachweis, unabhängig von generischen
      // Restore-Prüflücken. Änderungen während des Lesens werden abgewiesen.
      if (await _kopierInhalt(e.key, ids) != eigen.staende[e.value] ||
          await _probe(e.key) != probe) {
        return false;
      }
      proben[e.key] = probe;
    }
    vorgaenge.pruefeBindung(v);
    if (!_aktiv ||
        !_bindungPasst(profil, zugang) ||
        !eigen.gueltig() ||
        !identical(
          _eigeneSicherungen[v.fingerabdruck?.split('|').first],
          eigen,
        )) {
      return false;
    }
    _proben.addAll(proben);
    _kopierteProben.addAll(proben.keys);
    _uebernommeneVorgaenge.add(id);
    return true;
  }

  Future<String?> _kopierInhalt(
    int cmid,
    Map<int, ArchivAktivitaet> ids,
  ) async {
    final f = await formularHolen(moodle, '/course/modedit.php?update=$cmid');
    return _mitProbe(cmid, (gelesen) async {
      final dateien = await _dateienStand(gelesen);
      if (dateien == null) return null;
      final felder = <String, List<String>>{};
      const technisch = {
        'sesskey',
        'submitbutton',
        'submitbutton2',
        'cancel',
        'course',
        'coursemodule',
        'section',
        'module',
        'instance',
        'add',
        'update',
        'return',
        'sr',
        'beforemod',
        'showonly',
        'placestore',
        'svgcode',
      };
      for (final e in f.felder) {
        if (technisch.contains(e.key) ||
            istEntwurfsId(e.key) ||
            _ausgeschalteterTermin(f, e.key) ||
            e.key.startsWith('mform_isexpanded_') ||
            e.key.endsWith('[text]')) {
          continue;
        }
        (felder[e.key] ??= []).add(e.value);
      }
      final geordnet = {
        for (final k in felder.keys.toList()..sort()) k: felder[k],
      };
      Object? karte;
      if (f.modul == 'learningmap') {
        final daten = lernlandkarteLesen(f.form);
        if (daten == null) return null;
        final store = Map<String, dynamic>.from(daten['placestore'] as Map)
          ..remove('mapid');
        store.putIfAbsent('version', () => 2024072201);
        store.putIfAbsent('strokeopacity', () => 1);
        for (final ort in (store['places'] as List).cast<Map>()) {
          final ziel = (ort['linkedActivity'] as num?)?.toInt() ?? 0;
          if (ziel != 0 && !ids.containsKey(ziel)) return null;
          ort['linkedActivity'] = ziel == 0
              ? null
              : [ids[ziel]!.modul, ids[ziel]!.titel];
        }
        karte = [ohneOrtsbeschriftung(daten['svgcode']), store];
      }
      // JSON-Schlüssel unabhängig von der Reihenfolge im Moodle-Formular vergleichen.
      Object? sortiert(Object? x) => x is Map
          ? {
              for (final k in x.keys.map((k) => '$k').toList()..sort())
                k: sortiert(x[k]),
            }
          : x is List
          ? x.map(sortiert).toList()
          : x;
      return jsonEncode(
        sortiert([
          geordnet,
          {for (final feld in gelesen.felder) feld.feld: feld.html},
          karte,
          dateien,
        ]),
      );
    });
  }
}

bool _gleicherInhalt(List<ArchivAktivitaet> a, List<ArchivAktivitaet> b) =>
    a.length == b.length &&
    a.toSet().length == a.length &&
    a.toSet().containsAll(b) &&
    b.toSet().length == b.length;

Future<File?> _sicherungsDatei(String ordner, String name) async {
  if (pfadFehler(name) != null || !name.endsWith('.mbz')) return null;
  final datei = File(p.join(ordner, name));
  if (!await datei.exists()) return null;
  final wurzel = await Directory(ordner).resolveSymbolicLinks();
  final pfad = await datei.resolveSymbolicLinks();
  return p.isWithin(wurzel, pfad) ? File(pfad) : null;
}
