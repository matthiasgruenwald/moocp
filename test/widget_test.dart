// Offline prüfbar: die Positivliste und das Lesen von Formularen.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/moodle/formular.dart';
import 'package:moocp/moodle/zeilenvergleich.dart';
import 'package:moocp/protokoll.dart';

void main() {
  final z = MoodleZugang(Protokoll());
  bool get(String a) => z.erlaubt('GET', Uri.parse(a));
  bool post(String a, [Felder? f]) => z.erlaubt('POST', Uri.parse(a), f);
  const anlegen43 = 'https://m.example/course/modedit.php?add=page&type=&course=43&section=0&return=0&sr=0';

  test('Lesen: erlaubt, was aktivitaet_lesen braucht', () {
    expect(get('https://m.example/course/modedit.php?update=15271'), isTrue);
    expect(get('https://m.example/draftfile.php/2393/user/draft/905327642/bild.svg'), isTrue);
    expect(get('https://m.example/pluginfile.php/6520/mod_folder/content/0/a.odt'), isTrue);
    expect(get('https://m.example/login/index.php'), isTrue);
    expect(get('https://m.example/login/index.php?testsession=5'), isTrue);
  });

  test('Lesen: sperrt alles andere', () {
    expect(get('https://m.example/course/modedit.php?update=1&delete=1'), isFalse);
    expect(get('https://m.example/user/index.php?id=43'), isFalse);
    expect(get('https://m.example/grade/report/grader/index.php?id=43'), isFalse);
    expect(get('https://m.example/mod/assign/view.php?id=4703&action=grading'), isFalse);
    expect(get('https://m.example/my/'), isFalse);
    expect(get('https://m.example/login/logout.php?sesskey=x'), isFalse);
    expect(post('https://m.example/course/modedit.php?update=15271'), isFalse);
  });

  test('Schreiben: nur Formulare bekannter Typen, keine Sammeleingänge', () {
    expect(get(anlegen43), isTrue);
    expect(get(anlegen43.replaceFirst('course=43', 'course=47')), isTrue,
        reason: 'welche Kurse die Sitzung bearbeiten darf, entscheidet Moodle');
    expect(get(anlegen43.replaceFirst('add=page', 'add=assign')), isTrue);
    expect(get(anlegen43.replaceFirst('add=page', 'add=folder')), isTrue);
    expect(get(anlegen43.replaceFirst('add=page', 'add=forum')), isFalse, reason: 'nicht gemessen');
    expect(get(anlegen43.replaceFirst('section=0', 'section=x')), isFalse);
    final seite = <MapEntry<String, String>>[
      const MapEntry('course', '43'),
      const MapEntry('modulename', 'page'),
      const MapEntry('_qf__mod_page_mod_form', '1'),
    ];
    expect(post('https://m.example/course/modedit.php', seite), isTrue);
    expect(post('https://m.example/course/modedit.php'), isFalse);
    final forum = [
      const MapEntry('course', '43'),
      const MapEntry('modulename', 'forum'),
      const MapEntry('_qf__mod_forum_mod_form', '1'),
    ];
    expect(post('https://m.example/course/modedit.php', forum), isFalse);
    final aufgabe = [
      const MapEntry('course', '43'),
      const MapEntry('modulename', 'assign'),
      const MapEntry('_qf__mod_assign_mod_form', '1'),
    ];
    expect(post('https://m.example/course/modedit.php', aufgabe), isTrue);
    final falscheMarke = [...aufgabe]..[2] = const MapEntry('_qf__mod_page_mod_form', '1');
    expect(post('https://m.example/course/modedit.php', falscheMarke), isFalse);
    expect(get('https://m.example/course/editsection.php?id=812'), isTrue);
    expect(get('https://m.example/course/editsection.php?id=812&delete=1'), isFalse);
    expect(post('https://m.example/course/editsection.php',
        const [MapEntry('id', '812'), MapEntry('_qf__editsection_form', '1')]), isTrue);
    expect(post('https://m.example/course/editsection.php', const [MapEntry('id', '812')]), isFalse);
    // Upload nur mit Datei: ein Aufruf ohne Anhang ist kein Upload mehr.
    expect(post('https://m.example/repository/repository_ajax.php?action=upload'), isFalse);
    expect(post('https://m.example/repository/repository_ajax.php?action=delete'), isFalse);
    // Verbergen, Löschen, Verschieben laufen über die Kursstruktur-Aktionen,
    // nicht über course/mod.php.
    expect(post('https://m.example/course/mod.php',
        const [MapEntry('confirm', '1'), MapEntry('delete', '9'), MapEntry('sesskey', 'x')]), isFalse);
    expect(post('https://m.example/course/mod.php', const [MapEntry('hide', '9'), MapEntry('sesskey', 'x')]),
        isFalse);
    expect(post('https://m.example/repository/draftfiles_ajax.php?action=delete',
        const [MapEntry('itemid', '5'), MapEntry('filepath', '/'), MapEntry('filename', 'a.svg'), MapEntry('sesskey', 'x')]), isTrue);
    expect(post('https://m.example/repository/draftfiles_ajax.php?action=list',
        const [MapEntry('itemid', '5'), MapEntry('filepath', '/sub/'), MapEntry('client_id', 'c'), MapEntry('sesskey', 'x')]), isTrue);
    expect(post('https://m.example/repository/draftfiles_ajax.php?action=list',
        const [MapEntry('itemid', '5'), MapEntry('filepath', '/'), MapEntry('client_id', 'c'), MapEntry('sesskey', 'x'), MapEntry('userid', '7')]), isFalse);
    expect(post('https://m.example/repository/draftfiles_ajax.php?action=deleteall',
        const [MapEntry('itemid', '5'), MapEntry('sesskey', 'x')]), isFalse);
  });

  test('Fragen löschen: Rückfrage frei, Bestätigung nur mit den Feldern von Moodle', () {
    const d = 'https://m.example/question/bank/deletequestion/delete.php';
    const zurueck = 'returnurl=%2Fquestion%2Fedit.php%3Fcmid%3D2384';
    expect(get('$d?cmid=2384&deleteselected=1&deleteall=1&$zurueck&q14961=1&q14962=1'), isTrue);
    expect(get('$d?cmid=2384&deleteselected=1&$zurueck&q14961=1'), isTrue);
    expect(get('$d?cmid=2384&deleteselected=1&q14961=1'), isFalse, reason: 'ohne returnurl stürzt Moodle ab');
    expect(get('$d?cmid=2384&deleteselected=1&returnurl=%2Fuser%2Findex.php&q14961=1'), isFalse,
        reason: 'returnurl nur die eigene Sammlung');
    expect(get('$d?cmid=2384&deleteselected=1&$zurueck'), isFalse, reason: 'nichts ausgewählt');
    expect(get('$d?cmid=2384&deleteselected=1&$zurueck&q14961=x'), isFalse);
    expect(get('$d?cmid=2384&deleteselected=1&$zurueck&q14961=1&userid=5'), isFalse);
    const md5 = '0123456789abcdef0123456789abcdef';
    final bestaetigt = [
      const MapEntry('deleteselected', '14961,14962'),
      const MapEntry('deleteall', '1'),
      const MapEntry('confirm', md5),
      const MapEntry('sesskey', 'abc'),
      const MapEntry('returnurl', '/question/edit.php?cmid=2384'),
      const MapEntry('cmid', '2384'),
    ];
    expect(post(d, bestaetigt), isTrue);
    expect(get('$d?deleteselected=14961&deleteall=1&confirm=$md5&sesskey=abc&cmid=2384'), isTrue);
    expect(post(d, [...bestaetigt, const MapEntry('userid', '5')]), isFalse, reason: 'fremdes Feld');
    expect(post(d, [...bestaetigt]..[2] = const MapEntry('confirm', 'ja')), isFalse, reason: 'confirm kein md5');
    expect(post(d, bestaetigt.where((e) => e.key != 'sesskey').toList()), isFalse, reason: 'ohne sesskey');
    expect(post('$d?cmid=2384', bestaetigt), isFalse, reason: 'Parameter in der Adresse');
  });

  test('CAS-Notizblock: nur über eine Frage, nur rechnen, nie speichern', () {
    const c = 'https://m.example/question/type/stack/adminui/caschat.php';
    const mitFrage = '$c?questionid=995&cmid=2384';
    expect(get(mitFrage), isTrue);
    expect(get(c), isFalse, reason: 'ohne Frage nur für Administratoren');
    expect(get('$c?questionid=995'), isFalse);
    expect(get('$mitFrage&initialise=1'), isFalse, reason: 'füllte das Formular mit Variablen und Feedback der Frage');
    final rechnen = [
      const MapEntry('maximavars', 'x : 3;'),
      const MapEntry('simp', 'on'),
      const MapEntry('cas', 'Ergebnis {@x@}'),
      const MapEntry('action', 'go'),
    ];
    expect(post(mitFrage, rechnen), isTrue);
    expect(post(c, rechnen), isFalse, reason: 'ohne Frage');
    // Mit questionid schreibt „Speichern" Variablen und Feedback ohne neue
    // Version in die Frage.
    expect(post(mitFrage, [...rechnen]..[3] = const MapEntry('action', 'Speichern')), isFalse);
    expect(post(mitFrage, [...rechnen, const MapEntry('action', 'Speichern')]), isFalse, reason: 'zweites action');
    expect(post(mitFrage, rechnen.where((e) => e.key != 'action').toList()), isFalse, reason: 'ohne action');
    expect(post(mitFrage, [...rechnen, const MapEntry('inputs', 'ans1:3;')]), isFalse, reason: 'fremdes Feld');
  });

  test('Moodle-Dienste: nur die freigegebenen, nur mit passenden Argumenten', () {
    bool dienst(String info, String methode, Map<String, Object?> args, {String? key = 'x'}) =>
        z.erlaubt(
            'POST',
            Uri.parse('https://m.example/lib/ajax/service.php?'
                '${key == null ? '' : 'sesskey=$key&'}info=$info'),
            null,
            jsonEncode([
              {'index': 0, 'methodname': methode, 'args': args}
            ]));
    const s = 'core_courseformat_get_state';
    expect(dienst(s, s, {'courseid': 43}), isTrue);
    expect(dienst(s, s, {'courseid': 47}), isTrue);
    expect(dienst(s, s, {'courseid': 43, 'userid': 5}), isFalse);
    expect(dienst(s, s, {'courseid': 43}, key: null), isFalse);
    expect(dienst(s, 'mod_assign_get_submissions', {'courseid': 43}), isFalse);
    expect(dienst('mod_assign_get_submissions', 'mod_assign_get_submissions', {}), isFalse);
    const u = 'core_courseformat_update_course';
    expect(dienst(u, u, {'action': 'cm_move', 'courseid': 43, 'ids': [9], 'targetsectionid': 5}), isTrue);
    expect(dienst(u, u, {'action': 'section_add', 'courseid': 43, 'ids': []}), isTrue);
    expect(dienst(u, u, {'action': 'cm_duplicate', 'courseid': 43, 'ids': [9]}), isTrue);
    expect(dienst(u, u, {'action': 'section_duplicate', 'courseid': 43, 'ids': [5]}), isTrue);
    expect(dienst(u, u, {'action': 'cm_stealth', 'courseid': 43, 'ids': [9]}), isFalse, reason: 'nicht gemessen');
    expect(dienst(u, u, {'action': 'cm_hide', 'courseid': 43}), isFalse, reason: 'ohne ids');
    expect(dienst(u, u, {'action': 'cm_hide', 'courseid': 43, 'ids': [9], 'userid': 5}), isFalse);
    const r = 'core_course_get_recent_courses';
    expect(dienst(r, r, {'userid': 5, 'limit': 5}), isFalse,
        reason: 'eigene id noch unbekannt: fremde Kurslisten nie');
    const m = 'core_course_get_enrolled_courses_by_timeline_classification';
    expect(dienst(m, m, {'classification': 'all', 'limit': 0, 'offset': 0, 'sort': 'fullname'}), isTrue);
    expect(dienst(m, m, {'classification': 'all', 'userid': 5}), isFalse);
    expect(z.erlaubt('POST', Uri.parse('https://m.example/lib/ajax/service.php?sesskey=x&info=$s')),
        isFalse,
        reason: 'ohne Rumpf');
  });

  test('Zeilenvergleich', () {
    final v = zeilenVergleich('a\nb\nc\nd\ne\nf\ng\nh', 'a\nb\nc\nX\ne\nf\ng\nh\ni', kontext: 1);
    expect(v.weg, 1);
    expect(v.neu, 2);
    expect(v.zeilen.map((z) => '${z.art.name}:${z.text}').toList(), [
      'ausgelassen:… 2 unveränderte Zeile(n) …',
      'gleich:c', 'weg:d', 'neu:X', 'gleich:e',
      'ausgelassen:… 2 unveränderte Zeile(n) …',
      'gleich:h', 'neu:i',
    ]);
    expect(zeilenVergleich('a\nb', 'a\nb').gleich, isTrue);
  });

  test('Formular wie ein Browser: Reihenfolge, Kontrollkästchen, Auswahl', () {
    final form = html_parser.parse('''<form class="mform">
      <input type="hidden" name="printintro" value="0"><input type="checkbox" name="printintro" value="1">
      <input type="hidden" name="printlastmodified" value="0"><input type="checkbox" name="printlastmodified" value="1" checked>
      <select name="visible"><option value="1" selected>Anzeigen</option><option value="0">Verbergen</option></select>
      <select name="tags[]" multiple><option value="a">a</option></select>
      <textarea name="page[text]">&lt;p&gt;Hallo&lt;/p&gt;</textarea>
      <input type="radio" name="completion" value="0" checked><input type="radio" name="completion" value="1">
      <input type="text" name="aus" value="x" disabled>
      <input type="submit" name="submitbutton" value="Speichern">
    </form>''').querySelector('form')!;
    final f = formularFelder(form);
    expect(f.map((e) => '${e.key}=${e.value}').toList(), [
      'printintro=0',
      'printlastmodified=0',
      'printlastmodified=1',
      'visible=1',
      'page[text]=<p>Hallo</p>',
      'completion=0',
    ]);
    setze(f, 'printlastmodified', '0');
    setze(f, 'visible', '0');
    expect(f.where((e) => e.key == 'printlastmodified').last.value, '0');
    expect(wertIn(f, 'visible'), '0');
  });
}
