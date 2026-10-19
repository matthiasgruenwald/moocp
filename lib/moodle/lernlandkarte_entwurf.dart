import 'dart:convert';

import 'moodle_zugang.dart';

/// Moodle-Formulare rücken SVG-Zeilen beim Speichern ein. Leerraum zwischen
/// Tags ist in SVG bedeutungslos; Text innerhalb eines Elements bleibt exakt.
String lernlandkarteSvgVergleichswert(String svg) =>
    svg.replaceAll(RegExp(r'>\s+<'), '><').trim();

/// Eine kleine, skriptfreie Lernlandkarte aus den nativen Feldern des
/// Moodle-Formulars. Eingaben enthalten nur Punkte und Verbindungen; IDs,
/// SVG und placestore werden von der App erzeugt.
({String svgcode, String placestore}) lernlandkarteEntwurfErzeugen(
  Map<String, dynamic> vorlage,
  String nativesPlacestore,
) {
  final Object? native;
  try {
    native = jsonDecode(nativesPlacestore);
  } on FormatException {
    throw MoodleFehler(
      'Das native placestore-Format ist ungültig; nichts angelegt.',
    );
  }
  if (native is! Map<String, dynamic> ||
      native['mapid'] is! String ||
      native['editmode'] is! bool) {
    throw MoodleFehler(
      'Das native placestore-Format der Lernlandkarte ist unbekannt; nichts angelegt.',
    );
  }

  final eingabeOrte = vorlage['orte'];
  final eingabeWege = vorlage['wege'];
  if (vorlage.keys.any((k) => !const {'orte', 'wege'}.contains(k)) ||
      eingabeOrte is! List ||
      eingabeOrte.isEmpty ||
      eingabeOrte.length > 64 ||
      eingabeWege is! List ||
      eingabeWege.length > 128) {
    throw MoodleFehler(
      'Die Kartenvorlage braucht 1–64 Orte und höchstens 128 Wege; '
      'erlaubt sind nur die Felder orte und wege.',
    );
  }

  final orte = <({String id, num x, num y, String titel})>[];
  final ids = <String>{};
  for (final eintrag in eingabeOrte) {
    if (eintrag is! Map<String, dynamic> ||
        eintrag.keys.any((k) => !const {'id', 'x', 'y', 'titel'}.contains(k))) {
      throw MoodleFehler(
        'Jeder Ort darf nur id, x, y und optional titel enthalten; '
        'Verknüpfungen setzt das separate Freigabewerkzeug.',
      );
    }
    final id = eintrag['id'];
    final x = eintrag['x'];
    final y = eintrag['y'];
    final titel = eintrag['titel'] ?? '';
    if (id is! String || !RegExp(r'^p[1-9][0-9]{0,2}$').hasMatch(id) ||
        !ids.add(id) ||
        id != 'p${orte.length + 1}' ||
        x is! num || !x.isFinite || x < 0 || x > 1000 ||
        y is! num || !y.isFinite || y < 0 || y > 560 ||
        titel is! String ||
        titel.length > 80 ||
        titel.runes.any((r) => r < 32 && r != 9 && r != 10)) {
      throw MoodleFehler(
        'Orte brauchen fortlaufende IDs p1–p64, Koordinaten in 0–1000 × 0–560 '
        'und einen kurzen, druckbaren Titel; nichts angelegt.',
      );
    }
    orte.add((id: id, x: x, y: y, titel: titel));
  }

  final wege = <({String id, String von, String nach})>[];
  final paare = <String>{};
  for (final eintrag in eingabeWege) {
    if (eintrag is! Map<String, dynamic> ||
        eintrag.keys.any((k) => !const {'von', 'nach'}.contains(k))) {
      throw MoodleFehler(
        'Jeder Weg darf nur von und nach enthalten; nichts angelegt.',
      );
    }
    final von = eintrag['von'];
    final nach = eintrag['nach'];
    final vonIndex = von is String
        ? orte.indexWhere((o) => o.id == von)
        : -1;
    final nachIndex = nach is String
        ? orte.indexWhere((o) => o.id == nach)
        : -1;
    if (vonIndex < 0 || nachIndex < 0 || vonIndex >= nachIndex) {
      throw MoodleFehler(
        'Wege müssen zwei vorhandene, verschiedene Orte von links nach rechts '
        'verbinden; nichts angelegt.',
      );
    }
    final paar = '$von/$nach';
    if (!paare.add(paar)) {
      throw MoodleFehler('Doppelte Wege sind nicht erlaubt; nichts angelegt.');
    }
    wege.add((
      id: 'p${von.substring(1)}_${nach.substring(1)}',
      von: von,
      nach: nach,
    ));
  }

  String esc(String s) => const HtmlEscape().convert(s);
  String zahl(num n) => n == n.roundToDouble() ? '${n.toInt()}' : '$n';
  final svg = StringBuffer('''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1000" height="560" viewBox="0 0 1000 560">
<rect id="learningmap-background-image" class="learningmap-background-image" x="0" y="0" width="1000" height="560" fill="#f4f7fb"/>
<g id="pathsGroup">''');
  for (final weg in wege) {
    final start = orte.singleWhere((o) => o.id == weg.von);
    final ende = orte.singleWhere((o) => o.id == weg.nach);
    svg.write(
      '<path id="${weg.id}" class="learningmap-path" '
      'd="M ${zahl(start.x)} ${zahl(start.y)} L ${zahl(ende.x)} ${zahl(ende.y)}" '
      'fill="none" stroke="#64748b" stroke-width="8" stroke-linecap="round"/>',
    );
  }
  svg.write('</g><g id="placesGroup">');
  for (final ort in orte) {
    final n = ort.id.substring(1);
    svg.write(
      '<a id="a$n" xlink:href="" tabindex="0">'
      '<circle id="${ort.id}" class="learningmap-place learningmap-draggable learningmap-emptyplace" '
      'cx="${zahl(ort.x)}" cy="${zahl(ort.y)}" r="22" fill="#fff" stroke="#2563eb" stroke-width="6"/>'
      '<title id="title${ort.id}">${esc(ort.titel)}</title>'
      '<text id="text${ort.id}" x="${zahl(ort.x)}" y="${zahl(ort.y)}" '
      'dx="34" dy="8" fill="#172554" font-family="sans-serif" font-size="20">${esc(ort.titel)}</text>'
      '</a>',
    );
  }
  svg.write('</g></svg>');

  final store = Map<String, dynamic>.from(native)
    ..['places'] = [
      for (final ort in orte)
        {
          'id': ort.id,
          'linkId': 'a${ort.id.substring(1)}',
          'linkedActivity': null,
          'placecolor': null,
          'visitedcolor': null,
        },
    ]
    ..['paths'] = [
      for (final weg in wege)
        {'id': weg.id, 'from': weg.von, 'to': weg.nach},
    ]
    ..['startingplaces'] = [orte.first.id]
    ..['targetplaces'] = <String>[];
  return (svgcode: svg.toString(), placestore: jsonEncode(store));
}
