// Die Wiederherstellung einer Sicherungsdatei (.mbz) in einen bestehenden Kurs,
// verschmelzend (Ziel „in einem vorhandenen Kurs", target=4). Die Regeln ohne
// Netz stehen in wiederherstellung_regeln.dart.
//
// Ablauf:
//   Datei und Archiv prüfen (vor jedem Hochladen) -> Kurs und Name prüfen ->
//   Kontext des Kurses -> Freigabe in der App (Kurs, Inhalt, „verschmelzen",
//   neue Aktivitäten danach verborgen) -> Datei in den Entwurfsbereich -> Formular
//   „Wiederherstellen" -> Schritte 2, 4, 8 und 16 des Assistenten -> Hintergrund-
//   auftrag abfragen (Kennung: restoreid aus dem Prüfformular) -> neue Aktivitäten// verbergen -> Kurs zurücklesen und die neuen Aktivitäten nennen.
//
// Nach dem Schritt 16 gilt: Bricht die Verbindung ab oder läuft die Sitzung
// ab, steht der Vorgang auf „unklar". Er wird nie neu gestartet; sicherung_status
// fragt nur den Stand ab. Vor Schritt 16 hat Moodle im Kurs nichts geändert.
//
// Der Vorgang steht in vorgaenge.json unter wiederherstellung_status (Schlüssel
// im Zusammenhang mit sicherungen.dart). UNGEMESSEN steht im Code und in TODO.md.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:html/parser.dart' as html_parser;

import '../freigabe.dart';
import 'formular.dart';
import 'formular_lesen.dart';
import 'formular_schreiben.dart';
import 'kurs.dart';
import 'kurs_aendern.dart';
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
      'Moodle stellt die neuen Aktivitäten sichtbar wieder her; die App verbirgt sie danach. Sie können '
          'kurzzeitig für Lernende sichtbar sein. Verborgen ist kein Schutz: Wer im Kurs Rechte hat, sieht sie und kann sie sichtbar machen.',
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

    // Schritt 2: Sicherungsdetails (gemessen: schlichtes Formular ohne mform, stage=2),
    // dann die Zielseite mit stage=4, target/targetid/search vorausgefüllt.
    final adresse = '/backup/restore.php?contextid=$kontext&filename=$laufzeit';
    final s1 = restoreSeite(await moodle.lesen(adresse));
    if (schrittVon(s1.felder) != '2') {
      throw MoodleFehler('Die Seite Sicherungsdetails kommt nicht wie gemessen. Nichts geändert.');
    }
    final s2 = restoreSeite(await moodle.senden(s1.aktion, s1.felder));
    if (schrittVon(s2.felder) != '4') {
      throw MoodleFehler('Die Zielseite kommt nicht wie gemessen. Nichts geändert.');
    }
    final f2 = [...s2.felder];
    setze(f2, 'target', '4');
    setze(f2, 'targetid', '$kurs');
    final s4 = restoreSeite(await moodle.senden(s2.aktion, f2));
    if (!s4.felder.any((e) => e.key == '_qf__restore_settings_form')) {
      throw MoodleFehler('Der Zielkurs wird nicht angenommen (Kurssuche nötig; UNGEMESSEN). Nichts geändert.');
    }

    // Schritt 4: Einstellungen, nur wenn keine Nutzerdaten vorgesehen sind.
    if (!ohneNutzerdaten(s4.felder)) {
      throw MoodleFehler('Die Einstellungen sehen Nutzerdaten vor; abgebrochen. Nichts geändert.');
    }
    final s8 = restoreSeite(await moodle.senden(s4.aktion, s4.felder));
    if (!s8.felder.any((e) => e.key == '_qf__restore_schema_form')) {
      throw MoodleFehler('Das Schema kommt nicht wie gemessen. Nichts geändert.');
    }
    if (!ohneNutzerdaten(s8.felder)) {
      throw MoodleFehler('Das Schema sieht Nutzerdaten vor; abgebrochen. Nichts geändert.');
    }
    final s16 = restoreSeite(await moodle.senden(s8.aktion, s8.felder));
    if (!s16.felder.any((e) => e.key == '_qf__restore_review_form')) {
      throw MoodleFehler('Die Prüfseite kommt nicht wie gemessen. Nichts geändert.');
    }

    // Die Kennung für den Fortschritt ist die Restore-ID aus dem Prüfformular
    // (Feld restoreid), nicht der Dateinamen-Hash der Laufzeit (gemessen: Moodle
    // lehnt den Hash mit „Ungültiger Parameterwert" ab). Fehlt sie, startet nichts.
    final restoreid = wertIn(s16.felder, 'restore');
    if (restoreid == null || !RegExp(r'^[0-9a-f]{32}$').hasMatch(restoreid)) {
      throw MoodleFehler('Das Prüfformular nennt keine Kennung der Wiederherstellung (restoreid). Nichts geändert.');
    }

    // Ab hier: Schritt 16 startet die Wiederherstellung. Nie erneut senden.
    vorUpload = false;
    await _uebergang(vorgaenge, vg, WiederherstellungStand.laufend,
        laufzeit: laufzeit, backupid: restoreid, kontext: kontext);
    try {
      await moodle.senden(s16.aktion, s16.felder);
    } catch (_) {
      await _uebergang(vorgaenge, vg, WiederherstellungStand.unklar,
          text: 'Der Start ist nicht bestätigt. wiederherstellung_status prüft erneut; nicht neu senden.');
      rethrow;
    }
    return await _warten(moodle, vorgaenge, vg,
        restoreid: restoreid, kontext: kontext, kurs: kurs, vorherCmids: vorherCmids);
  } catch (e) {
    if (vorUpload) {
      await _uebergang(vorgaenge, vg, WiederherstellungStand.fehlgeschlagen,
          text: 'Vor dem Start abgebrochen; im Kurs ist nichts geändert.');
    }
    rethrow;
  }
}

/// Das Formular des Wiederherstellungsassistenten: Er hat auf manchen Seiten
/// kein `form.mform`; dann ist es das Formular mit Ziel /backup/restore.php
/// (gemessen auf der Seite „Sicherungsdetails").
({String aktion, Felder felder, Seitenangaben seite}) restoreSeite(Antwort r) {
  final doc = html_parser.parse(r.text);
  final form = doc.querySelectorAll('form').where((f) => (f.attributes['action'] ?? '').contains('/backup/restore.php')).firstOrNull ??
      hauptformular(doc);
  if (form == null) throw MoodleFehler('Moodle liefert kein Formular des Wiederherstellungsassistenten.');
  final ziel = r.adresse.resolve(form.attributes['action'] ?? r.adresse.path);
  return (
    aktion: ziel.hasQuery ? '${ziel.path}?${ziel.query}' : ziel.path,
    felder: formularFelder(form),
    seite: Seitenangaben.aus(r.text),
  );
}

/// Fragt den Hintergrundauftrag ab. Dann liest sie den Kurs zurück.
Future<String> _warten(
  MoodleZugang moodle,
  Vorgaenge vorgaenge,
  Vorgang vg, {
  required String restoreid,
  required int kontext,
  required int kurs,
  required List<int> vorherCmids,
  Duration gesamt = const Duration(minutes: 10),
  Duration takt = const Duration(seconds: 3),
}) async {
  final ende = DateTime.now().add(gesamt);
  try {
    while (true) {
      // Operation „restore" und die Restore-ID als backupids: ungemessen, siehe TODO.md.
      final antwort = await moodle.dienst('core_backup_get_async_backup_progress', {
        'backupids': [restoreid],
        'contextid': kontext,
      });
      final stand = bewerteFortschritt(antwort, restoreid);
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

/// Verbirgt die neuen Aktivitäten und liest den Kurs zurück. Moodle stellt die
/// wiederhergestellten Seiten sichtbar wieder her (gemessen), darum verbirgt die
/// App sie danach über dieselbe Kursaktion wie sichtbarkeit_setzen. Die Freigabe
/// für den ganzen Lauf gilt dafür; eine weitere gibt es nicht. Verborgen ist
/// kein Schutz: Kurzzeitig können Lernende die Aktivitäten gesehen haben.
/// verified nur, wenn es neue Aktivitäten gibt und alle verborgen sind.
Future<String> _gegenlesen(
  MoodleZugang moodle,
  Vorgaenge vorgaenge,
  Vorgang vg, {
  required int kurs,
  required List<int> vorherCmids,
}) async {
  // Erneut aufrufbar (nach „unklar"): Verborgenes wird nicht noch einmal angefasst.
  final vorVerbergen = await kursLesen(moodle, kurs);
  final sichtbareNeue = [
    for (final a in vorVerbergen.nachCmid.values)
      if (!vorherCmids.contains(a.cmid) && a.sichtbar) a.cmid,
  ];
  if (sichtbareNeue.isNotEmpty) {
    await kursAktion(moodle, kurs, 'cm_hide', sichtbareNeue);
  }

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
  final befund = alleVerborgen ? 'verborgen: verified' : 'verborgen: nicht bestätigt, siehe Zustand oben';
  return 'Wiederhergestellt (Nummer ${vg.id}): ${neue.isEmpty ? 'keine neuen Aktivitäten' : liste}. $befund';
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
  if ((stand == WiederherstellungStand.laufend || stand == WiederherstellungStand.unklar) && v.backupid != null) {
    _laufendeWiederherstellungen.add(v.id);
    try {
      final kontext = v.kontext;
      if (kontext == null) throw MoodleFehler('Der Vorgang ${v.id} hat keinen Kontext. Nichts geändert.');
      return await _warten(moodle, vorgaenge, v,
          restoreid: v.backupid!, kontext: kontext, kurs: v.kurs, vorherCmids: v.vorherCmids ?? const []);
    } finally {
      _laufendeWiederherstellungen.remove(v.id);
    }
  }
  return 'Stand (Nummer ${v.id}): ${stand.text}. ${v.text}';
}
