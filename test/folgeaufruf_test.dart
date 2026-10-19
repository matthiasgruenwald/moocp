// Befund 9 (Review, Ticket #18): Zeitlimit- und Startantworten nennen die
// Vorgangsnummer und genau einen Folgeaufruf; die Übersicht nennt ihn ebenfalls.
// Der Stillstandstext behauptet nicht „Moodle meldet ...", wenn nur Angaben fehlen.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/moodle/sicherung.dart';
import 'package:moocp/moodle/sicherung_regeln.dart';
import 'package:moocp/moodle/wiederherstellung_regeln.dart';
import 'package:moocp/protokoll.dart';

void main() {
  late Directory ordner;
  setUp(() => ordner = Directory.systemTemp.createTempSync('folgeaufruf_'));
  tearDown(() => ordner.deleteSync(recursive: true));

  test('laufende Sicherung: Übersicht nennt Nummer und sicherung_status als Folgeaufruf', () async {
    final vg = Vorgaenge(ordner.path);
    final v = await vg.neu(kurs: 1, cmid: 2, datei: 'a.mbz');
    await vg.aktualisieren(v, stand: SicherungStand.laufend);

    final text = await sicherungStatus(MoodleZugang(Protokoll()), vg, id: v.id);

    expect(text, contains('Folgeaufruf: sicherung_status ${v.id}'));
    expect(text, isNot(contains('Folgeaufruf: wiederherstellung_status')));
  });

  test('laufende Wiederherstellung: Folgeaufruf ist wiederherstellung_status mit der Nummer', () async {
    final vg = Vorgaenge(ordner.path);
    final v = await vg.neuWiederherstellung(kurs: 1, datei: 'a.mbz');
    await vg.aktualisieren(v, wiederherstellung: WiederherstellungStand.laufend);

    // Die Übersicht ohne Nummer listet die letzten Vorgänge über _zeile.
    final text = await sicherungStatus(MoodleZugang(Protokoll()), vg);

    expect(text, contains('Folgeaufruf: wiederherstellung_status ${v.id}'));
  });

  test('abgeschlossener Vorgang nennt keinen Folgeaufruf mehr', () async {
    final vg = Vorgaenge(ordner.path);
    final v = await vg.neu(kurs: 1, cmid: 2, datei: 'a.mbz');
    await vg.aktualisieren(v, stand: SicherungStand.fehlgeschlagen);

    final text = await sicherungStatus(MoodleZugang(Protokoll()), vg, id: v.id);

    expect(text, isNot(contains('Folgeaufruf')));
  });

  test('Zeitlimit mit bekannter Nummer nennt die Nummer und genau einen Folgeaufruf', () {
    final text = laufText('Die Sicherung', 'abc', 'sicherung_status');
    expect(text, contains('abc'));
    expect(RegExp('sicherung_status').allMatches(text).length, 1);
  });

  test('Zeitlimit ohne Nummer behauptet keine Nummer und keinen Start', () {
    final text = laufText('Die Wiederherstellung', null, 'wiederherstellung_status');
    expect(text, contains('noch nicht fest'));
    expect(text, isNot(contains('wiederherstellung_status')), reason: 'ohne Nummer gibt es keinen Folgeaufruf');
  });

  test('Stillstand, bei dem nur Angaben fehlen, behauptet nicht „Moodle meldet ..."', () {
    final text = stillstandText(
      nummer: 'n1',
      werkzeug: 'sicherung_status',
      fortschritt: null,
      seit: const Duration(minutes: 20),
      ursachen: 'Cron läuft nicht.',
    );
    expect(text, isNot(contains('Moodle meldet')));
    expect(text, contains('nicht belegt'));
  });
}
