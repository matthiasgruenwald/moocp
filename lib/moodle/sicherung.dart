// Die Sicherung einer einzelnen Aktivität in eine Datei auf dem Rechner.
//
// Ablauf (Schritte 1, 2 und 4 des Sicherungsassistenten, Nutzerdaten aus; die
// Regeln stehen in sicherung_regeln.dart):
//   Kurs und Name prüfen -> Schritt 1 -> Schritt 2 (genau diese Aktivität) ->
//   Bestätigungsseite gegen die Bestellung prüfen -> Freigabe in der App ->
//   Seite Wiederherstellen vorher lesen -> Schritt 4 starten -> Fortschritt abfragen
//   -> neuen Namen auf der Seite Wiederherstellen suchen -> Datei holen, Größe prüfen.
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

/// Vorgänge, die gerade laufen (Freigabe oder Abfrage) in dieser Sitzung der App.
final Set<String> _laufend = {};

/// Ein Sicherungsvorgang. Nur Kennzahlen und feste Texte: keine Namen, keine
/// Antworten aus Moodle.
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
    this.dateiname,
    this.vorher,
    this.text = '',
    this.bytes,
    this.verified = false,
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

  /// Dateiname, den Moodle für die Sicherung führt. Zuerst der Wert aus dem
  /// Formular, nach dem Ende der Name, unter dem die Datei auf der Seite
  /// Wiederherstellen steht (Moodle benennt sie selbst).
  String? dateiname;

  /// Die Sicherungsdateien auf der Seite Wiederherstellen vor dem Start. Neu ist,
  /// was danach dazukommt. Null heißt: nicht gelesen.
  List<String>? vorher;

  /// Ein fester, kurzer Hinweis zum Stand. Ohne Inhalte aus Moodle.
  String text;
  int? bytes;
  bool verified;

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
        'dateiname': dateiname,
        'vorher': vorher,
        'text': text,
        'bytes': bytes,
        'verified': verified,
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
      dateiname: o['dateiname'] as String?,
      vorher: o['vorher'] is List ? [for (final x in o['vorher'] as List) if (x is String) x] : null,
      text: o['text'] as String? ?? '',
      bytes: o['bytes'] as int?,
      verified: o['verified'] == true,
    );
  }
}

/// Alle Vorgänge im Sicherungsordner, in vorgaenge.json. Geschrieben wird über
/// eine Datei .tmp, die dann umbenannt wird; ein Absturz hinterlässt also
/// entweder den alten oder den neuen Stand.
class Vorgaenge {
  Vorgaenge(this.ordner);

  final String ordner;
  List<Vorgang>? _liste;

  File get _datei => File(p.join(ordner, 'vorgaenge.json'));

  Future<List<Vorgang>> alle() async {
    final bisher = _liste;
    if (bisher != null) return bisher;
    final l = <Vorgang>[];
    if (await _datei.exists()) {
      final Object? roh;
      try {
        roh = jsonDecode(await _datei.readAsString());
      } catch (_) {
        throw MoodleFehler('vorgaenge.json im Sicherungsordner ist beschädigt. Nichts geändert.');
      }
      if (roh is List) {
        for (final x in roh) {
          final v = Vorgang.ausJson(x);
          if (v != null) l.add(v);
        }
      }
    }
    return _liste = l;
  }

  Future<Vorgang?> finde(String id) async {
    for (final v in await alle()) {
      if (v.id == id) return v;
    }
    return null;
  }

  Future<Vorgang> neu({required int kurs, required int cmid, required String datei}) async {
    final v = Vorgang(
      id: '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
          '${Random.secure().nextInt(0xffff).toRadixString(36)}',
      kurs: kurs,
      cmid: cmid,
      datei: datei,
      stand: SicherungStand.anstehend,
      begonnen: DateTime.now(),
    );
    (await alle()).add(v);
    await _speichern();
    return v;
  }

  Future<void> aktualisieren(
    Vorgang v, {
    SicherungStand? stand,
    String? text,
    String? backupid,
    int? kontext,
    String? dateiname,
    List<String>? vorher,
    int? bytes,
    bool? verified,
  }) async {
    if (stand != null) v.stand = stand;
    if (text != null) v.text = text;
    if (backupid != null) v.backupid = backupid;
    if (kontext != null) v.kontext = kontext;
    if (dateiname != null) v.dateiname = dateiname;
    if (vorher != null) v.vorher = vorher;
    if (bytes != null) v.bytes = bytes;
    if (verified != null) v.verified = verified;
    v.aktualisiert = DateTime.now();
    await _speichern();
  }

  Future<void> _speichern() async {
    await Directory(ordner).create(recursive: true);
    final tmp = File('${_datei.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final v in _liste ?? const <Vorgang>[]) v.zuJson()]), flush: true);
    await tmp.rename(_datei.path);
  }
}

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
({String aktion, Felder felder, Seitenangaben seite}) _seite(Antwort r) {
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
  final s2 = _seite(r2);
  if (schrittVon(s2.felder) != '2') {
    throw MoodleFehler('Die Auswahlseite der Sicherung kommt nicht wie gemessen. Nichts gestartet.');
  }

  // Schritt 2: genau diese Aktivität.
  final auswahl = schemaAuswahl(s2.felder, cmid: cmid);
  if (auswahl == null) {
    throw MoodleFehler('Die Aktivität cmid $cmid fehlt auf der Auswahlseite der Sicherung. Nichts gestartet.');
  }
  final r4 = await moodle.senden(s2.aktion, [...auswahl, const MapEntry('submitbutton', 'Weiter')]);
  final s4 = _seite(r4);

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
  _laufend.add(vg.id);
  try {
    final kursText = await kursBezeichnung(moodle, kurs);
    final ja = await freigaben.anfragen(FreigabeAnfrage(
      titel: 'Sicherung ausführen?',
      punkte: [
        'Sicherung der Aktivität „${a.name}" (cmid $cmid, $kursText)',
        'Ohne Nutzerdaten: keine Teilnehmenden, Abgaben, Bewertungen. Im Kurs ändert sich nichts.',
        'Datei: Sicherungsordner der App${ziel.isEmpty ? '' : '/$ziel'}, Name $dateiName',
      ],
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

    // Vor dem Start: die Sicherungen, die schon auf der Seite Wiederherstellen stehen.
    // Nach dem Ende ist neu, was dazukommt (siehe _warten). Im Vorgang gespeichert,
    // damit sicherung_status den Stand nach einem Abbruch wieder findet.
    final vorher = sicherungsDateien((await moodle.lesen('/backup/restorefile.php?contextid=$kontext')).text);

    // Schritt 4 starten. Ob Moodle den Start angenommen hat, zeigt erst die Abfrage.
    await vorgaenge.aktualisieren(vg,
        stand: SicherungStand.laufend,
        backupid: backupid,
        kontext: kontext,
        dateiname: dateiname,
        vorher: vorher);
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

/// Fragt den Fortschritt ab, bis Moodle Ende oder Fehler meldet, und holt die
/// Datei. Nach [gesamt] ohne Ende bleibt der Vorgang „laufend".
Future<String> _warten(
  MoodleZugang moodle,
  Vorgaenge vorgaenge,
  Vorgang vg, {
  Duration gesamt = const Duration(minutes: 10),
  Duration takt = const Duration(seconds: 3),
}) async {
  final id = vg.backupid!;
  final ende = DateTime.now().add(gesamt);
  try {
    while (true) {
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
      if (DateTime.now().isAfter(ende)) {
        return 'Die Sicherung läuft noch (Nummer ${vg.id}). Mit sicherung_status später prüfen.';
      }
      await Future<void>.delayed(takt);
    }

    // Name und Link holt die Seite „Wiederherstellen": neu seit dem Start, zur
    // Aktivität passend. Genau ein Treffer, sonst unklar; nicht raten.
    final vorher = vg.vorher;
    if (vorher == null) {
      await vorgaenge.aktualisieren(vg, stand: SicherungStand.unklar, text: 'Der Stand vor dem Start fehlt im Vorgang.');
      return 'Unklar (Nummer ${vg.id}): Der Stand vor dem Start fehlt im Vorgang.';
    }
    final seite = await moodle.lesen('/backup/restorefile.php?contextid=${vg.kontext}');
    final neue = neueSicherungen(sicherungsDateien(seite.text), vorher, vg.cmid);
    if (neue.length != 1) {
      final grund = neue.isEmpty
          ? 'Die Sicherung steht nicht auf der Seite Wiederherstellen.'
          : 'Auf der Seite Wiederherstellen stehen mehrere neue Sicherungen dieser Aktivität.';
      await vorgaenge.aktualisieren(vg, stand: SicherungStand.unklar, text: grund);
      return 'Unklar (Nummer ${vg.id}): $grund sicherung_status prüft erneut.';
    }
    final tatsaechlich = neue.single;
    final pfade = sicherungsLinks(seite.text, tatsaechlich);
    if (pfade.length != 1) {
      const grund = 'Der Name steht auf der Seite Wiederherstellen mit mehreren Links.';
      await vorgaenge.aktualisieren(vg, stand: SicherungStand.unklar, text: grund);
      return 'Unklar (Nummer ${vg.id}): $grund sicherung_status prüft erneut.';
    }
    await vorgaenge.aktualisieren(vg, dateiname: tatsaechlich);
    final pfad = pfade.single;
    final ziel = File(p.join(vorgaenge.ordner, vg.datei));
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

String _zeile(Vorgang v) {
  final verified = v.stand == SicherungStand.fertig ? ' · verified: ${v.verified}' : '';
  final hinweis = v.text.isEmpty ? '' : '\n${v.text}';
  return '${v.id} · Kurs ${v.kurs} · cmid ${v.cmid} · ${v.stand.text} · ${v.datei}$verified$hinweis';
}
