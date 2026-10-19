// Formulare zurückschreiben und Aktivitäten anlegen: Werkzeuge aendern und
// aktivitaet_anlegen; dazu die Bausteine, die abschnitt_anlegen und
// buchkapitel_anlegen benutzen.
//
// Geschrieben wird über dieselben Formulare wie im Browser: Formular
// abrufen, ALLE Felder so übernehmen, wie ein Browser sie senden würde, nur
// die gewünschten ändern, absenden. Danach wird zurückgelesen und
// verglichen -- ein Schreibvorgang ohne Rückleseprobe gilt nicht als
// erledigt. Moodle meldet Erfolge, die keine sind: Ein Auswahlfeld nimmt
// einen Wert, den es nicht als Option hat, stillschweigend nicht an.
//
// Was geschrieben werden kann, liegt in einem Ordner, wie formularLesen ihn
// ablegt:
//   <feld>.html      Quelltext eines Editorfelds (page, introeditor,
//                    activityeditor, summary_editor …); Bilder als
//                    @@PLUGINFILE@@/<name>
//   dateien/<name>   die im Quelltext eingebundenen Dateien
//   bereiche/<feld>/ Dateibereiche, etwa Zusätzliche Dateien einer Aufgabe
// Einstellungen (Fristen, Abgabetypen, Punkte, Name …) kommen als Parameter,
// mit den Schlüsseln aus einstellungen.json.
//
// Grenzen, im Code und nicht nur in der Beschreibung:
//   - Dateien nur aus dem Arbeitsordner;
//   - neu Angelegtes ist verborgen; sichtbar nur nach Freigabe;
//   - Bestehendes ändern nur nach Freigabe in der App, mit
//     Änderungsübersicht und Zeilenvergleich;
//   - Ändern nur, wenn Moodle noch den Stand vom Lesen zeigt (.stand/).
// Welche Kurse die Sitzung bearbeiten darf, entscheidet Moodle.

import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

import '../freigabe.dart';
import '../log.dart';
import 'auswertung.dart';
import 'elemente.dart';
import 'formeln.dart';
import 'formular.dart';
import 'formular_lesen.dart';
import 'kurs.dart';
import 'moodle_zugang.dart';
import 'stack_skripte.dart';
import 'zeilenvergleich.dart';

/// Das Editorfeld, das eine neue Aktivität mindestens braucht. Fehlt ein Typ
/// hier, darf der Ordner leer sein (etwa beim Verzeichnis nur Dateien).
const Map<String, String> pflichtfeld = {
  'page': 'page', // Textseite: Inhalt
  'label': 'introeditor', // Textfeld: Inhalt
};

String typName(String? typ) => switch (typ) {
      'page' => 'Textseite',
      'label' => 'Textfeld',
      'assign' => 'Aufgabe',
      'folder' => 'Verzeichnis',
      'subsection' => 'Unterabschnitt',
      'book' => 'Buch',
      'quiz' => 'Test',
      'qbank' => 'Fragensammlung',
      'checklist' => 'Fortschrittsliste',
      'wiki' => 'Wiki',
      'board' => 'Board',
      'kanban' => 'Kanban-Board',
      'url' => 'Link',
      'resource' => 'Datei',
      'forum' => 'Forum',
      _ => typ ?? '?',
    };

// ---------------------------------------------------------------------------
// Hilfen
// ---------------------------------------------------------------------------

final attrMuster = RegExp(r'''(src|href)\s*=\s*(["'])(.*?)\2''', dotAll: true);

bool _istDatei(String wert) =>
    wert.contains('/draftfile.php/') || wert.contains('/pluginfile.php/') || wert.startsWith('@@PLUGINFILE@@/');

/// Namen der im Quelltext eingebundenen Dateien.
Set<String> eingebunden(String html) => {
      for (final m in attrMuster.allMatches(html))
        if (_istDatei(m.group(3)!)) dateiname(m.group(3)!.replaceAll('&amp;', '&'))
    };

String normalisiert(String html) => html.replaceAll(
    RegExp(r'/draftfile\.php/\d+/user/draft/\d+/'), '/draftfile.php/U/user/draft/X/');

/// Größte Datei, die in der Freigabe noch zeilenweise verglichen wird.
const int _vergleichGrenze = 256 * 1024;

/// Der Inhalt als Text, oder null, wenn es keiner ist: Nullbytes oder kein
/// gültiges UTF-8 heißt Bilddatei, Schrift, Archiv -- dort zeigt ein
/// Zeilenvergleich nichts. Zeilenenden werden angeglichen, sonst stünde eine
/// Datei mit CRLF komplett als geändert da.
String? alsText(List<int> b) {
  if (b.length > _vergleichGrenze || b.contains(0)) return null;
  try {
    return utf8.decode(b).replaceAll('\r\n', '\n');
  } on FormatException {
    return null;
  }
}

bool gleicheBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String mimeTyp(String name) => switch (p.extension(name).toLowerCase()) {
      '.svg' => 'image/svg+xml',
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.pdf' => 'application/pdf',
      '.xml' => 'text/xml',
      _ => 'application/octet-stream',
    };

String imArbeitsordner(String ordner, String arbeitsordner) {
  // Relativ heißt: relativ zum Arbeitsordner, nicht zum Startordner der App.
  final ao = _echterPfad(arbeitsordner);
  final q = _echterPfad(p.isAbsolute(ordner) ? ordner : p.join(ao, ordner));
  if (!p.isWithin(ao, q)) {
    throw MoodleFehler('Gesperrt: Der Ordner muss im Arbeitsordner liegen ($arbeitsordner).');
  }
  return q;
}

/// Liest eine Textdatei aus dem Arbeitsordner. Fehlt sie, sagt die Meldung
/// das, statt als „unerwarteter Fehler" mit Stack-Trace zu enden.
Future<String> dateiAusArbeitsordner(String datei, String arbeitsordner) async {
  final pfad = imArbeitsordner(datei, arbeitsordner);
  final f = File(pfad);
  if (!f.existsSync()) {
    throw MoodleFehler('Die Datei $pfad gibt es nicht. Nach einem Neustart der App ist der Arbeitsordner leer -- '
        'dann die Datei neu schreiben.');
  }
  return f.readAsString(encoding: utf8);
}

/// Ein Pfad so, wie Windows ihn selbst schreibt: Kurznamen ausgeschrieben
/// (%TEMP% steht auf manchen Rechnern als C:\Users\LEHRKR~1\…), Verknüpfungen
/// und Junctions aufgelöst. Sonst lehnte der Textvergleich in
/// [imArbeitsordner] denselben Ordner in anderer Schreibweise ab -- und ließe
/// umgekehrt über eine Junction im Arbeitsordner Dateien von außerhalb
/// hochladen. Aufgelöst wird der längste vorhandene Anfang; was es noch
/// nicht gibt, bleibt als Text dahinter stehen.
String _echterPfad(String pfad) {
  final rest = <String>[];
  var d = p.normalize(p.absolute(pfad));
  while (true) {
    try {
      return p.joinAll([File(d).resolveSymbolicLinksSync(), ...rest.reversed]);
    } on FileSystemException {
      final oben = p.dirname(d);
      if (oben == d) return p.normalize(p.absolute(pfad));
      rest.add(p.basename(d));
      d = oben;
    }
  }
}

/// Editorfelder eines Ordners: `<feld>.html` -> Quelltext. Nicht dazu gehören
/// die Vorschauen und das in .stand abgelegte Formular.
///
/// Zeilenenden werden LF. Zurückgelesen kommt immer LF: Der HTML-Parser
/// macht aus CRLF und einzelnem CR ein LF, wie der HTML-Standard es verlangt.
/// Eine auf Windows geschriebene Datei (CRLF) fiele sonst in der
/// Rückleseprobe durch, und beim Ändern zeigte der Zeilenvergleich jede Zeile
/// als neu. Bedeutung hat CR im HTML keine, auch nicht in <pre>.
Map<String, String> felderIn(String ordner) {
  final d = Directory(ordner);
  if (!d.existsSync()) return {};
  return {
    for (final f in d.listSync().whereType<File>())
      if (f.path.endsWith('.html') &&
          p.basename(f.path) != 'formular.html')
        p.basenameWithoutExtension(f.path):
            f.readAsStringSync(encoding: utf8).replaceAll('\r\n', '\n').replaceAll('\r', '\n')
  };
}

/// Dateibereiche eines Ordners: Feld -> {„/pfad/name" -> Bytes}.
Map<String, Map<String, List<int>>> bereicheIn(String ordner) {
  final wurzel = Directory(p.join(ordner, 'bereiche'));
  if (!wurzel.existsSync()) return {};
  final aus = <String, Map<String, List<int>>>{};
  for (final b in wurzel.listSync().whereType<Directory>()) {
    final dateien = <String, List<int>>{};
    for (final f in b.listSync(recursive: true).whereType<File>()) {
      dateien['/${p.relative(f.path, from: b.path).replaceAll(r'\', '/')}'] = f.readAsBytesSync();
    }
    aus[p.basename(b.path)] = dateien;
  }
  return aus;
}

(String, String) _pfadName(String schluessel) {
  final i = schluessel.lastIndexOf('/');
  return (schluessel.substring(0, i + 1), schluessel.substring(i + 1));
}

/// Vergleichbarer Name: Leerraum zusammengefasst.
String nameNormal(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Prüft den Namen, den das Modell nennt, gegen den in Moodle. So trifft eine
/// vertauschte Nummer nicht das Falsche.
void nameBestaetigen(String erwartet, String tatsaechlich, String was) {
  if (nameNormal(erwartet) != nameNormal(tatsaechlich)) {
    throw MoodleFehler('Abgebrochen, nichts geändert: $was heißt in Moodle „$tatsaechlich", nicht '
        '„$erwartet". Nummer und Namen prüfen (kurs_uebersicht).');
  }
}

// ---------------------------------------------------------------------------
// Formular abrufen, Dateien hochladen, absenden
// ---------------------------------------------------------------------------

class Formular {
  Formular(this.form, this.felder, this.aktion, this.seite, this.bereiche);
  final dom.Element form;
  final Felder felder;

  /// Wohin das Formular gesendet wird (Pfad samt Query).
  final String aktion;
  final Seitenangaben seite;

  /// Dateibereich -> Optionen des Dateimanagers (itemid, list …).
  final Map<String, Map<String, Object?>> bereiche;

  String? get sesskey => wertIn(felder, 'sesskey');
  int? get kurs => int.tryParse(wertIn(felder, 'course') ?? '') ?? seite.kurs;
  String? get modul => wertIn(felder, 'modulename') ?? wertIn(felder, 'qtype');
  String get name =>
      wertIn(felder, 'name') ?? wertIn(felder, 'name[value]') ?? wertIn(felder, 'title') ?? '';
  String? text(String feld) => wertIn(felder, '$feld[text]');
  Set<String> get editoren => {
        for (final e in felder)
          if (e.key.endsWith('[text]')) e.key.substring(0, e.key.length - '[text]'.length)
      };
}

Future<Formular> formularHolen(MoodleZugang moodle, String adresse) async {
  final r = await moodle.lesen(adresse);
  // Erst der Status: Eine Fehlerseite trägt eigene Formulare -- etwa den
  // Schalter „Bearbeiten einschalten". Ohne diese Prüfung wurde das erstbeste
  // davon abgeschickt, und die Meldung zeigte auf eine ganz andere Adresse
  // als die, die fehlte.
  if (r.status != 200) {
    throw MoodleFehler('Moodle liefert für $adresse HTTP ${r.status} statt der Seite. Gibt es das '
        'Ziel, und ist es für diesen Zweck die richtige Adresse?');
  }
  final form = hauptformular(html_parser.parse(r.text));
  if (form == null) {
    throw MoodleFehler('Moodle liefert kein Bearbeitungsformular (HTTP ${r.status}). Gibt es das '
        'Ziel, und darf diese Sitzung es bearbeiten?');
  }
  final felder = formularFelder(form);
  final ziel = r.adresse.resolve(form.attributes['action'] ?? r.adresse.path);
  final seite = Seitenangaben.aus(r.text);
  return Formular(form, felder, ziel.hasQuery ? '${ziel.path}?${ziel.query}' : ziel.path, seite, {
    for (final b in dateibereiche(r.text)) '${b['target'] ?? ''}'.replaceFirst('id_', ''): b
  });
}

/// Lädt eine Datei in einen Entwurfsbereich, wie der Dateiauswahl-Dialog es
/// tut (repository_ajax.php?action=upload). Die Werte stammen aus der
/// Formularseite: itemid aus `<feld>[itemid]` bzw. dem Dateimanager, ctx_id
/// aus M.cfg.contextid, repo_id aus der Liste der Dateiquellen -- die Quelle
/// vom Typ „upload". Deren Nummer ist je Moodle-Installation eine andere
/// (auf der Testinstanz 4), deshalb wird sie gelesen, nicht gesetzt.
Future<String> hochladen(
    MoodleZugang moodle, Formular f, String itemid, String pfad, String name, List<int> bytes) async {
  final kontext = f.seite.kontext, repo = f.seite.upload, sesskey = f.sesskey;
  if (kontext == null || repo == null || sesskey == null) {
    throw MoodleFehler('Im Formular fehlt sesskey, contextid oder der Upload-Dienst.');
  }
  final a = await moodle.hochladen('/repository/repository_ajax.php?action=upload', [
    MapEntry('itemid', itemid),
    MapEntry('ctx_id', kontext),
    MapEntry('sesskey', sesskey),
    MapEntry('repo_id', repo),
    MapEntry('savepath', pfad),
    MapEntry('title', name),
  ], Anhang('repo_upload_file', name, bytes, mimeTyp(name)));
  final j = jsonDecode(a.text) as Map<String, dynamic>;
  if (j['error'] != null) throw MoodleFehler('Upload von $name abgelehnt: ${j['error']}');
  final url = j['url'] as String?;
  if (url == null || dateiname(url) != name) {
    throw MoodleFehler('Upload von $name: unerwartete Antwort (${j.keys.join(", ")}).');
  }
  return url;
}

/// Entfernt eine Datei aus einem Entwurfsbereich. Gibt es sie nicht,
/// antwortet Moodle mit false -- das ist in Ordnung.
Future<void> _entwurfEntfernen(MoodleZugang moodle, Formular f, String itemid, String pfad, String name) =>
    moodle.senden('/repository/draftfiles_ajax.php?action=delete', [
      MapEntry('itemid', itemid),
      MapEntry('filepath', pfad),
      MapEntry('filename', name),
      MapEntry('sesskey', f.sesskey ?? ''),
    ]);

/// Setzt den Quelltext eines Editorfelds. Lädt eingebundene Dateien, die
/// noch nicht im Entwurfsbereich liegen oder in [ersetzen] stehen, hoch
/// (gleichnamige vorher entfernt) und ordnet alle Datei-Adressen über den
/// Namen zu -- die Adressen beim Lesen zeigen auf einen anderen
/// Entwurfsbereich. Gibt den gesetzten Quelltext zurück.
Future<String> feldSetzen(MoodleZugang moodle, Formular f, String feld, String html, String quelle,
    Set<String> ersetzen, {bool leer = false}) async {
  final itemid = wertIn(f.felder, '$feld[itemid]');
  if (itemid == null) throw MoodleFehler('Feld $feld hat keinen Entwurfsbereich.');
  final adresse = <String, String>{
    for (final m in attrMuster.allMatches(f.text(feld) ?? ''))
      if (m.group(3)!.contains('/draftfile.php/'))
        dateiname(m.group(3)!.replaceAll('&amp;', '&')): m.group(3)!.replaceAll('&amp;', '&')
  };
  final namen = eingebunden(html);
  for (final n in namen.where((n) => ersetzen.contains(n) || !adresse.containsKey(n))) {
    if (!leer) await _entwurfEntfernen(moodle, f, itemid, '/', n);
    adresse[n] = await hochladen(moodle, f, itemid, '/', n, await File(p.join(quelle, 'dateien', n)).readAsBytes());
  }
  final neu = html.replaceAllMapped(attrMuster, (m) {
    final wert = m.group(3)!.replaceAll('&amp;', '&');
    if (!_istDatei(wert)) return m.group(0)!;
    final ziel = adresse[dateiname(wert)];
    return ziel == null ? m.group(0)! : '${m.group(1)}=${m.group(2)}$ziel${m.group(2)}';
  });
  setze(f.felder, '$feld[text]', neu);
  return neu;
}

class BereichAenderung {
  BereichAenderung(this.feld, this.lokal, this.stand);
  final String feld;
  final Map<String, List<int>> lokal;
  final Map<String, List<int>> stand;

  List<String> get neu => [for (final k in lokal.keys) if (!stand.containsKey(k)) k];
  List<String> get geaendert =>
      [for (final k in lokal.keys) if (stand.containsKey(k) && !gleicheBytes(lokal[k]!, stand[k]!)) k];
  List<String> get weg => [for (final k in stand.keys) if (!lokal.containsKey(k)) k];
  bool get leer => neu.isEmpty && geaendert.isEmpty && weg.isEmpty;

  String beschreibung() => [
        if (neu.isNotEmpty) 'neu: ${neu.join(", ")}',
        if (geaendert.isNotEmpty) 'ersetzt: ${geaendert.join(", ")}',
        if (weg.isNotEmpty) 'entfernt: ${weg.join(", ")}',
      ].join('; ');
}

Future<void> bereichSetzen(MoodleZugang moodle, Formular f, BereichAenderung b) async {
  final opt = f.bereiche[b.feld];
  if (opt == null) {
    throw MoodleFehler('Dateibereich ${b.feld} gibt es im Formular nicht '
        '(vorhanden: ${f.bereiche.keys.join(", ")}).');
  }
  final itemid = '${opt['itemid']}';
  for (final k in [...b.weg, ...b.geaendert]) {
    final (pfad, name) = _pfadName(k);
    await _entwurfEntfernen(moodle, f, itemid, pfad, name);
  }
  for (final k in [...b.geaendert, ...b.neu]) {
    final (pfad, name) = _pfadName(k);
    await hochladen(moodle, f, itemid, pfad, name, b.lokal[k]!);
  }
}

/// Setzt den Namen, je nachdem, wie das Formular ihn führt: einfaches Feld
/// „name" oder „title" (Buchkapitel), oder -- im Abschnittsformular mancher
/// Kursformate -- „name[value]" mit Haken „name[customize]" bzw. dem Haken
/// „usedefaultname". Solange der Standardname angehakt ist, ignoriert Moodle
/// den eingetragenen Namen.
void nameSetzen(dom.Element form, Felder f, String name) {
  bool hat(String n) => form.querySelectorAll('[name]').any((e) => e.attributes['name'] == n);
  if (hat('name[value]')) {
    setze(f, 'name[value]', name);
    f.removeWhere((e) => e.key == 'name[customize]');
    f.add(const MapEntry('name[customize]', '1'));
  } else if (hat('name')) {
    setze(f, 'name', name);
  } else if (hat('title')) {
    setze(f, 'title', name);
  } else {
    throw MoodleFehler('Das Formular hat kein Namensfeld.');
  }
  f.removeWhere((e) => e.key == 'usedefaultname' && e.value != '0');
}

/// Sendet das Formular mit „Speichern" (bei Aktivitäten „Speichern und zum
/// Kurs", das es bei jedem Typ gibt). Erfolg ist eine Umleitung; sonst
/// sammelt die Meldung Moodles Hinweise aus dem Formular.
Future<Antwort> absenden(MoodleZugang moodle, Formular f, {List<String> knoepfe = const ['submitbutton2', 'submitbutton']}) async {
  final felder = [...f.felder];
  final knopf = knoepfe
      .map((n) => f.form.querySelectorAll('input, button').where((e) => e.attributes['name'] == n).firstOrNull)
      .whereType<dom.Element>()
      .firstOrNull;
  if (knopf != null) felder.add(MapEntry(knopf.attributes['name']!, knopf.attributes['value'] ?? ''));
  final antwort = await moodle.senden(f.aktion, felder);
  if (moodle.umleitungsziel(antwort) != null) return antwort;
  final d = html_parser.parse(antwort.text);
  // Jede Meldung mit dem Feld, zu dem sie gehört -- „Erforderlich" allein
  // sagt nicht, was fehlt.
  final meldungen = <String>{};
  for (final e in d.querySelectorAll('.invalid-feedback, .form-control-feedback, .error, .alert-danger')) {
    final text = e.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) continue;
    var zeile = e.parent;
    while (zeile != null && !zeile.classes.contains('fitem')) {
      zeile = zeile.parent;
    }
    final feld = zeile?.querySelector('.col-form-label')?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    final name = zeile?.querySelector('[name]')?.attributes['name'];
    meldungen.add(feld.isEmpty ? text : '„$feld"${name == null ? '' : ' ($name)'}: $text');
  }
  throw MoodleFehler(formularAbgelehnt(antwort.status, meldungen));
}

/// Die Meldung, wenn Moodle ein Formular nicht annimmt. Bei HTTP 403 ohne
/// Hinweise aus dem Formular kann es Moodle selbst gewesen sein (ein Recht
/// fehlt) oder ein Filter vor der Instanz, der Formulare mit bestimmten
/// Inhalten abweist -- auf der Testinstanz etwa srcdoc und <script> in
/// Abschnitt und Buchkapitel (elemente.dart). Die Antwort selbst sagt dann
/// nichts Brauchbares.
String formularAbgelehnt(int status, Iterable<String> meldungen) =>
    'Moodle hat das Formular nicht angenommen (HTTP $status)'
    '${meldungen.isNotEmpty ? ': ${meldungen.join(' | ')}' : status == 403 ? ': abgelehnt von Moodle, weil ein Recht '
        'fehlt, oder von einem Filter vor der Instanz, der Formulare mit bestimmten Inhalten abweist' : ''}';

// ---------------------------------------------------------------------------
// Rückleseprobe
// ---------------------------------------------------------------------------

class Probe {
  final List<String> abweichend = [];
  int gleich = 0;
  int gesamt = 0;

  void pruefe(bool ok, String was) {
    gesamt++;
    if (ok) {
      gleich++;
    } else {
      abweichend.add(was);
    }
  }

  bool get ok => abweichend.isEmpty;
  String get text => 'Rückleseprobe (verified: $ok): $gleich von $gesamt Prüfungen gleich'
      '${abweichend.isEmpty ? '' : ' -- ABWEICHEND: ${abweichend.join("; ")}'}';
}

Future<Probe> zuruecklesen(
  FormularGelesen g, {
  required Map<String, String> felder,
  required Map<String, List<int>> dateien,
  required Map<String, Map<String, List<int>>> bereiche,
  required List<Gesetzt> einstellungen,
  String? name,
}) async {
  final probe = Probe();
  if (name != null) probe.pruefe(nameNormal(g.name ?? '') == nameNormal(name), 'Name (gelesen „${g.name}")');
  for (final e in felder.entries) {
    final gelesen = g.felder.where((x) => x.feld == e.key).firstOrNull?.html ?? '';
    probe.pruefe(normalisiert(gelesen) == normalisiert(e.value), 'Quelltext ${e.key}');
  }
  for (final e in dateien.entries) {
    final f = File(p.join(g.ordner, 'dateien', e.key));
    probe.pruefe(await f.exists() && gleicheBytes(await f.readAsBytes(), e.value), 'Datei ${e.key}');
  }
  for (final b in bereiche.entries) {
    for (final d in b.value.entries) {
      final f = File(p.joinAll([g.ordner, 'bereiche', b.key, ...d.key.split('/').where((s) => s.isNotEmpty)]));
      probe.pruefe(await f.exists() && gleicheBytes(await f.readAsBytes(), d.value), 'bereiche/${b.key}${d.key}');
    }
    final gelesen = g.bereiche.where((x) => x.feld == b.key).firstOrNull;
    final zuviel = gelesen?.dateien.keys.where((k) => !b.value.containsKey(k)).toList() ?? const [];
    probe.pruefe(zuviel.isEmpty, 'bereiche/${b.key}: zusätzlich ${zuviel.join(", ")}');
  }
  for (final s in einstellungen) {
    final w = g.einstellungen.where((e) => e.schluessel == s.schluessel).firstOrNull?.wert ?? '';
    probe.pruefe(s.erwartet.every((t) => w.toLowerCase().contains(t.toLowerCase())),
        'Einstellung ${s.label} (erwartet ${s.nachher}, gelesen $w)');
  }
  return probe;
}

String wichtigeText(FormularGelesen g) {
  final zeigen = [...?wichtigeEinstellungen[g.modul], ...immerZeigen];
  return [
    for (final k in zeigen)
      for (final e in g.einstellungen.where((e) => e.schluessel == k)) '  ${e.label}: ${e.wert}'
  ].join('\n');
}

/// Liest den Inhalt eines Quellordners für ein neues Objekt und prüft, dass
/// jede eingebundene Datei da ist. Elementdateien bekommen dabei [kopf]
/// (elemente.dart).
({Map<String, String> felder, Map<String, Map<String, List<int>>> bereiche, Map<String, List<int>> dateien})
    quelleLesen(String? quelle, {required String kopf}) {
  if (quelle == null) return (felder: const {}, bereiche: const {}, dateien: const {});
  final felder = felderIn(quelle);
  formelnPruefen(felder);
  skripteImTextPruefen(felder);
  final fehlend = {
    for (final h in felder.values)
      for (final n in eingebunden(h))
        if (!File(p.join(quelle, 'dateien', n)).existsSync()) n
  };
  if (fehlend.isNotEmpty) {
    throw MoodleFehler('Im Quelltext eingebunden, aber nicht in dateien/: ${fehlend.join(", ")}');
  }
  elementeVorbereiten(quelle, felder, kopf);
  final dateien = {
    for (final h in felder.values)
      for (final n in eingebunden(h)) n: File(p.join(quelle, 'dateien', n)).readAsBytesSync()
  };
  final bereiche = bereicheIn(quelle);
  final elemente = {for (final h in felder.values) for (final r in elementRahmen(h)) r.datei};
  dateienPruefen({
    for (final e in dateien.entries)
      if (!elemente.contains(e.key)) 'dateien/${e.key}': e.value,
    for (final b in bereiche.entries)
      for (final d in b.value.entries) 'bereiche/${b.key}${d.key}': d.value,
  });
  return (felder: felder, bereiche: bereiche, dateien: dateien);
}

/// Füllt ein frisch geholtes Formular mit Einstellungen, Name, Editorfeldern
/// und Dateibereichen aus einem Quellordner. Einstellungen zuerst: Unbekanntes
/// bricht ab, bevor etwas hochgeladen ist.
Future<(Map<String, String>, List<Gesetzt>)> formularFuellen(MoodleZugang moodle, Formular f,
    {String? quelle,
    Map<String, String> felder = const {},
    Map<String, Map<String, List<int>>> bereiche = const {},
    Map<String, Object?> einstellungen = const {},
    String? name,
    String was = 'Formular'}) async {
  final gesetzt = einstellungenSetzen(f.form, f.felder, einstellungen);
  if (name != null) nameSetzen(f.form, f.felder, name);
  final geschrieben = <String, String>{};
  for (final e in felder.entries) {
    if (!f.editoren.contains(e.key)) {
      if (e.value.trim().isEmpty) continue;
      throw MoodleFehler('Feld ${e.key} gibt es in $was nicht (Felder: ${f.editoren.join(", ")}).');
    }
    geschrieben[e.key] = await feldSetzen(moodle, f, e.key, e.value, quelle!, const {}, leer: true);
  }
  for (final b in bereiche.entries) {
    await bereichSetzen(moodle, f, BereichAenderung(b.key, b.value, const {}));
  }
  return (geschrieben, gesetzt);
}

// ---------------------------------------------------------------------------
// aktivitaet_anlegen
// ---------------------------------------------------------------------------

/// Die neue Aktivität aus der Kursstruktur: cmid und Name, wie Moodle sie
/// jetzt führt.
Future<(int, String)> _neueAktivitaet(MoodleZugang moodle, int kurs, String typ, Set<int> vorher) async {
  final neu = (await kursLesen(moodle, kurs)).nachCmid.values
      .where((c) => !vorher.contains(c.cmid) && c.modul == typ)
      .toList();
  if (neu.length != 1) {
    throw MoodleFehler('Gespeichert, aber die neue Aktivität ist nicht eindeutig zu finden '
        '(${neu.length} neue ${typName(typ)}-Einträge in Kurs $kurs). Bitte mit kurs_uebersicht prüfen.');
  }
  return (neu.single.cmid, neu.single.name);
}

/// Dasselbe für eine Fragensammlung -- über die Sammlungsliste, weil die
/// Kursstruktur sie nicht führt. Ohne diesen Weg meldete das Anlegen einen
/// Fehler, obwohl die Sammlung entstanden war.
Future<(int, String)> _neueSammlung(MoodleZugang moodle, int kurs, Set<int> vorher) async {
  final neu = (await fragensammlungenLesen(moodle, kurs)).where((s) => !vorher.contains(s.cmid)).toList();
  if (neu.length != 1) {
    throw MoodleFehler('Gespeichert, aber die neue Fragensammlung ist nicht eindeutig zu finden '
        '(${neu.length} neue Einträge in Kurs $kurs). Bitte mit fragensammlungen prüfen.');
  }
  return (neu.single.cmid, neu.single.name);
}

Future<String> aktivitaetAnlegen(
  MoodleZugang moodle,
  Freigaben freigaben, {
  required int kurs,
  required int abschnittId,
  required String typ,
  required String name,
  required String arbeitsordner,
  String? ordner,
  bool sichtbar = false,
  Map<String, Object?> einstellungen = const {},
}) async {
  if (!MoodleZugang.schreibbareModule.contains(typ)) {
    throw MoodleFehler('Typ „$typ" kann die App nicht anlegen. Möglich: '
        '${MoodleZugang.schreibbareModule.map((t) => '$t (${typName(t)})').join(", ")}.');
  }
  final quelle = ordner == null ? null : imArbeitsordner(ordner, arbeitsordner);
  final inhalt = quelleLesen(quelle, kopf: elementKopfFuer(moodle));
  final pflicht = pflichtfeld[typ];
  if (pflicht != null && (inhalt.felder[pflicht] ?? '').trim().isEmpty) {
    throw MoodleFehler('Im Ordner fehlt $pflicht.html -- der Inhalt der ${typName(typ)}.');
  }

  final vorherStruktur = await kursLesen(moodle, kurs);
  final abschnitt = vorherStruktur.nachId[abschnittId];
  if (abschnitt == null) {
    throw MoodleFehler('Abschnitt id $abschnittId gibt es in Kurs $kurs nicht (kurs_uebersicht).');
  }
  // Eine Fragensammlung ist eine Aktivität, aber keine Kursseite: Moodle nimmt
  // sie nur im allgemeinen Abschnitt an (gemessen: add=qbank&section=0 -> 200,
  // jeder andere Abschnitt -> 404), und sie steht nicht in der Kursstruktur.
  // Daher die beiden Sonderwege unten -- Abschnitt 0 und Zurücklesen über die
  // Sammlungsliste.
  final istSammlung = typ == 'qbank';
  final wo = istSammlung
      ? '${await kursBezeichnung(moodle, kurs)}, allgemeiner Abschnitt'
      : '${await kursBezeichnung(moodle, kurs)}, Abschnitt „${abschnitt.titel}"';

  // Sichtbar anlegen fragt ab „mittel", verborgen anlegen erst bei „alle":
  // Verborgenes sieht niemand außer der Lehrkraft (A3).
  final ja = await freigaben.anfragen(FreigabeAnfrage(
    titel: sichtbar ? 'Sichtbar anlegen?' : 'Verborgen anlegen?',
    punkte: [
      '${typName(typ)} „$name" in $wo',
      sichtbar
          ? 'Für Lernende SOFORT SICHTBAR (sonst legt die App verborgen an).'
          : 'Für Lernende verborgen; sichtbar wird es erst mit sichtbarkeit_setzen.',
      for (final e in inhalt.felder.entries)
        if (e.value.trim().isNotEmpty) '${e.key}: ${e.value.length} Zeichen',
      for (final e in einstellungen.entries) 'Einstellung ${e.key}: ${e.value}',
    ],
    vergleich: const [],
    knopf: sichtbar ? 'Sichtbar anlegen' : 'Anlegen',
    ohneEntscheidung: 'wird nichts angelegt',
    ab: sichtbar ? Bestaetigungen.mittel : Bestaetigungen.alle,
  ));
  if (!ja) {
    return 'Nicht angelegt: ${sichtbar ? 'Sichtbares Anlegen' : 'Das Anlegen'} wurde in der App '
        'abgelehnt oder nicht innerhalb von ${freigaben.frist.inMinutes} Minuten freigegeben.'
        '${sichtbar ? ' Verborgen anlegen braucht nur bei Bestätigungen „alle" eine Freigabe.' : ''}';
  }

  final vorher = istSammlung
      ? (await fragensammlungenLesen(moodle, kurs)).map((s) => s.cmid).toSet()
      : vorherStruktur.nachCmid.keys.toSet();

  Future<(Map<String, String>, List<Gesetzt>)> versuch() async {
    final f = await formularHolen(
        moodle,
        '/course/modedit.php?add=$typ&type=&course=$kurs'
        '&section=${istSammlung ? 0 : abschnitt.nummer}&return=0&sr=0');
    final (geschrieben, gesetzt) = await formularFuellen(moodle, f,
        quelle: quelle,
        felder: inhalt.felder,
        bereiche: inhalt.bereiche,
        einstellungen: einstellungen,
        name: f.form.querySelector('input[name="name"]') != null ? name : null,
        was: 'einer ${typName(typ)}');
    setze(f.felder, 'visible', sichtbar ? '1' : '0');
    await absenden(moodle, f);
    return (geschrieben, gesetzt);
  }

  (Map<String, String>, List<Gesetzt>) ergebnis;
  try {
    ergebnis = await versuch();
  } on SitzungAbgelaufen {
    // Einmal von vorn: frisches Formular, neuer Entwurfsbereich, neuer sesskey.
    ergebnis = await versuch();
  }
  final (geschrieben, gesetzt) = ergebnis;

  // Die neue cmid: was vorher nicht da war. Das Textfeld hat keine eigene
  // Seite, auf die Moodle umleiten könnte -- so geht es für alle Typen.
  final (int cmid, String angelegt) = istSammlung
      ? await _neueSammlung(moodle, kurs, vorher)
      : await _neueAktivitaet(moodle, kurs, typ, vorher);
  if (!sichtbar) moodle.selbstAngelegt.add(cmid);

  final g = await formularLesen(moodle, Formularziel.aktivitaet(cmid), arbeitsordner);
  final probe = await zuruecklesen(g,
      felder: geschrieben, dateien: inhalt.dateien, bereiche: inhalt.bereiche, einstellungen: gesetzt);
  return [
    'Angelegt: ${typName(typ)} „$angelegt" in $wo, cmid $cmid, '
        '${sichtbar ? "SICHTBAR" : "verborgen"}.',
    if (istSammlung && abschnitt.nummer != 0)
      'Hinweis: Moodle legt Fragensammlungen nur im allgemeinen Abschnitt an; '
          'der gewünschte Abschnitt „${abschnitt.titel}" wurde nicht verwendet.',
    if (geschrieben.isNotEmpty || inhalt.dateien.isNotEmpty || inhalt.bereiche.isNotEmpty)
      'Geschrieben: ${[
        if (geschrieben.isNotEmpty) geschrieben.keys.map((k) => '$k.html').join(", "),
        if (inhalt.dateien.isNotEmpty) 'Dateien: ${inhalt.dateien.keys.join(", ")}',
        if (inhalt.bereiche.isNotEmpty)
          'Dateibereiche: ${inhalt.bereiche.entries.map((b) => '${b.key} (${b.value.length})').join(", ")}',
      ].join('; ')}.',
    if (gesetzt.isNotEmpty) 'Einstellungen: ${gesetzt.map((s) => '${s.label}: ${s.nachher}').join("; ")}.',
    probe.text,
    'Einstellungen jetzt:',
    wichtigeText(g),
    'Zurückgelesen nach: ${g.ordner}',
  ].join('\n');
}

// ---------------------------------------------------------------------------
// aendern: jedes gelesene Formular zurückschreiben
// ---------------------------------------------------------------------------

/// Prüft ein frisch geholtes Formular gegen den Stand beim Lesen. Wirft,
/// wenn Moodle seither geändert wurde -- dann wird nichts überschrieben.
void _pruefeStand(Formular f, Formularziel ziel, String stand, Map<String, String> standFelder,
    Iterable<String> bereiche, Iterable<String> einstellungen) {
  if (ziel.art == Zielart.aktivitaet && !MoodleZugang.schreibbareModule.contains(f.modul)) {
    throw MoodleFehler('Ändern geht bisher für ${MoodleZugang.schreibbareModule.map(typName).join(", ")}; '
        '${ziel.bezeichnung} ist ${typName(f.modul)}.');
  }
  const hinweis = 'Nichts überschrieben. Erst neu lesen und die Änderung auf dem neuen Stand aufbauen.';
  for (final e in standFelder.entries) {
    if (normalisiert(f.text(e.key) ?? '') != normalisiert(e.value)) {
      throw MoodleFehler('${e.key} wurde in Moodle seit dem Lesen geändert. $hinweis');
    }
  }
  if (bereiche.isNotEmpty) {
    final datei = File(p.join(stand, 'dateibereiche.json'));
    final alt = datei.existsSync() ? jsonDecode(datei.readAsStringSync()) as List : const [];
    // Name, Größe und Änderungszeit: Die Größe allein ließe eine Änderung
    // durch, die gleich lang ist -- bei einer Textdatei keine Seltenheit.
    // „datemodified" stammt von der Datei, nicht vom Entwurfsbereich, und
    // bleibt über mehrere Formularaufrufe gleich (gemessen 05.10.2026).
    String liste(Object? l) => [
          for (final e in (l as List?) ?? const [])
            if (e is Map) '${e['filepath']}${e['filename']}:${e['size']}:${e['datemodified']}'
        ].join('|');
    for (final b in bereiche) {
      final vorher = alt.whereType<Map>().where((x) => '${x['target']}' == 'id_$b').firstOrNull;
      if (liste(vorher?['list']) != liste(f.bereiche[b]?['list'])) {
        throw MoodleFehler('Dateibereich $b wurde in Moodle seit dem Lesen geändert. $hinweis');
      }
    }
  }
  if (einstellungen.isNotEmpty) {
    final datei = File(p.join(stand, 'einstellungen.json'));
    final alt = {
      if (datei.existsSync())
        for (final e in jsonDecode(datei.readAsStringSync()) as List) '${e['schluessel']}': '${e['wert']}'
    };
    final jetzt = {for (final e in einstellungenLesen(f.form)) e.schluessel: e.wert};
    for (final k in einstellungen) {
      if (alt.containsKey(k) && alt[k] != jetzt[k]) {
        throw MoodleFehler('Einstellung $k wurde in Moodle seit dem Lesen geändert '
            '(„${alt[k]}" -> „${jetzt[k]}"). $hinweis');
      }
    }
  }
}

String _was(Formularziel z, Formular f) => switch (z.art) {
      Zielart.aktivitaet => typName(f.modul),
      Zielart.abschnitt => 'Abschnitt',
      Zielart.buchkapitel => 'Buchkapitel',
      Zielart.frage => 'Frage (${f.modul ?? "?"})',
    };

/// Eine vorbereitete Änderung an einem gelesenen Ordner: gegen den Stand in
/// Moodle geprüft, mit allem, was die Freigabe zeigt. Geschrieben ist noch
/// nichts -- so gehen eine Änderung (aendern) und mehrere mit einer Freigabe
/// (aendernMehrere) denselben Weg.
class _Aenderung {
  _Aenderung({
    required this.ordner,
    required this.quelle,
    required this.ziel,
    required this.lokal,
    required this.zuSchreiben,
    required this.neu,
    required this.geaendert,
    required this.dateien,
    required this.bereiche,
    required this.einstellungen,
    required this.vorab,
    required this.wo,
    required this.einzelheiten,
    required this.vergleich,
  });

  /// Wie der Aufrufer den Ordner genannt hat.
  final String ordner;
  final String quelle;
  final Formularziel ziel;
  final Map<String, String> lokal;
  final List<String> zuSchreiben;
  final Set<String> neu, geaendert;
  final Map<String, List<int>> dateien;
  final List<BereichAenderung> bereiche;
  final Map<String, Object?> einstellungen;
  final Formular vorab;

  /// ", Kurs 12 „…"" oder leer.
  final String wo;

  /// Je geschriebenes Feld, Datei, Bereich und Einstellung eine Zeile.
  final List<String> einzelheiten;
  final List<Zeile> vergleich;

  String get stand => p.join(quelle, '.stand');

  /// Die Aktivität, die sich ändert -- bei einem Buchkapitel das Buch; null
  /// bei Abschnitt und Frage. Danach richtet sich, ob die Änderung noch der
  /// Arbeitssitzung gehört ([fuellenAb]).
  int? get cmid => switch (ziel.art) {
        Zielart.aktivitaet => ziel.id,
        Zielart.buchkapitel => ziel.cmid,
        Zielart.abschnitt || Zielart.frage => null,
      };

  String kopf({bool mitKurs = true}) =>
      '${_was(ziel, vorab)} „${vorab.name}" (${ziel.bezeichnung}${mitKurs ? wo : ''})';
}

/// Prüft einen Ordner gegen den Stand in Moodle und baut, was die Freigabe
/// zeigt. null: nichts geändert.
Future<_Aenderung?> _vorbereiten(
  MoodleZugang moodle, {
  required String ordner,
  required String arbeitsordner,
  Map<String, Object?> einstellungen = const {},
  bool neuSpeichern = false,
}) async {
  final quelle = imArbeitsordner(ordner, arbeitsordner);
  final ziel = Formularziel.ausOrdner(quelle);
  final stand = p.join(quelle, '.stand');
  final lokal = felderIn(quelle);
  final alt = felderIn(stand);
  final unbekannt = lokal.keys.where((k) => !alt.containsKey(k)).toList();
  if (unbekannt.isNotEmpty) {
    throw MoodleFehler('${unbekannt.map((k) => '$k.html').join(", ")}: kein Editorfeld dieses Formulars '
        '(vorhanden: ${alt.keys.join(", ")}).');
  }

  // Eingebundene Dateien einordnen.
  final namen = {for (final h in lokal.values) ...eingebunden(h)};
  final fehlend = [for (final n in namen) if (!File(p.join(quelle, 'dateien', n)).existsSync()) n];
  if (fehlend.isNotEmpty) {
    throw MoodleFehler('Im Quelltext eingebunden, aber nicht in dateien/: ${fehlend.join(", ")}');
  }
  // Kein neuer Code im Text, und Elemente nur im abgeschotteten Rahmen, mit
  // dem Kopf der App -- eingesetzt, bevor verglichen wird (elemente.dart).
  // In einer Frage gibt es keine Elemente; dort zeichnet STACK.
  final istFrage = ziel.art == Zielart.frage;
  skripteImTextPruefen(lokal, alt: alt, elementeErlaubt: !istFrage);
  if (!istFrage) elementeVorbereiten(quelle, lokal, elementKopfFuer(moodle), stand: stand);
  final neu = <String>{}, geaendert = <String>{};
  final dateien = <String, List<int>>{};
  for (final n in namen) {
    final b = await File(p.join(quelle, 'dateien', n)).readAsBytes();
    dateien[n] = b;
    final s = File(p.join(stand, 'dateien', n));
    if (!await s.exists()) {
      neu.add(n);
    } else if (!gleicheBytes(b, await s.readAsBytes())) {
      geaendert.add(n);
    }
  }
  // Geschrieben wird ein Feld, wenn sein Text sich geändert hat oder eine
  // darin eingebundene Datei neu oder geändert ist.
  final zuSchreiben = [
    for (final e in lokal.entries)
      if (normalisiert(alt[e.key]!) != normalisiert(e.value) ||
          eingebunden(e.value).any((n) => neu.contains(n) || geaendert.contains(n)))
        e.key
  ];
  // Ein Feld, das geschrieben wird, darf keinen Formelfehler haben -- auch
  // keinen, der schon in Moodle stand (formeln.dart).
  formelnPruefen({for (final k in zuSchreiben) k: lokal[k]!});
  // In einer Frage wirken STACK-Blöcke; nichts davon darf von außen laden
  // (stack_skripte.dart).
  if (istFrage) stackSkriptePruefen({for (final k in zuSchreiben) k: lokal[k]!});
  final nichtMehr = {for (final h in alt.values) ...eingebunden(h)}.difference(namen).toList()..sort();

  final lokaleBereiche = bereicheIn(quelle);
  final standBereiche = bereicheIn(stand);
  final bereiche = [
    for (final b in {...lokaleBereiche.keys, ...standBereiche.keys})
      BereichAenderung(b, lokaleBereiche[b] ?? const {}, standBereiche[b] ?? const {})
  ].where((b) => !b.leer).toList();
  // Kein Code in einer neuen oder geänderten Datei, die kein Element ist;
  // was schon in Moodle stand, bleibt (elemente.dart).
  final elemente =
      istFrage ? const <String>{} : {for (final h in lokal.values) for (final r in elementRahmen(h)) r.datei};
  dateienPruefen({
    for (final n in [...neu, ...geaendert])
      if (!elemente.contains(n)) 'dateien/$n': dateien[n]!,
    for (final b in bereiche)
      for (final k in [...b.neu, ...b.geaendert]) 'bereiche/${b.feld}$k': b.lokal[k]!,
  });

  if (zuSchreiben.isEmpty && bereiche.isEmpty && einstellungen.isEmpty && !neuSpeichern) return null;

  // Prüfen, bevor gefragt wird -- und die Einstellungen probehalber setzen:
  // Unbekanntes fällt hier auf, nicht erst nach der Freigabe.
  final vorab = await formularHolen(moodle, ziel.adresse);
  _pruefeStand(vorab, ziel, stand, alt, bereiche.map((b) => b.feld), einstellungen.keys);
  final probeSetzen = einstellungenSetzen(vorab.form, [...vorab.felder], einstellungen);
  final kurs = vorab.kurs;
  final wo = kurs == null ? '' : ', ${await kursBezeichnung(moodle, kurs)}';

  final vergleich = <Zeile>[];
  final einzelheiten = <String>[];
  for (final k in zuSchreiben) {
    final v = zeilenVergleich(normalisiert(alt[k]!), normalisiert(lokal[k]!));
    einzelheiten.add('$k: ${v.gleich ? "Text unverändert" : "${v.neu} Zeile(n) neu, ${v.weg} Zeile(n) weg"}');
    if (!v.gleich) {
      vergleich
        ..add(Zeile(ZeilenArt.ausgelassen, '──── $k ────'))
        ..addAll(v.zeilen);
    }
  }
  if (neu.isNotEmpty) einzelheiten.add('Neue Dateien: ${neu.join(", ")}');
  if (geaendert.isNotEmpty) einzelheiten.add('Geänderte Dateien (werden ersetzt): ${geaendert.join(", ")}');
  // Ein Element ist Code, der bei jedem Betrachter läuft: Die Freigabe zeigt
  // seine Zeilen wie die einer Seite, nicht nur den Namen.
  for (final n in [...geaendert, ...neu].where(istElementdatei)) {
    final s = File(p.join(stand, 'dateien', n));
    final vorher = s.existsSync() ? alsText(await s.readAsBytes()) : '';
    final jetzt = alsText(dateien[n]!);
    if (vorher == null || jetzt == null) continue;
    final v = zeilenVergleich(vorher, jetzt);
    if (v.gleich) continue;
    vergleich
      ..add(Zeile(ZeilenArt.ausgelassen, '──── dateien/$n ────'))
      ..addAll(v.zeilen);
  }
  if (nichtMehr.isNotEmpty) {
    einzelheiten.add('Nicht mehr eingebunden (bleiben in Moodle gespeichert): ${nichtMehr.join(", ")}');
  }
  for (final b in bereiche) {
    einzelheiten.add('Dateibereich ${b.feld}: ${b.beschreibung()}');
    // Bei einer Textdatei zeigt die Freigabe auch, welche Zeilen sich ändern.
    // „ersetzt: CLAUDE.md" allein sagt der Lehrkraft nicht, was sie freigibt;
    // der Zeilenvergleich ist bei einer Seite die eigentliche Kontrolle, und
    // eine Datei ist nicht weniger wert. Bilder, Schriften und große Dateien
    // bleiben bei Name und Größe.
    for (final n in [...b.geaendert, ...b.neu]) {
      final jetzt = alsText(b.lokal[n]!);
      final vorher = b.stand.containsKey(n) ? alsText(b.stand[n]!) : '';
      if (jetzt == null || vorher == null) continue;
      final v = zeilenVergleich(vorher, jetzt);
      if (v.gleich) continue;
      vergleich
        ..add(Zeile(ZeilenArt.ausgelassen, '──── ${b.feld}$n ────'))
        ..addAll(v.zeilen);
    }
  }
  for (final s in probeSetzen) {
    einzelheiten.add('Einstellung $s');
  }
  if (neuSpeichern && zuSchreiben.isEmpty && bereiche.isEmpty && probeSetzen.isEmpty) {
    einzelheiten.add('Unverändert neu speichern (Moodle prüft dabei, was es nur im Formular prüft).');
  }
  if (ziel.art == Zielart.frage) einzelheiten.add('Moodle legt dafür eine neue Version der Frage an.');

  return _Aenderung(
    ordner: ordner,
    quelle: quelle,
    ziel: ziel,
    lokal: lokal,
    zuSchreiben: zuSchreiben,
    neu: neu,
    geaendert: geaendert,
    dateien: dateien,
    bereiche: bereiche,
    einstellungen: einstellungen,
    vorab: vorab,
    wo: wo,
    einzelheiten: einzelheiten,
    vergleich: vergleich,
  );
}

/// Schreibt eine freigegebene Änderung -- mit frischem Formular, denn die
/// Freigabe kann gedauert haben; der Stand wird dabei noch einmal geprüft --
/// und liest zurück. Gibt den Bericht und das Ergebnis der Rückleseprobe.
Future<(String, bool)> _schreiben(MoodleZugang moodle, _Aenderung a, String arbeitsordner) =>
    ordnerSperre(ordnerSchluessel(a.ziel, arbeitsordner),
      () => _schreibenOhneSperre(moodle, a, arbeitsordner));

Future<(String, bool)> _schreibenOhneSperre(MoodleZugang moodle, _Aenderung a, String arbeitsordner) async {
  final alt = felderIn(a.stand);
  Future<(Map<String, String>, List<Gesetzt>, Antwort)> schreiben() async {
    final f = await formularHolen(moodle, a.ziel.adresse);
    _pruefeStand(f, a.ziel, a.stand, alt, a.bereiche.map((b) => b.feld), a.einstellungen.keys);
    final gesetzt = einstellungenSetzen(f.form, f.felder, a.einstellungen);
    final geschrieben = <String, String>{};
    for (final k in a.zuSchreiben) {
      geschrieben[k] = await feldSetzen(moodle, f, k, a.lokal[k]!, a.quelle, {...a.neu, ...a.geaendert});
    }
    for (final b in a.bereiche) {
      await bereichSetzen(moodle, f, b);
    }
    final antwort = await absenden(moodle, f);
    return (geschrieben, gesetzt, antwort);
  }

  (Map<String, String>, List<Gesetzt>, Antwort) ergebnis;
  try {
    ergebnis = await schreiben();
  } on SitzungAbgelaufen {
    ergebnis = await schreiben();
  }
  final (geschrieben, gesetzt, antwort) = ergebnis;

  // Zurücklesen. Eine Frage hat danach eine neue Version mit neuer id --
  // Moodle leitet auf die Fragenliste; die neue id steht nicht in der
  // Umleitung. Fragen liest frage_lesen über die Sachnummer neu.
  var zurueck = a.ziel;
  if (a.ziel.art == Zielart.frage) {
    final neueId = int.tryParse(moodle.umleitungsziel(antwort)?.queryParameters['lastchanged'] ?? '');
    if (neueId != null) zurueck = Formularziel.frage(a.ziel.cmid!, neueId);
  }
  final g = await formularLesenOhneSperre(moodle, zurueck, arbeitsordner);
  final probe = await zuruecklesen(g,
      felder: geschrieben,
      dateien: a.dateien,
      bereiche: {for (final b in a.bereiche) b.feld: b.lokal},
      einstellungen: gesetzt);
  final text = [
    'Gespeichert: ${_was(a.ziel, a.vorab)} „${g.name}" (${zurueck.bezeichnung}${a.wo}).',
    if (a.zuSchreiben.isNotEmpty) 'Felder: ${a.zuSchreiben.join(", ")}.',
    if (a.neu.isNotEmpty || a.geaendert.isNotEmpty) 'Dateien ersetzt/neu: ${[...a.geaendert, ...a.neu].join(", ")}.',
    for (final b in a.bereiche) 'Dateibereich ${b.feld}: ${b.beschreibung()}.',
    if (gesetzt.isNotEmpty) 'Einstellungen: ${gesetzt.join("; ")}.',
    probe.text,
    'Der Ordner ${g.ordner} zeigt jetzt den neuen Stand.',
  ].join('\n');
  return (text, probe.ok);
}

/// Schreibt einen gelesenen und bearbeiteten Ordner zurück. [neuSpeichern]:
/// auch ohne Änderung einmal über das Formular speichern (CodeRunner prüft
/// seine Musterlösung nur dort).
/// Die Sperre des Ordners umfasst das Prüfen des Stands (.stand) bis zum Schreiben
/// (Befund 6): Parallel gelesen oder geschrieben wird dieser Ordner dann nicht.
/// Sie gilt auch während der Freigabe; das wartet auf die Lehrkraft (höchstens die Frist).
Future<String> aendern(
  MoodleZugang moodle,
  Freigaben freigaben, {
  required String ordner,
  required String arbeitsordner,
  Map<String, Object?> einstellungen = const {},
  bool neuSpeichern = false,
}) {
  final quelle = imArbeitsordner(ordner, arbeitsordner);
  return ordnerSperre(ordnerSchluessel(Formularziel.ausOrdner(quelle), arbeitsordner), () => _aendernOhneSperre(
      moodle, freigaben,
      ordner: ordner, arbeitsordner: arbeitsordner, einstellungen: einstellungen, neuSpeichern: neuSpeichern));
}

Future<String> _aendernOhneSperre(
  MoodleZugang moodle,
  Freigaben freigaben, {
  required String ordner,
  required String arbeitsordner,
  Map<String, Object?> einstellungen = const {},
  bool neuSpeichern = false,
}) async {
  final a = await _vorbereiten(moodle,
      ordner: ordner, arbeitsordner: arbeitsordner, einstellungen: einstellungen, neuSpeichern: neuSpeichern);
  if (a == null) return 'Keine Änderung gegenüber dem Stand beim Lesen -- nichts geschrieben.';

  final ja = await freigaben.anfragen(FreigabeAnfrage(
      titel: 'Änderung speichern?',
      punkte: [a.kopf(), ...a.einzelheiten, 'Alles andere bleibt, wie es ist.'],
      vergleich: a.vergleich,
      ab: await fuellenAb(moodle, a.vorab.kurs, [a.cmid])));
  if (!ja) {
    return 'Nicht gespeichert: Die Änderung wurde in der App abgelehnt oder nicht innerhalb von '
        '${freigaben.frist.inMinutes} Minuten freigegeben. Der Ordner ist unverändert.';
  }
  return (await _schreibenOhneSperre(moodle, a, arbeitsordner)).$1;
}

/// Schreibt mehrere gelesene Ordner eines Abschnitts mit EINER Freigabe
/// zurück. Gebraucht, wo eine Arbeit sich über Seiten zieht, die
/// zusammengehören: die Links einer Lernsituation, die sich erst setzen
/// lassen, wenn jede Aktivität ihre Nummer hat; das Nachziehen der Verweise
/// nach einem Umbenennen oder Duplizieren. Einzeln wären das so viele
/// Freigaben wie Seiten, jede mit wenigen eingefügten Links.
///
/// Die Grenze ist ein Abschnitt samt Unterabschnitten -- eine Lernsituation.
/// Die Freigabe zeigt jede Seite mit Namen und Zeilenvergleich. Nur Inhalte:
/// Einstellungen gehen einzeln über aendern, ebenso Fragen, bei denen jede
/// Änderung eine neue Version ist.
///
/// Jeder Stand wird vor der Freigabe gegen Moodle geprüft; stimmt einer
/// nicht, wird nichts gespeichert. Danach wird der Reihe nach geschrieben und
/// zurückgelesen. Beim ersten Fehler oder verified: false hört es auf, und
/// die Antwort sagt genau, was gespeichert ist und was nicht -- ein halb
/// gespeicherter Stapel, den niemand bemerkt, wäre schlimmer als ein Abbruch.
///
/// [titel], [vorspann] und [anmerkungen] (Ordner -> Zeile) lassen einen
/// Aufrufer wie links_setzen in der Freigabe sagen, was er tut. [knapp]: Ist
/// alles gespeichert und zurückgelesen, genügt eine Zeile -- der Aufrufer hat
/// je Seite schon gesagt, was sich ändert. Bei einem Abbruch bleibt der
/// ausführliche Bericht.
Future<String> aendernMehrere(
  MoodleZugang moodle,
  Freigaben freigaben, {
  required List<String> ordner,
  required String arbeitsordner,
  String? titel,
  List<String> vorspann = const [],
  Map<String, String> anmerkungen = const {},
  bool knapp = false,
}) async {
  if (ordner.isEmpty) throw MoodleFehler('Keine Ordner angegeben.');
  const nichts = 'Nichts gespeichert.';
  final alle = <_Aenderung>[];
  final unveraendert = <String>[];
  final ziele = <String>{};
  for (final o in ordner) {
    final ziel = Formularziel.ausOrdner(imArbeitsordner(o, arbeitsordner));
    if (ziel.art == Zielart.frage) {
      throw MoodleFehler('$o ist eine Frage; jede Änderung einer Frage ist eine neue Version. '
          'Fragen einzeln mit aendern. $nichts');
    }
    if (!ziele.add(ziel.adresse)) throw MoodleFehler('$o steht doppelt in der Liste. $nichts');
    final _Aenderung? a;
    try {
      a = await _vorbereiten(moodle, ordner: o, arbeitsordner: arbeitsordner);
    } on MoodleFehler catch (x) {
      throw MoodleFehler('$o: ${x.meldung} $nichts');
    }
    if (a == null) {
      unveraendert.add(o);
    } else {
      alle.add(a);
    }
  }
  if (alle.isEmpty) return 'Keine Änderung gegenüber dem Stand beim Lesen -- nichts geschrieben.';

  // Ein Kurs, ein Abschnitt. Ein Unterabschnitt gehört zu seinem Abschnitt.
  final kurse = {for (final a in alle) a.vorab.kurs};
  if (kurse.length != 1 || kurse.single == null) {
    throw MoodleFehler('Die Ordner gehören nicht alle zu einem Kurs. $nichts');
  }
  final k = await kursLesen(moodle, kurse.single!);
  int? oben(int? id) {
    var s = k.nachId[id];
    while (s?.elternId != null) {
      s = k.nachId[s!.elternId];
    }
    return s?.id;
  }

  int? abschnittVon(_Aenderung a) => switch (a.ziel.art) {
        Zielart.aktivitaet => oben(k.nachCmid[a.ziel.id]?.abschnittId),
        Zielart.abschnitt => oben(a.ziel.id),
        Zielart.buchkapitel => oben(k.nachCmid[a.ziel.cmid]?.abschnittId),
        Zielart.frage => null,
      };
  final abschnitte = {for (final a in alle) abschnittVon(a)};
  if (abschnitte.length != 1 || abschnitte.single == null) {
    final welche = [for (final a in alle) '${a.ordner}: ${k.nachId[abschnittVon(a)]?.titel ?? "?"}'];
    throw MoodleFehler('Die Ordner liegen nicht in einem Abschnitt (${welche.join("; ")}). Eine '
        'Sammelfreigabe gilt für einen Abschnitt samt Unterabschnitten; anderes einzeln mit aendern. '
        '$nichts');
  }
  final abschnitt = k.nachId[abschnitte.single]!;

  final ja = await freigaben.anfragen(FreigabeAnfrage(
    ab: await fuellenAb(moodle, kurse.single, [for (final a in alle) a.cmid]),
    titel: titel ?? '${alle.length} Änderungen speichern?',
    knopf: 'Alle speichern',
    punkte: [
      '${alle.length} Seiten in Abschnitt „${abschnitt.titel}"${alle.first.wo}:',
      ...vorspann,
      for (final a in alle)
        '${a.kopf(mitKurs: false)}: ${[if (anmerkungen[a.ordner] != null) anmerkungen[a.ordner]!, ...a.einzelheiten].join("; ")}',
      if (unveraendert.isNotEmpty) 'Unverändert, wird nicht gespeichert: ${unveraendert.join(", ")}',
      'Alles andere bleibt, wie es ist.',
    ],
    vergleich: [
      for (final a in alle) ...[
        Zeile(ZeilenArt.ausgelassen, '════ ${a.kopf(mitKurs: false)} ════'),
        ...a.vergleich,
      ],
    ],
  ));
  if (!ja) {
    return 'Nicht gespeichert: Die Änderungen wurden in der App abgelehnt oder nicht innerhalb von '
        '${freigaben.frist.inMinutes} Minuten freigegeben. Die Ordner sind unverändert.';
  }

  final berichte = <String>[];
  for (var i = 0; i < alle.length; i++) {
    final a = alle[i];
    String? abbruch;
    try {
      final (text, ok) = await _schreiben(moodle, a, arbeitsordner);
      berichte.add(text);
      if (!ok) abbruch = '${a.kopf(mitKurs: false)} ist gespeichert, aber die Rückleseprobe weicht ab (oben).';
    } on MoodleFehler catch (x) {
      abbruch = '${a.kopf(mitKurs: false)}: ${x.meldung}';
    } catch (x, st) {
      abbruch = '${a.kopf(mitKurs: false)}: unerwarteter Fehler ${fehlerBeschreibung(x, st)}';
    }
    if (abbruch != null) {
      final rest = [for (final r in alle.skip(i + 1)) r.kopf(mitKurs: false)];
      return [
        'ABGEBROCHEN nach ${berichte.length} von ${alle.length} Seiten in Abschnitt „${abschnitt.titel}".',
        ...berichte,
        abbruch,
        if (rest.isNotEmpty) 'Nicht geschrieben: ${rest.join("; ")}. Ihre Ordner sind unverändert.',
      ].join('\n\n');
    }
  }
  return [
    'Gespeichert: ${alle.length} Seiten in Abschnitt „${abschnitt.titel}"${alle.first.wo}'
        '${knapp ? ', jede mit Rückleseprobe (verified: true).' : '.'}',
    if (!knapp) ...berichte,
    if (unveraendert.isNotEmpty) 'Unverändert, nicht gespeichert: ${unveraendert.join(", ")}.',
  ].join('\n\n');
}
