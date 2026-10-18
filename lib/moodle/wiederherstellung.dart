// Die Wiederherstellung einer Sicherungsdatei (.mbz) in einen Kurs, über alle fünf
// Zielwege des Assistenten (Issue #9). Die Regeln ohne Netz stehen in
// wiederherstellung_regeln.dart.
//
// Ablauf:
//   Datei und Archiv prüfen (vor jedem Hochladen) -> Zielweg und Angaben prüfen
//   (Rückfrage statt Raten, Löschen nur mit loeschend) -> Kurs und Name prüfen bzw.
//   Kategorie für neuer_kurs -> Freigabe in der App -> Vorgang anlegen, bei löschenden
//   Wegen Übersicht des Zielkurses festhalten -> Datei in den Entwurfsbereich ->
//   Formular „Wiederherstellen" -> Schritte 2, Ziel, 4, 8 und 16 -> Hintergrundauftrag
//   abfragen (Kennung: restoreid) -> neue Aktivitäten verbergen -> Kurs zurücklesen.
//
// Nach dem Schritt 16 gilt: Bricht die Verbindung ab oder läuft die Sitzung ab, steht
// der Vorgang auf „unklar". Er wird nie neu gestartet; wiederherstellung_status fragt
// nur den Stand ab. Vor Schritt 16 hat Moodle im Zielkurs nichts gelöscht oder
// geändert. Ausnahme: Bei neuer_kurs legt Moodle beim Ziel bereits einen
// Platzhalterkurs an (siehe ADR/Plan „Bereits die Zielauswahl kann schreiben").
//
// Der Vorgang steht in vorgaenge.json unter wiederherstellung_status. UNGEMESSEN steht
// im Code und in TODO.md.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:html/parser.dart' as html_parser;

import '../freigabe.dart';
import 'formular.dart';
import 'formular_lesen.dart';
import 'wiederherstellung_fragen.dart';
import 'formular_schreiben.dart';
import 'fragen.dart';
import 'fragen_xml.dart';
import 'kurs.dart';
import 'kurs_aendern.dart';
import 'moodle_zugang.dart';
import 'sicherung.dart';
import 'sicherung_regeln.dart';
import 'test.dart';
import 'wiederherstellung_anhaenge.dart';
import 'wiederherstellung_regeln.dart';

/// Vorgänge, die gerade laufen (Freigabe, Upload oder Abfrage) in dieser Sitzung.
final Set<String> _laufendeWiederherstellungen = {};

/// Fingerabdrücke, für die gerade eine Freigabe oder ein Vorgang läuft (Ticket #19).
/// Hält den Doppelstart-Schutz auch dann, wenn der Vorgang noch nicht gespeichert ist.
final Set<String> _reserviert = {};

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
  List<ArchivAktivitaet>? wiederherstellungAktivitaeten,
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
      vorherCmids: vorherCmids,
      wiederherstellungAktivitaeten: wiederherstellungAktivitaeten);
}

/// Stellt eine Sicherungsdatei aus dem Sicherungsordner wieder her. [datei] liegt
/// relativ zum Sicherungsordner. [weg] ist einer der fünf Zielwege (Zielweg) und
/// Pflicht; fehlt er, kommt eine Rückfrage statt eines Standardwegs. [instanz] ist
/// der Name des Profils, nur für die Freigabe. Löschende Wege brauchen [loeschend].
Future<String> wiederherstellen(
  MoodleZugang moodle,
  Freigaben freigaben,
  Vorgaenge vorgaenge, {
  required String datei,
  required String instanz,
  required String? weg,
  int? kurs,
  String? name,
  bool loeschend = false,
  String? neuerKursName,
  String? kurzname,
  int? kategorieId,
  int? sammlung,
  void Function(String vorgangId)? beiVorgang,
  String? wiederholungVon,
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

  // 3. Zielweg und Angaben, bevor Moodle gelesen wird. Keine Rückfrage wird geraten.
  final wahl = zielwegPruefen(
    weg: weg,
    loeschend: loeschend,
    kurs: kurs,
    neuerKursName: neuerKursName,
    kurzname: kurzname,
  );
  if (wahl.rueckfrage != null) throw MoodleFehler(wahl.rueckfrage!);
  final zielweg = wahl.weg!;

  // 4. Zielkurs (bestehend) bzw. Kategorie (neuer Kurs) und Kontext des Hochladens.
  var kursName = '';
  var vorherCmids = <int>[];
  var vorherText = '';
  int kontext;
  int? kategorie;
  if (zielweg.brauchtKurs) {
    final k = kurs!;
    kursName = await kursname(moodle, k) ?? '';
    if ((name ?? '').trim().isEmpty) throw MoodleFehler('Der Kursname (name) fehlt. Nichts geändert.');
    nameBestaetigen(name!, kursName, 'Kurs $k');
    final vorher = await kursLesen(moodle, k);
    vorherCmids = vorher.nachCmid.keys.toList();
    if (zielweg.loescht) {
      final liste = [for (final a in vorher.nachCmid.values) '„${a.name}" (${a.modul})'];
      vorherText = 'Vor dem Lauf im Kurs $k: ${liste.isEmpty ? 'keine Aktivitäten' : liste.join(', ')}.';
    }
    // Kontext des Kurses (Seitenangaben der Kursseite; UNGEMESSEN).
    final seite = await moodle.lesen('/course/view.php?id=$k');
    final ctx = int.tryParse(Seitenangaben.aus(seite.text).kontext ?? '');
    if (ctx == null) throw MoodleFehler('Moodle nennt den Kontext des Kurses nicht. Nichts geändert.');
    kontext = ctx;
  } else {
    kategorie = await _kategorie(moodle, kategorieId);
    kontext = await _kategorieKontext(moodle, kategorie);
  }

  // 4b. Doppelstart-Schutz (Ticket #19, Spec #17): Vor der Freigabe prüfen, damit ein
  // abgewiesener Aufruf nichts fragt. Der Inhalt zählt, nicht der Dateiname.
  final fp = fingerabdruck(bytes, kurs: kurs ?? 0, weg: zielweg);
  if (_reserviert.contains(fp)) {
    throw MoodleFehler('Diese Datei wird für diesen Zielweg gerade schon wiederhergestellt. Nichts geändert.');
  }
  final sperre = doppelstartSperre(
    doppelstartEintraege(await vorgaenge.alle()),
    fingerabdruck: fp,
    wiederholungVon: wiederholungVon,
    kurs: kurs ?? 0,
  );
  if (sperre != null) {
    throw MoodleFehler('Dieselbe Datei für diesen Zielweg ist schon im Vorgang Nummer $sperre offen. '
        'Mit wiederherstellung_status prüfen. Eine erneute Wiederherstellung nur mit wiederholung_von=$sperre. Nichts geändert.');
  }

  // 5. Freigabe in der App, vor jedem Schreiben (beim neuen Kurs vor dem Platzhalter).
  _reserviert.add(fp);
  final aktivitaeten = [
    for (final a in befund.aktivitaeten) '„${a.titel}" (${a.modul})',
  ];
  final zielZeile = zielweg.brauchtKurs
      ? 'Kurs ${kurs!} „$kursName" (bestehender Kurs)'
      : 'Neuer Kurs „$neuerKursName" (Kurzname „$kurzname“) in Kategorie $kategorie. '
          'Moodle legt vor den Einstellungen einen Platzhalterkurs an; nach einem Abbruch wird er über Moodle entfernt.';
  final modusZeile = switch (zielweg) {
    Zielweg.neuerKurs => 'Modus: neuer Kurs. Nichts Bestehendes wird verändert.',
    Zielweg.aktuellerKursVerschmelzen || Zielweg.anderKursVerschmelzen =>
      'Modus: verschmelzen. Inhalte werden zum Kurs hinzugefügt; nichts im Kurs wird gelöscht.',
    _ => 'Modus: ${zielweg.nennung}. Im Kurs gilt: vorhandene Inhalte werden gelöscht, dann wiederhergestellt. '
        'Die Übersicht vor dem Lauf wird im Vorgang festgehalten. Nicht rückgängig zu machen.',
  };
  final herkunftZeilen = await _herkunftZeilen(moodle, befund, sammlung);
  final ja = await freigaben.anfragen(FreigabeAnfrage(
    titel: zielweg.loescht ? 'Vorhandene Inhalte löschen und wiederherstellen?' : 'Wiederherstellen ausführen?',
    punkte: [
      'Profil: $instanz',
      zielZeile,
      'Datei: ${p.basename(datei)} (${befund.typ == 'course' ? 'ganzer Kurs' : 'Aktivität'}, Moodle ${befund.moodleVersion ?? '?'})',
      modusZeile,
      if (zielweg.loescht && zielweg.brauchtKurs)
        'Im Kurs „$kursName" werden vorhandene Inhalte gelöscht, bevor die Datei wieder hineinkommt.',
      if (aktivitaeten.isNotEmpty) 'Angelegt werden: ${aktivitaeten.join(', ')}',
      // Fragenherkunft (Issue #20) vor dem Start; die Lesart ist UNGEMESSEN (TODO.md).
      ...herkunftZeilen,
      'Moodle stellt die neuen Aktivitäten sichtbar wieder her; die App verbirgt sie danach. Sie können '
          'kurzzeitig für Lernende sichtbar sein. Verborgen ist kein Schutz: Wer im Kurs Rechte hat, sieht sie und kann sie sichtbar machen.',
      'Nutzerdaten sind im Archiv nicht enthalten (geprüft). Rechte und Einschreibungen bleiben unverändert.',
      if (wiederholungVon != null)
        'Wiederholung des Vorgangs $wiederholungVon, der nicht abgeschlossen ist. Moodle kann ihn schon ausgeführt haben.',
    ],
    vergleich: const [],
    knopf: zielweg.loescht ? 'Löschen und wiederherstellen' : 'Wiederherstellen',
    ohneEntscheidung: 'wird nichts wiederhergestellt',
  ));
  if (!ja) {
    _reserviert.remove(fp);
    return 'Nicht wiederhergestellt: in der App abgelehnt oder nicht innerhalb von '
        '${freigaben.frist.inMinutes} Minuten freigegeben. Nichts geändert.';
  }

  // 6. Vorgang anlegen und Datei hochladen (jedes Mal neu, nie eine alte Kennung).
  final vg = await vorgaenge.neuWiederherstellung(
      kurs: kurs ?? 0, datei: datei, fingerabdruck: fp, wiederholungVon: wiederholungVon);
  _laufendeWiederherstellungen.add(vg.id);
  // Die Nummer geht nur an den Aufrufer, damit er das Ergebnis je Ziel
  // zuordnen kann (uebertragen, Issue #10). Ohne Rückruf unverändert.
  beiVorgang?.call(vg.id);
  try {
    return await _ausfuehren(moodle, vorgaenge, vg,
        bytes: bytes,
        kontext: kontext,
        zielweg: zielweg,
        kurs: kurs,
        kategorie: kategorie,
        neuerKursName: neuerKursName,
        kurzname: kurzname,
        vorherCmids: vorherCmids,
        wiederherstellungAktivitaeten: befund.aktivitaeten,
        quizQuelle: befund.quizFragen.length == 1 ? befund.quizFragen.values.first : null,
        vorherText: vorherText,
        name: p.basename(datei));
  } finally {
    _laufendeWiederherstellungen.remove(vg.id);
    _reserviert.remove(fp);
  }
}

/// Kategorie des neuen Kurses: die Angabe, sonst die Vorgabe des Kursformulars.
/// Ohne beides eine Rückfrage.
Future<int> _kategorie(MoodleZugang moodle, int? kategorieId) async {
  if (kategorieId != null) return kategorieId;
  final f = await formularHolen(moodle, '/course/edit.php');
  final k = int.tryParse(wertIn(f.felder, 'category') ?? '');
  if (k == null) {
    throw MoodleFehler('Das Kursformular nennt keine Kategorie. Bitte kategorie_id angeben. Nichts geändert.');
  }
  return k;
}

/// Kontext der Kategorie, unter dem das Hochladen für einen neuen Kurs geschieht
/// (UNGEMESSEN: Seitenangaben der Kursverwaltung).
Future<int> _kategorieKontext(MoodleZugang moodle, int kategorie) async {
  final seite = await moodle.lesen('/course/management.php?categoryid=$kategorie');
  final ctx = int.tryParse(Seitenangaben.aus(seite.text).kontext ?? '');
  if (ctx == null) throw MoodleFehler('Moodle nennt den Kontext der Kategorie nicht (UNGEMESSEN). Nichts geändert.');
  return ctx;
}

Future<String> _ausfuehren(
  MoodleZugang moodle,
  Vorgaenge vorgaenge,
  Vorgang vg, {
  required List<int> bytes,
  required int kontext,
  required Zielweg zielweg,
  required int? kurs,
  required int? kategorie,
  required String? neuerKursName,
  required String? kurzname,
  required List<int> vorherCmids,
  required List<ArchivAktivitaet> wiederherstellungAktivitaeten,
  List<QuizFrage>? quizQuelle,
  required String vorherText,
  required String name,
}) async {
  var vorUpload = true;
  var platzhalter = false;
  try {
    if (vorherText.isNotEmpty) {
      await vorgaenge.aktualisieren(vg, text: vorherText);
    }

    // Formular „Wiederherstellen" holen; der Entwurfsbereich ist sein Feld backupfile.
    final f = await formularHolen(moodle, '/backup/restorefile.php?contextid=$kontext');
    final itemid = wertIn(f.felder, 'backupfile');
    if (itemid == null) throw MoodleFehler('Das Formular nennt keinen Entwurfsbereich. Nichts geändert.');
    await hochladen(moodle, f, itemid, '/', name, bytes);
    await _uebergang(vorgaenge, vg, WiederherstellungStand.hochgeladen,
        vorherCmids: vorherCmids, wiederherstellungAktivitaeten: wiederherstellungAktivitaeten);

    // Formular absenden: Moodle legt die Datei ab und leitet zum Assistenten.
    final r = await moodle.senden(f.aktion, f.felder);
    final ziel = moodle.umleitungsziel(r) ?? r.adresse;
    final laufzeit = ziel.queryParameters['filename'];
    if (ziel.path != '/backup/restore.php' || laufzeit == null || laufzeit.isEmpty) {
      throw MoodleFehler('Moodle übernimmt die Datei nicht (keine Kennung). Nichts geändert.');
    }
    await vorgaenge.aktualisieren(vg, wiederherstellungDatei: laufzeit);

    // Schritt 2: Sicherungsdetails (gemessen: schlichtes Formular ohne mform, stage=2).
    final adresse = '/backup/restore.php?contextid=$kontext&filename=$laufzeit';
    final s1 = restoreSeite(await moodle.lesen(adresse));
    if (schrittVon(s1.felder) != '2') {
      throw MoodleFehler('Die Seite Sicherungsdetails kommt nicht wie gemessen. Nichts geändert.');
    }

    // Zielseite (stage=4): Moodle bietet je Zielweg ein eigenes Formular an
    // (gemessen im Kurskontext). Nur das Formular mit dem gewählten target senden;
    // fehlt es, wird das nicht erzwungen.
    final zielAntwort = await moodle.senden(s1.aktion, s1.felder);
    if (schrittVon(restoreSeite(zielAntwort).felder) != '4') {
      throw MoodleFehler('Die Zielseite kommt nicht wie gemessen. Nichts geändert.');
    }
    final angebote = restoreFormulare(zielAntwort);
    final angeboten = {for (final a in angebote) if (wertIn(a.felder, 'target') != null) wertIn(a.felder, 'target')!};
    final gewaehlt = angebote.where((a) => wertIn(a.felder, 'target') == '${zielweg.moodle}').firstOrNull;
    if (gewaehlt == null) {
      throw MoodleFehler('Moodle bietet „${zielweg.nennung}" auf dieser Seite nicht an '
          '(angeboten: ${angeboten.isEmpty ? 'keine' : angeboten.join(', ')}). Nichts geändert.');
    }
    final f2 = [...gewaehlt.felder];
    setze(f2, 'target', '${zielweg.moodle}');
    // targetid: der Kurs bei den Wegen mit Kurs-ID, die Kategorie bei neuer_kurs.
    setze(f2, 'targetid', zielweg.brauchtKurs ? '$kurs' : '$kategorie');
    platzhalter = zielweg == Zielweg.neuerKurs;
    final s4 = restoreSeite(await moodle.senden(gewaehlt.aktion, f2));
    if (!s4.felder.any((e) => e.key == '_qf__restore_settings_form')) {
      throw MoodleFehler('Der Zielweg „${zielweg.nennung}" wird nicht wie gemessen angenommen (UNGEMESSEN). Nichts weiter gestartet.');
    }

    // Schritt 4: Einstellungen, nur wenn keine Nutzerdaten vorgesehen sind.
    if (!ohneNutzerdaten(s4.felder)) {
      throw MoodleFehler('Die Einstellungen sehen Nutzerdaten vor; abgebrochen. Nichts geändert.');
    }
    final s8 = restoreSeite(await moodle.senden(s4.aktion, s4.felder));
    if (!s8.felder.any((e) => e.key == '_qf__restore_schema_form')) {
      throw MoodleFehler('Das Schema kommt nicht wie gemessen. Nichts weiter gestartet.');
    }
    if (!ohneNutzerdaten(s8.felder)) {
      throw MoodleFehler('Das Schema sieht Nutzerdaten vor; abgebrochen. Nichts geändert.');
    }
    // Neuer Kurs: Kursname, Kurzname und (falls das Formular es bietet) verborgen.
    var sichtbarGesetzt = false;
    final schema = [...s8.felder];
    if (zielweg == Zielweg.neuerKurs) {
      sichtbarGesetzt = _neuerKursFelder(schema, neuerKursName!, kurzname!);
    }
    final s16 = restoreSeite(await moodle.senden(s8.aktion, schema));
    if (!s16.felder.any((e) => e.key == '_qf__restore_review_form')) {
      throw MoodleFehler('Die Prüfseite kommt nicht wie gemessen. Nichts weiter gestartet.');
    }

    // Die Kennung für den Fortschritt ist die Restore-ID aus dem Prüfformular
    // (Feld restoreid), nicht der Dateinamen-Hash der Laufzeit (gemessen: Moodle
    // lehnt den Hash mit „Ungültiger Parameterwert" ab). Fehlt sie, startet nichts.
    final restoreid = wertIn(s16.felder, 'restore');
    if (restoreid == null || !RegExp(r'^[0-9a-f]{32}$').hasMatch(restoreid)) {
      throw MoodleFehler('Das Prüfformular nennt keine Kennung der Wiederherstellung (restoreid). Nichts weiter gestartet.');
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
    final ergebnis = await _warten(moodle, vorgaenge, vg,
        restoreid: restoreid,
        kontext: kontext,
        kurs: kurs,
        vorherCmids: vorherCmids,
        wiederherstellungAktivitaeten: wiederherstellungAktivitaeten,
        quizQuelle: quizQuelle,
        sichtbarGesetzt: sichtbarGesetzt);
    return ergebnis;
  } catch (e) {
    if (vorUpload) {
      await _uebergang(vorgaenge, vg, WiederherstellungStand.fehlgeschlagen,
          text: platzhalter
              ? 'Der Platzhalterkurs ist möglicherweise angelegt; in Moodle prüfen. Nichts weiter gestartet '
                  '(nativer Abbruch der Angaben: UNGEMESSEN).'
              : 'Vor dem Start abgebrochen; im Kurs ist nichts geändert.');
    }
    rethrow;
  }
}

/// Setzt Kursname und Kurzname des neuen Kurses im Schema. Die Feldnamen sind
/// gemessen nur als Präfix (`setting_course_course_fullname…`); fehlen sie, bricht
/// das ab. Gibt zurück, ob die Sichtbarkeit auf verborgen gesetzt wurde.
bool _neuerKursFelder(Felder f, String name, String kurzname) {
  final schluessel = {for (final e in f) e.key};
  final voll = schluessel.where((k) => k.startsWith('setting_course_course_fullname')).toList();
  final kurz = schluessel.where((k) => k.startsWith('setting_course_course_shortname')).toList();
  if (voll.isEmpty || kurz.isEmpty) {
    throw MoodleFehler('Das Schema nennt keine Felder für Kursname und Kurzname (UNGEMESSEN). Nichts weiter gestartet.');
  }
  for (final k in voll) {
    setze(f, k, name);
  }
  for (final k in kurz) {
    setze(f, k, kurzname);
  }
  final sichtbar = schluessel.where((k) => k.startsWith('setting_course_course_visible')).toList();
  for (final k in sichtbar) {
    setze(f, k, '0');
  }
  return sichtbar.isNotEmpty;
}

/// Das Formular des Wiederherstellungsassistenten: Er hat auf manchen Seiten
/// kein `form.mform`; dann ist es das Formular mit Ziel /backup/restore.php
/// (gemessen auf der Seite „Sicherungsdetails").
({String aktion, Felder felder, Seitenangaben seite}) restoreSeite(Antwort r) {
  final form = restoreFormulare(r).firstOrNull;
  if (form == null) {
    final doc = html_parser.parse(r.text);
    final haupt = hauptformular(doc);
    if (haupt == null) throw MoodleFehler('Moodle liefert kein Formular des Wiederherstellungsassistenten.');
    return (aktion: r.adresse.path, felder: formularFelder(haupt), seite: Seitenangaben.aus(r.text));
  }
  return (aktion: form.aktion, felder: form.felder, seite: Seitenangaben.aus(r.text));
}

/// Alle Formulare des Assistenten auf einer Seite (Ziel /backup/restore.php), mit
/// Aktion und Feldern. Die Aktion ist ohne Host, wie die Positivliste sie prüft.
List<({String aktion, Felder felder})> restoreFormulare(Antwort r) {
  final doc = html_parser.parse(r.text);
  return [
    for (final form in doc.querySelectorAll('form'))
      if ((form.attributes['action'] ?? '').contains('/backup/restore.php'))
        (
          aktion: () {
            final ziel = r.adresse.resolve(form.attributes['action'] ?? r.adresse.path);
            return ziel.hasQuery ? '${ziel.path}?${ziel.query}' : ziel.path;
          }(),
          felder: formularFelder(form),
        ),
  ];
}

/// Fragt den Hintergrundauftrag ab. Dann liest sie den Kurs zurück. Bei neuer_kurs
/// ist die Kursnummer unbekannt (UNGEMESSEN): dann wird nicht gegengelesen.
/// Stillstand (Ticket #18) wird am Anfang des Aufrufs geprüft, wie bei der Sicherung.
Future<String> _warten(
  MoodleZugang moodle,
  Vorgaenge vorgaenge,
  Vorgang vg, {
  required String restoreid,
  required int kontext,
  required int? kurs,
  required List<int> vorherCmids,
  required List<ArchivAktivitaet> wiederherstellungAktivitaeten,
  List<QuizFrage>? quizQuelle,
  bool sichtbarGesetzt = false,
  Duration gesamt = const Duration(minutes: 10),
  Duration takt = const Duration(seconds: 3),
}) async {
  final ende = jetzt().add(gesamt);
  var erster = true;
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
      final fortschritt = fortschrittswert(antwort, restoreid);
      final jetzige = jetzt();
      if (fortschritt != vg.fortschritt) {
        await vorgaenge.aktualisieren(vg, fortschritt: fortschritt, fortschrittSeit: jetzige);
      }
      if (erster && istStillstand(jetzige, vg.fortschrittSeit)) {
        return stillstandText(
          nummer: vg.id,
          werkzeug: 'wiederherstellung_status',
          fortschritt: fortschritt,
          seit: jetzige.difference(vg.fortschrittSeit!),
          ursachen: 'Die Ad-hoc-Aufgaben oder der Cron von Moodle laufen nicht weiter; '
              'die Administration prüft das. Die Wiederherstellung ist nicht als gescheitert gemeldet.',
        );
      }
      erster = false;
      if (jetzt().isAfter(ende)) {
        return 'Die Wiederherstellung läuft noch (Nummer ${vg.id}), letzte Beobachtung '
            '${fortschritt == null ? 'unbekannt' : '${(fortschritt * 100).round()} %'}. '
            'Mit wiederherstellung_status später prüfen.';
      }
      await schlafe(takt);
    }
    if (kurs == null) {
      await _uebergang(vorgaenge, vg, WiederherstellungStand.fertig,
          text: 'Neuer Kurs: Die Kursnummer ist nicht bekannt (UNGEMESSEN); Aktivitäten nicht gegengelesen. '
              'Im Kursverzeichnis prüfen und ob der Kurs verborgen ist.',
          verified: false);
      return 'Neuer Kurs angelegt (Nummer ${vg.id}). Die Kursnummer ist nicht bekannt; Kurs bitte in Moodle prüfen '
          '(nicht verifiziert).${sichtbarGesetzt ? ' Verborgen gesetzt, sofern das Formular es bot.' : ''}';
    }
    return await _gegenlesen(moodle, vorgaenge, vg, kurs: kurs, vorherCmids: vorherCmids,
        erwartet: wiederherstellungAktivitaeten, quizQuelle: quizQuelle);
  } on MoodleFehler {
    await _uebergang(vorgaenge, vg, WiederherstellungStand.unklar,
        text: 'Abfrage nicht gelungen; wiederherstellung_status prüft erneut.');
    rethrow;
  }
}

/// Die Zeilen zur Fragenherkunft in der Freigabe (Issue #20), vor dem Start. Ohne eigene
/// Sammlung ist es eine Prüflücke, nie ein Nachweis. Die Sachnummern liest die App wie
/// fragen_lesen über Kategorien und Export.
Future<List<String>> _herkunftZeilen(MoodleZugang moodle, ArchivBefund befund, int? sammlung) async {
  if (!befund.aktivitaeten.any((a) => a.modul == 'quiz')) return const [];
  if (sammlung == null) {
    return const ['Fragenherkunft nicht geprüft: keine eigene Fragensammlung angegeben (Prüflücke).'];
  }
  if (befund.quizFragen.isEmpty) {
    return [herkunftPruefen(verwendet: null, eigeneSachnummern: const {}, eigeneAnzahl: 0).text];
  }
  final nummern = <String>{};
  var anzahl = 0;
  for (final k in await kategorienLesen(moodle, sammlung)) {
    if (k.anzahl == 0) continue;
    for (final f in fragenAusXml(await exportieren(moodle, sammlung, k))) {
      anzahl++;
      final nr = f.idnummer;
      if (nr != null) nummern.add(nr);
    }
  }
  return [
    for (final e in befund.quizFragen.entries)
      'Quiz ${e.key}: ${herkunftPruefen(verwendet: e.value, eigeneSachnummern: nummern, eigeneAnzahl: anzahl).text}',
  ];
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
  required List<ArchivAktivitaet> erwartet,
  List<QuizFrage>? quizQuelle,
}) async {
  // Erneut aufrufbar (nach „unklar"): Verborgenes wird nicht noch einmal angefasst.
  final vorVerbergen = await kursLesen(moodle, kurs);
  final zugeordnet = importierteCmidsEindeutig(
    erwartet: erwartet,
    vorher: vorherCmids.toSet(),
    aktuell: [for (final a in vorVerbergen.nachCmid.values) (cmid: a.cmid, modul: a.modul, titel: a.name)],
  );
  final sichtbareNeue = zugeordnet == null ? const <int>[] :
      [for (final cmid in zugeordnet) if (vorVerbergen.nachCmid[cmid]!.sichtbar) cmid];
  if (sichtbareNeue.isNotEmpty) {
    await kursAktion(moodle, kurs, 'cm_hide', sichtbareNeue);
  }

  final jetzt = await kursLesen(moodle, kurs);
  final neue = [
    for (final a in jetzt.nachCmid.values)
      if (!vorherCmids.contains(a.cmid)) a,
  ];
  final abschliessendZugeordnet = importierteCmidsEindeutig(
    erwartet: erwartet,
    vorher: vorherCmids.toSet(),
    aktuell: [for (final a in jetzt.nachCmid.values) (cmid: a.cmid, modul: a.modul, titel: a.name)],
  );
  final zuordnungUnveraendert = zugeordnet != null && abschliessendZugeordnet != null &&
      zugeordnet.toSet().containsAll(abschliessendZugeordnet) && abschliessendZugeordnet.toSet().containsAll(zugeordnet);
  final alleVerborgen = zuordnungUnveraendert && zugeordnet.isNotEmpty &&
      zugeordnet.every((cmid) => jetzt.nachCmid[cmid]?.sichtbar == false);
  final liste = neue.map((a) => '„${a.name}" (${a.modul}${a.sichtbar ? ', sichtbar' : ', verborgen'})').join(', ');
  // Ticket #21: Anhänge und Bilder der eindeutig zugeordneten Aktivitäten zurücklesen.
  // Nur bei eindeutiger Zuordnung; sonst bleibt die Prüfung aus (keine Raterei).
  final bestaetigt = zuordnungUnveraendert ? abschliessendZugeordnet : null;
  final anhang = bestaetigt == null
      ? null
      : await anhaengePruefen(moodle, vorgaenge, vg, [
          for (final cmid in bestaetigt)
            (cmid: cmid, modul: jetzt.nachCmid[cmid]!.modul, titel: jetzt.nachCmid[cmid]!.name),
        ]);
  final basis = zugeordnet == null
      ? 'Importierte Aktivitäten konnten nicht eindeutig von anderen neuen Aktivitäten unterschieden werden. Keine Aktivität wurde verborgen; bitte prüfen.'
      : !zuordnungUnveraendert
          ? 'Nach dem Verbergen kamen weitere oder mehrdeutige neue Aktivitäten hinzu. Nur zuvor eindeutig zugeordnete Importaktivitäten wurden verborgen; bitte prüfen.'
      : neue.isEmpty
      ? 'Keine neuen Aktivitäten im Kurs gefunden.'
      : alleVerborgen
          ? 'Neu im Kurs: $liste.'
          : 'Neu im Kurs: $liste. Nicht alle sind verborgen; bitte prüfen.';
  // Fragenvergleich (Issue #20) nach dem Wiederherstellen: nur bei genau einem Quiz im
  // Archiv und genau einem neuen Quiz im Kurs. Sonst Prüflücke, nie Gleichheit.
  final quizArchiv = erwartet.where((a) => a.modul == 'quiz').length;
  final neueQuizze = [for (final a in neue) if (a.modul == 'quiz') a.cmid];
  FragenVergleich? vergleich;
  if (quizArchiv > 0) {
    vergleich = quizQuelle == null || quizArchiv != 1 || neueQuizze.length != 1
        ? FragenVergleich(VergleichArt.pruefluecke,
            'Fragenvergleich nicht möglich: Quiz im Archiv oder im Kurs nicht eindeutig zuzuordnen.')
        : fragenVergleichen(
            quelle: quizQuelle,
            ziel: [for (final p in (await testLesen(moodle, neueQuizze.single)).plaetze) (name: p.name, zufall: p.zufall)],
          );
  }
  // verified nur, wenn alle Prüfungen es erlauben: Verbergen, Anhänge und Fragenvergleich.
  final anhangOk = anhang == null || anhang.vollstaendig;
  final vergleichOk = vergleich == null || quizVerifiziert(vergleich);
  final verifiziert = alleVerborgen && anhangOk && vergleichOk;
  final zusatz = [if (anhang != null) anhang.text, if (vergleich != null) vergleich.text].join(' ');
  final text = zusatz.isEmpty ? basis : '$basis $zusatz';
  await _uebergang(vorgaenge, vg, WiederherstellungStand.fertig, text: text, verified: verifiziert);
  final befund = verifiziert ? 'verborgen: verified' : 'verborgen oder Anhänge/Vergleich nicht bestätigt, siehe Zustand oben';
  return 'Wiederhergestellt (Nummer ${vg.id}): ${neue.isEmpty ? 'keine neuen Aktivitäten' : liste}. $befund.'
      '${zusatz.isEmpty ? '' : ' $zusatz'}';
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
      // Kurs 0 steht für einen neuen Kurs, dessen Nummer nicht bekannt ist.
      return await _warten(moodle, vorgaenge, v,
          restoreid: v.backupid!,
          kontext: kontext,
          kurs: v.kurs == 0 ? null : v.kurs,
          vorherCmids: v.vorherCmids ?? const [],
          wiederherstellungAktivitaeten: v.wiederherstellungAktivitaeten ?? const []);
    } finally {
      _laufendeWiederherstellungen.remove(v.id);
    }
  }
  return 'Stand (Nummer ${v.id}): ${stand.text}. ${v.text}';
}
