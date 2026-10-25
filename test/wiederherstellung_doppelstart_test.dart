// Doppelstart-Schutz der Wiederherstellung : Eine Datei für
// denselben Kurs und Zielweg wird nicht ein zweites Mal gestartet, solange ein
// Vorgang offen ist. Ohne Netz; der Speicher läuft über eine Datei im Temp-Ordner.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/sicherung.dart';
import 'package:moocp/moodle/wiederherstellung_regeln.dart';

DoppelstartEintrag _e(String id, WiederherstellungStand stand,
        {String fp = 'fp', String? von, int kurs = 42}) =>
    (id: id, fingerabdruck: fp, wiederholungVon: von, stand: stand, kurs: kurs);

void main() {
  group('Fingerabdruck', () {
    test('gleicher Inhalt, Kurs und Weg ergeben denselben Schlüssel', () {
      expect(
        fingerabdruck([1, 2, 3], instanz: 'profil-a', kurs: 42, weg: Zielweg.anderKursErsetzen),
        fingerabdruck([1, 2, 3], instanz: 'profil-a', kurs: 42, weg: Zielweg.anderKursErsetzen),
      );
    });

    test('anderer Inhalt, anderer Kurs oder anderer Weg ergeben einen anderen Schlüssel', () {
      final basis = fingerabdruck([1, 2, 3], instanz: 'profil-a', kurs: 42, weg: Zielweg.anderKursErsetzen);
      expect(fingerabdruck([1, 2, 4], instanz: 'profil-a', kurs: 42, weg: Zielweg.anderKursErsetzen), isNot(basis));
      expect(fingerabdruck([1, 2, 3], instanz: 'profil-a', kurs: 43, weg: Zielweg.anderKursErsetzen), isNot(basis));
      expect(fingerabdruck([1, 2, 3], instanz: 'profil-a', kurs: 42, weg: Zielweg.anderKursVerschmelzen), isNot(basis));
    });

    test('dieselbe Datei auf zwei Profilen ergibt verschiedene Schlüssel (Befund 3)', () {
      expect(
        fingerabdruck([1, 2, 3], instanz: 'profil-a', kurs: 42, weg: Zielweg.anderKursErsetzen),
        isNot(fingerabdruck([1, 2, 3], instanz: 'profil-b', kurs: 42, weg: Zielweg.anderKursErsetzen)),
      );
    });
  });

  group('doppelstartSperre', () {
    test('ein offener Vorgang sperrt die Wiederholung (Zeitlimit, Neustart)', () {
      for (final stand in [
        WiederherstellungStand.anstehend,
        WiederherstellungStand.hochgeladen,
        WiederherstellungStand.laufend,
        WiederherstellungStand.unklar,
        WiederherstellungStand.fertig,
      ]) {
        expect(doppelstartSperre([_e('a', stand)], fingerabdruck: 'fp', wiederholungVon: null, kurs: 42), 'a',
            reason: stand.text);
      }
    });

    test('fehlgeschlagen vor dem Start sperrt bei bestehendem Kurs nicht', () {
      expect(
        doppelstartSperre([_e('a', WiederherstellungStand.fehlgeschlagen)],
            fingerabdruck: 'fp', wiederholungVon: null, kurs: 42),
        isNull,
      );
    });

    test('fehlgeschlagen gilt nur mit Beleg (Prozess beendet, nichts Neues im Kurs) und sperrt dann nicht', () {
      expect(
        doppelstartSperre([_e('a', WiederherstellungStand.fehlgeschlagen)],
            fingerabdruck: 'fp', wiederholungVon: null, kurs: 42),
        isNull,
      );
    });

    test('fehlgeschlagen bei neuem Kurs sperrt, weil ein Platzhalterkurs bleiben kann', () {
      expect(
        doppelstartSperre([_e('a', WiederherstellungStand.fehlgeschlagen, kurs: 0)],
            fingerabdruck: 'fp', wiederholungVon: null, kurs: 0),
        'a',
      );
    });

    test('ein anderer Fingerabdruck sperrt nicht', () {
      expect(
        doppelstartSperre([_e('a', WiederherstellungStand.laufend, fp: 'andere')],
            fingerabdruck: 'fp', wiederholungVon: null, kurs: 42),
        isNull,
      );
    });

    test('keine Einträge: keine Sperre', () {
      expect(doppelstartSperre(const [], fingerabdruck: 'fp', wiederholungVon: null, kurs: 42), isNull);
    });

    test('Wiederholung mit dem sperrenden Vorgang wird zugelassen', () {
      expect(
        doppelstartSperre([_e('a', WiederherstellungStand.unklar)],
            fingerabdruck: 'fp', wiederholungVon: 'a', kurs: 42),
        isNull,
      );
    });

    test('Wiederholung mit einer fremden oder unbekannten Nummer bleibt gesperrt', () {
      expect(
        doppelstartSperre([_e('a', WiederherstellungStand.unklar)],
            fingerabdruck: 'fp', wiederholungVon: 'fremd', kurs: 42),
        'a',
      );
    });

    test('vor Start gescheiterte Wiederholung entsperrt unklaren Vorgänger nicht', () {
      // a ist unklar, b ist seine Wiederholung und fehlgeschlagen vor dem Start.
      final alle = [
        _e('a', WiederherstellungStand.unklar),
        _e('b', WiederherstellungStand.fehlgeschlagen, von: 'a'),
      ];
      expect(doppelstartSperre(alle, fingerabdruck: 'fp', wiederholungVon: null, kurs: 42), 'a');
      expect(doppelstartSperre(alle, fingerabdruck: 'fp', wiederholungVon: 'a', kurs: 42), isNull);
      expect(doppelstartSperre(alle, fingerabdruck: 'fp', wiederholungVon: 'b', kurs: 42), 'a');
    });

    test('mehrere gescheiterte Wiederholungen erhalten den letzten sperrenden Kopf', () {
      final alle = [
        _e('a', WiederherstellungStand.unklar),
        _e('b', WiederherstellungStand.unklar, von: 'a'),
        _e('c', WiederherstellungStand.fehlgeschlagen, von: 'b'),
        _e('d', WiederherstellungStand.fehlgeschlagen, von: 'c'),
      ];
      expect(doppelstartSperre(alle, fingerabdruck: 'fp', wiederholungVon: null, kurs: 42), 'b');
      expect(doppelstartSperre(alle, fingerabdruck: 'fp', wiederholungVon: 'b', kurs: 42), isNull);
    });

    test('gestarteter Nachfolger überholt auch eine gescheiterte Zwischenwiederholung', () {
      final alle = [
        _e('a', WiederherstellungStand.unklar),
        _e('b', WiederherstellungStand.fehlgeschlagen, von: 'a'),
        _e('c', WiederherstellungStand.laufend, von: 'b'),
      ];
      expect(doppelstartSperre(alle, fingerabdruck: 'fp', wiederholungVon: null, kurs: 42), 'c');
    });

    test('eine Wiederholung mit einer überholten Nummer bleibt gesperrt, der Kopf wird genannt', () {
      final alle = [
        _e('a', WiederherstellungStand.unklar),
        _e('b', WiederherstellungStand.unklar, von: 'a'),
      ];
      expect(doppelstartSperre(alle, fingerabdruck: 'fp', wiederholungVon: 'a', kurs: 42), 'b');
    });
  });

  group('Vorgang-Speicher', () {
    late Directory ordner;
    setUp(() => ordner = Directory.systemTemp.createTempSync('doppelstart'));
    tearDown(() => ordner.deleteSync(recursive: true));

    test('Fingerabdruck und Wiederholung überstehen den Neustart', () async {
      final vg = Vorgaenge(ordner.path);
      final v = await vg.neuWiederherstellung(
          kurs: 42, datei: 'x.mbz', fingerabdruck: 'fp', wiederholungVon: 'alt');

      final nach = Vorgaenge(ordner.path);
      final gespeichert = await nach.finde(v.id);

      expect(gespeichert, isNotNull);
      expect(gespeichert!.fingerabdruck, 'fp');
      expect(gespeichert.wiederholungVon, 'alt');
    });

    test('Dateinamen spielen keine Rolle: der Eintrag trägt nur den Inhaltsschlüssel', () async {
      final vg = Vorgaenge(ordner.path);
      final v = await vg.neuWiederherstellung(kurs: 42, datei: 'umbenannt.mbz', fingerabdruck: 'fp');

      final eintraege = doppelstartEintraege(await vg.alle());

      expect(eintraege.single.id, v.id);
      expect(eintraege.single.fingerabdruck, 'fp');
    });
  });
}
