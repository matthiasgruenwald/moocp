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

const gruppierungsHinweis = 'Gruppen werden nicht mitgesichert. Die Zuordnung zu einer Gruppierung '
    'im Zielkurs ist nicht garantiert und wird nicht gegengeprüft. Vorhandene Gruppen und der '
    'Gruppenmodus ersetzen die Auswahl der Gruppierung nicht; nach der Wiederherstellung prüfen.';

/// Das `_userinfo`-Feld je Aktivität und je Abschnitt (gemessen: jedes Abschnittsfeld hat eines).
final RegExp _nutzerdatenUserinfo = RegExp(r'^setting_(activity|section)_[a-z0-9_]+_\d+_userinfo$');
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

final RegExp _abschnittEingeschaltet = RegExp(r'^setting_section_section_(\d+)_included$');

/// Die Abschnitte, die die Seite einschließt: id -> Wert ('1' oder '0').
/// Gemessen ist nur der Feldname (`setting_section_section_ABSCHNITTSID_included`).
Map<int, String> eingeschlosseneAbschnitte(List<MapEntry<String, String>> f) {
  final aus = <int, String>{};
  letzteWerte(f).forEach((k, v) {
    final m = _abschnittEingeschaltet.firstMatch(k);
    if (m != null) aus[int.parse(m.group(1)!)] = v;
  });
  return aus;
}

/// Zu welchem Abschnitt jede Aktivität gehört: cmid -> Abschnittsid. Gemessen:
/// Moodle setzt jede Aktivität hinter das Abschnittsfeld, zu dem sie gehört.
/// Eine Aktivität vor dem ersten Abschnittsfeld hat keinen Eintrag.
Map<int, int> abschnittJeAktivitaet(List<MapEntry<String, String>> f) {
  final aus = <int, int>{};
  int? abschnitt;
  for (final e in f) {
    final s = _abschnittEingeschaltet.firstMatch(e.key);
    if (s != null) {
      abschnitt = int.parse(s.group(1)!);
      continue;
    }
    final a = _aktivitaetEingeschaltet.firstMatch(e.key);
    if (a != null && abschnitt != null) aus.putIfAbsent(int.parse(a.group(1)!), () => abschnitt!);
  }
  return aus;
}

/// Die Aktivitäten, die eine Auswahl nennt: die gewählten und alle Aktivitäten
/// der gewählten Abschnitte.
Set<int> genannteAktivitaeten(
  List<MapEntry<String, String>> f, {
  required Set<int> cmids,
  required Set<int> abschnitte,
}) {
  final zu = abschnittJeAktivitaet(f);
  return {...cmids, for (final e in zu.entries) if (abschnitte.contains(e.value)) e.key};
}

/// Die Abschnitte, die eine Auswahl einschließen muss: die gewählten und der
/// Abschnitt jeder gewählten Aktivität. Moodle nimmt eine Aktivität nur mit,
/// wenn ihr Abschnitt eingeschlossen ist (gemessen). Dieser Abschnitt kommt
/// dann als Rahmen mit, ohne seine übrigen Aktivitäten.
Set<int> genannteAbschnitte(
  List<MapEntry<String, String>> f, {
  required Set<int> cmids,
  required Set<int> abschnitte,
}) {
  final zu = abschnittJeAktivitaet(f);
  return {...abschnitte, for (final c in cmids) if (zu[c] != null) zu[c]!};
}

/// Die Auswahl, wie sie auf der Schema-Seite (Schritt 2) stehen soll: ein
/// [cmids] und ein [abschnitte] nach der Angabe, dazu der Abschnitt jeder
/// gewählten Aktivität als Rahmen (siehe [genannteAbschnitte]). Alle übrigen
/// Aktivitäten und Abschnitte aus, `_userinfo` und Nutzerdaten aus. Null, wenn
/// eine Nummer auf der Seite fehlt oder eine gewählte Aktivität zu keinem
/// Abschnitt der Seite gehört. Die Seite wird nicht erweitert; jedes Feld behält
/// seine Stelle, nur der Wert ändert sich.
List<MapEntry<String, String>>? schemaWahl(
  List<MapEntry<String, String>> f, {
  required Set<int> cmids,
  required Set<int> abschnitte,
}) {
  final akt = eingeschlosseneAktivitaeten(f).keys.toSet();
  final sek = eingeschlosseneAbschnitte(f).keys.toSet();
  final zu = abschnittJeAktivitaet(f);
  if (!cmids.every(akt.contains) || !abschnitte.every(sek.contains)) return null;
  if (!cmids.every(zu.containsKey)) return null;
  final aktWahl = genannteAktivitaeten(f, cmids: cmids, abschnitte: abschnitte);
  final sekWahl = genannteAbschnitte(f, cmids: cmids, abschnitte: abschnitte);
  return [
    for (final e in f)
      MapEntry(e.key, _wahlWert(e.key, e.value, aktWahl, sekWahl)),
  ];
}

String _wahlWert(String k, String v, Set<int> aktWahl, Set<int> sekWahl) {
  final a = _aktivitaetEingeschaltet.firstMatch(k);
  if (a != null) return aktWahl.contains(int.parse(a.group(1)!)) ? '1' : '0';
  final s = _abschnittEingeschaltet.firstMatch(k);
  if (s != null) return sekWahl.contains(int.parse(s.group(1)!)) ? '1' : '0';
  if (_nutzerdatenUserinfo.hasMatch(k)) return '0';
  if (k.startsWith('setting_root_') && nutzerdatenOptionen.contains(k.substring('setting_root_'.length))) {
    return '0';
  }
  return v;
}

/// Prüft die Bestätigungsseite (Schritt 4) einer Auswahl gegen die Bestellung.
/// Erwartet eingeschaltet sind die genannten Aktivitäten ([genannteAktivitaeten])
/// und die genannten Abschnitte ([genannteAbschnitte]), sonst nichts, und keine
/// Nutzerdaten. Null heißt in Ordnung, sonst der Grund für den Abbruch vor der
/// Ausführung.
String? bestaetigungWahlFehler(
  List<MapEntry<String, String>> f, {
  required Set<int> cmids,
  required Set<int> abschnitte,
}) {
  if (schrittVon(f) != '4') {
    return 'Die Seite ist keine Bestätigung (Schritt ${schrittVon(f) ?? 'unbekannt'}).';
  }
  final erwartetAkt = genannteAktivitaeten(f, cmids: cmids, abschnitte: abschnitte);
  final erwartetSek = genannteAbschnitte(f, cmids: cmids, abschnitte: abschnitte);
  final akt = {
    for (final e in eingeschlosseneAktivitaeten(f).entries)
      if (e.value == '1') e.key,
  };
  final sek = {
    for (final e in eingeschlosseneAbschnitte(f).entries)
      if (e.value == '1') e.key,
  };
  if (akt.length != erwartetAkt.length || !akt.containsAll(erwartetAkt)) {
    final mehr = akt.difference(erwartetAkt).toList()..sort();
    final weniger = erwartetAkt.difference(akt).toList()..sort();
    return 'Die Bestätigung weicht bei den Aktivitäten ab (zu viel: ${mehr.join(', ')}; '
        'fehlt: ${weniger.join(', ')}).';
  }
  if (sek.length != erwartetSek.length || !sek.containsAll(erwartetSek)) {
    final mehr = sek.difference(erwartetSek).toList()..sort();
    final weniger = erwartetSek.difference(sek).toList()..sort();
    return 'Die Bestätigung weicht bei den Abschnitten ab (zu viel: ${mehr.join(', ')}; '
        'fehlt: ${weniger.join(', ')}).';
  }
  if (!ohneNutzerdaten(f)) return 'Die Bestätigung schaltet Nutzerdaten ein.';
  return null;
}

/// Was in einer Sicherung ohne Nutzerdaten fehlt, je Modultyp: nur die Typen,
/// die Lernende füllen. Der Text ist für die Freigabe gedacht.
///
/// UNGEMESSEN je Typ: ob Moodle die Einträge der Lehrkraft (Glossar,
/// Datenbank) trotzdem mitnimmt und wie weit Wiki-Seiten fehlen. Die Liste
/// ist eine Vorsicht: lieber zu viel nennen als etwas verschweigen.
const Map<String, String> _inhaltsLuecke = {
  'glossary': 'Glossar: Einträge der Lernenden',
  'data': 'Datenbank: Einträge der Lernenden',
  'forum': 'Forum: alle Beiträge',
  'wiki': 'Wiki: Seiten nur teilweise, Beiträge der Lernenden fehlen',
  'assign': 'Aufgabe: Abgaben und Bewertungen',
  'feedback': 'Feedback: Antworten',
  'questionnaire': 'Fragebogen: Antworten',
  'quiz': 'Test: Versuche und Antworten',
  'lesson': 'Lektion: Versuche und Antworten',
  'workshop': 'Workshop: Beiträge und Bewertungen',
  'choice': 'Auswahl: Antworten',
  'chat': 'Chat: Nachrichten',
  'journal': 'Journal: Einträge',
  'h5pactivity': 'H5P: Ergebnisse',
  'scorm': 'SCORM: Versuche',
};

/// Die Lücken zu den Modultypen [module], ohne Doppelte, in Reihenfolge.
List<String> inhaltsLuecken(Iterable<String> module) {
  final aus = <String>[];
  for (final m in module) {
    final t = _inhaltsLuecke[m];
    if (t != null && !aus.contains(t)) aus.add(t);
  }
  return aus;
}

/// Die Art einer Sicherung, wie sie in Freigabe und Protokoll steht. Eine
/// Einschränkung macht den ganzen Kurs nicht zu einer Auswahl: Der Typ hängt
/// nur am Kennzeichen „ganzer Kurs" und an der Zahl der gewählten Teile (null
/// oder nicht), nie an der Anzahl der Aktivitäten.
enum AuswahlArt {
  /// Der ganze Kurs, nichts eingeschränkt.
  ganzerKurs,

  /// Der ganze Kurs, aber nur die genannten Teile.
  ganzerKursEingeschraenkt,

  /// Teile eines Kurses, ohne Kennzeichen „ganzer Kurs".
  auswahl;

  String get text => switch (this) {
        ganzerKurs => 'ganzer Kurs',
        ganzerKursEingeschraenkt => 'ganzer Kurs, eingeschränkt auf die Auswahl',
        auswahl => 'Auswahl',
      };
}

AuswahlArt auswahlArt({required bool ganzerKurs, required bool nurGenannte}) {
  if (!ganzerKurs) return AuswahlArt.auswahl;
  return nurGenannte ? AuswahlArt.ganzerKursEingeschraenkt : AuswahlArt.ganzerKurs;
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

/// Frist für den Stillstandshinweis: so lange ohne neuen
/// Fortschrittswert gilt ein laufender Vorgang als möglicherweise hängend. Die
/// Lehrkraft hat 15 Minuten bestätigt. Ungemessen ist, wie lange Moodle für eine
/// Sicherung oder Wiederherstellung braucht; 15 Minuten sind ein Vielfaches des
/// 60-Sekunden-Zeitlimits des Werkzeugs und geben Cron oder einer Ad-hoc-Aufgabe
/// Zeit, weiterzulaufen, bevor die Lehrkraft die Administration bittet zu prüfen.
const Duration stillstandsFrist = Duration(minutes: 15);

/// Gilt ein laufender Vorgang als Stillstand: seit [seit] kein neuer Fortschritt,
/// mindestens [stillstandsFrist] lang. Ohne bekannten Zeitpunkt nie.
bool istStillstand(DateTime jetzt, DateTime? seit) =>
    seit != null && jetzt.difference(seit) >= stillstandsFrist;

/// Muss der Zeitpunkt der letzten Beobachtung neu gesetzt werden: bei geändertem Wert
/// und bei der ersten Beobachtung, auch ohne Fortschrittswert (null, und war schon null).
/// Sonst bliebe [seit] leer und ein Stillstand würde nie erkannt.
bool fortschrittNeuBeobachtet(double? alt, double? neu, DateTime? seit) => neu != alt || seit == null;

/// Der Hinweistext bei Stillstand. Feste Worte und Kennzahlen, keine
/// Moodle-Inhalte. Stillstand ist keine Aussage über Erfolg oder Fehler: Die letzte
/// Abfrage nannte weder Ende noch Fehler (oder die Angaben fehlten), und ob der
/// Vorgang hängt, ist nicht belegt.
String stillstandText({
  required String nummer,
  required String werkzeug,
  required double? fortschritt,
  required Duration seit,
  required String ursachen,
}) {
  final prozent = fortschritt == null ? 'unbekannt' : '${(fortschritt * 100).round()} %';
  return 'Stillstand (Nummer $nummer): Seit ${seit.inMinutes} Minuten kein neuer Fortschritt, '
      'letzte Beobachtung $prozent. Die letzte Abfrage nannte kein Ende und keinen Fehler; ob der Vorgang '
      'hängt, ist nicht belegt. Mögliche Ursachen: $ursachen '
      'Mit $werkzeug später erneut prüfen.';
}

/// Der Fortschrittswert (0 bis 1) des Vorgangs [backupid] aus der Antwort, oder null.
double? fortschrittswert(Object? antwort, String backupid) {
  final p = _eintrag(antwort, backupid)?['progress'];
  return p is num ? p.toDouble() : null;
}

Map? _eintrag(Object? antwort, String backupid) {
  Map? eintrag;
  final kandidaten = antwort is List ? antwort : [antwort];
  for (final x in kandidaten) {
    if (x is Map && '${x['backupid']}' == backupid) eintrag = x;
  }
  return eintrag;
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
  final eintrag = _eintrag(antwort, backupid);
  if (eintrag == null) return SicherungStand.unklar;
  if (eintrag['error'] != null || eintrag['errorcode'] != null) return SicherungStand.fehlgeschlagen;
  final p = eintrag['progress'];
  final s = eintrag['status'];
  if (p is num && s is num && p >= 1 && s == 1000) return SicherungStand.fertig;
  if (p is num && p < 1) return SicherungStand.laufend;
  return SicherungStand.unklar;
}

/// Ob Moodle den Vorgang als beendet mit Fehler führt (Status 800, `backup::STATUS_FINISHED_ERR`;
/// ungemessen). Ein Fehlerfeld allein belegt das Ende nicht: Ohne diesen Status kann der
/// Hintergrundauftrag noch laufen oder hängen.
bool fehlerBeendet(Object? antwort, String backupid) {
  final s = _eintrag(antwort, backupid)?['status'];
  return s is num && s == 800;
}

/// Die Art des gemeldeten Fehlers, nur als kurzer Bezeichner (Fehlercode, sonst das Fehlerfeld,
/// wenn es ein solcher ist). Freitext kann Inhalte tragen (E11) und wird nie übernommen.
String fehlerArt(Object? antwort, String backupid) {
  final eintrag = _eintrag(antwort, backupid);
  final bezeichner = RegExp(r'^[A-Za-z0-9_.\-]{1,80}$');
  for (final feld in ['errorcode', 'error']) {
    final w = eintrag?[feld];
    if (w is String && bezeichner.hasMatch(w)) return w;
  }
  return 'nicht benannt';
}

/// Die Downloadpfade (von /pluginfile.php an, mit Query) der Sicherung
/// [dateiname] auf der Seite /backup/restorefile.php. Gesucht wird genau der
/// eigene Dateiname; andere Sicherungen auf derselben Seite bleiben außen vor.
/// Die App nimmt nur einen Treffer; keiner oder mehrere heißen: nicht raten.
///
/// Warum diese Seite und nicht core_backup_get_async_backup_links_backup: Der
/// Dienst meldet für eine fertige Sicherung `backup_controller_dbops_loading_
/// invalid_controller` (Messung auf der Testinstanz). Die Seite listet dieselbe
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
  final modulTeil = modul.replaceAll(RegExp(r'[^a-z0-9_]'), '');
  return '$modulTeil-cm$cmid-${_stempel(zeit)}.mbz';
}

/// Der Dateiname einer Auswahl aus dem Kurs: die Kursnummer und der Zeitpunkt.
/// Kein Kursname, keine Person.
String kursSicherungsName(int kurs, DateTime zeit) => 'kurs-k$kurs-${_stempel(zeit)}.mbz';

String _stempel(DateTime zeit) {
  String zwei(int n) => n.toString().padLeft(2, '0');
  return '${zeit.year}-${zwei(zeit.month)}-${zwei(zeit.day)}_'
      '${zwei(zeit.hour)}${zwei(zeit.minute)}${zwei(zeit.second)}';
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

/// Der Text, den ein Werkzeug bei Zeitlimit zurückgibt (Befund 9). Ist die
/// Nummer schon vergeben, nennt er sie und genau einen Folgeaufruf. Ist sie es
/// nicht, sagt er das, und es gibt keinen Folgeaufruf mit einer Nummer, die es
/// noch nicht gibt. In beiden Fällen ist nichts neu gestartet.
String laufText(String was, String? nummer, String werkzeug) => nummer == null
    ? '$was läuft noch. Die normale Antwortfrist des Werkzeugaufrufs ist erreicht; das ist kein Fehler '
        'und kein Abbruch. Die Nummer steht noch nicht fest; es ist noch nichts gestartet. '
        'Gegebenenfalls die Freigabe in der App beantworten. Den Auftrag nicht erneut senden.'
    : '$was läuft weiter (Nummer $nummer). Die normale Antwortfrist des Werkzeugaufrufs ist erreicht; '
        'das ist kein Fehler und kein Abbruch. Die Arbeit läuft im Hintergrund weiter. '
        'Mit $werkzeug und der Nummer $nummer in Abständen bis zu 30 Minuten weiterfragen. '
        'Den Auftrag nicht erneut senden; echte Fehler oder Stillstandshinweise des Statuswerkzeugs weitergeben.';
