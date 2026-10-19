import 'dart:convert';

import 'package:html/dom.dart' as dom;

import '../freigabe.dart';
import 'formular.dart';
import 'formular_lesen.dart';
import 'formular_schreiben.dart';
import 'kurs.dart';
import 'moodle_zugang.dart';

/// Die gespeicherten Kartendaten aus dem Lernlandkarten-Formular.
///
/// SVG und Ortsdaten bleiben unverändert erhalten; die abgeleiteten Angaben
/// helfen beim Prüfen von Wegen und Aktivitätsverknüpfungen.
Map<String, Object?>? lernlandkarteLesen(dom.Element form) {
  final svgcode = form.querySelector('textarea[name="svgcode"]')?.text;
  final placestore = form
      .querySelector('input[name="placestore"]')
      ?.attributes['value'];
  if (svgcode == null || placestore == null) return null;
  final daten = jsonDecode(placestore);
  if (daten is! Map<String, dynamic> ||
      daten['places'] is! List ||
      daten['paths'] is! List) {
    throw const FormatException(
      'Das placestore-Format der Lernlandkarte ist unbekannt.',
    );
  }
  return {
    'svgcode': svgcode,
    'orte': daten['places'],
    'wege': daten['paths'],
    'startorte': daten['startingplaces'] ?? const [],
    'zielorte': daten['targetplaces'] ?? const [],
    'placestore': daten,
  };
}

/// Prüft, ob eine Ortskennung als Start oder Ziel der Karte markiert ist.
String? lernlandkarteRolle(Map karte, String id) {
  final start = (karte['startingplaces'] as List?)?.contains(id) ?? false;
  final ziel = (karte['targetplaces'] as List?)?.contains(id) ?? false;
  if (start && ziel) return 'Start- und Zielort';
  if (start) return 'Startort';
  if (ziel) return 'Zielort';
  return null;
}

/// Ändert ausschließlich die angegebenen Ortsziele und erhält den übrigen
/// placestore-Stand unverändert.
Future<String> lernlandkarteVerknuepfungenSetzen(
  MoodleZugang moodle,
  Freigaben freigaben, {
  required String arbeitsordner,
  required int cmid,
  required String name,
  required List<Map<String, Object?>> zuordnungen,
}) async {
  if (zuordnungen.isEmpty) {
    throw MoodleFehler('Mindestens eine Ortszuordnung angeben.');
  }
  final ziel = Formularziel.aktivitaet(cmid);
  final vorher = await formularHolen(moodle, ziel.adresse);
  if (vorher.modul != 'learningmap') {
    throw MoodleFehler('Die Aktivität ist keine Lernlandkarte.');
  }
  nameBestaetigen(name, vorher.name, 'Lernlandkarte');
  final kurs = vorher.kurs;
  if (kurs == null) {
    throw MoodleFehler('Das Formular nennt keinen Kurs; nichts geändert.');
  }
  final raw = wertIn(vorher.felder, 'placestore');
  if (raw == null) {
    throw MoodleFehler(
      'Das Lernlandkarten-Formular enthält kein placestore-Feld.',
    );
  }
  final daten = jsonDecode(raw);
  if (daten is! Map<String, dynamic> ||
      daten['places'] is! List ||
      daten['paths'] is! List) {
    throw MoodleFehler(
      'Das Lernlandkarten-Formular hat ein unbekanntes placestore-Format; nichts geändert.',
    );
  }
  final original = raw;
  final lesestand = await formularLesen(moodle, ziel, arbeitsordner);
  final orte = (daten['places'] as List).whereType<Map>().toList();
  final ids = orte.map((o) => '${o['id'] ?? ''}').toList();
  final struktur = await kursLesen(moodle, kurs);
  final kartenaktivitaet = struktur.nachCmid[cmid];
  if (kartenaktivitaet == null ||
      kartenaktivitaet.modul != 'learningmap' ||
      kartenaktivitaet.name != vorher.name) {
    throw MoodleFehler(
      'Die Lernlandkarte stimmt nicht mehr mit der Kursübersicht überein; nichts geändert.',
    );
  }
  final kursText = await kursBezeichnung(moodle, kurs);
  final gesehen = <String>{};
  for (final a in zuordnungen) {
    final ort = '${a['ort'] ?? ''}';
    if (ort.isEmpty ||
        !gesehen.add(ort) ||
        ids.where((id) => id == ort).length != 1) {
      throw MoodleFehler(
        'Ort „$ort" fehlt oder kommt mehrfach vor; nichts geändert.',
      );
    }
    final place = orte.singleWhere((o) => o['id'] == ort);
    final erwartet = (a['aktuell'] as num?)?.toInt();
    final aktuell = erwartet == 0 ? null : erwartet;
    if ((place['linkedActivity'] as num?)?.toInt() != aktuell) {
      throw MoodleFehler(
        'Die Verknüpfung von Ort „$ort" ist seit dem Lesen anders. '
        'Lernlandkarte neu lesen und die Entscheidung erneut prüfen.',
      );
    }
    final neuesZiel = (a['ziel'] as num?)?.toInt();
    final neu = neuesZiel == 0 ? null : neuesZiel;
    if (neu != null) {
      final aktivitaet = struktur.nachCmid[neu];
      if (aktivitaet == null || aktivitaet.modul == 'learningmap') {
        throw MoodleFehler(
          'Ziel cm $neu ist keine vorhandene Aktivität in diesem Kurs.',
        );
      }
    }
  }
  String zielText(int? cmid) {
    if (cmid == null) return 'ohne Verknüpfung';
    final aktivitaet = struktur.nachCmid[cmid];
    return aktivitaet == null
        ? 'ungeklärtes Ziel cm $cmid'
        : '„${aktivitaet.name}" (cmid $cmid)';
  }

  final zielstaende = <int, (String, String, int)>{};
  final ungeklaerteAlteZiele = <int>{};
  for (final a in zuordnungen) {
    final alt = (a['aktuell'] as num?)?.toInt();
    if (alt != null && alt != 0 && struktur.nachCmid[alt] == null) {
      ungeklaerteAlteZiele.add(alt);
    }
    for (final wert in [a['aktuell'], a['ziel']]) {
      final cmid = (wert as num?)?.toInt();
      final aktivitaet = cmid == null ? null : struktur.nachCmid[cmid];
      if (aktivitaet != null) {
        zielstaende[cmid!] = (
          aktivitaet.name,
          aktivitaet.modul,
          aktivitaet.abschnittId,
        );
      }
    }
  }
  final details = <String>[];
  for (final a in zuordnungen) {
    final ort = '${a['ort']}';
    final erwartet = (a['aktuell'] as num?)?.toInt();
    final aktuell = erwartet == 0 ? null : erwartet;
    final neuesZiel = (a['ziel'] as num?)?.toInt();
    final neu = neuesZiel == 0 ? null : neuesZiel;
    details.add(
      'Ort $ort: ${zielText(aktuell)} → ${zielText(neu)}',
    );
  }
  final ja = await freigaben.anfragen(
    FreigabeAnfrage(
      titel: 'Lernlandkarte ändern?',
      punkte: [
        'Lernlandkarte „${vorher.name}" (cmid $cmid, $kursText)',
        ...details,
        'SVG, Wege, Ortsdarstellung und andere Kartendaten bleiben erhalten.',
      ],
      vergleich: const [],
    ),
  );
  if (!ja) {
    return 'Nicht gespeichert: Die Ortszuordnung wurde nicht freigegeben.';
  }

  final aktuell = await formularHolen(moodle, ziel.adresse);
  final aktuelleStruktur = await kursLesen(moodle, kurs);
  final aktuellerKursText = await kursBezeichnung(moodle, kurs);
  final aktuelleKarte = aktuelleStruktur.nachCmid[cmid];
  if (aktuell.modul != 'learningmap' ||
      aktuell.name != vorher.name ||
      aktuell.kurs != kurs ||
      aktuellerKursText != kursText ||
      aktuelleKarte == null ||
      aktuelleKarte.modul != kartenaktivitaet.modul ||
      aktuelleKarte.name != kartenaktivitaet.name ||
      aktuelleKarte.abschnittId != kartenaktivitaet.abschnittId ||
      wertIn(aktuell.felder, 'placestore') != original ||
      !_gleicheFormularFelder(vorher, aktuell) ||
      zielstaende.entries.any((e) {
        final jetzt = aktuelleStruktur.nachCmid[e.key];
        return jetzt == null ||
            (jetzt.name, jetzt.modul, jetzt.abschnittId) != e.value;
      }) ||
      ungeklaerteAlteZiele.any(
        aktuelleStruktur.nachCmid.containsKey,
      ) ||
      zuordnungen.any((a) {
        final cmid = (a['ziel'] as num?)?.toInt();
        return cmid != null && cmid != 0 &&
            aktuelleStruktur.nachCmid[cmid] == null;
      })) {
    throw MoodleFehler(
      'Die Lernlandkarte wurde seit der Freigabe geändert. Nichts überschrieben; '
      'neu lesen und die Entscheidung erneut prüfen.',
    );
  }
  final store = jsonDecode(original) as Map<String, dynamic>;
  final places = (store['places'] as List).whereType<Map>().toList();
  for (final a in zuordnungen) {
    final place = places.singleWhere((o) => o['id'] == a['ort']);
    final neuesZiel = (a['ziel'] as num?)?.toInt();
    final neu = neuesZiel == 0 ? null : neuesZiel;
    if (neu == null) {
      place.remove('linkedActivity');
    } else {
      place['linkedActivity'] = neu;
    }
  }
  setze(aktuell.felder, 'placestore', jsonEncode(store));
  await absenden(moodle, aktuell);
  final rueckForm = await formularHolen(moodle, ziel.adresse);
  final gelesen = await formularLesen(moodle, ziel, arbeitsordner);
  final rueck = gelesen.lernlandkarte?['placestore'];
  final karteOk = gelesen.lernlandkarte?['svgcode'] ==
          lesestand.lernlandkarte?['svgcode'] &&
      const JsonEncoder().convert(rueck) == const JsonEncoder().convert(store);
  final formularOk = gelesen.name == vorher.name && gelesen.kurs == kurs &&
      _gleicheFormularFelder(aktuell, rueckForm) &&
      _gleicheFelder(lesestand, gelesen) &&
      _gleicheEinstellungen(lesestand, gelesen);
  final verified = karteOk && formularOk;
  return 'Lernlandkarte „${gelesen.name}" zurückgelesen; Ortszuordnungen verified: $verified.';
}

bool _gleicheFelder(FormularGelesen vorher, FormularGelesen nachher) {
  final a = {for (final f in vorher.felder) f.feld: f.html};
  final b = {for (final f in nachher.felder) f.feld: f.html};
  return const JsonEncoder().convert(a) == const JsonEncoder().convert(b);
}

bool _gleicheFormularFelder(Formular vorher, Formular nachher) {
  List<List<String>> stand(Formular f) => [
    for (final e in f.felder)
      if (e.key != 'sesskey') [e.key, e.value],
  ];
  return const JsonEncoder().convert(stand(vorher)) ==
      const JsonEncoder().convert(stand(nachher));
}

bool _gleicheEinstellungen(FormularGelesen vorher, FormularGelesen nachher) {
  final a = {for (final e in vorher.einstellungen) e.schluessel: e.wert};
  final b = {for (final e in nachher.einstellungen) e.schluessel: e.wert};
  return const JsonEncoder().convert(a) == const JsonEncoder().convert(b);
}
