// Regeln für die Sicherung einer Aktivität: reine Funktionen ohne Netz und ohne
// Datei. Die Positivliste in moodle_zugang.dart und der Ablauf in sicherung.dart
// prüfen dasselbe hier, und die Tests prüfen es gegen HTML-Vorlagen
// (test/sicherung_regeln_test.dart).
//
// Gemessen (docs/plans/moodle-sicherung-formulare.md): Die Schritte laufen über
// /backup/backup.php mit dem versteckten Feld stage (1, 2, 4). setting_root_users=0
// steht auf dem geprüften Konto bereits im Formular. Alles andere hier ist
// UNGEMESSEN und ist im Code als solches markiert.

/// Die Nutzerdaten-Optionen der Sicherung. Alle aus, sonst fällt die Sicherung
/// nicht unter „ohne Nutzerdaten". UNGEMESSEN außer users und enrolments; die
/// übrigen sind die Namen des Moodle-Kerns und stehen auf der Liste, damit sie
/// nicht still eingeschaltet bleiben.
const Set<String> nutzerdatenOptionen = {
  'users', 'enrolments', 'groups', 'userscompletion', 'logs', 'grade_histories', 'badges',
};

final RegExp _nutzerdatenUserinfo = RegExp(r'^setting_activity_[a-z0-9_]+_\d+_userinfo$');
final RegExp _aktivitaetEingeschaltet = RegExp(r'^setting_activity_[a-z0-9_]+_(\d+)_included$');

/// Der letzte Wert je Feldname. Moodle setzt vor jedes Kontrollkästchen ein
/// verstecktes Feld mit 0, und PHP nimmt den letzten Wert.
Map<String, String> letzteWerte(List<MapEntry<String, String>> f) => {for (final e in f) e.key: e.value};

/// Sind alle Nutzerdaten-Optionen aus? Fehlende Felder zählen als aus, ein
/// eingeschaltetes Feld nicht.
bool ohneNutzerdaten(List<MapEntry<String, String>> f) {
  for (final e in letzteWerte(f).entries) {
    final k = e.key;
    if (k.startsWith('setting_root_') &&
        nutzerdatenOptionen.contains(k.substring('setting_root_'.length)) &&
        e.value != '0') {
      return false;
    }
    if (_nutzerdatenUserinfo.hasMatch(k) && e.value != '0') return false;
  }
  return true;
}

/// Die Stufe der Seite (stage), als Text, oder null.
String? schrittVon(List<MapEntry<String, String>> f) => letzteWerte(f)['stage'];

/// Die Aktivitäten, die die Seite einschließt: cmid -> Wert ('1' oder '0').
/// Auf der Schema- und der Bestätigungsseite sind das die versteckten
/// `setting_activity_<art>_<cmid>_included`-Felder.
Map<int, String> eingeschlosseneAktivitaeten(List<MapEntry<String, String>> f) {
  final aus = <int, String>{};
  letzteWerte(f).forEach((k, v) {
    final m = _aktivitaetEingeschaltet.firstMatch(k);
    if (m != null) aus[int.parse(m.group(1)!)] = v;
  });
  return aus;
}

/// Prüft die Bestätigungsseite (Schritt 4) gegen die Bestellung, bevor etwas
/// ausgeführt wird: genau diese Aktivität ist eingeschaltet, keine andere, und
/// keine Nutzerdaten. Null heißt in Ordnung, sonst der Grund für den Abbruch.
String? bestaetigungFehler(List<MapEntry<String, String>> f, {required int cmid}) {
  if (schrittVon(f) != '4') {
    return 'Die Seite ist keine Bestätigung (Schritt ${schrittVon(f) ?? 'unbekannt'}).';
  }
  final auswahl = eingeschlosseneAktivitaeten(f);
  if (auswahl[cmid] != '1') {
    return 'Die Bestätigung nennt nicht die gewählte Aktivität (cmid $cmid).';
  }
  for (final e in auswahl.entries) {
    if (e.key != cmid && e.value == '1') {
      return 'Die Bestätigung nimmt eine weitere Aktivität mit (cmid ${e.key}).';
    }
  }
  if (!ohneNutzerdaten(f)) return 'Die Bestätigung schaltet Nutzerdaten ein.';
  return null;
}

/// Schaltet auf einer Seite alle Nutzerdaten-Optionen aus, die sie schon
/// enthält (Schritt 1). Fehlende Felder bleiben fehlend.
List<MapEntry<String, String>> nutzerdatenAus(List<MapEntry<String, String>> f) {
  final neu = [...f];
  for (final k in letzteWerte(f).keys) {
    final rootOption = k.startsWith('setting_root_') && nutzerdatenOptionen.contains(k.substring('setting_root_'.length));
    if (rootOption || _nutzerdatenUserinfo.hasMatch(k)) {
      for (var i = 0; i < neu.length; i++) {
        if (neu[i].key == k) neu[i] = MapEntry(k, '0');
      }
    }
  }
  return neu;
}

/// Setzt auf der Schema-Seite (Schritt 2) genau die eine Aktivität ein und
/// alle anderen aus. Gibt die Felder zurück, die gesendet werden. Nutzerdaten
/// werden ausgeschaltet. Null, wenn die Aktivität auf der Seite fehlt.
List<MapEntry<String, String>>? schemaAuswahl(List<MapEntry<String, String>> f, {required int cmid}) {
  if (!eingeschlosseneAktivitaeten(f).containsKey(cmid)) return null;
  final neu = [...f];
  void setze(String name, String wert) {
    for (var i = neu.length - 1; i >= 0; i--) {
      if (neu[i].key == name) {
        neu[i] = MapEntry(name, wert);
        return;
      }
    }
    neu.add(MapEntry(name, wert));
  }

  for (final k in letzteWerte(f).keys) {
    final m = _aktivitaetEingeschaltet.firstMatch(k);
    if (m != null) setze(k, int.parse(m.group(1)!) == cmid ? '1' : '0');
    if (_nutzerdatenUserinfo.hasMatch(k)) setze(k, '0');
    if (k.startsWith('setting_root_') && nutzerdatenOptionen.contains(k.substring('setting_root_'.length))) {
      setze(k, '0');
    }
  }
  return neu;
}

// ---------------------------------------------------------------------------
// Zustand und Fortschritt
// ---------------------------------------------------------------------------

/// Der Stand eines Sicherungsvorgangs. „unklar" heißt: Moodle hat etwas
/// geantwortet, das die App nicht zuordnen kann. Es heißt nicht „fehlgeschlagen".
enum SicherungStand {
  /// Bestellt, Moodle hat noch nicht angefangen.
  anstehend,

  /// Läuft im Hintergrund.
  laufend,

  /// Moodle meldet Ende, und der Downloadlink ist da.
  fertig,

  /// Moodle meldet einen Fehler.
  fehlgeschlagen,

  /// Die Antwort passt auf kein bekanntes Muster; sicherung_status prüft erneut.
  unklar;

  String get text => switch (this) {
        anstehend => 'anstehend',
        laufend => 'laufend',
        fertig => 'fertig',
        fehlgeschlagen => 'fehlgeschlagen',
        unklar => 'unklar',
      };

  static SicherungStand? aus(String? s) {
    for (final v in values) {
      if (v.name == s) return v;
    }
    return null;
  }
}

/// Liest den Eintrag der Sicherung [backupid] aus der Antwort von
/// core_backup_get_async_backup_progress.
///
/// UNGEMESSEN: die Form der Antwort. Angenommen wird eine Liste von Einträgen
/// mit backupid, progress (0 bis 1) und status. Gemessen ist nur das Ende:
/// progress=1 und status=1000. Ein Fehlerfeld (error oder errorcode) gilt als
/// fehlgeschlagen. Alles andere, das nicht eindeutig läuft oder endet, ist
/// unklar.
SicherungStand bewerteFortschritt(Object? antwort, String backupid) {
  Map? eintrag;
  final kandidaten = antwort is List ? antwort : [antwort];
  for (final x in kandidaten) {
    if (x is Map && '${x['backupid']}' == backupid) eintrag = x;
  }
  if (eintrag == null) return SicherungStand.unklar;
  if (eintrag['error'] != null || eintrag['errorcode'] != null) return SicherungStand.fehlgeschlagen;
  final p = eintrag['progress'];
  final s = eintrag['status'];
  if (p is num && s is num && p >= 1 && s == 1000) return SicherungStand.fertig;
  if (p is num && p < 1) return SicherungStand.laufend;
  return SicherungStand.unklar;
}

/// Die Downloadpfade (von /pluginfile.php an, mit Query) der Sicherung
/// [dateiname] auf der Seite /backup/restorefile.php. Gesucht wird genau der
/// eigene Dateiname; andere Sicherungen auf derselben Seite bleiben außen vor.
/// Die App nimmt nur einen Treffer; keiner oder mehrere heißen: nicht raten.
///
/// Warum diese Seite und nicht core_backup_get_async_backup_links_backup: Der
/// Dienst meldet für eine fertige Sicherung `backup_controller_dbops_loading_
/// invalid_controller` (Messung im Spike, Kurs 41). Die Seite listet dieselbe
/// Datei mit Downloadlink.
///
/// UNGEMESSEN: ob die Seite die Datei immer listet (Rechte, Papierkorb,
/// Abstände); das zeigt die Messung im Testkurs.
List<String> sicherungsLinks(String html, String dateiname) {
  final name = RegExp.escape(dateiname);
  final muster = RegExp('/pluginfile\\.php/\\d+/user/backup/(?:\\d+/)?$name\\?forcedownload=1(?=["\'\\s<>])');
  final treffer = <String>{};
  for (final m in muster.allMatches(html.replaceAll('&amp;', '&'))) {
    treffer.add(m.group(0)!);
  }
  return treffer.toList();
}

/// Der Dateiname im Sicherungsordner: Modul und cmid, Zeitpunkt. Kein Name
/// aus Moodle, kein Kursname, keine Person.
String sicherungsName(String modul, int cmid, DateTime zeit) {
  String zwei(int n) => n.toString().padLeft(2, '0');
  final modulTeil = modul.replaceAll(RegExp(r'[^a-z0-9_]'), '');
  final stempel = '${zeit.year}-${zwei(zeit.month)}-${zwei(zeit.day)}_'
      '${zwei(zeit.hour)}${zwei(zeit.minute)}${zwei(zeit.second)}';
  return '$modulTeil-cm$cmid-$stempel.mbz';
}

/// Ein Zielordner im Sicherungsordner. Nur relative Pfade ohne „..", ohne
/// Laufwerk und ohne Sonderzeichen; sonst null.
String? zielOrdnerPruefen(String? ordner) {
  if (ordner == null || ordner.trim().isEmpty) return '';
  final t = ordner.trim().replaceAll('\\', '/');
  if (t.startsWith('/') || t.contains(':') || t.contains('\u0000')) return null;
  final teile = t.split('/').where((s) => s.isNotEmpty).toList();
  if (teile.any((s) => s == '..' || s == '.')) return null;
  if (!teile.every((s) => RegExp(r'^[A-Za-z0-9_ äöüÄÖÜß-]+$').hasMatch(s))) return null;
  return teile.join('/');
}
