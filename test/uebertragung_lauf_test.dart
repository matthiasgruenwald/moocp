// Tests der Übertragung in einem Auftrag Prüfung der Ziele,
// Wiederholungsschutz, Protokoll uebertragungen.json und der Ablauf je Ziel.
// Moodle wird durch Fakes ersetzt. Nur erfundene Daten (A11): Kurse 12, 34, 56.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/wiederherstellung_regeln.dart';
import 'package:moocp/uebertragung_lauf.dart';

PlanZiel ziel(int kurs, {Zielweg weg = Zielweg.anderKursVerschmelzen}) =>
    PlanZiel(kurs: kurs, name: 'Kurs $kurs', weg: weg);

UebertragungsEintrag eintrag(
  String datei,
  int kurs, {
  ZielStand stand = ZielStand.fertig,
  int? quellkurs,
  String profil = 'zielprofil',
  String? vorgang,
}) =>
    UebertragungsEintrag(
      datei: datei,
      profil: profil,
      kurs: kurs,
      stand: stand,
      zeit: DateTime(2026, 10, 18, 9),
      quellkurs: quellkurs,
      vorgang: vorgang,
    );

void main() {
  group('pruefeZiele', () {
    test('ohne Ziele eine Rückfrage', () {
      expect(pruefeZiele([]), isA<PlanungRueckfrage>());
    });

    test('gültige Ziele werden mit aufgelöstem Weg geprüft', () {
      final p = pruefeZiele([
        const ZielAngabe(kurs: 12, name: 'Kurs 12', weg: 'anderer_kurs_verschmelzen'),
        const ZielAngabe(kurs: 34, name: 'Kurs 34', weg: 'aktueller_kurs_verschmelzen'),
      ], quellkurs: 56);
      expect(p, isA<PlanungOk>());
      final ziele = (p as PlanungOk).ziele;
      expect(ziele.map((z) => z.kurs), [12, 34]);
      expect(ziele.first.weg, Zielweg.anderKursVerschmelzen);
    });

    test('fehlender Weg wird nicht geraten', () {
      final p = pruefeZiele([const ZielAngabe(kurs: 12, name: 'Kurs 12')]);
      expect(p, isA<PlanungRueckfrage>());
      expect((p as PlanungRueckfrage).text, contains('Nichts wird geraten'));
    });

    test('unbekannter Weg ergibt eine Rückfrage', () {
      final p = pruefeZiele([const ZielAngabe(kurs: 12, name: 'Kurs 12', weg: 'irgendwie')]);
      expect(p, isA<PlanungRueckfrage>());
    });

    test('neuer_kurs gehört nicht in uebertragen', () {
      final p = pruefeZiele([const ZielAngabe(kurs: 12, name: 'Kurs 12', weg: 'neuer_kurs')]);
      expect(p, isA<PlanungRueckfrage>());
      expect((p as PlanungRueckfrage).text, contains('wiederherstellen_datei'));
    });

    test('doppelte Kursnummer ergibt eine Rückfrage', () {
      final p = pruefeZiele([
        const ZielAngabe(kurs: 12, name: 'Kurs 12', weg: 'anderer_kurs_verschmelzen'),
        const ZielAngabe(kurs: 12, name: 'Kurs 12', weg: 'aktueller_kurs_verschmelzen'),
      ]);
      expect(p, isA<PlanungRueckfrage>());
    });

    test('der Quellkurs darf kein Ziel sein, auch nicht mit einem löschenden Weg', () {
      final p = pruefeZiele(
        [const ZielAngabe(kurs: 56, name: 'Kurs 56', weg: 'anderer_kurs_ersetzen')],
        quellkurs: 56,
      );
      expect(p, isA<PlanungRueckfrage>());
    });

    test('leerer Name ergibt eine Rückfrage', () {
      final p = pruefeZiele([const ZielAngabe(kurs: 12, name: ' ', weg: 'anderer_kurs_verschmelzen')]);
      expect(p, isA<PlanungRueckfrage>());
    });

    test('ungültige Kursnummer ergibt eine Rückfrage', () {
      final p = pruefeZiele([const ZielAngabe(kurs: 0, name: 'Kurs 0', weg: 'anderer_kurs_verschmelzen')]);
      expect(p, isA<PlanungRueckfrage>());
    });

    test('löschender Weg ohne loeschend: true ist eine Rückfrage', () {
      for (final weg in ['aktueller_kurs_ersetzen', 'anderer_kurs_ersetzen']) {
        final p = pruefeZiele([ZielAngabe(kurs: 12, name: 'Kurs 12', weg: weg)]);
        expect(p, isA<PlanungRueckfrage>(), reason: weg);
        expect((p as PlanungRueckfrage).text, contains('loeschend: true'), reason: weg);
      }
    });

    test('löschender Weg mit loeschend: true wird geprüft', () {
      final p = pruefeZiele([
        const ZielAngabe(kurs: 12, name: 'Kurs 12', weg: 'anderer_kurs_ersetzen', loeschend: true),
      ], quellkurs: 56);
      expect(p, isA<PlanungOk>());
      expect((p as PlanungOk).ziele.single.weg, Zielweg.anderKursErsetzen);
    });

    test('loeschend: true bei einem nicht löschenden Weg ist eine Rückfrage', () {
      final p = pruefeZiele([
        const ZielAngabe(kurs: 12, name: 'Kurs 12', weg: 'anderer_kurs_verschmelzen', loeschend: true),
      ]);
      expect(p, isA<PlanungRueckfrage>());
    });
  });

  group('wiederholungsRueckfrage', () {
    test('dieselbe Datei und dasselbe Ziel: Rückfrage', () {
      final protokoll = [eintrag('a.mbz', 12, vorgang: '7')];
      final r = wiederholungsRueckfrage(protokoll,
          profil: 'zielprofil', kurs: 12, datei: 'a.mbz');
      expect(r, isNotNull);
      expect(r, contains('Nichts wird erneut importiert'));
      expect(r, contains('Nummer 7'));
      expect(r, contains('wiederherstellen_datei mit wiederholung_von=7'));
    });

    test('andere Datei: keine Rückfrage', () {
      final protokoll = [eintrag('a.mbz', 12)];
      expect(
        wiederholungsRueckfrage(protokoll, profil: 'zielprofil', kurs: 12, datei: 'b.mbz'),
        isNull,
      );
    });

    test('anderes Profil: keine Rückfrage', () {
      final protokoll = [eintrag('a.mbz', 12, profil: 'anderes')];
      expect(
        wiederholungsRueckfrage(protokoll, profil: 'zielprofil', kurs: 12, datei: 'a.mbz'),
        isNull,
      );
    });

    test('abgelehnte Versuche zählen nicht', () {
      final protokoll = [eintrag('a.mbz', 12, stand: ZielStand.abgelehnt)];
      expect(
        wiederholungsRueckfrage(protokoll, profil: 'zielprofil', kurs: 12, datei: 'a.mbz'),
        isNull,
      );
    });

    test('ohne Datei greift der Quellkurs (frische Sicherung)', () {
      final protokoll = [eintrag('neu1.mbz', 12, quellkurs: 56)];
      expect(
        wiederholungsRueckfrage(protokoll,
            profil: 'zielprofil', kurs: 12, quellkurs: 56),
        isNotNull,
      );
      expect(
        wiederholungsRueckfrage(protokoll,
            profil: 'zielprofil', kurs: 12, quellkurs: 34),
        isNull,
      );
    });
  });

  group('Uebertragungsprotokoll', () {
    late Directory ordner;

    setUp(() {
      ordner = Directory.systemTemp.createTempSync('moocp_uebertragung_');
    });

    tearDown(() {
      if (ordner.existsSync()) ordner.deleteSync(recursive: true);
    });

    test('fehlende Datei ergibt ein leeres Protokoll', () async {
      final p = await Uebertragungsprotokoll.laden('${ordner.path}/uebertragungen.json');
      expect(p.eintraege, isEmpty);
    });

    test('Einträge bleiben über ein erneutes Laden erhalten', () async {
      final pfad = '${ordner.path}/uebertragungen.json';
      final p = await Uebertragungsprotokoll.laden(pfad);
      await p.eintragen(eintrag('a.mbz', 12, vorgang: '7'));
      await p.eintragen(eintrag('a.mbz', 34, stand: ZielStand.fehlgeschlagen));

      final neu = await Uebertragungsprotokoll.laden(pfad);
      expect(neu.eintraege.length, 2);
      expect(neu.eintraege.first.datei, 'a.mbz');
      expect(neu.eintraege.first.kurs, 12);
      expect(neu.eintraege.first.vorgang, '7');
      expect(neu.eintraege.last.stand, ZielStand.fehlgeschlagen);
      expect(neu.eintraege.first.zeit, DateTime(2026, 10, 18, 9));
    });

    test('zwei vorab geladene Sitzungen erhalten beide Einträge', () async {
      final pfad = '${ordner.path}/uebertragungen.json';
      final a = await Uebertragungsprotokoll.laden(pfad);
      final b = await Uebertragungsprotokoll.laden(pfad);
      await a.eintragen(eintrag('a.mbz', 12));
      await b.eintragen(eintrag('b.mbz', 34));
      expect((await Uebertragungsprotokoll.laden(pfad)).eintraege.map((e) => e.kurs), [12, 34]);
    });

    test('gleichzeitige Sitzungen verlieren keine Einträge', () async {
      final pfad = '${ordner.path}/uebertragungen.json';
      final a = await Uebertragungsprotokoll.laden(pfad);
      final b = await Uebertragungsprotokoll.laden(pfad);
      await Future.wait([a.eintragen(eintrag('a.mbz', 12)), b.eintragen(eintrag('b.mbz', 34))]);
      expect((await Uebertragungsprotokoll.laden(pfad)).eintraege.map((e) => e.kurs), unorderedEquals([12, 34]));
    });

    test('nach Laden beschädigtes Protokoll bleibt beim Eintragen unverändert', () async {
      final pfad = '${ordner.path}/uebertragungen.json';
      final a = await Uebertragungsprotokoll.laden(pfad);
      File(pfad).writeAsStringSync('{kaputt');
      await expectLater(a.eintragen(eintrag('a.mbz', 12)), throwsA(isA<StateError>()));
      expect(File(pfad).readAsStringSync(), '{kaputt');
    });

    test('beschädigte Datei wirft und wird nicht überschrieben', () async {
      final datei = File('${ordner.path}/uebertragungen.json');
      datei.writeAsStringSync('{kaputt');
      await expectLater(
        Uebertragungsprotokoll.laden(datei.path),
        throwsA(isA<StateError>()),
      );
      expect(datei.readAsStringSync(), '{kaputt');
    });

    test('Eintrag mit fehlenden Feldern macht die Datei beschädigt', () async {
      final datei = File('${ordner.path}/uebertragungen.json');
      datei.writeAsStringSync('[{"datei": "a.mbz"}]');
      await expectLater(
        Uebertragungsprotokoll.laden(datei.path),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('uebertragungAusfuehren', () {
    late Directory ordner;
    late Uebertragungsprotokoll protokoll;

    setUp(() async {
      ordner = Directory.systemTemp.createTempSync('moocp_lauf_');
      protokoll = await Uebertragungsprotokoll.laden('${ordner.path}/uebertragungen.json');
    });

    tearDown(() {
      if (ordner.existsSync()) ordner.deleteSync(recursive: true);
    });

    test('teilweise fehlgeschlagener Lauf: jedes Ziel genau einmal, Erfolge werden nicht erneut angefasst', () async {
      final aufrufe = <int>[];
      final berichte = await uebertragungAusfuehren(
        [ziel(12), ziel(34), ziel(56)],
        datei: 'a.mbz',
        profil: 'zielprofil',
        protokoll: protokoll,
        lauf: (z) async {
          aufrufe.add(z.kurs);
          if (z.kurs == 34) {
            return const ZielErgebnis(ZielStand.fehlgeschlagen,
                vorgang: '8', text: 'Moodle meldet einen Fehler.');
          }
          return ZielErgebnis(ZielStand.fertig, vorgang: '${z.kurs}');
        },
      );

      // Jedes Ziel genau einmal: das fehlgeschlagene wird nicht stillschweigend
      // wiederholt, und das erfolgreiche vor ihm läuft nicht noch einmal.
      expect(aufrufe, [12, 34, 56]);
      expect(berichte.map((b) => b.stand), [ZielStand.fertig, ZielStand.fehlgeschlagen, ZielStand.fertig]);
      expect(berichte.map((b) => b.vorgang), ['12', '8', '56']);

      // Jedes Ergebnis ist im Protokoll festgehalten.
      expect(protokoll.eintraege.map((e) => e.kurs), [12, 34, 56]);
      expect(protokoll.eintraege.map((e) => e.stand),
          [ZielStand.fertig, ZielStand.fehlgeschlagen, ZielStand.fertig]);

      // Ein späterer Versuch für das erfolgreiche Ziel braucht eine Rückfrage.
      expect(
        wiederholungsRueckfrage(protokoll.eintraege,
            profil: 'zielprofil', kurs: 12, datei: 'a.mbz'),
        isNotNull,
      );
    });

    test('ein Fehler stoppt die übrigen Ziele nicht', () async {
      final aufrufe = <int>[];
      final berichte = await uebertragungAusfuehren(
        [ziel(12), ziel(34)],
        datei: 'a.mbz',
        profil: 'zielprofil',
        protokoll: protokoll,
        lauf: (z) async {
          aufrufe.add(z.kurs);
          return z.kurs == 12
              ? const ZielErgebnis(ZielStand.fehlgeschlagen)
              : const ZielErgebnis(ZielStand.fertig, vorgang: '9');
        },
      );
      expect(aufrufe, [12, 34]);
      expect(berichte.last.stand, ZielStand.fertig);
    });

    test('Ablehnung stoppt den Lauf: übrige Ziele werden nicht begonnen', () async {
      final aufrufe = <int>[];
      final berichte = await uebertragungAusfuehren(
        [ziel(12), ziel(34), ziel(56)],
        datei: 'a.mbz',
        profil: 'zielprofil',
        protokoll: protokoll,
        lauf: (z) async {
          aufrufe.add(z.kurs);
          return const ZielErgebnis(ZielStand.abgelehnt, text: 'In der App abgelehnt.');
        },
      );
      expect(aufrufe, [12]);
      expect(berichte.map((b) => b.stand),
          [ZielStand.abgelehnt, ZielStand.nichtBegonnen, ZielStand.nichtBegonnen]);
      // Nur der tatsächlich gelaufene Versuch steht im Protokoll.
      expect(protokoll.eintraege.map((e) => e.kurs), [12]);
    });

    test('eine Ausnahme wird zu unklar, ohne ihre Meldung zu übernehmen', () async {
      final berichte = await uebertragungAusfuehren(
        [ziel(12)],
        datei: 'a.mbz',
        profil: 'zielprofil',
        protokoll: protokoll,
        lauf: (z) async => throw StateError('Geheimer Inhalt aus Moodle'),
      );
      expect(berichte.single.stand, ZielStand.unklar);
      expect(berichte.single.text, isNot(contains('Geheimer')));
      expect(protokoll.eintraege.single.stand, ZielStand.unklar);
    });

    test('Bericht nennt Dubletten und die Nummer; Ziele ohne Erfolg sind nicht zugesagt', () async {
      final berichte = await uebertragungAusfuehren(
        [ziel(12), ziel(34)],
        datei: 'a.mbz',
        profil: 'zielprofil',
        protokoll: protokoll,
        lauf: (z) async => z.kurs == 12
            ? const ZielErgebnis(ZielStand.fertig, vorgang: '5')
            : const ZielErgebnis(ZielStand.fehlgeschlagen, text: 'Moodle meldet einen Fehler.'),
      );
      final text = uebertragungsBericht(berichte);
      expect(text, contains('1 fertig'));
      expect(text, contains('1 fehlgeschlagen oder unklar'));
      expect(text, contains('Nummer 5'));
      expect(text, contains('Dubletten'));
      expect(text, contains('Ein Aktualisieren bestehender Inhalte ist nicht zugesagt'));
      expect(text, contains('Nicht erneut gesendet'));
    });
  });

  test('Bericht erhält Prüfprobleme auch bei fertigen Zielen', () {
    final text = uebertragungsBericht([
      ZielBericht(ziel(12), ZielStand.fertig, '7', 'Fehlend: ZZ Frage. Fragenherkunft nicht bestätigt.'),
      ZielBericht(ziel(34), ZielStand.fertig, '8', 'Anhang fehlt im Ziel; nicht verifiziert.'),
    ]);
    expect(text, contains('Fehlend: ZZ Frage'));
    expect(text, contains('Fragenherkunft nicht bestätigt'));
    expect(text, contains('Anhang fehlt im Ziel; nicht verifiziert'));
  });

  group('ZielStand', () {
    test('zielStandAus: fertig und fehlgeschlagen direkt, alles andere unklar', () {
      expect(zielStandAus(WiederherstellungStand.fertig), ZielStand.fertig);
      expect(zielStandAus(WiederherstellungStand.fehlgeschlagen), ZielStand.fehlgeschlagen);
      expect(zielStandAus(WiederherstellungStand.laufend), ZielStand.unklar);
      expect(zielStandAus(null), ZielStand.unklar);
    });
  });
}
