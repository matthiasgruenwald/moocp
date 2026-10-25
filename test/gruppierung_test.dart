// Gruppierungen lesen und anlegen -- an einem nachgebauten Moodle, das nur die
// Gruppenseiten kennt. Ob die echten Seiten so aussehen, ist auf einer Instanz
// zu messen (TODO.md); hier steht, was die App aus solchen Seiten macht.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:moocp/freigabe.dart';
import 'package:moocp/moodle/gruppierung.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/moodle/sperrliste.dart';
import 'package:moocp/protokoll.dart';

class GruppenMoodle {
  late HttpServer server;
  final gruppen = <int, String>{1: 'ZZ Gruppe A', 2: 'ZZ Gruppe C'};
  final gruppierungen = <int, ({String name, Set<int> gruppen})>{
    10: (name: 'ZZ Alt', gruppen: {2}),
  };
  var naechste = 20;
  var gruppenAngelegt = 0;
  var gruppierungenAngelegt = 0;
  var zuordnungen = 0;
  /// Moodle hängt die Mitgliederzahl an den Namen (nicht auf jeder Seite).
  var mitZahl = false;
  Uri get basis => Uri.parse('http://127.0.0.1:${server.port}');

  String _name(int id) => mitZahl ? '${gruppen[id]} (0)' : gruppen[id]!;

  Future<void> starten() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final body = await utf8.decoder.bind(r).join();
      final post = r.method == 'POST';
      final f = post ? Uri.splitQueryString(body) : <String, String>{};
      final raw = post ? Uri(query: body).query.split('&') : <String>[];
      String seite(String t) => '<script>M.cfg = {"sesskey":"sk"};</script>$t';
      Future<void> umleiten(String ziel) async {
        r.response.redirect(Uri.parse(ziel), status: 303);
        await r.response.close();
      }

      String antwort;
      final q = r.uri.queryParameters;
      switch (r.uri.path) {
        case '/login/index.php':
          if (post || q.containsKey('testsession')) {
            await umleiten(post ? '/login/index.php?testsession=1' : '/my/');
            return;
          }
          r.response.cookies.add(Cookie('MoodleSession', 'test'));
          antwort = r.cookies.isNotEmpty
              ? seite('Angemeldet')
              : '<form><input name="logintoken" value="tok"></form>';
        case '/lib/ajax/service.php':
          antwort = jsonEncode([
            {
              'error': false,
              'data': {
                'courses': [
                  {'id': 12, 'fullname': 'ZZ Kurs', 'shortname': 'ZZ'},
                ],
              },
            },
          ]);
        case '/group/groupings.php':
          antwort = seite(
            '<a href="/group/grouping.php?courseid=12">Neu</a>'
            '<a href="/group/index.php?id=12">Gruppen</a>'
            '${[for (final e in gruppierungen.entries) '<a href="/group/grouping.php?id=${e.key}">${e.value.name}</a>'
                '<a href="/group/assign.php?id=${e.key}">Gruppen zuordnen</a>'
                '<a href="/group/grouping.php?id=${e.key}&amp;delete=1">Löschen</a>'].join()}',
          );
        case '/group/grouping.php':
          if (post) {
            gruppierungen[naechste++] = (name: f['name']!, gruppen: {});
            gruppierungenAngelegt++;
            await umleiten('/group/groupings.php?id=12');
            return;
          }
          final id = int.tryParse(q['id'] ?? '');
          antwort = seite(
            '<form class="mform" action="/group/grouping.php?courseid=12" method="post">'
            '<input type="hidden" name="_qf__grouping_form" value="1"><input type="hidden" name="sesskey" value="sk">'
            '<input type="hidden" name="id" value="${id ?? 0}"><input type="hidden" name="courseid" value="12">'
            '<input type="text" name="name" value="${id == null ? '' : gruppierungen[id]!.name}">'
            '<input type="submit" name="submitbutton" value="Änderungen speichern"></form>',
          );
        case '/group/group.php':
          if (post) {
            gruppen[naechste++] = f['name']!;
            gruppenAngelegt++;
            await umleiten('/group/index.php?id=12');
            return;
          }
          antwort = seite(
            '<form class="mform" action="/group/group.php?courseid=12" method="post">'
            '<input type="hidden" name="_qf__group_form" value="1"><input type="hidden" name="sesskey" value="sk">'
            '<input type="hidden" name="id" value="0"><input type="hidden" name="courseid" value="12">'
            '<input type="text" name="name" value=""><textarea name="description_editor[text]"></textarea>'
            '<input type="submit" name="submitbutton" value="Änderungen speichern"></form>',
          );
        case '/group/assign.php':
          final id = int.parse(q['id']!);
          if (post) {
            for (final e in raw) {
              final kv = e.split('=');
              if (Uri.decodeQueryComponent(kv[0]) == 'addselect[]') {
                gruppierungen[id]!.gruppen.add(int.parse(kv[1]));
              }
            }
            zuordnungen++;
          }
          final drin = gruppierungen[id]!.gruppen;
          antwort = seite(
            '<form id="assignform" method="post" action="">'
            '<input type="hidden" name="sesskey" value="sk">'
            '<select name="removeselect[]" multiple>${[for (final g in drin) '<option value="$g">${_name(g)}</option>'].join()}</select>'
            '<select name="addselect[]" multiple>${[for (final g in gruppen.keys.where((g) => !drin.contains(g))) '<option value="$g">${_name(g)}</option>'].join()}</select>'
            '<input name="add" type="submit" value="Hinzufügen"><input name="remove" type="submit" value="Entfernen"></form>',
          );
        default:
          antwort = seite('ZZ Kurs');
      }
      r.response.headers.contentType = ContentType.html;
      r.response.write(antwort);
      await r.response.close();
    });
  }
}

void main() {
  late GruppenMoodle extern;
  late MoodleZugang moodle;
  late Freigaben freigaben;

  setUp(() async {
    extern = GruppenMoodle();
    await extern.starten();
    freigaben = Freigaben(Protokoll(), stufe: Bestaetigungen.alle, frist: const Duration(milliseconds: 200));
    moodle = await MoodleZugang.fuerTest(Protokoll(), extern.basis, benutzer: 'e.mustermann', passwort: 'erfunden');
  });
  tearDown(() async {
    moodle.abmelden();
    await extern.server.close(force: true);
  });

  /// Der Test spielt die Lehrkraft: ein Klick, sobald der Dialog steht.
  void entscheide(bool ja) {
    freigaben.addListener(() {
      if (freigaben.aktuell != null) scheduleMicrotask(() => freigaben.entscheiden(ja));
    });
  }

  group('Positivliste', () {
    final z = MoodleZugang(Protokoll());
    bool get(String a) => z.erlaubt('GET', Uri.parse('https://m.example$a'));
    bool post(String a, Felder f) => z.erlaubt('POST', Uri.parse('https://m.example$a'), f);
    Felder felder(Map<String, String> m) => [for (final e in m.entries) MapEntry(e.key, e.value)];

    test('die Verwaltungsseiten sind lesbar, die Mitgliederseiten bleiben gesperrt', () {
      for (final a in [
        '/group/groupings.php?id=12',
        '/group/grouping.php?id=7',
        '/group/grouping.php?courseid=12',
        '/group/group.php?courseid=12',
        '/group/assign.php?id=7',
      ]) {
        expect(get(a), isTrue, reason: a);
        expect(gesperrt(Uri.parse('https://m.example$a')), isFalse, reason: a);
      }
      for (final a in ['/group/index.php?id=12', '/group/members.php?group=3', '/group/overview.php?id=12']) {
        expect(gesperrt(Uri.parse('https://m.example$a')), isTrue, reason: a);
      }
      expect(get('/group/group.php?id=3'), isFalse, reason: 'bestehende Gruppe bearbeiten gibt es nicht');
      expect(get('/group/delete.php?courseid=12&groupid=3'), isFalse);
    });

    test('geschrieben wird nur Neues und das Hinzufügen', () {
      final gruppe = {'_qf__group_form': '1', 'id': '0', 'courseid': '12', 'name': 'ZZ'};
      expect(post('/group/group.php?courseid=12', felder(gruppe)), isTrue);
      expect(post('/group/group.php?courseid=12', felder({...gruppe, 'id': ''})), isTrue, reason: 'leer heißt neu');
      expect(post('/group/group.php?courseid=12', felder({...gruppe, 'id': '5'})), isFalse);
      expect(post('/group/group.php?courseid=12', felder({...gruppe}..remove('id'))), isFalse);
      final gr = {'_qf__grouping_form': '1', 'id': '0', 'courseid': '12', 'name': 'ZZ'};
      expect(post('/group/grouping.php?courseid=12', felder(gr)), isTrue);
      expect(post('/group/grouping.php?courseid=12', felder({...gr, 'id': ''})), isTrue);
      expect(post('/group/grouping.php?courseid=12', felder({...gr, 'id': '5'})), isFalse);
      final zu = [
        const MapEntry('sesskey', 'sk'),
        const MapEntry('addselect[]', '4'),
        const MapEntry('add', '1'),
      ];
      expect(post('/group/assign.php?id=10', zu), isTrue);
      expect(post('/group/assign.php', zu), isFalse, reason: 'ohne Nummer in der Adresse');
      expect(post('/group/assign.php?id=10', [...zu, const MapEntry('removeselect[]', '4')]), isFalse);
      expect(post('/group/assign.php?id=10', [...zu, const MapEntry('remove', '1')]), isFalse);
      expect(post('/group/assign.php?id=10', [...zu, const MapEntry('addselect[]', 'g7_1')]), isTrue);
      expect(post('/group/assign.php?id=10', [...zu, const MapEntry('addselect[]', '1;2')]), isFalse);
      expect(post('/group/assign.php?id=10', [...zu, const MapEntry('addselect[]', '')]), isFalse);
      expect(post('/group/delete.php', felder({'confirm': '1'})), isFalse);
    });
  });

  test('Lesen zeigt Gruppierungen mit den Namen ihrer Gruppen, ohne Löschverweise zu verfolgen', () async {
    final gs = await gruppierungenLesen(moodle, 12);
    expect(gs, hasLength(1));
    expect(gs.single.name, 'ZZ Alt');
    expect(gs.single.gruppen, ['ZZ Gruppe C']);
    final text = await gruppierungenLesenText(moodle, 12);
    expect(text, contains('„ZZ Alt" (id 10): ZZ Gruppe C'));
    expect(text, contains('Kurs 12 „ZZ Kurs"'));
    expect(extern.gruppierungen, hasLength(1));
  });

  for (final mitZahl in [false, true]) {
    test('Anlegen: Gruppierung, fehlende Gruppe neu, vorhandene nur zugeordnet (Mitgliederzahl am Namen: $mitZahl)',
        () async {
      extern.mitZahl = mitZahl;
      entscheide(true);
      final text = await gruppierungAnlegen(moodle, freigaben,
          kurs: 12, name: 'ZZ Neu', gruppen: ['ZZ Gruppe A', 'ZZ Gruppe B', 'zz gruppe a']);
      expect(text, contains('verified: true'), reason: text);
      expect(text, contains('Neu angelegte Gruppen: ZZ Gruppe B'));
      expect(extern.gruppierungenAngelegt, 1);
      expect(extern.gruppenAngelegt, 1, reason: 'doppelte Namen und vorhandene Gruppen legen nichts an');
      expect(extern.zuordnungen, 1);
      final neu = extern.gruppierungen.values.singleWhere((g) => g.name == 'ZZ Neu');
      expect({for (final g in neu.gruppen) extern.gruppen[g]}, {'ZZ Gruppe A', 'ZZ Gruppe B'});
      expect(extern.gruppierungen.values.singleWhere((g) => g.name == 'ZZ Alt').gruppen, {2});
    });
  }

  test('Anlegen ohne Gruppen legt nur die Gruppierung an', () async {
    entscheide(true);
    final text = await gruppierungAnlegen(moodle, freigaben, kurs: 12, name: 'ZZ Leer');
    expect(text, contains('verified: true'));
    expect(extern.gruppenAngelegt, 0);
    expect(extern.zuordnungen, 0);
  });

  test('Abgelehnt: nichts wird angelegt', () async {
    entscheide(false);
    final text = await gruppierungAnlegen(moodle, freigaben, kurs: 12, name: 'ZZ Neu', gruppen: ['ZZ Gruppe B']);
    expect(text, startsWith('Nicht angelegt'));
    expect(extern.gruppierungenAngelegt + extern.gruppenAngelegt + extern.zuordnungen, 0);
  });

  test('Die Freigabe nennt Gruppierung, Gruppen und was neu entsteht', () async {
    String? titel;
    List<String>? punkte;
    freigaben.addListener(() {
      final a = freigaben.aktuell;
      if (a == null) return;
      titel = a.titel;
      punkte = a.punkte;
      scheduleMicrotask(() => freigaben.entscheiden(false));
    });
    await gruppierungAnlegen(moodle, freigaben, kurs: 12, name: 'ZZ Neu', gruppen: ['ZZ Gruppe A', 'ZZ Gruppe B']);
    expect(titel, 'Gruppierung anlegen?');
    expect(punkte!.join('\n'), allOf(contains('„ZZ Neu"'), contains('ZZ Gruppe A, ZZ Gruppe B'), contains('Neu angelegt werden die Gruppen: ZZ Gruppe B')));
  });

  test('Eine bestehende Gruppierung bekommt nur fehlende Gruppen dazu, nichts wird entfernt', () async {
    entscheide(true);
    final text = await gruppierungAnlegen(moodle, freigaben,
        kurs: 12, name: 'zz alt', gruppen: ['ZZ Gruppe A', 'ZZ Gruppe C']);
    expect(text, startsWith('Ergänzt'), reason: text);
    expect(text, contains('verified: true'));
    expect(extern.gruppierungenAngelegt, 0);
    expect(extern.gruppenAngelegt, 0);
    expect(extern.gruppierungen[10]!.gruppen, {1, 2});
  });

  test('Fehlt der bestehenden Gruppierung nichts, geschieht nichts und niemand wird gefragt', () async {
    var gefragt = false;
    freigaben.addListener(() => gefragt = true);
    final text = await gruppierungAnlegen(moodle, freigaben, kurs: 12, name: 'ZZ Alt', gruppen: ['ZZ Gruppe C']);
    expect(text, startsWith('Unverändert'));
    expect(text, contains('verified: true'));
    expect(gefragt, isFalse);
    expect(extern.zuordnungen, 0);
  });

  test('Nach einem Abbruch mitten im Anlegen führt ein zweiter Aufruf es zu Ende', () async {
    entscheide(true);
    extern.gruppierungen[30] = (name: 'ZZ Halb', gruppen: {});
    extern.gruppen[31] = 'ZZ Gruppe H1';
    final text = await gruppierungAnlegen(moodle, freigaben,
        kurs: 12, name: 'ZZ Halb', gruppen: ['ZZ Gruppe H1', 'ZZ Gruppe H2']);
    expect(text, contains('verified: true'), reason: text);
    expect(extern.gruppierungenAngelegt, 0);
    expect(extern.gruppenAngelegt, 1);
    expect({for (final g in extern.gruppierungen[30]!.gruppen) extern.gruppen[g]}, {'ZZ Gruppe H1', 'ZZ Gruppe H2'});
  });

  group('Rückfrage statt stillem Abbruch', () {
    final form = html_parser.parse('<form><select name="groupingid">'
        '<option value="0">Keine</option><option value="216">Expertengruppierung</option>'
        '<option value="218">Testersatzgruppierung</option></select></form>').querySelector('form')!;

    test('eine vorhandene Gruppierung, nach Name oder Nummer, geht durch', () {
      gruppierungPruefen(form, 'Testersatzgruppierung', 12);
      gruppierungPruefen(form, 'testersatzgruppierung', 12);
      gruppierungPruefen(form, '216', 12);
      gruppierungPruefen(form, 'Keine', 12);
      gruppierungPruefen(form, null, 12);
    });

    test('eine fehlende Gruppierung wird zur Rückfrage mit dem Weg weiter', () {
      expect(
        () => gruppierungPruefen(form, 'Auseinanderbau', 1835),
        throwsA(
          isA<GruppierungFehlt>().having(
            (e) => e.meldung,
            'meldung',
            allOf(
              contains('Rückfrage an die Lehrkraft'),
              contains('„Auseinanderbau" gibt es in Kurs 1835 nicht'),
              contains('Expertengruppierung, Testersatzgruppierung'),
              contains('gruppierungen_lesen'),
              contains('gruppierung_anlegen'),
              contains('Nichts gespeichert'),
            ),
          ),
        ),
      );
    });
  });
}
