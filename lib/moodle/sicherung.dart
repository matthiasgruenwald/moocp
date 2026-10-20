// Die Sicherung einer einzelnen Aktivität in eine Datei auf dem Rechner.
//
// Ablauf (Schritte 1, 2 und 4 des Sicherungsassistenten, Nutzerdaten aus; die
// Regeln stehen in sicherung_regeln.dart):
//   Kurs und Name prüfen -> Schritt 1 -> Schritt 2 (genau diese Aktivität) ->
//   Bestätigungsseite gegen die Bestellung prüfen -> Freigabe in der App ->
//   Schritt 4 starten -> Fortschritt abfragen -> Datei holen, Größe prüfen.
//
// Der Vorgang steht von Anfang an in vorgaenge.json, auch während auf die
// Freigabe gewartet wird. Bricht der Client ab, bleibt der Eintrag; sicherung_status
// greift ihn wieder auf, ohne die App neu zu starten.
//
// Ablage: <Einstellungsordner>/sicherungen, außerhalb des Arbeitsordners
// (E29). Dateinamen tragen Modul, cmid und Zeitpunkt, sonst nichts.
//
// Gemessen ist der Ablauf bis Schritt 2 (docs/plans/moodle-sicherung-formulare.md).
// Die Stellen mit UNGEMESSEN stehen im Code und in TODO.md.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

import '../freigabe.dart';
import 'formular.dart';
import 'formular_lesen.dart';
import 'formular_schreiben.dart';
import 'kurs.dart';
import 'moodle_zugang.dart';
import 'sicherung_regeln.dart';
import 'wiederherstellung_regeln.dart';
import 'wiederherstellung_fragen.dart';

/// Vorgänge, die gerade laufen (Freigabe oder Abfrage) in dieser Sitzung der App.
final Set<String> _laufend = {};

/// Uhr und Wartezeit. Nur Testnähte: Tests setzen sie auf
/// einen Zeitverlauf, damit Zeitlimit und Stillstand ohne echtes Warten laufen.
DateTime Function() jetzt = DateTime.now;
Future<void> Function(Duration d) schlafe = (d) => Future<void>.delayed(d);

/// Ein Sicherungsvorgang mit Kennzahlen und Prüfbefunden. Wiederherstellungen
/// behalten zusätzlich ihre Quellaufnahme für eine spätere Rückleseprobe.
class Vorgang {
  Vorgang({
    required this.id,
    required this.kurs,
    required this.cmid,
    required this.datei,
    required this.stand,
    required this.begonnen,
    DateTime? aktualisiert,
    this.backupid,
    this.kontext,
    this.fortschritt,
    this.fortschrittSeit,
    this.dateiname,
    this.text = '',
    this.bytes,
    this.verified = false,
    this.auswahl,
    this.wiederherstellung,
    this.wiederherstellungDatei,
    this.vorherCmids,
    this.wiederherstellungAktivitaeten,
    this.fingerabdruck,
    this.wiederholungVon,
    this.profilKennung,
    this.instanzAdresse,
    this.quizQuellen,
    this.herkunftEigen = false,
    this.sichtbarkeit = WiederherstellungsSichtbarkeit.verborgen,
  }) : aktualisiert = aktualisiert ?? begonnen;

  final String id;
  final int kurs;
  final int cmid;

  /// Pfad der Datei relativ zum Sicherungsordner.
  final String datei;
  SicherungStand stand;
  final DateTime begonnen;
  DateTime aktualisiert;

  /// Moodle-Nummer der Sicherung und Kontext-Nummer, für die Abfrage.
  String? backupid;
  int? kontext;

  /// Letzter Fortschrittswert (0 bis 1) und der Zeitpunkt, seit dem er unverändert
  /// ist. Daraus entsteht der Stillstandshinweis.
  double? fortschritt;
  DateTime? fortschrittSeit;

  /// Dateiname, den Moodle für die Sicherung führt (setting_root_filename).
  String? dateiname;

  /// Ein fester, kurzer Hinweis zum Stand. Ohne Inhalte aus Moodle.
  String text;
  int? bytes;
  bool verified;

  /// Bei einer Auswahl aus dem Kurs (sichern_auswahl) statt der einen cmid: Art und Zahlen.
  String? auswahl;

  /// Nur bei einer Wiederherstellung (wiederherstellung.dart): ihr Stand, die
  /// Laufzeitkennung von Moodle und die Nummern der Aktivitäten im Zielkurs vor
  /// dem Start. Die Sicherung nutzt diese Felder nicht.
  WiederherstellungStand? wiederherstellung;
  String? wiederherstellungDatei;
  List<int>? vorherCmids;
  List<ArchivAktivitaet>? wiederherstellungAktivitaeten;

  /// Doppelstart-Schutz: Inhalts- und Zielschlüssel (fingerabdruck) und
  /// bei einer bewusst wiederholten Wiederherstellung die Nummer des überholten Vorgangs.
  String? fingerabdruck;
  String? wiederholungVon;

  /// Stabile Zielidentität; null bei Altvorgängen mit Anzeigenamen im Fingerabdruck.
  String? profilKennung;

  /// Normalisierte tatsächliche Moodle-Basisadresse einschließlich Installationspfad.
  String? instanzAdresse;

  /// Quellfragen bleiben auch ohne laufende Sitzung für den Vergleich verfügbar.
  Map<String, List<QuizFrage>>? quizQuellen;

  /// Die Fragenherkunft war vor dem Start als eigen belegt; bleibt für spätere Statusabfragen erhalten.
  bool herkunftEigen;

  /// Altvorgänge behalten das bisherige Verbergen, auch nach einem Neustart.
  WiederherstellungsSichtbarkeit sichtbarkeit;

  Map<String, Object?> zuJson() => {
        'id': id,
        'kurs': kurs,
        'cmid': cmid,
        'datei': datei,
        'stand': stand.name,
        'begonnen': begonnen.toIso8601String(),
        'aktualisiert': aktualisiert.toIso8601String(),
        'backupid': backupid,
        'kontext': kontext,
        'fortschritt': fortschritt,
        'fortschritt_seit': fortschrittSeit?.toIso8601String(),
        'dateiname': dateiname,
        'text': text,
        'bytes': bytes,
        'verified': verified,
        'auswahl': auswahl,
        'wiederherstellung_status': wiederherstellung?.name,
        'wiederherstellung_laufzeit': wiederherstellungDatei,
        'vorher_cmids': vorherCmids,
        'wiederherstellung_aktivitaeten': wiederherstellungAktivitaeten?.map((a) => {'modul': a.modul, 'titel': a.titel}).toList(),
        'fingerabdruck': fingerabdruck,
        'wiederholung_von': wiederholungVon,
        'profil_kennung': profilKennung,
        'instanz_adresse': instanzAdresse,
        'herkunft_eigen': herkunftEigen,
        'sichtbarkeit': sichtbarkeit.wert,
        'quiz_quellen': quizQuellen?.map((titel, fragen) => MapEntry(titel, [
              for (final f in fragen) {'name': f.name, 'sachnummer': f.sachnummer, 'zufall': f.zufall, 'lokal': f.lokal},
            ])),
      };

  static Vorgang? ausJson(Object? o) {
    if (o is! Map) return null;
    final stand = SicherungStand.aus(o['stand'] as String?);
    final id = o['id'], kurs = o['kurs'], cmid = o['cmid'], datei = o['datei'];
    if (stand == null || id is! String || kurs is! int || cmid is! int || datei is! String) return null;
    return Vorgang(
      id: id,
      kurs: kurs,
      cmid: cmid,
      datei: datei,
      stand: stand,
      begonnen: DateTime.tryParse('${o['begonnen']}') ?? DateTime.now(),
      aktualisiert: DateTime.tryParse('${o['aktualisiert']}'),
      backupid: o['backupid'] as String?,
      kontext: o['kontext'] as int?,
      fortschritt: (o['fortschritt'] as num?)?.toDouble(),
      fortschrittSeit: DateTime.tryParse('${o['fortschritt_seit']}'),
      dateiname: o['dateiname'] as String?,
      text: o['text'] as String? ?? '',
      bytes: o['bytes'] as int?,
      verified: o['verified'] == true,
      auswahl: o['auswahl'] as String?,
      wiederherstellung: WiederherstellungStand.aus(o['wiederherstellung_status'] as String?),
      wiederherstellungDatei: o['wiederherstellung_laufzeit'] as String?,
      vorherCmids: (o['vorher_cmids'] as List?)?.whereType<int>().toList(),
      wiederherstellungAktivitaeten: (o['wiederherstellung_aktivitaeten'] as List?)
          ?.whereType<Map>()
          .where((a) => a['modul'] is String && a['titel'] is String)
          .map((a) => (modul: a['modul'] as String, titel: a['titel'] as String))
          .toList(),
      fingerabdruck: o['fingerabdruck'] as String?,
      wiederholungVon: o['wiederholung_von'] as String?,
      profilKennung: o['profil_kennung'] as String?,
      instanzAdresse: o['instanz_adresse'] as String?,
      herkunftEigen: o['herkunft_eigen'] == true,
      sichtbarkeit: WiederherstellungsSichtbarkeit.aus(o['sichtbarkeit'] as String? ?? 'verborgen'),
      quizQuellen: _quizQuellenAus(o['quiz_quellen']),
    );
  }
}

Map<String, List<QuizFrage>>? _quizQuellenAus(Object? o) {
  if (o is! Map) return null;
  return {
    for (final e in o.entries)
      if (e.key is String && e.value is List)
        e.key as String: [
          for (final f in (e.value as List).whereType<Map>())
            if (f['name'] is String && f['zufall'] is bool)
              (name: f['name'] as String, sachnummer: f['sachnummer'] as String?, zufall: f['zufall'] as bool, lokal: f['lokal'] as bool?),
        ],
  };
}

/// Alle Vorgänge im Sicherungsordner, in vorgaenge.json. Geschrieben wird über
/// eine Datei .tmp, die dann umbenannt wird; ein Absturz hinterlässt also
/// entweder den alten oder den neuen Stand.
class Vorgaenge {
  Vorgaenge(this.ordner, {this.profilKennung, this.instanzBasis});

  final String ordner;
  final String? profilKennung;

  /// Der angemeldete Zugang kann nach Abmelden eine andere Basis haben. Darum
  /// wird vor dem Fortsetzen stets die aktuelle Basis gelesen.
  final Uri? Function()? instanzBasis;

  String? get instanzAdresse {
    final basis = instanzBasis?.call();
    if (basis == null || basis.host.isEmpty || !{'https', 'http'}.contains(basis.scheme)) return null;
    final pfad = basis.normalizePath().path.replaceFirst(RegExp(r'/+$'), '');
    return Uri(scheme: basis.scheme, host: basis.host, port: basis.hasPort ? basis.port : null, path: pfad).toString();
  }

  bool _passt(Vorgang v) =>
      (profilKennung == null || v.profilKennung == profilKennung) &&
      (instanzBasis == null || (instanzAdresse != null && v.instanzAdresse == instanzAdresse));

  /// Prüft erneut, bevor ein Hintergrundvorgang Moodle anfragt oder verändert.
  void pruefeBindung(Vorgang v) {
    if (!_passt(v)) {
      throw MoodleFehler('Der Vorgang gehört nicht zur aktuell angemeldeten Moodle-Instanz. Nichts weiter ausgeführt.');
    }
  }

  // Alle MCP-Sitzungen und Profile teilen dieselbe Datei. Eine Änderung liest
  // unter dieser Sperre frisch und ersetzt nur ihren eigenen Vorgang, damit
  // ein alter Sitzungsstand keine neueren Vorgänge überschreibt.
  static final Map<String, Future<void>> _schreibend = {};
  String get _schluessel => p.normalize(p.absolute(ordner));
  File get _datei => File(p.join(ordner, 'vorgaenge.json'));

  Future<List<Vorgang>> _lesen() async {
    if (!await _datei.exists()) return [];
    final Object? roh;
    try {
      roh = jsonDecode(await _datei.readAsString());
    } catch (_) {
      throw MoodleFehler('vorgaenge.json im Sicherungsordner ist beschädigt. Nichts geändert.');
    }
    if (roh is! List) {
      throw MoodleFehler('vorgaenge.json im Sicherungsordner ist beschädigt. Nichts geändert.');
    }
    return [for (final x in roh) if (Vorgang.ausJson(x) case final Vorgang v) v];
  }

  Future<List<Vorgang>> _alle() async {
    final vorher = _schreibend[_schluessel];
    if (vorher != null) {
      try {
        await vorher;
      } catch (_) {
        // Der Schreibaufruf hat den Fehler bereits gemeldet. Frisch lesen
        // entscheidet, ob die Datei inzwischen wieder nutzbar ist.
      }
    }
    return _lesen();
  }

  Future<List<Vorgang>> alle() async => [
    for (final v in await _alle())
      if (_passt(v)) v,
  ];

  /// Alte Vorgänge ohne Profilbindung dürfen sperren, aber keine Statusabfrage
  /// auf einer möglicherweise falschen Instanz auslösen.
  Future<List<Vorgang>> alleFuerDoppelstart() async => [
    for (final v in await _alle())
      if ((profilKennung == null || v.profilKennung == null || v.profilKennung == profilKennung) &&
          (instanzBasis == null || v.instanzAdresse == null || v.instanzAdresse == instanzAdresse)) v,
  ];

  Future<Vorgang?> finde(String id) async {
    for (final v in await alle()) {
      if (v.id == id) return v;
    }
    return null;
  }

  Future<Vorgang> neu({required int kurs, required int cmid, required String datei, String? auswahl}) async {
    final v = Vorgang(
      id: '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
          '${Random.secure().nextInt(0xffff).toRadixString(36)}',
      kurs: kurs,
      cmid: cmid,
      datei: datei,
      stand: SicherungStand.anstehend,
      begonnen: DateTime.now(),
      auswahl: auswahl,
      profilKennung: profilKennung,
      instanzAdresse: instanzAdresse,
    );
    await _speichern(v);
    return v;
  }

  /// Ein Vorgang für die Wiederherstellung. Die Datei liegt relativ zum
  /// Sicherungsordner; der Kurs ist der Zielkurs.
  Future<Vorgang> neuWiederherstellung({
    required int kurs,
    required String datei,
    String? fingerabdruck,
    String? wiederholungVon,
    String? profilKennung,
    Map<String, List<QuizFrage>>? quizQuellen,
    bool herkunftEigen = false,
    WiederherstellungsSichtbarkeit sichtbarkeit = WiederherstellungsSichtbarkeit.wieQuelle,
  }) async {
    final v = await neu(kurs: kurs, cmid: 0, datei: datei);
    v.wiederherstellung = WiederherstellungStand.anstehend;
    v.fingerabdruck = fingerabdruck;
    v.wiederholungVon = wiederholungVon;
    v.profilKennung = profilKennung ?? this.profilKennung;
    v.quizQuellen = quizQuellen;
    v.herkunftEigen = herkunftEigen;
    v.sichtbarkeit = sichtbarkeit;
    await _speichern(v);
    return v;
  }

  Future<void> aktualisieren(
    Vorgang v, {
    SicherungStand? stand,
    String? text,
    String? backupid,
    int? kontext,
    double? fortschritt,
    DateTime? fortschrittSeit,
    String? dateiname,
    int? bytes,
    bool? verified,
    WiederherstellungStand? wiederherstellung,
    String? wiederherstellungDatei,
    List<int>? vorherCmids,
    List<ArchivAktivitaet>? wiederherstellungAktivitaeten,
  }) async {
    if (wiederherstellung != null) v.wiederherstellung = wiederherstellung;
    if (wiederherstellungDatei != null) v.wiederherstellungDatei = wiederherstellungDatei;
    if (vorherCmids != null) v.vorherCmids = vorherCmids;
    if (wiederherstellungAktivitaeten != null) v.wiederherstellungAktivitaeten = wiederherstellungAktivitaeten;
    if (stand != null) v.stand = stand;
    if (text != null) v.text = text;
    if (backupid != null) v.backupid = backupid;
    if (kontext != null) v.kontext = kontext;
    if (fortschritt != null) v.fortschritt = fortschritt;
    if (fortschrittSeit != null) v.fortschrittSeit = fortschrittSeit;
    if (dateiname != null) v.dateiname = dateiname;
    if (bytes != null) v.bytes = bytes;
    if (verified != null) v.verified = verified;
    v.aktualisiert = DateTime.now();
    await _speichern(v);
  }

  Future<void> _speichern(Vorgang v) {
    final vorher = _schreibend[_schluessel] ?? Future<void>.value();
    final schreiben = vorher.catchError((Object _) {
      // Ein früher fehlgeschlagener Auftrag meldet seinen Fehler selbst; ein
      // späterer Auftrag darf nach Behebung der Datei wieder speichern.
    }).then((_) async {
      final liste = await _lesen();
      final i = liste.indexWhere((x) => x.id == v.id);
      if (i < 0) {
        liste.add(v);
      } else {
        liste[i] = v;
      }
      await Directory(ordner).create(recursive: true);
      final tmp = File('${_datei.path}.tmp');
      await tmp.writeAsString(jsonEncode([for (final x in liste) x.zuJson()]), flush: true);
      await tmp.rename(_datei.path);
    });
    _schreibend[_schluessel] = schreiben;
    return schreiben;
  }
}

/// Die Angaben der Doppelstart-Prüfung zu allen Vorgängen, in der gespeicherten Reihenfolge.
List<DoppelstartEintrag> doppelstartEintraege(Iterable<Vorgang> alle) => [
      for (final v in alle)
        (
          id: v.id,
          fingerabdruck: v.fingerabdruck,
          wiederholungVon: v.wiederholungVon,
          stand: v.wiederherstellung,
          kurs: v.kurs,
        ),
    ];

/// Ein Dateiname, den es in [ordner] noch nicht gibt, auch nicht als Teil einer
/// laufenden Übertragung. Nie überschreiben: aus `x.mbz` wird `x-2.mbz`.
Future<String> freierName(String ordner, String basis) async {
  final stamm = basis.endsWith('.mbz') ? basis.substring(0, basis.length - 4) : basis;
  var name = basis;
  var n = 2;
  while (await File(p.join(ordner, name)).exists() || await File(p.join(ordner, '$name.teil')).exists()) {
    name = '$stamm-$n.mbz';
    n++;
  }
  return name;
}

/// Die Antwortseite einer Sicherung: Ziel, Felder, Seitenangaben.
({String aktion, Felder felder, Seitenangaben seite}) seiteVon(Antwort r) {
  final dom.Element? form = hauptformular(html_parser.parse(r.text));
  if (form == null) {
    throw MoodleFehler('Moodle liefert kein Sicherungsformular. Ist die Aktivität für diese Sitzung sicherbar?');
  }
  final ziel = r.adresse.resolve(form.attributes['action'] ?? r.adresse.path);
  return (
    aktion: ziel.hasQuery ? '${ziel.path}?${ziel.query}' : ziel.path,
    felder: formularFelder(form),
    seite: Seitenangaben.aus(r.text),
  );
}

/// Sichert eine Aktivität. Gibt den Ergebnistext zurück; wartet höchstens auf
/// Freigabe und Sicherung. Danach läuft nichts mehr ohne den Vorgang in
/// [vorgaenge] -- sicherung_status nimmt ihn wieder auf.
Future<String> aktivitaetSichern(
  MoodleZugang moodle,
  Freigaben freigaben,
  Vorgaenge vorgaenge, {
  required int kurs,
  required int cmid,
  required String name,
  String? zielOrdner,
  void Function(String vorgangId)? beiVorgang,
}) async {
  final ziel = zielOrdnerPruefen(zielOrdner);
  if (ziel == null) {
    throw MoodleFehler('ziel_ordner ist ungültig: nur Ordnernamen relativ zum Sicherungsordner, ohne „..", '
        'ohne Laufwerk und ohne Sonderzeichen.');
  }
  final k = await kursLesen(moodle, kurs);
  final a = k.nachCmid[cmid];
  if (a == null) throw MoodleFehler('cmid $cmid gibt es in Kurs $kurs nicht. Nummer prüfen (kurs_uebersicht).');
  nameBestaetigen(name, a.name, 'cmid $cmid');

  // Schritt 1: Nutzerdaten aus, weiter.
  final f1 = await formularHolen(moodle, '/backup/backup.php?id=$kurs&cm=$cmid');
  if (schrittVon(f1.felder) != '1') {
    throw MoodleFehler('Die Sicherung beginnt nicht auf Schritt 1. Nichts gestartet.');
  }
  final r2 = await moodle.senden(f1.aktion, [...nutzerdatenAus(f1.felder), const MapEntry('submitbutton', 'Weiter')]);
  final s2 = seiteVon(r2);
  if (schrittVon(s2.felder) != '2') {
    throw MoodleFehler('Die Auswahlseite der Sicherung kommt nicht wie gemessen. Nichts gestartet.');
  }

  // Schritt 2: genau diese Aktivität.
  final auswahl = schemaAuswahl(s2.felder, cmid: cmid);
  if (auswahl == null) {
    throw MoodleFehler('Die Aktivität cmid $cmid fehlt auf der Auswahlseite der Sicherung. Nichts gestartet.');
  }
  final r4 = await moodle.senden(s2.aktion, [...auswahl, const MapEntry('submitbutton', 'Weiter')]);
  final s4 = seiteVon(r4);

  // Bestätigungsseite gegen die Bestellung prüfen, bevor etwas ausgeführt wird.
  final fehler = bestaetigungFehler(s4.felder, cmid: cmid);
  if (fehler != null) throw MoodleFehler('Abgebrochen, nichts gesichert: $fehler');
  final backupid = wertIn(s4.felder, 'backup');
  final kontext = int.tryParse(s4.seite.kontext ?? '');
  final dateiname = wertIn(s4.felder, 'setting_root_filename');
  if (backupid == null || backupid.isEmpty || kontext == null || dateiname == null) {
    throw MoodleFehler('Moodle nennt auf der Bestätigungsseite Nummer, Kontext oder Dateinamen nicht. Nichts gestartet.');
  }

  // Name der Datei: Modul, cmid und Zeit. Kein Kurs-, Personen- oder Aktivitätsname.
  final ordner = p.join(vorgaenge.ordner, ziel);
  await Directory(ordner).create(recursive: true);
  final dateiName = await freierName(ordner, sicherungsName(a.modul, cmid, DateTime.now()));
  final vg = await vorgaenge.neu(kurs: kurs, cmid: cmid, datei: p.join(ziel, dateiName));
  beiVorgang?.call(vg.id);
  final kursText = await kursBezeichnung(moodle, kurs);
  return _nachFreigabe(moodle, freigaben, vorgaenge, vg,
      s4: s4,
      backupid: backupid,
      kontext: kontext,
      dateiname: dateiname,
      punkte: [
        'Sicherung der Aktivität „${a.name}" (cmid $cmid, $kursText)',
        'Ohne Nutzerdaten: keine Teilnehmenden, Abgaben, Bewertungen. Im Kurs ändert sich nichts.',
        'Datei: Sicherungsordner der App${ziel.isEmpty ? '' : '/$ziel'}, Name $dateiName',
      ]);
}

/// Der gemeinsame Teil nach der Prüfung: Freigabe in der App, dann Schritt 4
/// starten und auf das Ergebnis warten. Ohne Freigabe nichts an Moodle.
Future<String> _nachFreigabe(
  MoodleZugang moodle,
  Freigaben freigaben,
  Vorgaenge vorgaenge,
  Vorgang vg, {
  required ({String aktion, Felder felder, Seitenangaben seite}) s4,
  required String backupid,
  required int kontext,
  required String dateiname,
  required List<String> punkte,
}) async {
  _laufend.add(vg.id);
  try {
    final ja = await freigaben.anfragen(FreigabeAnfrage(
      titel: 'Sicherung ausführen?',
      punkte: punkte,
      vergleich: const [],
      knopf: 'Sichern',
      ohneEntscheidung: 'wird nichts gesichert',
    ));
    if (!ja) {
      await vorgaenge.aktualisieren(vg,
          stand: SicherungStand.fehlgeschlagen, text: 'Nicht freigegeben; nichts gesichert.');
      return 'Nicht gesichert: in der App abgelehnt oder nicht innerhalb von '
          '${freigaben.frist.inMinutes} Minuten freigegeben. Nichts geändert.';
    }

    // Schritt 4 starten. Ob Moodle den Start angenommen hat, zeigt erst die Abfrage.
    await vorgaenge.aktualisieren(vg,
        stand: SicherungStand.laufend, backupid: backupid, kontext: kontext, dateiname: dateiname);
    try {
      await moodle.senden(s4.aktion, [...s4.felder, const MapEntry('submitbutton', 'Weiter')]);
    } on MoodleFehler {
      await vorgaenge.aktualisieren(vg,
          stand: SicherungStand.unklar, text: 'Der Start ist nicht bestätigt; sicherung_status prüft erneut.');
      rethrow;
    }
    return await _warten(moodle, vorgaenge, vg);
  } finally {
    _laufend.remove(vg.id);
  }
}

/// Sichert mehrere Aktivitäten, Abschnitte oder den ganzen Kurs in eine Datei
/// (sichern_auswahl). Der Ablauf läuft über `/backup/backup.php?id=KURS` ohne
/// cm, Schritte 1, 2 und 4, Nutzerdaten aus.
///
/// Ohne [aktivitaeten] und [abschnitte], mit [ganzerKurs]: der ganze Kurs. Mit
/// Angaben und [ganzerKurs]: der Kurs, eingeschränkt auf die Auswahl (die Art
/// bleibt „Kurs"). Ein Abschnitt nimmt alle seine Aktivitäten mit.
Future<String> auswahlSichern(
  MoodleZugang moodle,
  Freigaben freigaben,
  Vorgaenge vorgaenge, {
  required int kurs,
  required String name,
  required List<({int cmid, String name})> aktivitaeten,
  required List<({int id, String name})> abschnitte,
  required bool ganzerKurs,
  String? zielOrdner,
  void Function(String vorgangId)? beiVorgang,
}) async {
  final ziel = zielOrdnerPruefen(zielOrdner);
  if (ziel == null) {
    throw MoodleFehler('ziel_ordner ist ungültig: nur Ordnernamen relativ zum Sicherungsordner, ohne „..", '
        'ohne Laufwerk und ohne Sonderzeichen.');
  }
  final nurGenannte = aktivitaeten.isNotEmpty || abschnitte.isNotEmpty;
  if (!ganzerKurs && !nurGenannte) {
    throw MoodleFehler('Nichts ausgewählt: aktivitaeten, abschnitte oder ganzer_kurs angeben.');
  }
  final art = auswahlArt(ganzerKurs: ganzerKurs, nurGenannte: nurGenannte);

  // Namen prüfen, bevor etwas bei Moodle geschieht.
  final k = await kursLesen(moodle, kurs);
  nameBestaetigen(name, await kursname(moodle, kurs) ?? '', 'Kurs $kurs');
  for (final a in aktivitaeten) {
    final x = k.nachCmid[a.cmid];
    if (x == null) throw MoodleFehler('cmid ${a.cmid} gibt es in Kurs $kurs nicht. Nummer prüfen (kurs_uebersicht).');
    nameBestaetigen(a.name, x.name, 'cmid ${a.cmid}');
  }
  for (final s in abschnitte) {
    final x = k.nachId[s.id];
    if (x == null) throw MoodleFehler('Abschnitt ${s.id} gibt es in Kurs $kurs nicht. Nummer prüfen (kurs_uebersicht).');
    nameBestaetigen(s.name, x.titel, 'Abschnitt ${s.id}');
  }

  // Erwartete Auswahl: bei „nur Genannte" die Angaben plus alle Aktivitäten der
  // genannten Abschnitte. Bei „ganzer Kurs" die Seite selbst, die mit der
  // Kursübersicht verglichen wird.
  final angegebeneAbschnitte = {for (final s in abschnitte) s.id};
  final genannteCmids = {
    for (final a in aktivitaeten) a.cmid,
    for (final s in abschnitte) ...?k.nachId[s.id]?.aktivitaeten.map((x) => x.cmid),
  };

  // Schritt 1: Nutzerdaten aus, weiter.
  final f1 = await formularHolen(moodle, '/backup/backup.php?id=$kurs');
  if (schrittVon(f1.felder) != '1') {
    throw MoodleFehler('Die Sicherung beginnt nicht auf Schritt 1. Nichts gestartet.');
  }
  final r2 = await moodle.senden(f1.aktion, [...nutzerdatenAus(f1.felder), const MapEntry('submitbutton', 'Weiter')]);
  final s2 = seiteVon(r2);
  if (schrittVon(s2.felder) != '2') {
    throw MoodleFehler('Die Auswahlseite der Sicherung kommt nicht wie gemessen. Nichts gestartet.');
  }

  final seiteCmids = eingeschlosseneAktivitaeten(s2.felder).keys.toSet();
  final seiteAbschnitte = eingeschlosseneAbschnitte(s2.felder).keys.toSet();
  final Set<int> wahlCmids;
  final Set<int> wahlAbschnitte;
  if (nurGenannte) {
    wahlCmids = genannteCmids;
    wahlAbschnitte = angegebeneAbschnitte;
  } else {
    if (seiteCmids.length != k.nachCmid.length || !seiteCmids.containsAll(k.nachCmid.keys)) {
      throw MoodleFehler('Die Auswahlseite nennt andere Aktivitäten als die Kursübersicht. Nichts gestartet.');
    }
    wahlCmids = seiteCmids;
    wahlAbschnitte = seiteAbschnitte;
  }

  // Schritt 2: genau die Auswahl.
  final schema = schemaWahl(s2.felder, cmids: wahlCmids, abschnitte: wahlAbschnitte);
  if (schema == null) {
    throw MoodleFehler('Ein gewählter Teil fehlt auf der Auswahlseite der Sicherung. Nichts gestartet.');
  }
  final r4 = await moodle.senden(s2.aktion, [...schema, const MapEntry('submitbutton', 'Weiter')]);
  final s4 = seiteVon(r4);

  // Bestätigungsseite gegen die Bestellung prüfen, bevor etwas ausgeführt wird.
  final fehler = bestaetigungWahlFehler(s4.felder, cmids: wahlCmids, abschnitte: wahlAbschnitte);
  if (fehler != null) throw MoodleFehler('Abgebrochen, nichts gesichert: $fehler');
  final backupid = wertIn(s4.felder, 'backup');
  final kontext = int.tryParse(s4.seite.kontext ?? '');
  final dateiname = wertIn(s4.felder, 'setting_root_filename');
  if (backupid == null || backupid.isEmpty || kontext == null || dateiname == null) {
    throw MoodleFehler('Moodle nennt auf der Bestätigungsseite Nummer, Kontext oder Dateinamen nicht. Nichts gestartet.');
  }

  // Was ausgewählt ist, für die Freigabe: Namen aus der Kursübersicht.
  final ausgewaehlt = [
    for (final c in wahlCmids.toList()..sort())
      if (k.nachCmid[c] != null) k.nachCmid[c]!,
  ];
  final abschnittNamen = [
    for (final id in wahlAbschnitte.toList()..sort())
      if (k.nachId[id] != null) '„${k.nachId[id]!.titel}"',
  ];
  // Abschnitte, die nur als Rahmen mitgehen, weil eine ihrer Aktivitäten gewählt
  // ist (Moodle nimmt sonst die Aktivität nicht mit). Ihre übrigen Aktivitäten
  // bleiben aus, das sagt die Freigabe.
  final rahmen = (genannteAbschnitte(s2.felder, cmids: wahlCmids, abschnitte: wahlAbschnitte)
      .difference(wahlAbschnitte)).toList()
    ..sort();
  final luecken = inhaltsLuecken(ausgewaehlt.map((a) => a.modul));
  final kursName = await kursname(moodle, kurs) ?? '';
  final ordner = p.join(vorgaenge.ordner, ziel);
  await Directory(ordner).create(recursive: true);
  final dateiName = await freierName(ordner, kursSicherungsName(kurs, DateTime.now()));
  final anzahl = '${ausgewaehlt.length} Aktivitäten, ${wahlAbschnitte.length + rahmen.length} Abschnitte';
  final vg = await vorgaenge.neu(
      kurs: kurs, cmid: 0, datei: p.join(ziel, dateiName), auswahl: '${art.text}: $anzahl');
  beiVorgang?.call(vg.id);

  return _nachFreigabe(moodle, freigaben, vorgaenge, vg,
      s4: s4,
      backupid: backupid,
      kontext: kontext,
      dateiname: dateiname,
      punkte: [
        'Sicherung (${art.text}) von Kurs $kurs „$kursName"',
        if (abschnittNamen.isNotEmpty) 'Abschnitte: ${abschnittNamen.join(', ')}',
        for (final id in rahmen)
          'Abschnitt ${k.nachId[id]?.nummer ?? id} wird als Rahmen mitgesichert, ohne seine übrigen Aktivitäten',
        'Aktivitäten ($anzahl): ${ausgewaehlt.map((a) => '„${a.name}"').join(', ')}',
        if (art != AuswahlArt.ganzerKurs) 'Nicht enthalten: alle übrigen Abschnitte und Aktivitäten des Kurses',
        'Ohne Nutzerdaten: keine Teilnehmenden, Abgaben, Bewertungen. Im Kurs ändert sich nichts.',
        for (final l in luecken) 'Nicht mitgesichert, weil ohne Nutzerdaten: $l',
        'Datei: Sicherungsordner der App${ziel.isEmpty ? '' : '/$ziel'}, Name $dateiName',
      ]);
}

/// Fragt den Fortschritt ab, bis Moodle Ende oder Fehler meldet, und holt die
/// Datei. Nach [gesamt] ohne Ende bleibt der Vorgang „laufend" und die letzte
/// Beobachtung steht im Text. Stillstand wird am Anfang des Aufrufs
/// geprüft: seit der Frist ohne neuen Fortschritt, dann kein weiteres Warten.
Future<String> _warten(
  MoodleZugang moodle,
  Vorgaenge vorgaenge,
  Vorgang vg, {
  Duration gesamt = const Duration(minutes: 10),
  Duration takt = const Duration(seconds: 3),
}) async {
  final id = vg.backupid!;
  final ende = jetzt().add(gesamt);
  var erster = true;
  try {
    while (true) {
      vorgaenge.pruefeBindung(vg);
      final antwort = await moodle.dienst('core_backup_get_async_backup_progress', {
        'backupids': [id],
        'contextid': vg.kontext,
      });
      final stand = bewerteFortschritt(antwort, id);
      if (stand == SicherungStand.fertig) break;
      if (stand == SicherungStand.fehlgeschlagen) {
        await vorgaenge.aktualisieren(vg,
            stand: SicherungStand.fehlgeschlagen, text: 'Moodle meldet einen Fehler bei der Sicherung.');
        return 'Sicherung fehlgeschlagen (Nummer ${vg.id}): Moodle meldet einen Fehler.';
      }
      if (stand == SicherungStand.unklar) {
        await vorgaenge.aktualisieren(vg,
            stand: SicherungStand.unklar, text: 'Die Antwort von Moodle passt auf kein bekanntes Muster.');
        return 'Unklar (Nummer ${vg.id}): Die Antwort von Moodle passt auf kein bekanntes Muster. '
            'sicherung_status prüft erneut.';
      }
      final fortschritt = fortschrittswert(antwort, id);
      final jetzige = jetzt();
      if (fortschrittNeuBeobachtet(vg.fortschritt, fortschritt, vg.fortschrittSeit)) {
        await vorgaenge.aktualisieren(vg, fortschritt: fortschritt, fortschrittSeit: jetzige);
      }
      if (erster && istStillstand(jetzige, vg.fortschrittSeit)) {
        return stillstandText(
          nummer: vg.id,
          werkzeug: 'sicherung_status',
          fortschritt: fortschritt,
          seit: jetzige.difference(vg.fortschrittSeit!),
          ursachen: 'Der Cron von Moodle läuft nicht oder zu selten; nach einem Upgrade ist die '
              'Sicherung eventuell nicht mehr freigegeben. Die Administration prüft das.',
        );
      }
      erster = false;
      if (jetzt().isAfter(ende)) {
        return 'Die Sicherung läuft noch (Nummer ${vg.id}), letzte Beobachtung '
            '${fortschritt == null ? 'unbekannt' : '${(fortschritt * 100).round()} %'}. '
            'Mit sicherung_status später prüfen.';
      }
      await schlafe(takt);
    }

    final dateiname = vg.dateiname;
    if (dateiname == null) {
      await vorgaenge.aktualisieren(vg, stand: SicherungStand.unklar, text: 'Der Dateiname fehlt im Vorgang.');
      return 'Unklar (Nummer ${vg.id}): Der Dateiname fehlt im Vorgang.';
    }
    // Den Link holt die Seite „Wiederherstellen" (siehe sicherungsLinks).
    vorgaenge.pruefeBindung(vg);
    final seite = await moodle.lesen('/backup/restorefile.php?contextid=${vg.kontext}');
    final pfade = sicherungsLinks(seite.text, dateiname);
    if (pfade.length != 1) {
      final grund = pfade.isEmpty
          ? 'Der Downloadlink fehlt auf der Seite Wiederherstellen.'
          : 'Auf der Seite Wiederherstellen steht der Name mehrfach.';
      await vorgaenge.aktualisieren(vg, stand: SicherungStand.unklar, text: grund);
      return 'Unklar (Nummer ${vg.id}): $grund sicherung_status prüft erneut.';
    }
    final pfad = pfade.single;
    final ziel = File(p.join(vorgaenge.ordner, vg.datei));
    vorgaenge.pruefeBindung(vg);
    final bytes = await moodle.herunterladen(pfad, ziel);

    // Lesen zurück: Die Datei auf der Platte muss die gemeldete Größe haben.
    final groesse = await ziel.length();
    final ok = bytes > 0 && groesse == bytes;
    await vorgaenge.aktualisieren(vg,
        stand: ok ? SicherungStand.fertig : SicherungStand.unklar,
        bytes: bytes,
        verified: ok,
        text: ok ? '' : 'Die Größe der Datei stimmt nach dem Speichern nicht.');
    return ok
        ? 'Gesichert: ${vg.datei} ($bytes Bytes, Nummer ${vg.id}). verified: true'
        : 'Unklar (Nummer ${vg.id}): Die Größe der Datei stimmt nicht. verified: false';
  } on MoodleFehler {
    await vorgaenge.aktualisieren(vg,
        stand: SicherungStand.unklar, text: 'Abfrage oder Download nicht gelungen; sicherung_status prüft erneut.');
    rethrow;
  }
}

/// Der Stand eines Vorgangs, auf Wunsch mit einer neuen Abfrage bei Moodle.
/// Ohne [id]: die letzten Vorgänge.
Future<String> sicherungStatus(MoodleZugang moodle, Vorgaenge vorgaenge, {String? id}) async {
  if (id == null) {
    final alle = await vorgaenge.alle();
    if (alle.isEmpty) return 'Noch keine Sicherung.';
    return alle.reversed.take(10).map(_zeile).join('\n');
  }
  final v = await vorgaenge.finde(id);
  if (v == null) throw MoodleFehler('Keine Sicherung mit der Nummer $id.');
  if (_laufend.contains(v.id)) {
    return 'Läuft noch (Nummer ${v.id}). Bitte später erneut prüfen.\n${_zeile(v)}';
  }
  if (v.wiederherstellung != null) {
    return 'Das ist eine Wiederherstellung (wiederherstellung_status, Nummer ${v.id}).';
  }
  if (v.stand == SicherungStand.anstehend) {
    await vorgaenge.aktualisieren(v,
        stand: SicherungStand.fehlgeschlagen,
        text: 'Unterbrochen, bevor die Sicherung startete; nichts gesichert.');
    return _zeile(v);
  }
  if ((v.stand == SicherungStand.laufend || v.stand == SicherungStand.unklar) && v.backupid != null) {
    _laufend.add(v.id);
    try {
      final text = await _warten(moodle, vorgaenge, v);
      return '$text\n${_zeile(v)}';
    } finally {
      _laufend.remove(v.id);
    }
  }
  return _zeile(v);
}

/// Eine Zeile je Vorgang für die Übersicht. Offene Vorgänge nennen genau einen
/// Folgeaufruf mit ihrer Nummer.
String _zeile(Vorgang v) {
  if (v.wiederherstellung != null) {
    final verified = v.wiederherstellung == WiederherstellungStand.fertig ? ' · verified: ${v.verified}' : '';
    final hinweis = v.text.isEmpty ? '' : '\n${v.text}';
    final folge = _offen(v) ? '\nFolgeaufruf: wiederherstellung_status ${v.id}' : '';
    return '${v.id} · Wiederherstellung in Kurs ${v.kurs} · ${v.wiederherstellung!.text} · ${v.datei}$verified$hinweis$folge';
  }
  final verified = v.stand == SicherungStand.fertig ? ' · verified: ${v.verified}' : '';
  final hinweis = v.text.isEmpty ? '' : '\n${v.text}';
  final wer = v.auswahl ?? 'cmid ${v.cmid}';
  final folge = _offen(v) ? '\nFolgeaufruf: sicherung_status ${v.id}' : '';
  return '${v.id} · Kurs ${v.kurs} · $wer · ${v.stand.text} · ${v.datei}$verified$hinweis$folge';
}

bool _offen(Vorgang v) => v.wiederherstellung != null
    ? v.wiederherstellung != WiederherstellungStand.fertig && v.wiederherstellung != WiederherstellungStand.fehlgeschlagen
    : v.stand != SicherungStand.fertig && v.stand != SicherungStand.fehlgeschlagen;
