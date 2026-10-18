import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/sicherung.dart';
import 'package:moocp/moodle/sicherung_regeln.dart';

void main() {
  late Directory folder;
  setUp(() => folder = Directory.systemTemp.createTempSync('vorgaenge-'));
  tearDown(() => folder.deleteSync(recursive: true));

  test('zwei zuvor gelesene Speicher verlieren weder Neuanlagen noch Statusänderungen', () async {
    final a = Vorgaenge(folder.path, profilKennung: 'a');
    final b = Vorgaenge(folder.path, profilKennung: 'b');
    await Future.wait([a.alle(), b.alle()]);
    final one = await a.neu(kurs: 12, cmid: 7, datei: 'a.mbz');
    final two = await b.neu(kurs: 12, cmid: 8, datei: 'b.mbz');
    await Future.wait([
      a.aktualisieren(one, stand: SicherungStand.unklar),
      b.neu(kurs: 12, cmid: 9, datei: 'c.mbz'),
      a.neu(kurs: 12, cmid: 10, datei: 'd.mbz'),
    ]);
    final restarted = Vorgaenge(folder.path);
    expect((await restarted.alle()).map((v) => v.datei).toSet(), {'a.mbz', 'b.mbz', 'c.mbz', 'd.mbz'});
    expect((await restarted.finde(one.id))!.stand, SicherungStand.unklar);
    expect(await a.finde(two.id), isNull);
    expect(await b.finde(one.id), isNull);
  });

  test('gleichzeitiges erstes Anlegen bleibt nach erneutem Laden vollständig', () async {
    final handles = List.generate(8, (_) => Vorgaenge(folder.path));
    final created = await Future.wait([
      for (var i = 0; i < handles.length; i++) handles[i].neu(kurs: 12, cmid: i, datei: '$i.mbz'),
    ]);
    expect((await Vorgaenge(folder.path).alle()).map((v) => v.id).toSet(), created.map((v) => v.id).toSet());
  });
}
