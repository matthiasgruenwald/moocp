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
  final orte = (daten['places'] as List).whereType<Map>().toList();
  final ids = orte.map((o) => '${o['id'] ?? ''}').toList();
  final struktur = await kursLesen(moodle, kurs);
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
  final details = <String>[];
  for (final a in zuordnungen) {
    final ort = '${a['ort']}';
    final erwartet = (a['aktuell'] as num?)?.toInt();
    final aktuell = erwartet == 0 ? null : erwartet;
    final neuesZiel = (a['ziel'] as num?)?.toInt();
    final neu = neuesZiel == 0 ? null : neuesZiel;
    details.add(
      'Ort $ort: ${aktuell == null ? 'ohne Verknüpfung' : 'cm $aktuell'} → '
      '${neu == null ? 'ohne Verknüpfung' : 'cm $neu'}',
    );
  }
  final ja = await freigaben.anfragen(
    FreigabeAnfrage(
      titel: 'Lernlandkarte ändern?',
      punkte: [
        'Lernlandkarte „${vorher.name}" (cmid $cmid, Kurs $kurs)',
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
  if (aktuell.modul != 'learningmap' ||
      aktuell.name != vorher.name ||
      aktuell.kurs != kurs ||
      wertIn(aktuell.felder, 'placestore') != original) {
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
  final gelesen = await formularLesen(moodle, ziel, arbeitsordner);
  final rueck = gelesen.lernlandkarte?['placestore'];
  final verified =
      const JsonEncoder().convert(rueck) == const JsonEncoder().convert(store);
  return 'Lernlandkarte „${gelesen.name}" zurückgelesen; Ortszuordnungen verified: $verified.';
}
