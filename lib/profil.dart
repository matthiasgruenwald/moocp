// Instanzprofile: Moodle-Instanzen, mit denen die App gleichzeitig angemeldet
// sein kann (Issue #4). Ein Profil hat eine stabile Kennung, einen Anzeigenamen,
// die Adresse und eine optionale Rolle (nur als Feld gespeichert, ohne Wirkung).
//
// Die Kennung ist der Schlüssel für alles, was je Instanz getrennt liegt:
// Zugangsdaten (anmeldedaten.dart), Registry (moodle/instanzen.dart) und
// Dateinamen im Arbeitsordner, wo mehrere Profile Kollisionen erzeugen könnten.
//
// Altbestand: Eine Einstellungsdatei mit nur `moodleAdresse` wird zu einem
// Profil mit der Kennung `standard` (Einstellungen.aus). Dessen Zugangsdaten
// liegen weiter unter den alten Schlüsseln, damit niemand neu eingeben muss.
//
// Offen (Konflikt mit E31, siehe TODO.md): Der MCP-Teil nimmt den Parameter
// `instanz` nicht an; E31 verwirft einen Server mit Instanz als Parameter.

import 'dart:math';

class Profil {
  const Profil({
    required this.kennung,
    required this.name,
    required this.adresse,
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

  /// Nur ein Feld, ohne Wirkung auf Rechte oder Werkzeuge.
  final String? rolle;

  bool get istStandard => kennung == standardKennung;

  Profil copyWith({String? name, String? adresse, String? rolle}) => Profil(
        kennung: kennung,
        name: name ?? this.name,
        adresse: adresse ?? this.adresse,
        rolle: rolle ?? this.rolle,
      );

  Map<String, Object?> toJson() => {
        'kennung': kennung,
        'name': name,
        'adresse': adresse,
        if (rolle != null) 'rolle': rolle,
      };

  /// Null, wenn die Angabe unbrauchbar ist; die Einstellungen fallen dann auf
  /// die übrigen Profile zurück, statt die ganze Datei zu verwerfen.
  static Profil? ausJson(Object? j) {
    if (j is! Map) return null;
    final kennung = j['kennung'];
    final name = j['name'];
    final adresse = j['adresse'];
    if (kennung is! String || kennung.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    if (adresse is! String) return null;
    final rolle = j['rolle'];
    return Profil(
      kennung: kennung,
      name: name,
      adresse: adresse,
      rolle: rolle is String && rolle.isNotEmpty ? rolle : null,
    );
  }

  /// Das Profil für eine einzelne Adresse aus dem Altbestand.
  static Profil migriert(String adresse) =>
      Profil(kennung: standardKennung, name: standardName, adresse: adresse);

  /// Eine neue Kennung: acht Hexziffern, zufällig. Die Kennung bleibt danach
  /// unverändert, auch wenn der Name geändert wird.
  static String neueKennung([Random? zufall]) {
    final r = zufall ?? Random.secure();
    return List.generate(8, (_) => r.nextInt(16).toRadixString(16)).join();
  }
}

/// Eine Anfrage, die kein Profil eindeutig trifft. Die Meldung nennt die
/// Profile mit Kennung und Namen, nie die Adressen.
class ProfilFehler implements Exception {
  ProfilFehler(this.meldung);
  final String meldung;
  @override
  String toString() => meldung;
}

/// Welches Profil ein Aufruf meint (Werkzeugparameter `instanz`).
///
/// - Mit Angabe: Kennung oder Anzeigename (ohne Groß-/Kleinschreibung).
/// - Ohne Angabe und genau ein Profil: dieses ist der Standard.
/// - Ohne Angabe und mehrere Profile: Fehler mit der Profilliste, nie ein
///   Rateversuch.
Profil profilAufloesen(List<Profil> profile, String? instanz) {
  final liste = [for (final p in profile) '${p.name} (${p.kennung})'].join(', ');
  final angabe = instanz?.trim();
  if (angabe == null || angabe.isEmpty) {
    if (profile.isEmpty) {
      throw ProfilFehler('Keine Moodle-Instanz eingerichtet. Bitte in der App eine Adresse eintragen.');
    }
    if (profile.length == 1) return profile.first;
    throw ProfilFehler(
      'Mehrere Moodle-Instanzen sind angemeldet; bitte den Parameter instanz angeben. Verfügbar: $liste',
    );
  }
  final gleich = profile.where((p) => p.kennung == angabe).toList();
  if (gleich.length == 1) return gleich.first;
  final namen = profile.where((p) => p.name.toLowerCase() == angabe.toLowerCase()).toList();
  if (namen.length == 1) return namen.first;
  if (namen.length > 1) {
    throw ProfilFehler(
      'Der Name „$angabe" passt zu mehreren Instanzen; bitte die Kennung angeben. Verfügbar: $liste',
    );
  }
  throw ProfilFehler('Keine Instanz „$angabe". Verfügbar: $liste');
}
