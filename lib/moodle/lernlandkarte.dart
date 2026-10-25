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

part 'lernlandkarte_schreiben.dart';

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

/// Das Ziel eines Kartenorts als cmid. Moodle speichert `linkedActivity` je
/// nach Weg als Zahl oder als Zeichenkette („123"); ohne Ziel steht `null`
/// oder eine leere Zeichenkette. Alles andere gilt als ohne lesbares Ziel.
int? ortsziel(Object? linkedActivity) => switch (linkedActivity) {
  final num n => n.toInt(),
  final String s => int.tryParse(s.trim()),
  _ => null,
};

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

/// Bestehende Aufrufer und Tests: entfernt Ortsbeschriftungen für eine reine
/// Darstellung. Die Schreibprüfung verwendet stattdessen den engeren Vergleich
/// [_gleicheSvgMitNeubeschriftungen].
String? ohneOrtsbeschriftung(Object? svg) => svg is String
    ? svg.replaceAllMapped(
        RegExp(r'(<(?:title|text) id="(?:title|text)[^"]*"[^>]*>)[^<]*'),
        (m) => m[1]!,
      )
    : null;

/// Fingerabdruck des lesbaren Formularinhalts einer Lernlandkarte, einschließlich
/// Beschreibung, nativer Einstellungen und heruntergeladener Dateiinhalte.
/// Null bedeutet eine ausdrückliche Prüflücke.
String? formularInhaltsstand(FormularGelesen f) {
  if (f.modul == null ||
      f.kurs == null ||
      f.name == null ||
      f.fehlend.isNotEmpty ||
      f.bereiche.any((b) => b.nichtGelesen.isNotEmpty)) {
    return null;
  }
  final dateien = <String, String>{};
  for (final wurzel in ['dateien', 'bereiche']) {
    final ordner = Directory(p.join(f.ordner, wurzel));
    if (!ordner.existsSync()) continue;
    for (final datei in ordner.listSync(recursive: true).whereType<File>()) {
      dateien['$wurzel/${p.relative(datei.path, from: ordner.path)}'] = sha256
          .convert(datei.readAsBytesSync())
          .toString();
    }
  }
  return jsonEncode({
    'name': f.name,
    'modul': f.modul,
    'felder': [
      for (final feld in f.felder)
        if (feld.feld != 'svgcode' && feld.feld != 'placestore')
          [feld.feld, _vergleichHtml(feld.feld, feld.html)],
    ],
    'editorFormate': f.editorFormate,
    'einstellungen': {
      for (final e in f.einstellungen)
        if (!{'visible', 'backgroundfile', 'svgcode'}.contains(e.schluessel))
          e.schluessel: e.wert,
    },
    'dateien': dateien,
    'bereiche': [
      for (final b in f.bereiche)
        [
          b.feld,
          b.label,
          for (final e in b.dateien.entries) [e.key, e.value.bytes],
        ],
    ],
  });
}

bool _gleicheFelder(FormularGelesen vorher, FormularGelesen nachher) {
  final a = {
    for (final f in vorher.felder)
      if (f.feld != 'svgcode' && f.feld != 'placestore')
        f.feld: _vergleichHtml(f.feld, f.html),
  };
  final b = {
    for (final f in nachher.felder)
      if (f.feld != 'svgcode' && f.feld != 'placestore')
        f.feld: _vergleichHtml(f.feld, f.html),
  };
  return const JsonEncoder().convert(a) == const JsonEncoder().convert(b);
}

/// Moodle vergibt den Entwurfsbereich beim Lesen neu; Bildname und Inhalt
/// bleiben maßgeblich, die Bytes werden separat geprüft.
String lernlandkartenSvgVergleich(String svg) => svg.replaceAll(
  RegExp(r'/draftfile\.php/\d+/user/draft/\d+/'),
  '/draftfile.php/U/user/draft/X/',
);

String _vergleichHtml(String feld, String wert) =>
    const {'introeditor[text]', 'introeditor', 'svgcode'}.contains(feld)
    ? lernlandkartenSvgVergleich(wert)
    : wert;

// Moodle setzt den ausgeschalteten Abschlusstermin bei jedem GET auf „jetzt“.
bool _unwirksamerAbschlusswert(String key, bool aktiv) =>
    !aktiv && const {
      'completionexpected[year]', 'completionexpected[month]', 'completionexpected[day]',
      'completionexpected[hour]', 'completionexpected[minute]',
    }.contains(key);

/// Moodle darf nur die Beschriftung eines geänderten Orts aus dessen neuem
/// Aktivitätsnamen erzeugen. Alle anderen SVG-Texte bleiben Teil des Vergleichs.
bool _gleicheSvgMitNeubeschriftungen(
  Object? vorher,
  Object? nachher,
  Map<String, String> erwarteteNamen,
) {
  if (vorher is! String || nachher is! String) return false;
  var normalisiert = nachher;
  for (final e in erwarteteNamen.entries) {
    if (e.value.trim().isEmpty) return false;
    var ortsbeschriftungVorhanden = false;
    for (final tag in ['title', 'text']) {
      final id = RegExp.escape(e.key);
      final muster = RegExp('(<$tag id="$tag$id"[^>]*>)([^<]*)(</$tag>)');
      final vorherTreffer = muster.allMatches(vorher).toList();
      final nachherTreffer = muster.allMatches(normalisiert).toList();
      if (vorherTreffer.length > 1 || nachherTreffer.length > 1) {
        return false;
      }
      if (nachherTreffer.isEmpty) {
        if (vorherTreffer.isNotEmpty) return false;
        continue;
      }
      ortsbeschriftungVorhanden = true;
      if (nachherTreffer.single.group(2) != e.value) return false;
      final original = vorherTreffer.isEmpty
          ? null
          : vorherTreffer.single.group(2);
      normalisiert = normalisiert.replaceRange(
        nachherTreffer.single.start,
        nachherTreffer.single.end,
        original == null
            ? ''
            : '${nachherTreffer.single.group(1)}$original${nachherTreffer.single.group(3)}',
      );
    }
    if (!ortsbeschriftungVorhanden) return false;
  }
  return lernlandkartenSvgVergleich(vorher) ==
      lernlandkartenSvgVergleich(normalisiert);
}

/// Gleicher Formularstand ohne Entwurfs-IDs. Der Hintergrund wird über seine
/// Dateiliste geprüft, wie beim Ändern.
bool _gleicheFormularFelder(
  Formular vorher,
  Formular nachher, {
  bool nachSpeichern = false,
}) {
  // SVG-Beschriftungen prüft der Aufrufer anhand der Zielnamen. Moodle ändert
  // außerdem das Änderungsdatum der Hintergrunddatei; ihren Inhalt vergleicht
  // _gleicheHintergrund.
  List<List<String>> stand(Formular f) => [
    for (final e in f.felder)
      if (e.key != 'sesskey' &&
          !istEntwurfsId(e.key) &&
          !_unwirksamerAbschlusswert(e.key,
              f.felder.any((e) => e.key == 'completionexpected[enabled]' && const {'1', 'on'}.contains(e.value))) &&
          !(nachSpeichern && e.key == 'svgcode'))
        [e.key, _vergleichHtml(e.key, e.value)],
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
  final a = {
    for (final e in vorher.einstellungen)
      if (!(beschriftungenNeu && e.schluessel == 'svgcode'))
        e.schluessel: e.wert,
  };
  final b = {
    for (final e in nachher.einstellungen)
      if (!(beschriftungenNeu && e.schluessel == 'svgcode'))
        e.schluessel: e.wert,
  };
  return const JsonEncoder().convert(a) == const JsonEncoder().convert(b);
}
