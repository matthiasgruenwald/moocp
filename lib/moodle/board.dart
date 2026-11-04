// Board (mod_board) und Kanban-Board (mod_kanban): Werkzeuge board_lesen,
// board_aendern, kanban_lesen, kanban_aendern.
//
// Board: Spalten von der Lehrkraft sind Kursinhalt, Notizen sind Beiträge
// einzelner Personen -- jede trägt eine userid. Die App gibt deshalb nur die
// EIGENEN Notizen heraus und zählt die anderen; ändern und löschen kann sie
// nur eigene. Export und das Board einer einzelnen Person (ownerid≠0) sind
// gesperrt. Eine Spalte zu löschen nimmt ALLE Notizen darin mit, auch die
// anderer -- nur leere Spalten, oder ausdrücklich mit_notizen.
// Gemessen (22.09.2026): Lesen über mod_board_get_board {id, ownerid 0,
// groupid 0}; Spalten und Notizen entstehen über Formulare unter
// /mod/board/*_ajax.php (ein leerer POST liefert {status: render, html},
// der gefüllte speichert: {status: submitted}); löschen, verschieben,
// sperren über Webservices, alle ohne Rückfrage. Die Board-ID steht auf der
// Ansichtsseite im Aufruf initialize("<boardid>", <ownerid>, <groupid>).
//
// Kanban: das gemeinsame Kursboard, kooperativer Inhalt wie ein Wiki.
// Nicht herausgegeben wird, wer eine Karte angelegt hat, wem sie zugewiesen
// ist, die Nutzerliste, Diskussionen und der Verlauf. Persönliche Boards
// (userid≠0) und der Export sind gesperrt. Lesen über
// mod_kanban_get_kanban_content_init; Änderungen über mod_kanban_<aktion>
// {cmid, boardid, data}; Titel und Beschreibung über die dynamischen
// Formulare edit_card_form und edit_column_form. Die Board-ID steht als
// data-id am Container .mod_kanban_render_container.

import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import '../freigabe.dart';
import 'formular.dart';
import 'formular_schreiben.dart';
import 'kurs.dart';
import 'moodle_zugang.dart';

// ---------------------------------------------------------------------------
// Board
// ---------------------------------------------------------------------------

class BoardSpalte {
  BoardSpalte(this.id, this.name, this.gesperrt, this.notizen, this.eigene);
  final int id;
  final String name;
  final bool gesperrt;
  final int notizen;

  /// Eigene Notizen: (noteid, Titel, Inhalt).
  final List<(int, String, String)> eigene;
}

Future<(int, int)> _boardId(MoodleZugang moodle, int cmid) async {
  final t = (await moodle.lesen('/mod/board/view.php?id=$cmid')).text;
  final m = RegExp(r'mod_board/main[\s\S]{0,200}?initialize\("(\d+)",\s*(\d+),\s*(\d+)\)').firstMatch(t);
  if (m == null) throw MoodleFehler('Auf /mod/board/view.php?id=$cmid steht kein Board.');
  if (m.group(2) != '0') {
    throw MoodleFehler('Dieses Board zeigt das Board EINER Person (Einzelnutzermodus) -- dort liest und schreibt die App nichts.');
  }
  return (int.parse(m.group(1)!), int.parse(m.group(3)!));
}

Future<List<BoardSpalte>> _board(MoodleZugang moodle, int boardid) async {
  if (moodle.eigeneId == null) await moodle.eigeneIdErmitteln();
  final roh = await moodle.dienst('mod_board_get_board', {'id': boardid, 'ownerid': 0, 'groupid': 0});
  return [
    for (final s in (roh as List? ?? const []))
      if (s is Map)
        BoardSpalte(
          (s['id'] as num).toInt(),
          '${s['name'] ?? ''}',
          s['locked'] == true || s['locked'] == 1,
          (s['notes'] as List? ?? const []).length,
          [
            for (final n in (s['notes'] as List? ?? const []))
              if (n is Map && '${n['userid']}' == '${moodle.eigeneId}')
                ((n['id'] as num).toInt(), '${n['heading'] ?? ''}', '${n['content'] ?? ''}')
          ],
        )
  ];
}

String _boardText(List<BoardSpalte> l) => [
      for (final s in l)
        '  Spalte ${s.id} „${s.name}"${s.gesperrt ? ' [gesperrt]' : ''}: ${s.notizen} Notiz(en)'
            '${s.eigene.isEmpty ? '' : ', eigene: ${s.eigene.map((n) => '${n.$1} „${n.$2}"').join(', ')}'}'
    ].join('\n');

Future<String> boardLesen(MoodleZugang moodle, int cmid) async {
  final (boardid, _) = await _boardId(moodle, cmid);
  final l = await _board(moodle, boardid);
  return 'Board cmid $cmid (boardid $boardid): ${l.length} Spalten\n${_boardText(l)}\n'
      'Notizen anderer werden nur gezählt, nie gelesen -- das sind Beiträge einzelner Personen.';
}

/// Ein Formular unter /mod/board/*_ajax.php: leer holen, füllen, speichern.
Future<Map> _ajaxFormular(MoodleZugang moodle, String adresse, Map<String, String> werte) async {
  final leer = jsonDecode((await moodle.senden(adresse, const [])).text) as Map;
  final daten = leer['data'];
  if (daten is! Map || daten['status'] != 'render') throw MoodleFehler('Kein Formular unter ${adresse.split('?').first}.');
  final form = html_parser.parse('${daten['html']}');
  final f = formularFelder(form.querySelector('form') ?? form.body!);
  for (final e in werte.entries) {
    setze(f, e.key, e.value);
  }
  final voll = jsonDecode((await moodle.senden(adresse, f)).text) as Map;
  final d2 = voll['data'];
  if (d2 is! Map || d2['status'] != 'submitted') throw MoodleFehler('Nicht gespeichert (${adresse.split('?').first}).');
  return (d2['callbackdata'] as Map?) ?? {};
}

Future<String> boardAendern(MoodleZugang moodle, Freigaben freigaben,
    {required int cmid, required String name, required List<Map<String, Object?>> aktionen}) async {
  final (boardid, gruppe) = await _boardId(moodle, cmid);
  final vorher = await _board(moodle, boardid);
  final f0 = await formularHolen(moodle, '/course/modedit.php?update=$cmid');
  nameBestaetigen(name, f0.name, 'cmid $cmid');
  BoardSpalte spalte(Object? id) => vorher.firstWhere((s) => '${s.id}' == '$id',
      orElse: () => throw MoodleFehler('Spalte $id gibt es nicht. Vorhanden:\n${_boardText(vorher)}'));
  (int, String, String) eigene(Object? id) => vorher.expand((s) => s.eigene).firstWhere((n) => '${n.$1}' == '$id',
      orElse: () => throw MoodleFehler('Notiz $id ist keine eigene Notiz -- Notizen anderer ändert und löscht die App nicht.'));
  final punkte = <String>['Board „${f0.name}" (cmid $cmid${f0.kurs == null ? '' : ', ${await kursBezeichnung(moodle, f0.kurs!)}'})'];
  for (final a in aktionen) {
    punkte.add(switch (a['art']) {
      'spalte_neu' => 'Neue Spalte „${a['name']}"',
      'spalte_umbenennen' => 'Spalte „${spalte(a['spalte']).name}" heißt dann „${a['name']}"',
      'spalte_loeschen' => () {
          final s = spalte(a['spalte']);
          if (s.notizen > 0 && a['mit_notizen'] != true) {
            throw MoodleFehler('Spalte „${s.name}" enthält ${s.notizen} Notizen -- Beiträge von Personen. Nur mit mit_notizen: true.');
          }
          return 'Spalte „${s.name}" LÖSCHEN${s.notizen > 0 ? ' samt ${s.notizen} Notizen (auch von anderen)' : ''}';
        }(),
      'spalte_verschieben' => 'Spalte „${spalte(a['spalte']).name}" an Position ${a['position']}',
      'spalte_sperren' => 'Spalte „${spalte(a['spalte']).name}" ${a['gesperrt'] == false ? 'freigeben' : 'sperren'}',
      'notiz_neu' => 'Eigene Notiz „${a['titel'] ?? ''}" in „${spalte(a['spalte']).name}"',
      'notiz_aendern' => 'Eigene Notiz „${eigene(a['notiz']).$2}" ändern',
      'notiz_loeschen' => 'Eigene Notiz „${eigene(a['notiz']).$2}" löschen',
      _ => throw MoodleFehler('Unbekannte Aktion „${a['art']}". Möglich: spalte_neu, spalte_umbenennen, spalte_loeschen, '
          'spalte_verschieben, spalte_sperren, notiz_neu, notiz_aendern, notiz_loeschen.'),
    });
  }
  final ja = await freigaben.anfragen(FreigabeAnfrage(
      titel: 'Board ändern?', punkte: punkte, vergleich: const [], knopf: 'Ändern', ab: await fuellenAb(moodle, f0.kurs, [cmid])));
  if (!ja) return 'Nicht geändert: in der App abgelehnt oder nicht rechtzeitig freigegeben.';
  for (final a in aktionen) {
    final id = (a['spalte'] ?? a['notiz']) is num ? ((a['spalte'] ?? a['notiz']) as num).toInt() : null;
    switch (a['art']) {
      case 'spalte_neu':
        await _ajaxFormular(moodle, '/mod/board/column_create_ajax.php?boardid=$boardid', {'name': '${a['name']}'});
      case 'spalte_umbenennen':
        await _ajaxFormular(moodle, '/mod/board/column_update_ajax.php?id=$id', {'name': '${a['name']}'});
      case 'spalte_loeschen':
        await moodle.dienst('mod_board_delete_column', {'id': id});
      case 'spalte_verschieben':
        await moodle.dienst('mod_board_move_column', {'id': id, 'sortorder': (a['position'] as num?)?.toInt() ?? 0});
      case 'spalte_sperren':
        await moodle.dienst('mod_board_lock_column', {'id': id, 'status': a['gesperrt'] != false});
      case 'notiz_neu':
        await _ajaxFormular(moodle, '/mod/board/note_create_ajax.php?columnid=$id&ownerid=0&groupid=$gruppe',
            {'heading': '${a['titel'] ?? ''}', 'content': '${a['inhalt'] ?? ''}', 'mediatype': '0'});
      case 'notiz_aendern':
        final alt = eigene(id);
        await _ajaxFormular(moodle, '/mod/board/note_update_ajax.php?id=$id',
            {'heading': '${a['titel'] ?? alt.$2}', 'content': '${a['inhalt'] ?? alt.$3}', 'mediatype': '0'});
      case 'notiz_loeschen':
        await moodle.dienst('mod_board_delete_note', {'id': id});
    }
  }
  final nachher = await _board(moodle, boardid);
  return 'Ausgeführt. ${boardPruefen(aktionen, vorher, nachher).text}\nJetzt:\n${_boardText(nachher)}';
}

/// Text ohne Auszeichnung und mit einfachen Leerzeichen -- so vergleicht die
/// Probe, was Moodle beim Speichern an HTML und Umbrüchen ändern darf.
String _klartext(String s) => nameNormal(html_parser.parseFragment(s).text ?? '');

/// Ein Klartextfeld (Name, Titel, Inhalt einer Notiz) gegen das Geschriebene:
/// Moodle gibt es HTML-maskiert zurück (gemessen: „&amp;" für „&"), das
/// Geschriebene ist Text, auch wenn es wie HTML aussieht.
bool _gleich(String gelesen, Object? soll) => _klartext(gelesen) == nameNormal('$soll');

/// Ob eine spätere Aktion desselben Aufrufs das Ziel von aktionen[i] wieder
/// ändert oder löscht -- dann zählt in der Probe nur deren Ergebnis.
/// [eintrag]: der Schlüssel der Einträge, `notiz` oder `karte`.
bool _ueberholt(List<Map<String, Object?>> aktionen, int i, String eintrag) {
  final a = aktionen[i];
  String k(Map<String, Object?> x, String s) => '${x[s]}';
  for (final b in aktionen.skip(i + 1)) {
    if (!'${a['art']}'.endsWith('_neu') &&
        b['art'] == a['art'] &&
        k(b, 'spalte') == k(a, 'spalte') &&
        k(b, eintrag) == k(a, eintrag)) {
      return true;
    }
    if (b['art'] == 'spalte_loeschen' && a['spalte'] != null && k(b, 'spalte') == k(a, 'spalte')) return true;
    if (b['art'] == '${eintrag}_loeschen' && a[eintrag] != null && k(b, eintrag) == k(a, eintrag)) return true;
  }
  return false;
}

/// Rückleseprobe von board_aendern: Steht nach allen Aktionen da, was sie
/// bewirken sollten? Webservices und Formulare des Boards melden Erfolg auch,
/// wenn nichts geschehen ist. Geprüft wird der Endstand gegen jede Aktion.
/// `position` bei spalte_verschieben ist die Stelle von 0 an (gemessen
/// 29.10.2026: 0 = ganz vorn, 2 = dritte Spalte).
Probe boardPruefen(
    List<Map<String, Object?>> aktionen, List<BoardSpalte> vorher, List<BoardSpalte> nachher) {
  final probe = Probe();
  BoardSpalte? spalte(Object? id) => nachher.where((s) => '${s.id}' == '$id').firstOrNull;
  final notizen = {for (final s in nachher) for (final n in s.eigene) '${n.$1}': n};
  final neueSpalten = nachher.where((s) => !vorher.any((v) => v.id == s.id)).toList();
  final alt = {for (final s in vorher) for (final n in s.eigene) n.$1};
  final neueNotizen = [for (final s in nachher) for (final n in s.eigene) if (!alt.contains(n.$1)) (s.id, n)];
  for (var i = 0; i < aktionen.length; i++) {
    final a = aktionen[i];
    if (_ueberholt(aktionen, i, 'notiz')) continue;
    final s = spalte(a['spalte']);
    switch (a['art']) {
      case 'spalte_neu':
        final n = neueSpalten.where((x) => _gleich(x.name, a['name'])).firstOrNull;
        if (n != null) neueSpalten.remove(n);
        probe.pruefe(n != null, 'neue Spalte „${a['name']}" fehlt');
      case 'spalte_umbenennen':
        probe.pruefe(s != null && _gleich(s.name, a['name']),
            'Spalte ${a['spalte']} heißt „${s?.name}", nicht „${a['name']}"');
      case 'spalte_loeschen':
        probe.pruefe(s == null, 'Spalte ${a['spalte']} ist noch da');
      case 'spalte_verschieben':
        final i = nachher.indexWhere((x) => '${x.id}' == '${a['spalte']}');
        probe.pruefe(i == ((a['position'] as num?)?.toInt() ?? 0),
            'Spalte ${a['spalte']} ${i < 0 ? 'fehlt' : 'steht an Stelle $i, nicht ${a['position'] ?? 0}'}');
      case 'spalte_sperren':
        probe.pruefe(s != null && s.gesperrt == (a['gesperrt'] != false),
            'Spalte ${a['spalte']} ist ${s?.gesperrt == true ? 'gesperrt' : 'nicht gesperrt'}');
      case 'notiz_neu':
        final n = neueNotizen
            .where((x) =>
                '${x.$1}' == '${a['spalte']}' &&
                _gleich(x.$2.$2, a['titel'] ?? '') &&
                _gleich(x.$2.$3, a['inhalt'] ?? ''))
            .firstOrNull;
        if (n != null) neueNotizen.remove(n);
        // Abweichend: nennen, was gelesen wurde -- nur eigene Notizen.
        final da = [for (final x in neueNotizen) if ('${x.$1}' == '${a['spalte']}') '„${x.$2.$2}": „${x.$2.$3}"'];
        probe.pruefe(n != null,
            'neue Notiz „${a['titel'] ?? ''}" fehlt in Spalte ${a['spalte']}${da.isEmpty ? '' : ' (neu gelesen: ${da.join(', ')})'}');
      case 'notiz_aendern':
        final n = notizen['${a['notiz']}'];
        probe.pruefe(
            n != null &&
                (a['titel'] == null || _gleich(n.$2, a['titel'])) &&
                (a['inhalt'] == null || _gleich(n.$3, a['inhalt'])),
            'Notiz ${a['notiz']} ${n == null ? 'fehlt' : 'zeigt nicht den neuen Text'}');
      case 'notiz_loeschen':
        probe.pruefe(!notizen.containsKey('${a['notiz']}'), 'Notiz ${a['notiz']} ist noch da');
    }
  }
  return probe;
}

// ---------------------------------------------------------------------------
// Kanban
// ---------------------------------------------------------------------------

class KanbanKarte {
  KanbanKarte(this.id, this.titel, this.spalte, this.beschreibung, this.erledigt, this.vergeben);
  final int id;
  final String titel;
  final int spalte;
  final String beschreibung;
  final bool erledigt;

  /// Nur OB jemand zugewiesen ist, nicht wer.
  final bool vergeben;
}

Future<int> _kanbanId(MoodleZugang moodle, int cmid) async {
  final d = html_parser.parse((await moodle.lesen('/mod/kanban/view.php?id=$cmid')).text);
  final id = int.tryParse(d.querySelector('.mod_kanban_render_container[data-id]')?.attributes['data-id'] ?? '');
  if (id == null) throw MoodleFehler('Auf /mod/kanban/view.php?id=$cmid steht kein Kanban-Board.');
  return id;
}

List<int> _folge(Object? s) => [for (final x in '${s ?? ''}'.split(',')) if (int.tryParse(x) != null) int.parse(x)];

Future<List<(int, String, List<KanbanKarte>)>> _kanban(MoodleZugang moodle, int cmid, int boardid) async {
  final roh = await moodle.dienst('mod_kanban_get_kanban_content_init', {'cmid': cmid, 'boardid': boardid, 'timestamp': 0});
  if (roh is! Map) throw MoodleFehler('Kanban: unerwartete Antwort.');
  final karten = [
    for (final c in (roh['cards'] as List? ?? const []))
      if (c is Map)
        KanbanKarte((c['id'] as num).toInt(), '${c['title'] ?? ''}', (c['kanban_column'] as num?)?.toInt() ?? 0,
            '${c['description'] ?? ''}', c['completed'] == true || c['completed'] == 1, (c['assignees'] as List? ?? const []).isNotEmpty)
  ];
  final reihe = _folge((roh['board'] as Map?)?['sequence']);
  final spalten = [for (final s in (roh['columns'] as List? ?? const [])) if (s is Map) s]
    ..sort((a, b) => reihe.indexOf((a['id'] as num).toInt()).compareTo(reihe.indexOf((b['id'] as num).toInt())));
  return [
    for (final s in spalten)
      (
        (s['id'] as num).toInt(),
        '${s['title'] ?? ''}',
        karten.where((k) => k.spalte == (s['id'] as num).toInt()).toList()
          ..sort((a, b) => _folge(s['sequence']).indexOf(a.id).compareTo(_folge(s['sequence']).indexOf(b.id))),
      )
  ];
}

String _kanbanText(List<(int, String, List<KanbanKarte>)> l) => [
      for (final (id, titel, karten) in l) ...[
        '  Spalte $id „$titel":',
        for (final k in karten) '    Karte ${k.id} „${k.titel}"${k.erledigt ? ' [erledigt]' : ''}${k.vergeben ? ' [vergeben]' : ''}',
      ]
    ].join('\n');

Future<String> kanbanLesen(MoodleZugang moodle, int cmid) async {
  final b = await _kanbanId(moodle, cmid);
  return 'Kanban-Board cmid $cmid (boardid $b):\n${_kanbanText(await _kanban(moodle, cmid, b))}\n'
      'Ersteller und Zuweisungen liest die App nicht; [vergeben] sagt nur, dass jemand zugewiesen ist.';
}

Future<void> _dynForm(MoodleZugang moodle, String klasse, Map<String, Object?> parameter, Map<String, String> werte) async {
  final laden = await moodle.dienst('core_form_dynamic_form', {
    'form': klasse,
    'formdata': parameter.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent('${e.value}')}').join('&'),
  });
  final form = html_parser.parse('${(laden as Map)['html'] ?? ''}');
  final f = formularFelder(form.querySelector('form') ?? form.body!);
  for (final e in werte.entries) {
    setze(f, e.key, e.value);
  }
  final a = await moodle.dienst('core_form_dynamic_form', {
    'form': klasse,
    'formdata': f.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&'),
  });
  if (a is! Map || a['submitted'] != true) throw MoodleFehler('Formular $klasse hat nicht gespeichert -- meist ein Pflichtfeld.');
}

Future<String> kanbanAendern(MoodleZugang moodle, Freigaben freigaben,
    {required int cmid, required String name, required List<Map<String, Object?>> aktionen}) async {
  final b = await _kanbanId(moodle, cmid);
  final vorher = await _kanban(moodle, cmid, b);
  final f0 = await formularHolen(moodle, '/course/modedit.php?update=$cmid');
  nameBestaetigen(name, f0.name, 'cmid $cmid');
  String sp(Object? id) =>
      vorher.where((s) => '${s.$1}' == '$id').firstOrNull?.$2 ?? (throw MoodleFehler('Spalte $id gibt es nicht.\n${_kanbanText(vorher)}'));
  KanbanKarte ka(Object? id) => vorher.expand((s) => s.$3).firstWhere((k) => '${k.id}' == '$id',
      orElse: () => throw MoodleFehler('Karte $id gibt es nicht.\n${_kanbanText(vorher)}'));
  final punkte = <String>['Kanban-Board „${f0.name}" (cmid $cmid${f0.kurs == null ? '' : ', ${await kursBezeichnung(moodle, f0.kurs!)}'})'];
  // Wo jede Karte nach den bisherigen Aktionen dieses Aufrufs liegt -- eine
  // Spalte, deren Karten vorher gelöscht oder verschoben werden, ist leer.
  final lage = <String, String?>{
    for (final s in vorher)
      for (final k in s.$3) '${k.id}': '${s.$1}'
  };
  for (final a in aktionen) {
    if (a['art'] == 'karte_loeschen') lage['${a['karte']}'] = null;
    if (a['art'] == 'karte_verschieben') lage['${a['karte']}'] = '${a['spalte']}';
    punkte.add(switch (a['art']) {
      'spalte_neu' => 'Neue Spalte „${a['titel']}"',
      'spalte_umbenennen' => 'Spalte „${sp(a['spalte'])}" heißt dann „${a['titel']}"',
      'spalte_loeschen' => () {
          final karten = lage.values.where((s) => s == '${a['spalte']}').length;
          if (karten > 0 && a['mit_karten'] != true) {
            throw MoodleFehler('Spalte „${sp(a['spalte'])}" enthält $karten Karten -- nur mit mit_karten: true.');
          }
          return 'Spalte „${sp(a['spalte'])}" LÖSCHEN${karten > 0 ? ' samt $karten Karten' : ''}';
        }(),
      'spalte_verschieben' => 'Spalte „${sp(a['spalte'])}" hinter ${a['nach'] == 0 || a['nach'] == null ? 'den Anfang' : '„${sp(a['nach'])}"'}',
      'karte_neu' => 'Neue Karte „${a['titel']}" in „${sp(a['spalte'])}"',
      'karte_aendern' => 'Karte „${ka(a['karte']).titel}" ändern',
      'karte_loeschen' => 'Karte „${ka(a['karte']).titel}" löschen',
      'karte_verschieben' => 'Karte „${ka(a['karte']).titel}" nach „${sp(a['spalte'])}"',
      _ => throw MoodleFehler('Unbekannte Aktion „${a['art']}". Möglich: spalte_neu, spalte_umbenennen, spalte_loeschen, '
          'spalte_verschieben, karte_neu, karte_aendern, karte_loeschen, karte_verschieben.'),
    });
  }
  final ja = await freigaben.anfragen(FreigabeAnfrage(
      titel: 'Kanban-Board ändern?', punkte: punkte, vergleich: const [], knopf: 'Ändern', ab: await fuellenAb(moodle, f0.kurs, [cmid])));
  if (!ja) return 'Nicht geändert: in der App abgelehnt oder nicht rechtzeitig freigegeben.';
  Future<Object?> aktion(String was, Map<String, Object?> data) =>
      moodle.dienst('mod_kanban_$was', {'cmid': cmid, 'boardid': b, 'data': data});
  int zahl(Object? x) => (x as num?)?.toInt() ?? 0;
  for (final a in aktionen) {
    final jetzt = await _kanban(moodle, cmid, b);
    switch (a['art']) {
      case 'spalte_neu':
        await aktion('add_column', {'aftercol': a['nach'] == null ? (jetzt.isEmpty ? 0 : jetzt.last.$1) : zahl(a['nach'])});
        final neu = (await _kanban(moodle, cmid, b)).where((s) => !jetzt.any((v) => v.$1 == s.$1)).toList();
        if (neu.length != 1) throw MoodleFehler('Die neue Spalte ist nicht eindeutig angekommen.');
        await _dynForm(moodle, r'mod_kanban\form\edit_column_form', {'id': neu.single.$1, 'boardid': b, 'cmid': cmid},
            {'title': '${a['titel']}'});
      case 'spalte_umbenennen':
        await _dynForm(moodle, r'mod_kanban\form\edit_column_form', {'id': zahl(a['spalte']), 'boardid': b, 'cmid': cmid},
            {'title': '${a['titel']}'});
      case 'spalte_loeschen':
        await aktion('delete_column', {'columnid': zahl(a['spalte'])});
      case 'spalte_verschieben':
        await aktion('move_column', {'columnid': zahl(a['spalte']), 'aftercol': zahl(a['nach'])});
      case 'karte_neu':
        await aktion('add_card', {'columnid': zahl(a['spalte']), 'aftercard': 0});
        final alle = jetzt.expand((s) => s.$3).map((k) => k.id).toSet();
        final neu = (await _kanban(moodle, cmid, b)).expand((s) => s.$3).where((k) => !alle.contains(k.id)).toList();
        if (neu.length != 1) throw MoodleFehler('Die neue Karte ist nicht eindeutig angekommen.');
        await _dynForm(moodle, r'mod_kanban\form\edit_card_form',
            {'id': neu.single.id, 'boardid': b, 'cmid': cmid, 'groupid': 0, 'userid': 0}, {
          'title': '${a['titel']}',
          if (a['beschreibung'] != null) 'description_editor[text]': '${a['beschreibung']}',
          if (a['beschreibung'] != null) 'description_editor[format]': '1',
        });
      case 'karte_aendern':
        await _dynForm(moodle, r'mod_kanban\form\edit_card_form',
            {'id': zahl(a['karte']), 'boardid': b, 'cmid': cmid, 'groupid': 0, 'userid': 0}, {
          if (a['titel'] != null) 'title': '${a['titel']}',
          if (a['beschreibung'] != null) 'description_editor[text]': '${a['beschreibung']}',
          if (a['beschreibung'] != null) 'description_editor[format]': '1',
        });
      case 'karte_loeschen':
        await aktion('delete_card', {'cardid': zahl(a['karte'])});
      case 'karte_verschieben':
        await aktion('move_card', {'cardid': zahl(a['karte']), 'columnid': zahl(a['spalte']), 'aftercard': zahl(a['nach'])});
    }
  }
  final nachher = await _kanban(moodle, cmid, b);
  return 'Ausgeführt. ${kanbanPruefen(aktionen, vorher, nachher).text}\nJetzt:\n${_kanbanText(nachher)}';
}

/// Rückleseprobe von kanban_aendern, wie [boardPruefen]: der Endstand gegen
/// jede Aktion. Positionen prüft sie, wo die Aktion eine nennt (`nach`, die
/// Spalte oder Karte davor; 0 = an den Anfang, gemessen 29.10.2026 auch für
/// Karten). Löscht eine spätere Aktion das `nach`-Ziel, bleibt nur zu prüfen,
/// ob die Karte in der Spalte steht.
Probe kanbanPruefen(List<Map<String, Object?>> aktionen, List<(int, String, List<KanbanKarte>)> vorher,
    List<(int, String, List<KanbanKarte>)> nachher) {
  final probe = Probe();
  final ids = [for (final s in nachher) '${s.$1}'];
  (int, String, List<KanbanKarte>)? spalte(Object? id) => nachher.where((s) => '${s.$1}' == '$id').firstOrNull;
  final karten = {for (final s in nachher) for (final k in s.$3) '${k.id}': k};
  final neueSpalten = nachher.where((s) => !vorher.any((v) => v.$1 == s.$1)).toList();
  final alt = {for (final s in vorher) for (final k in s.$3) k.id};
  final neueKarten = [for (final s in nachher) for (final k in s.$3) if (!alt.contains(k.id)) k];
  bool beschreibungGleich(KanbanKarte k, Object? soll) => soll == null || _klartext(k.beschreibung) == _klartext('$soll');
  for (var i = 0; i < aktionen.length; i++) {
    final a = aktionen[i];
    if (_ueberholt(aktionen, i, 'karte')) continue;
    final s = spalte(a['spalte']);
    final nach = (a['nach'] as num?)?.toInt() ?? 0;
    final nachWeg = nach != 0 &&
        aktionen.skip(i + 1).any((b) =>
            '${b['art']}'.endsWith('_loeschen') && '${b[a['art'] == 'karte_verschieben' ? 'karte' : 'spalte']}' == '$nach');
    switch (a['art']) {
      case 'spalte_neu':
        final n = neueSpalten.where((x) => _gleich(x.$2, a['titel'])).firstOrNull;
        if (n != null) neueSpalten.remove(n);
        probe.pruefe(n != null, 'neue Spalte „${a['titel']}" fehlt');
      case 'spalte_umbenennen':
        probe.pruefe(s != null && _gleich(s.$2, a['titel']),
            'Spalte ${a['spalte']} heißt „${s?.$2}", nicht „${a['titel']}"');
      case 'spalte_loeschen':
        probe.pruefe(s == null, 'Spalte ${a['spalte']} ist noch da');
      case 'spalte_verschieben':
        final i = ids.indexOf('${a['spalte']}');
        probe.pruefe(i >= 0 && (nachWeg || (nach == 0 ? i == 0 : i > 0 && ids[i - 1] == '$nach')),
            'Spalte ${a['spalte']} steht nicht ${nach == 0 ? 'am Anfang' : 'hinter Spalte $nach'}');
      case 'karte_neu':
        final n = neueKarten
            .where((k) =>
                '${k.spalte}' == '${a['spalte']}' &&
                _gleich(k.titel, a['titel']) &&
                beschreibungGleich(k, a['beschreibung']))
            .firstOrNull;
        if (n != null) neueKarten.remove(n);
        probe.pruefe(n != null, 'neue Karte „${a['titel']}" fehlt in Spalte ${a['spalte']} oder weicht ab');
      case 'karte_aendern':
        final k = karten['${a['karte']}'];
        probe.pruefe(
            k != null &&
                (a['titel'] == null || _gleich(k.titel, a['titel'])) &&
                beschreibungGleich(k, a['beschreibung']),
            'Karte ${a['karte']} ${k == null ? 'fehlt' : 'zeigt nicht den neuen Text'}');
      case 'karte_loeschen':
        probe.pruefe(!karten.containsKey('${a['karte']}'), 'Karte ${a['karte']} ist noch da');
      case 'karte_verschieben':
        final folge = [for (final k in s?.$3 ?? const <KanbanKarte>[]) '${k.id}'];
        final i = folge.indexOf('${a['karte']}');
        probe.pruefe(i >= 0 && (nachWeg || (nach == 0 ? i == 0 : i > 0 && folge[i - 1] == '$nach')),
            'Karte ${a['karte']} steht nicht in Spalte ${a['spalte']}${nachWeg ? '' : nach == 0 ? ' oben' : ' hinter Karte $nach'}');
    }
  }
  return probe;
}
