// Instanzprofile: Moodle-Instanzen, mit denen die App gleichzeitig angemeldet
// sein kann (Issue #4, E31). Ein Profil hat eine stabile Kennung, einen
// Anzeigenamen, die Adresse, eine optionale Rolle in der Übertragung (Issue #5,
// Rolle; Richtung und Prüfung in uebertragung.dart), einen eigenen Port und
// einen technischen Servernamen.
//
// Je Profil läuft ein eigener MCP-Server (mcp/mcp_dienst.dart) auf eigenem Port
// unter eigenem Namen (einrichtung.dart): Die KI-Werkzeuge sehen je Instanz
// eine eigene Werkzeugfamilie, etwa `moodle_…` und `moodle-test_…`. Es gibt
// keinen Parameter `instanz` (E31).
//
// Die Kennung ist der Schlüssel für alles, was je Instanz getrennt liegt:
// Zugangsdaten (anmeldedaten.dart), Registry (moodle/instanzen.dart) und
// Unterordner im Arbeitsordner, sobald mehrere Profile bestehen.
//
// Altbestand: Eine Einstellungsdatei mit nur `moodleAdresse` und `port` wird zu
// einem Profil mit der Kennung `standard`, Servername `moodle`, altem Port
// (Einstellungen.aus). Dessen Zugangsdaten liegen weiter unter den alten
// Schlüsseln, damit niemand neu eingeben muss.

import 'dart:math';

import 'einstellungen_ort.dart';

/// Rolle eines Profils für die Übertragung von Kursen (Issue #5). Die Rolle
/// ist eine lokale App-Einstellung; Moodle wird dadurch nicht geändert. Gespeichert
/// wird der Name des Werts (`quelle`, `ziel`), nicht die Anzeige.
enum Rolle {
  quelle('Quelle'),
  ziel('Ziel');

  const Rolle(this.anzeige);

  /// Die Bezeichnung in Texten für die Lehrkraft und die KI.
  final String anzeige;

  /// Null für nichts Gespeichertes oder einen unbekannten Wert: Ein Profil
  /// ohne brauchbare Rolle ist ohne Rolle, die Datei wird dafür nicht verworfen.
  static Rolle? ausText(Object? t) {
    for (final r in Rolle.values) {
      if (r.name == t) return r;
    }
    return null;
  }
}

class Profil {
  Profil({
    required this.kennung,
    required this.name,
    required this.adresse,
    required this.port,
    required this.mcpName,
    this.rolle,
  });

  /// Kennung des ersten Profils. Der Altbestand und der Testzugang gehören
  /// dazu (anmeldedaten.dart). Neue Profile bekommen eine zufällige Kennung.
  static const standardKennung = 'standard';

  /// Anzeigename des Altbestands. Bewusst kein Domainname (A11).
  static const standardName = 'Moodle';

  final String kennung;
  final String name;
  final String adresse;

  /// Port des MCP-Servers dieses Profils (127.0.0.1). Je Profil verschieden.
  /// Der Wert 0 heißt „noch nicht vergeben"; Einstellungen.aus setzt ihn.
  final int port;

  /// Technischer Servername für die KI-Werkzeuge, etwa `moodle-test`. Aus dem
  /// Anzeigenamen abgeleitet ([mcpNameAus]) und dann gespeichert, damit ein
  /// Umbenennen die Einrichtung in den Werkzeugen nicht still verstellt.
  final String mcpName;

  /// Rolle in der Übertragung, null = keine. Wirkt nur auf die Richtung
  /// einer Übertragung, nie auf Rechte oder die Werkzeuge der Instanz.
  final Rolle? rolle;

  bool get istStandard => kennung == standardKennung;

  /// Ändert nur den Anzeigenamen, der Servername bleibt (siehe [mcpName]).
  /// Ohne [rolle] bleibt die Rolle; eine Rolle wegnehmen geht über
  /// [mitRolle] (Einstellungen.rolleSetzen).
  Profil copyWith({String? name, String? adresse, Rolle? rolle, int? port}) => Profil(
        kennung: kennung,
        name: name ?? this.name,
        adresse: adresse ?? this.adresse,
        port: port ?? this.port,
        mcpName: mcpName,
        rolle: rolle ?? this.rolle,
      );

  /// Dieselbe Instanz mit anderer Rolle, auch ohne Rolle (null).
  Profil mitRolle(Rolle? neu) => Profil(
        kennung: kennung,
        name: name,
        adresse: adresse,
        port: port,
        mcpName: mcpName,
        rolle: neu,
      );

  Map<String, Object?> toJson() => {
        'kennung': kennung,
        'name': name,
        'adresse': adresse,
        'port': port,
        'mcpName': mcpName,
        if (rolle != null) 'rolle': rolle!.name,
      };

  /// Null, wenn die Angabe unbrauchbar ist; die Einstellungen fallen dann auf
  /// die übrigen Profile zurück, statt die ganze Datei zu verwerfen. Fehlt der
  /// Port oder der Servername, kommen 0 bzw. der aus dem Namen abgeleitete Name.
  static Profil? ausJson(Object? j) {
    if (j is! Map) return null;
    final kennung = j['kennung'];
    final name = j['name'];
    final adresse = j['adresse'];
    if (kennung is! String || kennung.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    if (adresse is! String) return null;
    final rolle = j['rolle'];
    final port = j['port'];
    final mcpName = j['mcpName'];
    return Profil(
      kennung: kennung,
      name: name,
      adresse: adresse,
      port: port is int && port > 0 ? port : 0,
      mcpName: mcpName is String && mcpNameGueltig(mcpName) ? mcpName : mcpNameFuer(name, kennung),
      rolle: Rolle.ausText(rolle),
    );
  }

  /// Das Profil für eine einzelne Adresse aus dem Altbestand.
  static Profil migriert(String adresse, {int port = standardPort}) => Profil(
        kennung: standardKennung,
        name: standardName,
        adresse: adresse,
        port: port,
        mcpName: mcpNameAus(standardName),
      );

  /// Eine neue Kennung: acht Hexziffern, zufällig. Die Kennung bleibt danach
  /// unverändert, auch wenn der Name geändert wird.
  static String neueKennung([Random? zufall]) {
    final r = zufall ?? Random.secure();
    return List.generate(8, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// Der technische Servername aus dem Anzeigennamen: Kleinbuchstaben, Ziffern
  /// und Bindestriche, keine Leerzeichen. Leer, wenn der Name nichts davon
  /// hergibt; Einstellungen.aus setzt dann die Kennung als Ersatz.
  static String mcpNameAus(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  /// Ob ein Servername gültig ist: wie [mcpNameAus] liefert, nicht leer.
  static bool mcpNameGueltig(String n) => RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(n);

  /// Der Servername, wenn er nicht gespeichert ist: aus dem Namen, und wenn
  /// der nichts hergibt, aus der Kennung.
  static String mcpNameFuer(String name, String kennung) {
    final a = mcpNameAus(name);
    if (a.isNotEmpty) return a;
    final k = mcpNameAus(kennung);
    return k.isEmpty ? 'moodle' : 'moodle-$k';
  }
}
