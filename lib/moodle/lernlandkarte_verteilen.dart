// Lernlandkarten beim Verteilen eines Themas.
//
// Reihenfolge je Auftrag:
//   1. Vor dem Kopieren: die Karten der Auswahl und ihre Verweisziele im
//      Quellkurs erfassen ([kartenErfassen]).
//   2. Das Thema wird in den Zielkurs kopiert (wiederherstellung.dart); die App
//      verbirgt die eindeutig belegten Kopien.
//   3. Je Zielkurs: aus dem tatsächlichen Kopiervorgang die Quell-/Ziel-
//      Zuordnung ableiten ([kartenZuordnen]) und die Karte dort abschließend
//      neu verknüpfen ([kartenVerknuepfen]).
//
// Als Nachweis für „diese Aktivität im Ziel ist die Kopie jener im Quellkurs"
// gilt allein: Die Aktivität ist in diesem Zielkurs durch genau diesen Vorgang
// neu entstanden (nicht in den Nummern vor dem Start) und passt in Typ und
// Titel eindeutig zu einem Eintrag des Archivs und der Quellerfassung, und alle
// neuen Aktivitäten lassen sich 1:1 dem Archiv zuordnen
// ([importierteCmidsEindeutig]). Alte Nummern, die Nummern eines anderen Ziels
// und gleich benannte Aktivitäten, die schon vorher im Zielkurs standen, sind
// kein Nachweis. Mehrdeutige Zuordnungen bleiben offen.
//
// Was sich so nicht belegen lässt, bleibt als konkrete ungelöste Zuordnung
// stehen. Die App kopiert dafür nichts zusätzlich und entscheidet nicht
// fachlich; die Lehrkraft entscheidet, danach gilt
// lernlandkarte_verknuepfungen_setzen.

import 'dart:convert';

import '../freigabe.dart';
import '../uebertragung_lauf.dart';
import 'formular_lesen.dart';
import 'formular_schreiben.dart';
import 'kurs.dart';
import 'lernlandkarte.dart';
import 'moodle_zugang.dart';
import 'wiederherstellung_regeln.dart';

/// Ein verknüpfter Ort der Quellkarte, vor dem Kopieren erfasst.
/// [mitkopiert] ist wahr, wenn das Ziel zur Auswahl des Auftrags gehört.
class KartenOrt {
  const KartenOrt(
    this.ort,
    this.quellZiel,
    this.zielName,
    this.zielModul,
    this.mitkopiert, {
    this.idnummer,
    this.formularstand,
  });

  final String ort;
  final int quellZiel;
  final String? zielName;
  final String? zielModul;
  final bool mitkopiert;
  final String? idnummer;
  final String? formularstand;
}

/// Eine Karte der Auswahl im Quellkurs mit ihren verknüpften Orten.
class KartenQuelle {
  const KartenQuelle(
    this.cmid,
    this.name,
    this.orte,
    this.stand,
    this.daten,
    this.formularstand,
    this.idnummer,
  );

  final int cmid;
  final String name;
  final List<KartenOrt> orte;
  final String stand;
  final Map<String, Object?> daten;
  final String? formularstand;
  final String? idnummer;
}

String? _idnummer(Formular form) {
  final wert = wertIn(form.felder, 'cmidnumber')?.trim();
  return wert == null || wert.isEmpty ? null : wert;
}

/// Liest die Lernlandkarten der Auswahl und ihre Verweisziele im Quellkurs.
/// [aktivitaeten] und [abschnitte] sind die Angaben des Auftrags; mit
/// [ganzerKurs] gehört alles dazu. Nur lesend. Eine Karte, deren Kartendaten
/// sich nicht lesen lassen, bricht den Auftrag ab, bevor etwas geschieht.
Future<List<KartenQuelle>> kartenErfassen(
  MoodleZugang moodle, {
  required String arbeitsordner,
  required int kurs,
  required List<int> aktivitaeten,
  required List<int> abschnitte,
  required bool ganzerKurs,
}) async {
  final struktur = await kursLesen(moodle, kurs);
  final gewaehlt = ganzerKurs
      ? struktur.nachCmid.keys.toSet()
      : {
          ...aktivitaeten,
          for (final id in abschnitte)
            if (struktur.nachId[id] != null)
              ...struktur.inhalt(struktur.nachId[id]!).map((a) => a.cmid),
        };
  final karten = <KartenQuelle>[];
  for (final cmid in gewaehlt.toList()..sort()) {
    final a = struktur.nachCmid[cmid];
    if (a == null || a.modul != 'learningmap') continue;
    final form = await formularHolen(
      moodle,
      Formularziel.aktivitaet(cmid).adresse,
    );
    if (form.modul != 'learningmap' ||
        form.kurs != kurs ||
        form.name != a.name) {
      throw MoodleFehler(
        'Die Aktivität „${a.name}" (cmid $cmid) ist keine lesbare Lernlandkarte. Nichts geändert.',
      );
    }
    final daten = lernlandkarteLesen(form.form);
    if (daten == null) {
      throw MoodleFehler(
        'Die Lernlandkarte „${a.name}" (cmid $cmid) hat keine lesbaren Kartendaten. Nichts geändert.',
      );
    }
    String? formularstand;
    try {
      formularstand = formularInhaltsstand(
        await formularLesen(
          moodle,
          Formularziel.aktivitaet(cmid),
          arbeitsordner,
        ),
      );
    } on MoodleFehler {
      // Nicht lesbar bleibt als Prüflücke gespeichert.
    }
    final idnummer = _idnummer(form);
    final zielBelege = <int, ({String? idnummer, String? stand})>{};
    final orte = <KartenOrt>[];
    for (final o in (daten['orte'] as List).whereType<Map>()) {
      final ziel = (o['linkedActivity'] as num?)?.toInt();
      if (ziel == null || ziel == 0) continue;
      final z = struktur.nachCmid[ziel];
      String? zielIdnummer;
      String? zielFormularstand;
      if (z != null && z.modul != 'learningmap' && gewaehlt.contains(ziel)) {
        if (!zielBelege.containsKey(ziel)) {
          try {
            final zielForm = await formularHolen(
              moodle,
              Formularziel.aktivitaet(ziel).adresse,
            );
            final zielLesung = await formularLesen(
              moodle,
              Formularziel.aktivitaet(ziel),
              arbeitsordner,
            );
            zielBelege[ziel] = (
              idnummer: _idnummer(zielForm),
              stand: formularInhaltsstand(zielLesung),
            );
          } on MoodleFehler {
            zielBelege[ziel] = (idnummer: null, stand: null);
          }
        }
        final beleg = zielBelege[ziel]!;
        zielIdnummer = beleg.idnummer;
        zielFormularstand = beleg.stand;
      }
      orte.add(
        KartenOrt(
          '${o['id']}',
          ziel,
          z?.name,
          z?.modul,
          z != null && z.modul != 'learningmap' && gewaehlt.contains(ziel),
          idnummer: zielIdnummer,
          formularstand: zielFormularstand,
        ),
      );
    }
    final stand = jsonEncode([
      for (final id in gewaehlt.toList()..sort())
        [id, struktur.nachCmid[id]?.modul, struktur.nachCmid[id]?.name],
      daten,
    ]);
    karten.add(
      KartenQuelle(cmid, a.name, orte, stand, daten, formularstand, idnummer),
    );
  }
  final auswahl = [
    for (final id in gewaehlt)
      if (struktur.nachCmid[id] != null) struktur.nachCmid[id]!,
  ];
  if (karten.isNotEmpty &&
      auswahl.map((a) => '${a.modul}\u0000${a.name}').toSet().length !=
          auswahl.length) {
    throw MoodleFehler(
      'Die ausgewählten Aktivitäten lassen sich nicht eindeutig 1:1 zuordnen '
      '(gleiche Art und gleicher Name). Nichts übertragen; Auswahl eindeutig benennen.',
    );
  }
  return karten;
}

/// Ein Ort einer kopierten Karte: das belegte neue Ziel oder der Grund, warum es
/// ungelöst bleibt.
class OrtZuordnung {
  const OrtZuordnung(
    this.ort,
    this.quellZiel,
    this.zielName, {
    this.neuesZiel,
    this.grund,
  });

  final String ort;
  final int quellZiel;
  final String? zielName;
  final int? neuesZiel;
  final String? grund;
}

/// Die Zuordnung einer Karte in einem Zielkurs. [zielKarte] ist null, wenn die
/// Kopie der Karte nicht belegt ist.
class KartenZuordnung {
  const KartenZuordnung(this.quelle, this.zielKarte, this.orte, {this.grund});

  final KartenQuelle quelle;
  final int? zielKarte;
  final List<OrtZuordnung> orte;

  /// Warum die Karte als Ganzes nicht belegt ist.
  final String? grund;

  List<OrtZuordnung> get ungeloest => [
    for (final o in orte)
      if (o.neuesZiel == null) o,
  ];
}

/// Identitäts- und Inhaltsbeleg, frisch aus dem Zielkurs gelesen.
class KartenBeleg {
  const KartenBeleg({
    required this.idnummer,
    required this.formularstand,
    this.kartendaten,
  });

  final String? idnummer;
  final String? formularstand;
  final Map<String, Object?>? kartendaten;
}

/// Ordnet nur neue Aktivitäten mit gleicher eindeutiger cmidnumber und gleichem
/// vollständigen Formularinhalt zu. Titel und Sortierung reichen nicht.
List<KartenZuordnung> kartenZuordnen(
  List<KartenQuelle> karten, {
  required Set<int> vorher,
  required List<WiederhergestellteAktivitaet> aktuell,
  required Map<int, KartenBeleg> belege,
}) {
  final quellen = <int, ({String modul, String titel, KartenBeleg beleg})>{};
  for (final k in karten) {
    quellen[k.cmid] = (
      modul: 'learningmap',
      titel: k.name,
      beleg: KartenBeleg(
        idnummer: k.idnummer,
        formularstand: k.formularstand,
        kartendaten: k.daten,
      ),
    );
    for (final o in k.orte) {
      if (!o.mitkopiert || o.zielModul == null || o.zielName == null) continue;
      quellen[o.quellZiel] = (
        modul: o.zielModul!,
        titel: o.zielName!,
        beleg: KartenBeleg(
          idnummer: o.idnummer,
          formularstand: o.formularstand,
        ),
      );
    }
  }
  final idnummern = <String, Set<int>>{};
  for (final e in quellen.entries) {
    final nummer = e.value.beleg.idnummer;
    if (nummer != null) idnummern.putIfAbsent(nummer, () => {}).add(e.key);
  }
  List<int> passendeZiele(int cmid) {
    final quelle = quellen[cmid]!;
    final nummer = quelle.beleg.idnummer;
    final stand = quelle.beleg.formularstand;
    if (nummer == null || stand == null || idnummern[nummer]?.length != 1) {
      return const [];
    }
    return [
      for (final a in aktuell)
        if (!vorher.contains(a.cmid) &&
            a.modul == quelle.modul &&
            a.titel == quelle.titel &&
            belege[a.cmid]?.idnummer == nummer &&
            belege[a.cmid]?.formularstand == stand &&
            (quelle.modul != 'learningmap' ||
                (belege[a.cmid]?.kartendaten != null &&
                    belege[a.cmid]!.kartendaten!['svgcode'] ==
                        quelle.beleg.kartendaten!['svgcode'] &&
                    _gleicherKartenInhalt(
                      belege[a.cmid]!.kartendaten!,
                      quelle.beleg.kartendaten!,
                    ))))
          a.cmid,
    ];
  }

  bool identitaetImZiel(int cmid) {
    final quelle = quellen[cmid]!;
    final nummer = quelle.beleg.idnummer;
    return nummer != null &&
        idnummern[nummer]?.length == 1 &&
        aktuell.any(
          (a) =>
              !vorher.contains(a.cmid) &&
              a.modul == quelle.modul &&
              a.titel == quelle.titel &&
              belege[a.cmid]?.idnummer == nummer,
        );
  }

  return [
    for (final k in karten)
      () {
        final passendeKarten = passendeZiele(k.cmid);
        final kopie = passendeKarten.length == 1 ? passendeKarten.single : null;
        final grund = k.idnummer == null || k.formularstand == null
            ? 'Die Quellkarte hat keine eindeutige cmidnumber oder keinen vollständigen Inhaltsbeleg.'
            : passendeKarten.length > 1
            ? 'Mehrere neue Lernlandkarten haben denselben Identitäts- und Inhaltsbeleg.'
            : identitaetImZiel(k.cmid)
            ? 'Die Aktivität hat dieselbe eindeutige cmidnumber, aber Formularinhalte oder Kartendaten weichen von der Quelle ab.'
            : 'Die Kartenkopie ist nicht durch eine eindeutige cmidnumber und übereinstimmende Formularinhalte belegt.';
        return KartenZuordnung(k, kopie, [
          for (final o in k.orte)
            if (kopie == null)
              OrtZuordnung(o.ort, o.quellZiel, o.zielName, grund: grund)
            else if (!o.mitkopiert || o.zielName == null || o.zielModul == null)
              OrtZuordnung(
                o.ort,
                o.quellZiel,
                o.zielName,
                grund: o.zielName == null
                    ? 'Das Ziel gibt es im Quellkurs nicht mehr.'
                    : 'Das Ziel gehört nicht zur kopierten Auswahl.',
              )
            else
              () {
                final passende = passendeZiele(o.quellZiel);
                final neu = passende.length == 1 ? passende.single : null;
                return neu == null
                    ? OrtZuordnung(
                        o.ort,
                        o.quellZiel,
                        o.zielName,
                        grund: o.idnummer == null || o.formularstand == null
                            ? 'Das Ziel hat keinen eindeutigen cmidnumber- und Inhaltsbeleg.'
                            : passende.length > 1
                            ? 'Mehrere neue Aktivitäten belegen das Ziel identisch.'
                            : 'Das Ziel ist nicht mit übereinstimmendem Inhalt belegt.',
                      )
                    : OrtZuordnung(
                        o.ort,
                        o.quellZiel,
                        o.zielName,
                        neuesZiel: neu,
                      );
              }(),
        ], grund: kopie == null ? grund : null);
      }(),
  ];
}

Map<String, int?> _verknuepfungen(Map<String, Object?> karte) => {
  for (final o in (karte['orte'] as List).whereType<Map>())
    '${o['id']}': (o['linkedActivity'] as num?)?.toInt(),
};

// Ortsbeschriftungen setzt Moodle neu; Geometrie und übrige Kartendaten müssen gleich bleiben.
String _kartenInhalt(Map<String, Object?> karte) {
  final store = Map<String, dynamic>.from(karte['placestore'] as Map)
    ..remove('mapid')
    ..remove('version');
  // Beim Wiederherstellen gemessen: neue mapid, ergänzte Formatversion und
  // strokeopacity=1. Nur fehlende Deckkraft entspricht dem Standardwert 1.
  store.putIfAbsent('strokeopacity', () => 1);
  store['places'] = [
    for (final ort in (store['places'] as List).cast<Map>())
      Map<String, dynamic>.from(ort)..remove('linkedActivity'),
  ];
  return jsonEncode([
    ohneOrtsbeschriftung(karte['svgcode']),
    _kanonischeMap(store),
  ]);
}

Map<String, Object?> _kanonischeMap(Map<dynamic, dynamic> quelle) => {
  for (final key in quelle.keys.toList()..sort((a, b) => '$a'.compareTo('$b')))
    '$key': switch (quelle[key]) {
      final Map m => _kanonischeMap(m),
      final List l => [
        for (final eintrag in l)
          if (eintrag is Map) _kanonischeMap(eintrag) else eintrag,
      ],
      final wert => wert,
    },
};

bool _gleicherKartenInhalt(Map<String, Object?> a, Map<String, Object?> b) {
  final av = (a['placestore'] as Map)['version'];
  final bv = (b['placestore'] as Map)['version'];
  return (av == null || bv == null || av == bv) &&
      _kartenInhalt(a) == _kartenInhalt(b);
}

/// Verknüpft eine kopierte Karte im Zielkurs [kurs] auf die belegten Ziele und
/// liest zurück. Ungelöste Orte bleiben unverändert; die Karte gilt dann als
/// „offen". Die Sichtbarkeit fasst die Funktion nie an. Die Freigabe der
/// Änderung holt [lernlandkarteVerknuepfungenSetzen] selbst.
Future<KartenErgebnis> kartenVerknuepfen(
  MoodleZugang moodle,
  Freigaben freigaben, {
  required String arbeitsordner,
  required int kurs,
  required KartenZuordnung zuordnung,
  required void Function() pruefeBindung,
}) async {
  pruefeBindung();
  final name = zuordnung.quelle.name;
  final karte = zuordnung.zielKarte;
  String ungeloest(List<OrtZuordnung> liste) => liste
      .map(
        (o) =>
            'Ort ${o.ort} (Quellziel „${o.zielName ?? 'cmid ${o.quellZiel}'}"): ${o.grund}',
      )
      .join('; ');
  if (karte == null) {
    return KartenErgebnis(
      KartenStand.offen,
      '„$name": ${zuordnung.grund} Die Kopie und ihre Sichtbarkeit sind nicht belegt; in Moodle prüfen. Nichts verknüpft. '
      'Ungelöst: ${ungeloest(zuordnung.ungeloest)}.',
    );
  }
  final ziel = Formularziel.aktivitaet(karte);
  Map<String, int?> aktuell;
  Map<String, Object?> daten;
  try {
    final form = await formularHolen(moodle, ziel.adresse);
    if (form.modul != 'learningmap' || form.kurs != kurs) {
      return KartenErgebnis(
        KartenStand.offen,
        '„$name": Die kopierte Karte (cmid $karte) gehört nicht zu Kurs $kurs oder ist keine Lernlandkarte. Nichts geändert.',
      );
    }
    daten =
        lernlandkarteLesen(form.form) ??
        (throw MoodleFehler(
          'Die kopierte Karte hat keine lesbaren Kartendaten.',
        ));
    aktuell = _verknuepfungen(daten);
  } on MoodleFehler catch (e) {
    return KartenErgebnis(
      KartenStand.offen,
      '„$name": Die kopierte Karte (cmid $karte) ist nicht lesbar: ${e.meldung} Nichts geändert.',
    );
  }

  final quellFormularstand = zuordnung.quelle.formularstand;
  if (quellFormularstand == null) {
    return KartenErgebnis(
      KartenStand.offen,
      '„$name": Das Quellformular einschließlich Dateien ist nicht vollständig lesbar (Prüflücke). Nichts verknüpft.',
    );
  }
  final zielFormularstand = formularInhaltsstand(
    await formularLesen(moodle, ziel, arbeitsordner),
  );
  if (zielFormularstand == null || zielFormularstand != quellFormularstand) {
    return KartenErgebnis(
      KartenStand.offen,
      '„$name": Kartendaten oder Formularfelder weichen von der Quellerfassung ab. Nichts verknüpft; Karte in Moodle prüfen.',
    );
  }

  final quellLinks = _verknuepfungen(zuordnung.quelle.daten);
  final soll = {
    ...quellLinks,
    for (final o in zuordnung.orte)
      if (o.neuesZiel != null) o.ort: o.neuesZiel,
  };
  if (!_gleicherKartenInhalt(daten, zuordnung.quelle.daten) ||
      aktuell.length != quellLinks.length ||
      aktuell.keys.any(
        (id) =>
            !quellLinks.containsKey(id) ||
            (aktuell[id] != quellLinks[id] && aktuell[id] != soll[id]),
      )) {
    return KartenErgebnis(
      KartenStand.offen,
      '„$name": Kartendaten oder Ortsziele weichen von der Quellerfassung ab. '
      'Nichts verknüpft; Karte in Moodle prüfen.',
    );
  }

  // Orte, die in der Kopie fehlen, sind ungelöst; die übrigen belegten werden gesetzt.
  final offen = <OrtZuordnung>[];
  final setzen = <OrtZuordnung>[];
  for (final o in zuordnung.orte) {
    if (o.neuesZiel == null) {
      offen.add(o);
    } else if (!aktuell.containsKey(o.ort)) {
      offen.add(
        OrtZuordnung(
          o.ort,
          o.quellZiel,
          o.zielName,
          grund: 'Der Ort fehlt in der kopierten Karte.',
        ),
      );
    } else {
      setzen.add(o);
    }
  }
  final aendern = [
    for (final o in setzen)
      if ((aktuell[o.ort] ?? 0) != o.neuesZiel) o,
  ];
  final alsKarte = 'Lernlandkarte „$name" (cmid $karte)';
  if (!await _verborgen(moodle, kurs, karte)) {
    return KartenErgebnis(
      KartenStand.offen,
      '$alsKarte: Die Karte ist nicht nachweislich verborgen. '
      'Nichts verknüpft; Sichtbarkeit in Moodle prüfen.',
    );
  }

  if (aendern.isNotEmpty) {
    final struktur = await kursLesen(moodle, kurs);
    final zielName = struktur.nachCmid[karte]?.name;
    if (zielName == null) {
      return KartenErgebnis(
        KartenStand.offen,
        '„$name": Die kopierte Karte (cmid $karte) steht nicht im Zielkurs. Nichts geändert.',
      );
    }
    String antwort;
    try {
      pruefeBindung();
      antwort = await lernlandkarteVerknuepfungenSetzen(
        moodle,
        freigaben,
        arbeitsordner: arbeitsordner,
        cmid: karte,
        name: zielName,
        pruefeBindung: pruefeBindung,
        zuordnungen: [
          for (final o in aendern)
            {'ort': o.ort, 'aktuell': aktuell[o.ort] ?? 0, 'ziel': o.neuesZiel},
        ],
      );
    } on MoodleFehler catch (e) {
      pruefeBindung();
      return await _nachFehler(moodle, karte, name, aktuell, e.meldung);
    }
    if (!antwort.contains('verified: true')) {
      final abgelehnt = antwort.startsWith('Nicht gespeichert');
      return KartenErgebnis(
        abgelehnt ? KartenStand.offen : KartenStand.unklar,
        '$alsKarte: ${abgelehnt ? 'nicht freigegeben, nichts geändert' : 'Rücklesen ohne verified: true'}. '
        '${abgelehnt ? '' : 'Die Karte in Moodle prüfen. '}'
        '${offen.isEmpty ? '' : 'Ungelöst: ${ungeloest(offen)}.'}',
        freigabeAbgelehnt: abgelehnt,
      );
    }
  }

  // Eigene Rückleseprobe, unabhängig vom Werkzeug: jedes belegte Ziel steht jetzt in der Karte.
  Map<String, int?> jetzt;
  try {
    pruefeBindung();
    final form = await formularHolen(moodle, ziel.adresse);
    final rueck =
        lernlandkarteLesen(form.form) ??
        (throw MoodleFehler('Kartendaten fehlen.'));
    if (form.kurs != kurs ||
        form.modul != 'learningmap' ||
        !_gleicherKartenInhalt(rueck, zuordnung.quelle.daten) ||
        formularInhaltsstand(
              await formularLesen(moodle, ziel, arbeitsordner),
            ) !=
            quellFormularstand) {
      return KartenErgebnis(
        KartenStand.unklar,
        '$alsKarte: Kartendaten stimmen beim Zurücklesen nicht überein.',
      );
    }
    jetzt = _verknuepfungen(rueck);
  } on MoodleFehler {
    return KartenErgebnis(
      KartenStand.unklar,
      '$alsKarte: Das Zurücklesen ist nicht gelungen. Die Karte in Moodle prüfen.',
    );
  }
  final falsch = [
    for (final id in {...soll.keys, ...jetzt.keys})
      if (!soll.containsKey(id) ||
          !jetzt.containsKey(id) ||
          jetzt[id] != soll[id])
        id,
  ];
  if (falsch.isNotEmpty) {
    return KartenErgebnis(
      KartenStand.unklar,
      '$alsKarte: Beim Zurücklesen stimmt Ort ${falsch.join(', ')} nicht mit dem belegten Ziel überein.',
    );
  }
  pruefeBindung();
  final weiterhinVerborgen = await _verborgen(moodle, kurs, karte);
  final stand = offen.isEmpty && weiterhinVerborgen
      ? KartenStand.verknuepft
      : KartenStand.offen;
  final gesetzt = setzen.isEmpty
      ? 'keine Verknüpfung zu setzen'
      : '${setzen.length} ${setzen.length == 1 ? 'Ort' : 'Orte'} auf die Kopien im Zielkurs verknüpft und zurückgelesen';
  return KartenErgebnis(
    stand,
    '$alsKarte: $gesetzt. '
    '${offen.isEmpty ? '' : 'Ungelöst, die Karte bleibt unverifiziert: ${ungeloest(offen)}. '}'
    '${weiterhinVerborgen ? 'Die Karte bleibt verborgen; sichtbar machen ist eine eigene Entscheidung.' : 'ACHTUNG: Die Karte ist sichtbar. Prüfen und gegebenenfalls verbergen.'}',
  );
}

Future<bool> _verborgen(MoodleZugang moodle, int kurs, int karte) async {
  final k = (await kursLesen(moodle, kurs)).nachCmid[karte];
  return k != null && !k.sichtbar;
}

/// Nach einem Fehler beim Schreiben: frisch lesen und sagen, was in der Karte steht.
Future<KartenErgebnis> _nachFehler(
  MoodleZugang moodle,
  int karte,
  String name,
  Map<String, int?> vorher,
  String meldung,
) async {
  try {
    final form = await formularHolen(
      moodle,
      Formularziel.aktivitaet(karte).adresse,
    );
    final jetzt = _verknuepfungen(
      lernlandkarteLesen(form.form) ??
          (throw MoodleFehler('Kartendaten fehlen.')),
    );
    if (jsonEncode(jetzt) == jsonEncode(vorher)) {
      return KartenErgebnis(
        KartenStand.offen,
        '„$name": Verknüpfen abgebrochen, die Ortsverknüpfungen sind nachweislich unverändert: $meldung',
      );
    }
  } on MoodleFehler {
    // Unlesbar: unklar.
  }
  return KartenErgebnis(
    KartenStand.unklar,
    '„$name": Beim Verknüpfen trat ein Fehler auf, der Stand der Karte ist nicht belegt: $meldung '
    'Die Karte in Moodle prüfen; nicht erneut senden.',
  );
}
