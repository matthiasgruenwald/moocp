// Einstellungen, die einen Neustart überleben: Moodle-Adresse, Port,
// Zugangsschlüssel für Claude, die gewählten Skills, die Update-Prüfung und
// die Stufe der Bestätigungen.
//
// Bewusst NICHT hier: Benutzername und Passwort. Die leben im Arbeitsspeicher,
// solange die App läuft -- und nur mit Haken „Anmeldedaten speichern" auch
// dauerhaft, siehe anmeldedaten.dart (Passwort mit DPAPI verschlüsselt).
// Ebenso wenig der Arbeitsordner: Der liegt fest und lebt nur so lange wie
// die App (arbeitsordner.dart).

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'einstellungen_ort.dart';
import 'freigabe.dart';
import 'profil.dart';

class Einstellungen {
  /// [moodleAdresse] ist der Altbestand eines einzelnen Moodle und wird zum
  /// ersten Profil ([profile]). Mit [profile] gewinnt die Liste.
  Einstellungen({
    String moodleAdresse = '',
    List<Profil>? profile,
    required this.port,
    required this.schluessel,
    this.bestaetigungen = Bestaetigungen.vorgabe,
    this.wahlSkills,
    this.werkzeugeAbgewaehlt = const {},
    this.updatePruefen,
    this.updateZuletzt,
    this.updateErwartet,
  }) : profile = profile ?? (moodleAdresse.isEmpty ? [] : [Profil.migriert(moodleAdresse)]);

  /// Die Moodle-Instanzen, mit denen die App angemeldet sein kann. Das erste
  /// Profil hat die Kennung `standard` (profil.dart), wenn es aus dem
  /// Altbestand stammt oder als erstes angelegt wurde.
  List<Profil> profile;

  /// Die Adresse des ersten Profils. Der Dialog und die Titelzeile arbeiten
  /// noch mit einer Adresse; ein zweites Profil kommt über [profile].
  String get moodleAdresse => profile.isEmpty ? '' : profile.first.adresse;

  set moodleAdresse(String a) {
    if (profile.isEmpty) {
      if (a.isNotEmpty) profile = [Profil.migriert(a)];
      return;
    }
    profile[0] = profile[0].copyWith(adresse: a);
  }

  int port;
  String schluessel;

  /// Wie viele Bestätigungen die Lehrkraft vor Änderungen in Moodle will
  /// (freigabe.dart). Die Einstellung gilt über einen Neustart hinweg; dass
  /// sie auf „keine" steht, zeigt die Titelzeile rot und das Protokoll beim
  /// Start -- eine Stufe, die sich von selbst zurückstellte, überraschte.
  Bestaetigungen bestaetigungen;

  /// Die gewählten unter den wählbaren Skills (einrichtung.dart,
  /// wahlSkills); null, solange im Dialog „KI-Werkzeuge einrichten" noch
  /// nichts gewählt wurde -- dann gilt gewaehltVorgabe.
  Set<String>? wahlSkills;

  /// Die KI-Werkzeuge, die die Lehrkraft im Dialog abgewählt hat
  /// (einrichtung.dart, KiWerkzeug.id). Gespeichert wird, was abgewählt
  /// ist, nicht was gewählt: So erscheint ein Werkzeug, das erst nach der
  /// App installiert wurde, von selbst im Dialog.
  Set<String> werkzeugeAbgewaehlt;

  /// Ob die App einmal täglich bei GitHub nach einer neuen Version sehen
  /// darf; null, solange nicht gefragt wurde (update.dart). Ohne
  /// ausdrückliches Ja fragt die App niemanden -- auch GitHub nicht.
  bool? updatePruefen;

  /// Tag der letzten Prüfung (`2026-10-03`), gesetzt auch nach einem
  /// Fehlversuch: Sonst wartete jemand ohne Netz bei jedem Start erneut auf
  /// die Zeitgrenze.
  String? updateZuletzt;

  /// Die Version, deren Installer gerade gestartet wurde; der nächste Start
  /// vergleicht sie mit der eigenen und meldet Erfolg oder Fehlschlag. Die
  /// App ist währenddessen beendet und sieht sonst nichts davon.
  String? updateErwartet;

  static File get _datei => einstellungenDatei;

  static String neuerSchluessel() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<Einstellungen> laden() async {
    final standard = Einstellungen(
      moodleAdresse: '',
      port: standardPort,
      schluessel: neuerSchluessel(),
    );
    try {
      if (await _datei.exists()) {
        final j = jsonDecode(await _datei.readAsString()) as Map<String, dynamic>;
        return Einstellungen.aus(j, standard);
      }
    } catch (_) {
      // Kaputte Datei: mit den Standardwerten weiter und beim Speichern ersetzen.
    }
    await standard.speichern();
    return standard;
  }

  /// Liest den Inhalt der Datei. Ohne `profile` (Stand bis Issue #4) wird die
  /// Adresse `moodleAdresse` zum ersten Profil; beim nächsten Speichern kommt
  /// `profile` dazu, `moodleAdresse` bleibt für ältere Versionen stehen.
  static Einstellungen aus(Map<String, dynamic> j, Einstellungen standard) {
    final liste = (j['profile'] as List?)?.map(Profil.ausJson).whereType<Profil>().toList();
    final altAdresse = j['moodleAdresse'] as String? ?? standard.moodleAdresse;
    return Einstellungen(
      moodleAdresse: altAdresse,
      profile: liste ?? (altAdresse.isEmpty ? [] : [Profil.migriert(altAdresse)]),
      port: j['port'] as int? ?? standard.port,
      schluessel: j['schluessel'] as String? ?? standard.schluessel,
      bestaetigungen: Bestaetigungen.ausText(j['bestaetigungen'] as String?),
      wahlSkills: (j['wahlSkills'] as List?)?.whereType<String>().toSet(),
      werkzeugeAbgewaehlt: (j['werkzeugeAbgewaehlt'] as List?)?.whereType<String>().toSet() ?? const {},
      updatePruefen: j['updatePruefen'] as bool?,
      updateZuletzt: j['updateZuletzt'] as String?,
      updateErwartet: j['updateErwartet'] as String?,
    );
  }

  /// Der Inhalt der Datei, wie ihn [speichern] schreibt.
  Map<String, Object?> zuJson() => {
        'moodleAdresse': moodleAdresse,
        'profile': [for (final p in profile) p.toJson()],
        'port': port,
        'schluessel': schluessel,
        'bestaetigungen': bestaetigungen.text,
        if (wahlSkills != null) 'wahlSkills': (wahlSkills!.toList()..sort()),
        if (werkzeugeAbgewaehlt.isNotEmpty) 'werkzeugeAbgewaehlt': (werkzeugeAbgewaehlt.toList()..sort()),
        if (updatePruefen != null) 'updatePruefen': updatePruefen,
        if (updateZuletzt != null) 'updateZuletzt': updateZuletzt,
        if (updateErwartet != null) 'updateErwartet': updateErwartet,
      };

  Future<void> speichern() async {
    await Directory(einstellungenOrdner).create(recursive: true);
    await _datei.writeAsString(const JsonEncoder.withIndent('  ').convert(zuJson()));
  }
}
