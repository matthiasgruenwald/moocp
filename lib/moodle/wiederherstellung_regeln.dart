// Die Regeln der Wiederherstellung ohne Netz: Prüfung der Sicherungsdatei
// (.mbz), Zustände und erlaubte Übergänge. Gespeichert wird in wiederherstellung.dart.
//
// Die Prüfung läuft vor dem Hochladen. Sie liest das Archiv selbst (Tar-Köpfe
// Feld für Feld) statt einem Entpacker zu vertrauen: jede Eintragsart, jeder
// Pfad und jede Größe wird einzeln geprüft. Nutzerdaten im Archiv lehnt sie ab
// (A1); die Fehlertexte nennen nie Inhalte aus dem Archiv (E11).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'sicherung_regeln.dart' show nutzerdatenOptionen;

/// Obergrenze für eine hochgeladene Sicherung. Das geprüfte Formular nennt 200 MB;
/// steht im Formular ein kleinerer Wert (maxbytes), gilt der kleinere.
const int archivGrenzeStandard = 200 * 1024 * 1024;

/// Obergrenze für den entpackten Inhalt (Schutz vor Gzip-Bomben).
const int entpacktGrenzeStandard = 1024 * 1024 * 1024;

/// Obergrenze für die Zahl der Einträge im Archiv.
const int eintragGrenzeStandard = 20000;

/// Das Verhältnis entpackt zu gepackt, ab dem das Archiv als verdächtig gilt.
const int verhaeltnisGrenze = 200;

/// Die Obergrenze für den Upload: der kleinere Wert aus dem Formular (maxbytes,
/// falls lesbar) und der Standard. Nicht größer als der Standard.
int hochladeGrenze(String? maxbytes) {
  final n = int.tryParse(maxbytes ?? '');
  if (n == null || n <= 0) return archivGrenzeStandard;
  return n < archivGrenzeStandard ? n : archivGrenzeStandard;
}

/// Der Stand einer Wiederherstellung, in vorgaenge.json als wiederherstellung_status.
enum WiederherstellungStand {
  /// Angelegt, noch nichts bei Moodle geändert.
  anstehend,

  /// Die Datei liegt im Entwurfsbereich der Lehrkraft.
  hochgeladen,

  /// Moodle hat die Wiederherstellung angenommen; sie läuft im Hintergrund.
  laufend,

  /// Moodle meldet Ende, und der Kurs ist gegengelesen.
  fertig,

  /// Vor dem Start abgebrochen oder von Moodle abgelehnt. Im Kurs ist nichts geändert.
  fehlgeschlagen,

  /// Ob Moodle die Wiederherstellung ausgeführt hat, ist nicht bekannt. Nie blind wiederholen.
  unklar;

  String get text => switch (this) {
        anstehend => 'anstehend',
        hochgeladen => 'hochgeladen',
        laufend => 'laufend',
        fertig => 'fertig',
        fehlgeschlagen => 'fehlgeschlagen',
        unklar => 'unklar',
      };

  static WiederherstellungStand? aus(String? s) {
    for (final v in values) {
      if (v.name == s) return v;
    }
    return null;
  }
}

/// Die erlaubten Übergänge. Ein Vorgang, der fertig oder fehlgeschlagen ist,
/// bewegt sich nicht mehr. „unklar" löst sich nur durch Gegenlesen auf.
bool erlaubterUebergang(WiederherstellungStand von, WiederherstellungStand nach) => switch (von) {
      WiederherstellungStand.anstehend =>
        nach == WiederherstellungStand.hochgeladen || nach == WiederherstellungStand.fehlgeschlagen,
      WiederherstellungStand.hochgeladen =>
        nach == WiederherstellungStand.laufend || nach == WiederherstellungStand.fehlgeschlagen,
      WiederherstellungStand.laufend => nach == WiederherstellungStand.fertig ||
          nach == WiederherstellungStand.fehlgeschlagen ||
          nach == WiederherstellungStand.unklar,
      WiederherstellungStand.unklar => nach == WiederherstellungStand.fertig ||
          nach == WiederherstellungStand.fehlgeschlagen ||
          nach == WiederherstellungStand.unklar,
      WiederherstellungStand.fertig || WiederherstellungStand.fehlgeschlagen => false,
    };

/// Eine Aktivität aus dem Archiv, für die Freigabe: Art und Titel.
typedef ArchivAktivitaet = ({String modul, String titel});

/// Ergebnis der Prüfung. [grund] ist null, wenn das Archiv angenommen ist.
class ArchivBefund {
  const ArchivBefund({this.grund, this.moodleVersion, this.typ, this.aktivitaeten = const []});
  final String? grund;
  final String? moodleVersion;

  /// „activity" oder „course", wie Moodle es im Archiv nennt.
  final String? typ;
  final List<ArchivAktivitaet> aktivitaeten;

  bool get ok => grund == null;
}

/// Prüft eine Sicherungsdatei vollständig, bevor sie hochgeladen wird.
/// [maxBytes] gilt für die gepackte Größe, [maxEntpackt] für den Inhalt.
Future<ArchivBefund> archivPruefen(
  Uint8List bytes, {
  int maxBytes = archivGrenzeStandard,
  int maxEntpackt = entpacktGrenzeStandard,
  int maxEintraege = eintragGrenzeStandard,
}) async {
  ArchivBefund nein(String g) => ArchivBefund(grund: g);
  if (bytes.length > maxBytes) return nein('Die Datei ist größer als die erlaubten ${maxBytes ~/ (1024 * 1024)} MB.');
  if (bytes.length < 18 || bytes[0] != 0x1f || bytes[1] != 0x8b) {
    return nein('Keine gepackte Sicherung (.mbz mit gzip-Tar). Andere Formate werden nicht angenommen.');
  }

  // Entpacken mit Obergrenze: beim Überschreiten bricht der Strom ab, bevor
  // der Speicher voll ist.
  final out = BytesBuilder(copy: false);
  var n = 0;
  try {
    await for (final stueck in gzip.decoder.bind(Stream.value(bytes))) {
      n += stueck.length;
      if (n > maxEntpackt) return nein('Der entpackte Inhalt ist zu groß.');
      if (n > 10 * 1024 * 1024 && n > verhaeltnisGrenze * bytes.length) {
        return nein('Das Verhältnis von gepackter zu entpackter Größe ist verdächtig.');
      }
      out.add(stueck);
    }
  } on FormatException {
    return nein('Die Sicherung ist beschädigt (gzip).');
  }
  final tar = out.takeBytes();

  // Tar Feld für Feld.
  final dateien = <String, Uint8List>{};
  var pos = 0;
  var eintraege = 0;
  while (pos + 512 <= tar.length) {
    final kopf = Uint8List.sublistView(tar, pos, pos + 512);
    if (kopf.every((b) => b == 0)) break;
    if (!_kopfOk(kopf)) return nein('Die Sicherung ist beschädigt (Tar-Kopf).');
    eintraege++;
    if (eintraege > maxEintraege) return nein('Das Archiv hat zu viele Einträge.');

    final typ = kopf[156];
    final ustar = _text(kopf, 257, 263) == 'ustar';
    final name = _text(kopf, 0, 100);
    final pfad = ustar && _text(kopf, 345, 500).isNotEmpty ? '${_text(kopf, 345, 500)}/$name' : name;
    final groesse = _oktal(kopf, 124, 136);
    if (groesse == null) return nein('Die Sicherung ist beschädigt (Größe im Tar-Kopf).');

    // Nur einfache Dateien und Ordner. Links, Geräte und Erweiterungsköpfe
    // (verlängerte Namen) lehnt die Prüfung ab, weil sie aus dem Zielordner
    // hinausführen oder Inhalte verbergen können.
    final istDatei = typ == 0x30 || typ == 0x00 || typ == 0x37;
    final istOrdner = typ == 0x35;
    if (!istDatei && !istOrdner) {
      if (typ == 0x78 || typ == 0x67 || typ == 0x4c || typ == 0x4b) {
        return nein('Das Archiv nutzt verlängerte Namen; nicht angenommen.');
      }
      return nein('Das Archiv enthält Links oder Sonderdateien; nicht angenommen.');
    }
    final fehler = pfadFehler(pfad);
    if (fehler != null) return nein('Unsicherer Pfad im Archiv ($fehler).');

    final anfang = pos + 512;
    final ende = anfang + groesse;
    if (ende > tar.length) return nein('Die Sicherung ist abgeschnitten.');
    if (istDatei && _braucht(pfad)) {
      dateien[pfad] = Uint8List.sublistView(tar, anfang, ende);
    }
    if (istDatei) {
      // Nutzerdaten erkennt der Name, bevor der Inhalt zählt.
      if (nutzerdatenPfad(pfad)) return nein('Das Archiv enthält Nutzerdaten (Pfad); nicht angenommen.');
    }
    pos = anfang + ((groesse + 511) ~/ 512) * 512;
  }
  if (!dateien.containsKey('moodle_backup.xml')) {
    return nein('Im Archiv fehlt moodle_backup.xml: keine Moodle-Sicherung.');
  }

  // Die Beschreibung des Archivs.
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(utf8.decode(dateien['moodle_backup.xml']!, allowMalformed: true));
  } on XmlException {
    return nein('moodle_backup.xml ist nicht lesbar.');
  }
  final format = _text1(doc, 'format');
  if (format != 'moodle2') return nein('Kein Moodle-2-Archiv (Format ${format ?? 'unbekannt'}).');
  final typ = _text1(doc, 'type');
  if (typ != 'activity' && typ != 'course') return nein('Unbekannter Sicherungstyp.');

  // Nutzerdaten-Einstellungen müssen aus sein.
  for (final s in doc.findAllElements('setting')) {
    final name = s.getElement('name')?.innerText.trim() ?? '';
    final wert = s.getElement('value')?.innerText.trim() ?? '';
    final nutzer = nutzerdatenOptionen.contains(name) || name.endsWith('_userinfo');
    if (nutzer && wert != '0') return nein('Die Sicherung enthält Nutzerdaten (Einstellung $name); nicht angenommen.');
  }

  // Bewertungen und Rollenzuordnungen: leere Platzhalter sind in Ordnung,
  // Einträge zu Personen nicht.
  for (final datei in const ['grades.xml', 'grade_history.xml', 'roles.xml']) {
    final inhalt = dateien[datei];
    if (inhalt == null) continue;
    final text = utf8.decode(inhalt, allowMalformed: true);
    if (RegExp(r'<(grade_grade|grade_history|role_assignment|userid)\b').hasMatch(text)) {
      return nein('Die Sicherung enthält Bewertungen oder Rollen von Personen; nicht angenommen.');
    }
  }

  final aktivitaeten = <ArchivAktivitaet>[
    for (final a in doc.findAllElements('activity'))
      (modul: a.getElement('modulename')?.innerText.trim() ?? '', titel: a.getElement('title')?.innerText.trim() ?? ''),
  ];
  return ArchivBefund(
    moodleVersion: _text1(doc, 'moodle_version'),
    typ: typ,
    aktivitaeten: aktivitaeten,
  );
}

/// Ein Pfad ist unsicher, wenn er absolut ist, Trennzeichen fremder Systeme
/// enthält oder „..“ als Abschnitt hat. Gibt den Grund zurück, sonst null.
/// Den Pfad selbst nennt der Grund nicht.
String? pfadFehler(String pfad) {
  if (pfad.isEmpty) return 'leer';
  if (pfad.startsWith('/') || pfad.contains('\\') || pfad.contains(':') || pfad.contains('\u0000')) {
    return 'absolut oder mit fremdem Trennzeichen';
  }
  for (final s in pfad.split('/')) {
    if (s == '..') return 'Pfad mit „..“';
  }
  return null;
}

/// Dateien, die auf Nutzerdaten hindeuten: die Liste der Nutzer, Nutzerordner
/// und Nutzerdaten je Aktivität.
bool nutzerdatenPfad(String pfad) =>
    pfad == 'users.xml' ||
    pfad.endsWith('/users.xml') ||
    pfad.startsWith('user/') ||
    pfad.contains('/userdata/');

/// Nur diese Dateien liest die Prüfung inhaltlich.
bool _braucht(String pfad) =>
    pfad == 'moodle_backup.xml' || pfad == 'grades.xml' || pfad == 'grade_history.xml' || pfad == 'roles.xml';

bool _kopfOk(Uint8List kopf) {
  final soll = _oktal(kopf, 148, 156);
  if (soll == null) return false;
  var summe = 0;
  for (var i = 0; i < 512; i++) {
    summe += (i >= 148 && i < 156) ? 0x20 : kopf[i];
  }
  return summe == soll;
}

String _text(Uint8List b, int von, int bis) {
  var ende = von;
  while (ende < bis && b[ende] != 0) {
    ende++;
  }
  return latin1.decode(b.sublist(von, ende));
}

/// Eine Oktalzahl aus dem Feld, mit Leerzeichen und NUL am Rand. Null, wenn
/// das Feld keine Oktalzahl ist (auch nicht die Binärform).
int? _oktal(Uint8List b, int von, int bis) {
  if ((b[von] & 0x80) != 0) return null;
  final s = _text(b, von, bis).trim();
  if (s.isEmpty) return 0;
  if (!RegExp(r'^[0-7]+$').hasMatch(s)) return null;
  return int.parse(s, radix: 8);
}

String? _text1(XmlDocument doc, String name) {
  final e = doc.findAllElements(name).firstOrNull;
  return e?.innerText.trim();
}
