import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:html/dom.dart' as dom;
import 'package:path/path.dart' as p;

import '../freigabe.dart';
import 'formular.dart';
import 'formular_lesen.dart';
import 'formular_schreiben.dart';
import 'kurs.dart';
import 'moodle_zugang.dart';

String _placestoreStruktur(Object? daten) {
  if (daten is Map) {
    final objekt = daten;
    final keys = objekt.keys.map((k) => '$k').toList()..sort();
    return keys
        .map((k) {
          final wert = objekt[k];
          final art = wert is List
              ? 'Liste(${wert.length})'
              : wert is Map
              ? 'Objekt'
              : wert?.runtimeType.toString() ?? 'null';
          return '$k:$art';
        })
        .join(', ');
  }
  if (daten is List) return 'Liste mit ${daten.length} Einträgen';
  return daten?.runtimeType.toString() ?? 'null';
}

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
  Object? daten;
  try {
    daten = jsonDecode(placestore);
  } on FormatException catch (e) {
    final signatur = placestore.trimLeft().runes.take(24).map((r) {
      if ('{}[]:,"'.runes.contains(r)) return String.fromCharCode(r);
      if (r >= 48 && r <= 57) return '0';
      if ((r >= 65 && r <= 90) || (r >= 97 && r <= 122)) return 'a';
      if (r == 32 || r == 9 || r == 10 || r == 13) return ' ';
      return '?';
    }).join();
    throw MoodleFehler(
      'Das placestore-Format der Lernlandkarte ist kein gültiges JSON '
      '(Parserposition ${e.offset ?? -1} von ${placestore.length}; Signatur: $signatur).',
    );
  }
  final defaults =
      daten is Map<String, dynamic> &&
      daten['mapid'] is String &&
      daten['editmode'] is bool;
  final orte = daten is Map<String, dynamic>
      ? daten['places'] ?? (defaults ? const [] : null)
      : null;
  final wege = daten is Map<String, dynamic>
      ? daten['paths'] ?? (defaults ? const [] : null)
      : null;
  final startorte = daten is Map<String, dynamic>
      ? daten['startingplaces'] ?? const []
      : null;
  final zielorte = daten is Map<String, dynamic>
      ? daten['targetplaces'] ?? const []
      : null;
  if (daten is! Map<String, dynamic> ||
      orte is! List ||
      wege is! List ||
      startorte is! List ||
      zielorte is! List) {
    final struktur = _placestoreStruktur(daten);
    throw MoodleFehler(
      'Das placestore-Format der Lernlandkarte ist unbekannt (JSON-Struktur: $struktur).',
    );
  }
  final speicher = Map<String, dynamic>.from(daten)
    ..['places'] = orte
    ..['paths'] = wege
    ..['startingplaces'] = startorte
    ..['targetplaces'] = zielorte;
  return {
    'svgcode': svgcode,
    'orte': orte,
    'wege': wege,
    'startorte': startorte,
    'zielorte': zielorte,
    'placestore': speicher,
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
  void Function()? pruefeBindung,
}) async {
  if (zuordnungen.isEmpty) {
    throw MoodleFehler('Mindestens eine Ortszuordnung angeben.');
  }
  pruefeBindung?.call();
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
  final karte = lernlandkarteLesen(vorher.form);
  if (karte == null) {
    throw MoodleFehler(
      'Das Lernlandkarten-Formular enthält keine lesbaren Kartendaten; nichts geändert.',
    );
  }
  final daten = karte['placestore'] as Map<String, dynamic>;
  final original = raw;
  final lesestand = await formularLesen(moodle, ziel, arbeitsordner);
  // Gleich jetzt: das spätere Lesen schreibt in denselben Ordner.
  final hintergrundVorher = _hintergrundHashes(lesestand);
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
    details.add('Ort $ort: ${zielText(aktuell)} → ${zielText(neu)}');
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
      ungeklaerteAlteZiele.any(aktuelleStruktur.nachCmid.containsKey) ||
      zuordnungen.any((a) {
        final cmid = (a['ziel'] as num?)?.toInt();
        return cmid != null &&
            cmid != 0 &&
            aktuelleStruktur.nachCmid[cmid] == null;
      })) {
    throw MoodleFehler(
      'Die Lernlandkarte wurde seit der Freigabe geändert. Nichts überschrieben; '
      'neu lesen und die Entscheidung erneut prüfen.',
    );
  }
  final store = Map<String, dynamic>.from(daten);
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
  pruefeBindung?.call();
  await absenden(moodle, aktuell);
  pruefeBindung?.call();
  final rueckForm = await formularHolen(moodle, ziel.adresse);
  final gelesen = await formularLesen(moodle, ziel, arbeitsordner);
  final rueck = gelesen.lernlandkarte?['placestore'];
  final karteOk =
      ohneOrtsbeschriftung(gelesen.lernlandkarte?['svgcode']) ==
          ohneOrtsbeschriftung(lesestand.lernlandkarte?['svgcode']) &&
      const JsonEncoder().convert(rueck) == const JsonEncoder().convert(store);
  final formularOk =
      gelesen.name == vorher.name &&
      gelesen.kurs == kurs &&
      _gleicheFormularFelder(aktuell, rueckForm, nachSpeichern: true) &&
      _gleicheHintergrund(hintergrundVorher, gelesen) &&
      _gleicheFelder(lesestand, gelesen) &&
      _gleicheEinstellungen(lesestand, gelesen, beschriftungenNeu: true);
  final verified = karteOk && formularOk;
  return 'Lernlandkarte „${gelesen.name}" zurückgelesen; Ortszuordnungen verified: $verified.';
}

/// Moodle schreibt beim Speichern die Beschriftung jedes Ortes neu, und zwar
/// aus dem Namen der verknüpften Aktivität (gemessen an der Spike-Instanz).
/// Der Vergleich der Zuordnung läuft über `placestore`; die Beschriftung im SVG
/// bleibt außen vor. Bewusst für alle Orte, nicht nur für die mit geändertem
/// Ziel: Moodle schreibt beim Speichern auch unveränderte Orte neu, und die
/// Zuordnung von Beschriftung zu Ort ist nur an einer Instanz gemessen.
String? ohneOrtsbeschriftung(Object? svg) => svg is String
    ? svg.replaceAllMapped(
        RegExp(r'(<(?:title|text) id="(?:title|text)[^"]*"[^>]*>)[^<]*'),
        (m) => m[1]!,
      )
    : null;

bool _gleicheFelder(FormularGelesen vorher, FormularGelesen nachher) {
  final a = {for (final f in vorher.felder) f.feld: f.html};
  final b = {for (final f in nachher.felder) f.feld: f.html};
  return const JsonEncoder().convert(a) == const JsonEncoder().convert(b);
}

/// Gleicher Formularstand ohne Entwurfs-IDs. Der Hintergrund wird über seine
/// Dateiliste geprüft, wie beim Ändern.
bool _gleicheFormularFelder(
  Formular vorher,
  Formular nachher, {
  bool nachSpeichern = false,
}) {
  // Nach dem Speichern darf sich nur unterscheiden, was Moodle selbst neu
  // schreibt: die Ortsbeschriftung im SVG und das Änderungsdatum der
  // Hintergrunddatei (gemessen an der Spike-Instanz: jedes Speichern legt sie
  // neu ab). Ihren Inhalt vergleicht _gleicheHintergrund. Beim Standvergleich
  // vor dem Schreiben unterscheidet sich nichts.
  List<List<String>> stand(Formular f) => [
    for (final e in f.felder)
      if (e.key != 'sesskey' && !istEntwurfsId(e.key))
        [
          e.key,
          nachSpeichern && e.key == 'svgcode'
              ? ohneOrtsbeschriftung(e.value)!
              : e.value,
        ],
  ];
  String liste(Formular f) => [
    for (final e
        in (f.bereiche['backgroundfile']?['list'] as List? ?? const []))
      if (e is Map)
        '${e['filepath']}${e['filename']}:${e['size']}'
            '${nachSpeichern ? '' : ':${e['datemodified']}'}',
  ].join('|');
  return const JsonEncoder().convert(stand(vorher)) ==
          const JsonEncoder().convert(stand(nachher)) &&
      liste(vorher) == liste(nachher);
}

/// Inhalt der Hintergrunddateien (SHA-256) eines gelesenen Stands; null, wenn
/// eine Datei nicht gelesen werden konnte (zu groß, Abruf gescheitert). Sie
/// fehlte sonst in beiden Ständen und sähe „gleich" aus.
String? _hintergrundHashes(FormularGelesen f) {
  if (f.bereiche.any(
    (b) => b.feld == 'backgroundfile' && b.nichtGelesen.isNotEmpty,
  )) {
    return null;
  }
  final wurzel = Directory(p.join(f.ordner, 'bereiche', 'backgroundfile'));
  if (!wurzel.existsSync()) return '{}';
  final hashes = {
    for (final d in wurzel.listSync(recursive: true).whereType<File>())
      p.relative(d.path, from: wurzel.path): sha256
          .convert(d.readAsBytesSync())
          .toString(),
  };
  return const JsonEncoder().convert(hashes);
}

/// Hintergrund nach dem Speichern gegen den Stand von vorher ([vorher] aus
/// [_hintergrundHashes]); nicht lesbar gilt nie als gleich.
bool _gleicheHintergrund(String? vorher, FormularGelesen nachher) {
  final jetzt = _hintergrundHashes(nachher);
  return vorher != null && jetzt != null && vorher == jetzt;
}

bool _gleicheEinstellungen(
  FormularGelesen vorher,
  FormularGelesen nachher, {
  bool beschriftungenNeu = false,
}) {
  Object? wert(String schluessel, Object? w) =>
      beschriftungenNeu && schluessel == 'svgcode'
      ? ohneOrtsbeschriftung(w)
      : w;
  final a = {
    for (final e in vorher.einstellungen)
      e.schluessel: wert(e.schluessel, e.wert),
  };
  final b = {
    for (final e in nachher.einstellungen)
      e.schluessel: wert(e.schluessel, e.wert),
  };
  return const JsonEncoder().convert(a) == const JsonEncoder().convert(b);
}
