// Die Wiederherstellung einer Sicherungsdatei (.mbz) in einen bestehenden Kurs,
// verschmelzend (Ziel „in einem vorhandenen Kurs", target=4). Die Regeln ohne
// Netz stehen in wiederherstellung_regeln.dart.
//
// Ablauf:
//   Datei und Archiv prüfen (vor jedem Hochladen) -> Kurs und Name prüfen ->
//   Kontext des Kurses -> Freigabe in der App (Kurs, Inhalt, „verschmelzen",
//   neue Aktivitäten verborgen) -> Datei in den Entwurfsbereich -> Formular
//   „Wiederherstellen" -> Schritte 2, 4, 8 und 16 des Assistenten -> Hintergrund-
//   auftrag abfragen -> Kurs zurücklesen und die neuen Aktivitäten nennen.
//
// Nach dem Schritt 16 gilt: Bricht die Verbindung ab oder läuft die Sitzung
// ab, steht der Vorgang auf „unklar". Er wird nie neu gestartet; sicherung_status
// fragt nur den Stand ab. Vor Schritt 16 hat Moodle im Kurs nichts geändert.
//
// Der Vorgang steht in vorgaenge.json unter wiederherstellung_status (Schlüssel
// im Zusammenhang mit sicherungen.dart). UNGEMESSEN steht im Code und in TODO.md.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../freigabe.dart';
import 'formular.dart';
import 'formular_lesen.dart';
import 'formular_schreiben.dart';
import 'kurs.dart';
import 'moodle_zugang.dart';
import 'sicherung.dart';
import 'sicherung_regeln.dart';
import 'wiederherstellung_regeln.dart';

/// Vorgänge, die gerade laufen (Freigabe, Upload oder Abfrage) in dieser Sitzung.
final Set<String> _laufendeWiederherstellungen = {};

/// Setzt den Stand nur nach einem erlaubten Übergang.
Future<void> _uebergang(
  Vorgaenge vorgaenge,
  Vorgang vg,
  WiederherstellungStand nach, {
  String? text,
  String? laufzeit,
  String? backupid,
  int? kontext,
  bool? verified,
  List<int>? vorherCmids,
}) async {
  final von = vg.wiederherstellung ?? WiederherstellungStand.anstehend;
  if (!erlaubterUebergang(von, nach)) {
    throw StateError('Unerlaubter Übergang der Wiederherstellung (${von.text} nach ${nach.text}).');
  }
  // Sicherungsstand bleibt unverändert; die Wiederherstellung führt ihren eigenen.
  await vorgaenge.aktualisieren(vg,
      wiederherstellung: nach,
      text: text,
      wiederherstellungDatei: laufzeit,
      backupid: backupid,
      kontext: kontext,
      verified: verified,
      vorherCmids: vorherCmids);
}

/// Stellt eine Sicherungsdatei aus dem Sicherungsordner in den Kurs [kurs] wieder
/// her (verschmelzen). [datei] liegt relativ zum Sicherungsordner. [instanz] ist
/// der Name des Profils, nur für die Freigabe.
Future<String> wiederherstellen(
  MoodleZugang moodle,
  Freigaben freigaben,
  Vorgaenge vorgaenge, {
  required String datei,
  required int kurs,
  required String name,
  required String instanz,
}) async {
  // 1. Datei: nur ein .mbz innerhalb des Sicherungsordners, nicht zu groß.
  final fehler = pfadFehler(datei);
  if (fehler != null || !datei.toLowerCase().endsWith('.mbz')) {
    throw MoodleFehler('datei muss ein .mbz-Name relativ zum Sicherungsordner sein (kein „..", kein absoluter Pfad).');
  }
  final ordner = vorgaenge.ordner;
  final quelle = File(p.join(ordner, datei));
  if (!await quelle.exists() || !p.isWithin(ordner, quelle.absolute.path)) {
    throw MoodleFehler('Die Datei $datei liegt nicht im Sicherungsordner. Nichts geändert.');
  }
  if (await quelle.length() > archivGrenzeStandard) {
    throw MoodleFehler('Die Datei ist größer als die erlaubten ${archivGrenzeStandard ~/ (1024 * 1024)} MB.');
  }

  // 2. Archiv prüfen, bevor es Moodle erreicht.
  final bytes = await quelle.readAsBytes();
  final befund = await archivPruefen(bytes);
  if (!befund.ok) throw MoodleFehler('Archiv abgelehnt, nichts hochgeladen: ${befund.grund}');

  // 3. Zielkurs und Name.
  final kursName = await kursname(moodle, kurs) ?? '';
  nameBestaetigen(name, kursName, 'Kurs $kurs');
  final vorher = await kursLesen(moodle, kurs);

  // 4. Kontext des Kurses (Seitenangaben der Kursseite; UNGEMESSEN).
  final seite = await moodle.lesen('/course/view.php?id=$kurs');
  final kontext = int.tryParse(Seitenangaben.aus(seite.text).kontext ?? '');
  if (kontext == null) throw MoodleFehler('Moodle nennt den Kontext des Kurses nicht. Nichts geändert.');

  // 5. Freigabe in der App: Kurs, Inhalt, Modus, neue Aktivitäten verborgen.
  final aktivitaeten = [
    for (final a in befund.aktivitaeten) '„${a.titel}" (${a.modul})',
  ];
  final ja = await freigaben.anfragen(FreigabeAnfrage(
    titel: 'Wiederherstellen ausführen?',
    punkte: [
      'Profil: $instanz',
      'Kurs $kurs „$kursName" (bestehender Kurs)',
      'Datei: ${p.basename(datei)} (${befund.typ == 'course' ? 'ganzer Kurs' : 'Aktivität'}, Moodle ${befund.moodleVersion ?? '?'})',
      'Modus: verschmelzen. Inhalte werden zum Kurs hinzugefügt; nichts im Kurs wird gelöscht.',
      if (aktivitaeten.isNotEmpty) 'Angelegt werden: ${aktivitaeten.join(', ')}',
      'Neue Aktivitäten werden verborgen angelegt. Verborgen ist kein Schutz: '
          'Wer im Kurs Rechte hat, sieht sie und kann sie sichtbar machen.',
      'Nutzerdaten sind im Archiv nicht enthalten (geprüft). Rechte und Einschreibungen bleiben unverändert.',
    ],
    vergleich: const [],
    knopf: 'Wiederherstellen',
    ohneEntscheidung: 'wird nichts wiederhergestellt',
  ));
  if (!ja) {
    return 'Nicht wiederhergestellt: in der App abgelehnt oder nicht innerhalb von '
        '${freigaben.frist.inMinutes} Minuten freigegeben. Nichts geändert.';
  }

  // 6. Vorgang anlegen und Datei hochladen (jedes Mal neu, nie eine alte Kennung).
  final vg = await vorgaenge.neuWiederherstellung(kurs: kurs, datei: datei);
  _laufendeWiederherstellungen.add(vg.id);
  try {
    return await _ausfuehren(moodle, vorgaenge, vg,
        bytes: bytes,
        kontext: kontext,
        kurs: kurs,
        vorherCmids: vorher.nachCmid.keys.toList(),
        name: p.basename(datei));
  } finally {
    _laufendeWiederherstellungen.remove(vg.id);
  }
}

Future<String> _ausfuehren(
  MoodleZugang moodle,
  Vorgaenge vorgaenge,
  Vorgang vg, {
  required List<int> bytes,
  required int kontext,
  required int kurs,
  required List<int> vorherCmids,
  required String name,
}) async {
  var vorUpload = true;
  try {
    // Formular „Wiederherstellen" holen; der Entwurfsbereich ist sein Feld backupfile.
    final f = await formularHolen(moodle, '/backup/restorefile.php?contextid=$kontext');
    final itemid = wertIn(f.felder, 'backupfile');
    if (itemid == null) throw MoodleFehler('Das Formular nennt keinen Entwurfsbereich. Nichts geändert.');
    await hochladen(moodle, f, itemid, '/', name, bytes);
    await _uebergang(vorgaenge, vg, WiederherstellungStand.hochgeladen, vorherCmids: vorherCmids);

    // Formular absenden: Moodle legt die Datei ab und leitet zum Assistenten.
    final r = await moodle.senden(f.aktion, f.felder);
    final ziel = moodle.umleitungsziel(r) ?? r.adresse;
    final laufzeit = ziel.queryParameters['filename'];
    if (ziel.path != '/backup/restore.php' || laufzeit == null || laufzeit.isEmpty) {
      throw MoodleFehler('Moodle übernimmt die Datei nicht (keine Kennung). Nichts geändert.');
    }
    await vorgaenge.aktualisieren(vg, wiederherstellungDatei: laufzeit);

    // Schritt 2: Ziel „in einem vorhandenen Kurs" mit target=4.
    final adresse = '/backup/restore.php?contextid=$kontext&filename=$laufzeit';
    final s2 = seiteVon(await moodle.lesen(adresse));
    if (schrittVon(s2.felder) != '2') {
      throw MoodleFehler('Die Zielseite kommt nicht wie gemessen. Nichts geändert.');
    }
    final f2 = [...s2.felder];
    setze(f2, 'target', '4');
    setze(f2, 'targetid', '$kurs');
    final s4 = seiteVon(await moodle.senden(s2.aktion, f2));
    if (schrittVon(s4.felder) != '4') {
      throw MoodleFehler('Der Zielkurs wird nicht angenommen (Kurssuche nötig; UNGEMESSEN). Nichts geändert.');
    }

    // Schritt 4: Einstellungen, nur wenn keine Nutzerdaten vorgesehen sind.
    if (!ohneNutzerdaten(s4.felder)) {
      throw MoodleFehler('Die Einstellungen sehen Nutzerdaten vor; abgebrochen. Nichts geändert.');
    }
    final s8 = seiteVon(await moodle.senden(s4.aktion, s4.felder));
    if (schrittVon(s8.felder) != '8') {
      throw MoodleFehler('Das Schema kommt nicht wie gemessen. Nichts geändert.');
    }
    if (!ohneNutzerdaten(s8.felder)) {
      throw MoodleFehler('Das Schema sieht Nutzerdaten vor; abgebrochen. Nichts geändert.');
    }
    final s16 = seiteVon(await moodle.senden(s8.aktion, s8.felder));
    if (schrittVon(s16.felder) != '16') {
      throw MoodleFehler('Die Prüfseite kommt nicht wie gemessen. Nichts geändert.');
    }

    // Ab hier: Schritt 16 startet die Wiederherstellung. Nie erneut senden.
    vorUpload = false;
    await _uebergang(vorgaenge, vg, WiederherstellungStand.laufend, laufzeit: laufzeit, backupid: laufzeit, kontext: kontext);
    try {
      await moodle.senden(s16.aktion, s16.felder);
    } catch (_) {
      await _uebergang(vorgaenge, vg, WiederherstellungStand.unklar,
          text: 'Der Start ist nicht bestätigt. wiederherstellung_status prüft erneut; nicht neu senden.');
      rethrow;
    }
    return await _warten(moodle, vorgaenge, vg, kontext: kontext, kurs: kurs, vorherCmids: vorherCmids);
  } catch (e) {
    if (vorUpload) {
      await _uebergang(vorgaenge, vg, WiederherstellungStand.fehlgeschlagen,
          text: 'Vor dem Start abgebrochen; im Kurs ist nichts geändert.');
    }
    rethrow;
  }
}

/// Fragt den Hintergrundauftrag ab. Dann liest sie den Kurs zurück.
Future<String> _warten(
  MoodleZugang moodle,
  Vorgaenge vorgaenge,
  Vorgang vg, {
  required int kontext,
  required int kurs,
  required List<int> vorherCmids,
  Duration gesamt = const Duration(minutes: 10),
  Duration takt = const Duration(seconds: 3),
}) async {
  final id = vg.wiederherstellungDatei!;
  final ende = DateTime.now().add(gesamt);
  try {
    while (true) {
      // UNGEMESSEN: operation „restore" und die Kennung als backupids (TODO.md).
      final antwort = await moodle.dienst('core_backup_get_async_backup_progress', {
        'backupids': [id],
        'contextid': kontext,
        'operation': 'restore',
      });
      final stand = bewerteFortschritt(antwort, id);
      if (stand == SicherungStand.fertig) break;
      if (stand == SicherungStand.fehlgeschlagen) {
        await _uebergang(vorgaenge, vg, WiederherstellungStand.fehlgeschlagen,
            text: 'Moodle meldet einen Fehler bei der Wiederherstellung. Kurs bitte prüfen.');
        return 'Wiederherstellung fehlgeschlagen (Nummer ${vg.id}): Moodle meldet einen Fehler. Kurs prüfen.';
      }
      if (stand == SicherungStand.unklar) {
        await _uebergang(vorgaenge, vg, WiederherstellungStand.unklar,
            text: 'Die Antwort von Moodle passt auf kein bekanntes Muster.');
        return 'Unklar (Nummer ${vg.id}): Die Antwort passt auf kein bekanntes Muster. '
            'wiederherstellung_status prüft erneut.';
      }
      if (DateTime.now().isAfter(ende)) {
        return 'Die Wiederherstellung läuft noch (Nummer ${vg.id}). Mit wiederherstellung_status später prüfen.';
      }
      await Future<void>.delayed(takt);
    }
    return await _gegenlesen(moodle, vorgaenge, vg, kurs: kurs, vorherCmids: vorherCmids);
  } on MoodleFehler {
    await _uebergang(vorgaenge, vg, WiederherstellungStand.unklar,
        text: 'Abfrage nicht gelungen; wiederherstellung_status prüft erneut.');
    rethrow;
  }
}

/// Liest den Kurs zurück. Neue Aktivitäten werden mit Namen und Art genannt.
/// verified nur, wenn es neue Aktivitäten gibt und alle verborgen sind.
Future<String> _gegenlesen(
  MoodleZugang moodle,
  Vorgaenge vorgaenge,
  Vorgang vg, {
  required int kurs,
  required List<int> vorherCmids,
}) async {
  final jetzt = await kursLesen(moodle, kurs);
  final neue = [
    for (final a in jetzt.nachCmid.values)
      if (!vorherCmids.contains(a.cmid)) a,
  ];
  final alleVerborgen = neue.isNotEmpty && neue.every((a) => !a.sichtbar);
  final liste = neue.map((a) => '„${a.name}" (${a.modul}${a.sichtbar ? ', sichtbar' : ', verborgen'})').join(', ');
  final text = neue.isEmpty
      ? 'Keine neuen Aktivitäten im Kurs gefunden.'
      : alleVerborgen
          ? 'Neu im Kurs: $liste.'
          : 'Neu im Kurs: $liste. Nicht alle sind verborgen; bitte prüfen.';
  await _uebergang(vorgaenge, vg, WiederherstellungStand.fertig, text: text, verified: alleVerborgen);
  return 'Wiederherstellt (Nummer ${vg.id}): ${neue.isEmpty ? 'keine neuen Aktivitäten' : liste}. '
      'verified: $alleVerborgen';
}

/// Der Stand eines Wiederherstellungsvorgangs. Fragt nur ab, startet nie neu.
Future<String> wiederherstellungStatus(MoodleZugang moodle, Vorgaenge vorgaenge, {required String id}) async {
  final v = await vorgaenge.finde(id);
  if (v == null || v.wiederherstellung == null) {
    throw MoodleFehler('Keine Wiederherstellung mit der Nummer $id.');
  }
  if (_laufendeWiederherstellungen.contains(v.id)) {
    return 'Läuft noch (Nummer ${v.id}). Bitte später erneut prüfen.';
  }
  final stand = v.wiederherstellung!;
  if (stand == WiederherstellungStand.anstehend || stand == WiederherstellungStand.hochgeladen) {
    // Ohne laufende Sitzung nie begonnen: im Kurs ist nichts geändert.
    await _uebergang(vorgaenge, v, WiederherstellungStand.fehlgeschlagen,
        text: 'Unterbrochen, bevor die Wiederherstellung startete; im Kurs ist nichts geändert.');
    return 'fehlgeschlagen (Nummer ${v.id}): Unterbrochen, bevor sie startete. Im Kurs ist nichts geändert.';
  }
  if ((stand == WiederherstellungStand.laufend || stand == WiederherstellungStand.unklar) && v.wiederherstellungDatei != null) {
    _laufendeWiederherstellungen.add(v.id);
    try {
      final kontext = v.kontext;
      if (kontext == null) throw MoodleFehler('Der Vorgang ${v.id} hat keinen Kontext. Nichts geändert.');
      return await _warten(moodle, vorgaenge, v,
          kontext: kontext, kurs: v.kurs, vorherCmids: v.vorherCmids ?? const []);
    } finally {
      _laufendeWiederherstellungen.remove(v.id);
    }
  }
  return 'Stand (Nummer ${v.id}): ${stand.text}. ${v.text}';
}
