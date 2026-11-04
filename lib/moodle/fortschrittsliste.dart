// Fortschrittsliste (mod_checklist): Werkzeuge fortschrittsliste_lesen und
// fortschrittsliste_aendern. Nur die EINTRÄGE -- wer abgehakt hat, steht auf
// der Berichtsseite (report.php, gesperrt), und eine Adresse mit studentid ist
// ebenfalls gesperrt.
//
// Gemessen in den Browser-Skills (17.09.2026): Die Eintragsliste steht auf
// /mod/checklist/edit.php. Deren Formulare sind KEINE mforms; neue Einträge
// (action=additem) und geänderte (updateitem, ohne action) gehen per POST.
// Die übrigen Aktionen sind Links mit sesskey (action=deleteitem,
// moveitemup …) -- Löschen fragt dort NICHT nach, es löscht sofort; die
// Freigabe steht deshalb in der App davor. Moodle nimmt jede Einrücktiefe,
// auch einen Sprung über mehrere Stufen; mehr als eine Stufe unter dem
// Vorgänger ergibt eine unlesbare Liste, deshalb wird darauf begrenzt.

import 'package:html/parser.dart' as html_parser;

import '../freigabe.dart';
import 'formular_schreiben.dart';
import 'kurs.dart';
import 'moodle_zugang.dart';

class Eintrag {
  Eintrag(this.id, this.text, this.zustand, this.tiefe, this.link);
  final int id;
  final String text;

  /// pflicht, optional, ueberschrift -- abgelesen an den angebotenen Aktionen.
  final String zustand;
  final int tiefe;
  final String? link;
}

/// Aktionen, die Moodle als Link anbietet (gemessen), mit ihrem Namen im Werkzeug.
const Map<String, String> listenAktionen = {
  'loeschen': 'deleteitem',
  'hoch': 'moveitemup',
  'runter': 'moveitemdown',
  'einruecken': 'indentitem',
  'ausruecken': 'unindentitem',
  'pflicht': 'makerequired',
  'optional': 'makeoptional',
  'ueberschrift': 'makeheading',
};

Future<List<Eintrag>> eintraegeLesen(MoodleZugang moodle, int cmid) async =>
    eintraegeAuswerten((await moodle.lesen('/mod/checklist/edit.php?id=$cmid')).text);

/// Die Einträge aus der Seite edit.php.
List<Eintrag> eintraegeAuswerten(String seite) {
  final d = html_parser.parse(seite);
  final aus = <Eintrag>[];
  for (final a in d.querySelectorAll('a[href*="action=edititem"]')) {
    final zeile = a.parent?.localName == 'li' ? a.parent! : (a.parent?.parent ?? a.parent!);
    var li = a.parent;
    while (li != null && li.localName != 'li') {
      li = li.parent;
    }
    final z = li ?? zeile;
    final eigen = Uri.parse(a.attributes['href'] ?? '').queryParameters;
    final aktionen = [
      for (final x in z.querySelectorAll('a[href*="action="]')) Uri.parse(x.attributes['href'] ?? '').queryParameters['action']
    ];
    // Der Text steht im <label>; li.text nähme die Aktionslinks mit.
    final text = (z.querySelector('label')?.text ?? z.text).replaceAll(RegExp(r'\s+'), ' ').trim();
    final link = z
        .querySelectorAll('a[href]')
        .where((x) => !RegExp(r'[?&]action=').hasMatch(x.attributes['href'] ?? ''))
        .firstOrNull
        ?.attributes['href'];
    // Jede Stufe ist ein weiteres <ol class="checklist"> um das <li>; das
    // äußerste trägt zusätzlich checklist-extendedit, und dort hört die
    // Zählung auf -- es zählt also schon nicht mit (gemessen 17.09.2026).
    var tiefe = 0;
    for (var e = z.parent; e != null && !e.classes.contains('checklist-extendedit'); e = e.parent) {
      if (e.localName == 'ol' && e.classes.contains('checklist')) tiefe++;
    }
    aus.add(Eintrag(
      int.parse(eigen['itemid'] ?? '0'),
      text,
      aktionen.contains('makeoptional')
          ? 'pflicht'
          : aktionen.contains('makeheading')
              ? 'optional'
              : aktionen.contains('makerequired')
                  ? 'ueberschrift'
                  : '?',
      tiefe,
      link,
    ));
  }
  return aus;
}

/// Rückleseprobe einer Listenaktion: Hat sich am Eintrag geändert, was die
/// Aktion ändern soll? Moodle antwortet auf jeden Aufruf mit derselben Seite,
/// auch wenn nichts geschehen ist.
String listenaktionPruefen(String art, int id, List<Eintrag> vorher, List<Eintrag> nachher) {
  final v = vorher.where((e) => e.id == id).firstOrNull;
  final n = nachher.where((e) => e.id == id).firstOrNull;
  if (art == 'loeschen') return n == null ? 'gelöscht' : 'NOCH DA';
  if (v == null || n == null) return 'NICHT GEFUNDEN';
  final ok = switch (art) {
    'einruecken' => n.tiefe == v.tiefe + 1,
    'ausruecken' => n.tiefe == v.tiefe - 1,
    'hoch' => nachher.indexOf(n) < vorher.indexOf(v),
    'runter' => nachher.indexOf(n) > vorher.indexOf(v),
    'pflicht' => n.zustand == 'pflicht',
    'optional' => n.zustand == 'optional',
    'ueberschrift' => n.zustand == 'ueberschrift',
    _ => false,
  };
  if (ok) return 'ausgeführt';
  return switch (art) {
    'einruecken' || 'ausruecken' => 'NICHT ausgeführt (Tiefe ${v.tiefe} -> ${n.tiefe})',
    'hoch' || 'runter' => 'NICHT ausgeführt (Position ${vorher.indexOf(v) + 1} -> ${nachher.indexOf(n) + 1})',
    _ => 'NICHT ausgeführt (Zustand ${v.zustand} -> ${n.zustand})',
  };
}

/// Die Art, die ein neuer Eintrag bekommen soll (`zustand`), oder null für
/// die Vorgabe. Unbekanntes bricht ab, bevor gefragt wird.
String? _neuerZustand(Map<String, Object?> a) {
  final z = a['zustand'];
  if (z == null) return null;
  if (z is! String || !const {'pflicht', 'optional', 'ueberschrift'}.contains(z)) {
    throw MoodleFehler('zustand „$z" gibt es nicht. Möglich: pflicht, optional, ueberschrift.');
  }
  return z;
}

String _liste(List<Eintrag> l) => l.isEmpty
    ? '  (keine Einträge)'
    : [for (final e in l) '  ${'  ' * e.tiefe}${e.id} „${e.text}" [${e.zustand}]${e.link == null ? '' : ' -> ${e.link}'}'].join('\n');

Future<String> fortschrittslisteLesen(MoodleZugang moodle, int cmid) async {
  final l = await eintraegeLesen(moodle, cmid);
  return 'Fortschrittsliste cmid $cmid: ${l.length} Einträge (id „Text" [Zustand] -> Link)\n${_liste(l)}\n'
      'Nur die Einträge; wer abgehakt hat, liest die App nicht.';
}

Future<String> fortschrittslisteAendern(MoodleZugang moodle, Freigaben freigaben,
    {required int cmid, required String name, required List<Map<String, Object?>> aktionen}) async {
  final vorher = await eintraegeLesen(moodle, cmid);
  final f0 = await formularHolen(moodle, '/course/modedit.php?update=$cmid');
  final kurs = f0.kurs;
  nameBestaetigen(name, f0.name, 'cmid $cmid');
  String text(Object? id) => vorher.where((e) => '${e.id}' == '$id').firstOrNull?.text ?? '(Eintrag $id gibt es nicht!)';
  final punkte = <String>[
    'Fortschrittsliste „${f0.name}" (cmid $cmid${kurs == null ? '' : ', ${await kursBezeichnung(moodle, kurs)}'})',
    for (final a in aktionen)
      switch (a['art']) {
        'neu' => 'Neuer Eintrag „${a['text']}"${a['link'] == null ? '' : ' mit Link ${a['link']}'}'
            '${_neuerZustand(a) == null ? '' : ' (${_neuerZustand(a)})'}',
        'aendern' => '„${text(a['eintrag'])}" wird „${a['text']}"',
        final String art when listenAktionen.containsKey(art) => '$art: „${text(a['eintrag'])}"',
        _ => throw MoodleFehler('Unbekannte Aktion „${a['art']}". Möglich: neu, aendern, ${listenAktionen.keys.join(", ")}.'),
      },
  ];
  final ja = await freigaben.anfragen(
      FreigabeAnfrage(
          titel: 'Fortschrittsliste ändern?', punkte: punkte, vergleich: const [], knopf: 'Ändern',
          ab: await fuellenAb(moodle, kurs, [cmid])));
  if (!ja) return 'Nicht geändert: in der App abgelehnt oder nicht rechtzeitig freigegeben.';

  final erg = <String>[];
  final probe = Probe();
  for (final a in aktionen) {
    final s = await moodle.sesskey();
    final jetzt = await eintraegeLesen(moodle, cmid);
    switch (a['art']) {
      case 'neu':
        final hoechstens = jetzt.isEmpty ? 0 : jetzt.last.tiefe + 1;
        final tiefe = ((a['tiefe'] as num?)?.toInt() ?? 0).clamp(0, hoechstens);
        await moodle.senden('/mod/checklist/edit.php', [
          MapEntry('id', '$cmid'),
          MapEntry('sesskey', s),
          const MapEntry('action', 'additem'),
          MapEntry('indent', '$tiefe'),
          MapEntry('displaytext', '${a['text']}'),
          MapEntry('linkurl', '${a['link'] ?? ''}'),
          const MapEntry('additem', '1'),
        ]);
        final nach = await eintraegeLesen(moodle, cmid);
        final neu = nach.where((e) => !jetzt.any((v) => v.id == e.id)).toList();
        probe.pruefe(neu.length == 1, 'neuer Eintrag „${a['text']}"');
        erg.add('Neu „${a['text']}": ${neu.length == 1 ? 'id ${neu.single.id}, Tiefe ${neu.single.tiefe}' : 'NICHT eindeutig angekommen'}');
        // Die Art setzt Moodle nicht beim Anlegen, sondern über dieselbe
        // Aktion wie bei einem vorhandenen Eintrag -- jetzt, wo die id
        // bekannt ist. So braucht eine Liste mit Überschriften keinen
        // zweiten Aufruf und keine zweite Freigabe.
        final zustand = _neuerZustand(a);
        if (zustand != null && neu.length == 1 && neu.single.zustand != zustand) {
          await moodle.aufrufen('/mod/checklist/edit.php?id=$cmid&sesskey=$s&itemid=${neu.single.id}'
              '&action=${listenAktionen[zustand]}');
          final r = listenaktionPruefen(zustand, neu.single.id, nach, await eintraegeLesen(moodle, cmid));
          probe.pruefe(r == 'ausgeführt', '$zustand ${neu.single.id}');
          erg.add('$zustand ${neu.single.id}: $r');
        }
      case 'aendern':
        final alt = jetzt.where((e) => '${e.id}' == '${a['eintrag']}').firstOrNull;
        if (alt == null) throw MoodleFehler('Eintrag ${a['eintrag']} gibt es nicht.');
        await moodle.senden('/mod/checklist/edit.php', [
          MapEntry('id', '$cmid'),
          MapEntry('itemid', '${alt.id}'),
          MapEntry('sesskey', s),
          MapEntry('displaytext', '${a['text']}'),
          MapEntry('linkurl', a.containsKey('link') ? '${a['link'] ?? ''}' : alt.link ?? ''),
          const MapEntry('updateitem', '1'),
        ]);
        final neu = (await eintraegeLesen(moodle, cmid)).where((e) => e.id == alt.id).firstOrNull;
        final ok = neu?.text == nameNormal('${a['text']}');
        probe.pruefe(ok, 'Eintrag ${alt.id} geändert');
        erg.add('Eintrag ${alt.id}: ${ok ? 'geändert' : 'NICHT wie gewünscht'}');
      default:
        final id = (a['eintrag'] as num).toInt();
        final alt = jetzt.where((e) => e.id == id).firstOrNull;
        if (alt == null) throw MoodleFehler('Eintrag $id gibt es nicht.');
        await moodle.aufrufen('/mod/checklist/edit.php?id=$cmid&sesskey=$s&itemid=$id&action=${listenAktionen[a['art']]}');
        final nach = await eintraegeLesen(moodle, cmid);
        final r = listenaktionPruefen('${a['art']}', id, jetzt, nach);
        probe.pruefe(r == 'ausgeführt' || r == 'gelöscht', '${a['art']} $id');
        erg.add('${a['art']} $id: $r');
    }
  }
  return '${erg.join('\n')}\n${probe.text}\n\nJetzt:\n${_liste(await eintraegeLesen(moodle, cmid))}';
}
