import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/freigabe.dart';
import 'package:moocp/main.dart' show FreigabeDialoge;
import 'package:moocp/protokoll.dart';

FreigabeAnfrage _anfrage(String titel) =>
    FreigabeAnfrage(titel: titel, punkte: const [], vergleich: const []);

Widget _fenster(Freigaben freigaben) => MaterialApp(
  home: FreigabeDialoge(
    freigaben: freigaben,
    nachVorn: (_) async {},
    child: const Scaffold(body: Text('Hauptfenster')),
  ),
);

void main() {
  testWidgets('Bild außerhalb des erneut geprüften Testumfangs braucht persönliche Freigabe', (tester) async {
    final freigaben = Freigaben(Protokoll(), stufe: Bestaetigungen.keine);
    await tester.pumpWidget(_fenster(freigaben));
    final anfrage = FreigabeAnfrage(titel: 'ZZ Bild?', punkte: const [], vergleich: const [],
      ab: Bestaetigungen.keine,
      bilder: [base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=')]);
    final antwort = freigaben.imTest(() => freigaben.anfragen(anfrage), pruefen: () async => false);
    await tester.pumpAndSettle();
    expect(find.text('ZZ Bild?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(await antwort, isFalse);
    expect(freigaben.testfreigaben, 0);
  });

  for (final fall in ['Zustimmung', 'Ablehnung', 'Fristablauf', 'Abbruch']) {
    testWidgets('realer Dialog: $fall beendet die Anfrage korrekt', (
      tester,
    ) async {
      final freigaben = Freigaben(
        Protokoll(),
        frist: const Duration(seconds: 3),
      );
      await tester.pumpWidget(_fenster(freigaben));
      final abbruch = Completer<void>();
      final antwort = Freigaben.mitAbbruch(
        abbruch.future,
        () => freigaben.anfragen(_anfrage('ZZ Änderung?')),
      );
      await tester.pumpAndSettle();
      expect(find.text('ZZ Änderung?'), findsOneWidget);
      switch (fall) {
        case 'Zustimmung':
          await tester.tap(find.text('Speichern'));
        case 'Ablehnung':
          await tester.tap(find.text('Abbrechen'));
        case 'Fristablauf':
          await tester.pump(const Duration(seconds: 3));
        case 'Abbruch':
          abbruch.complete();
      }
      await tester.pumpAndSettle();
      expect(await antwort, fall == 'Zustimmung');
      expect(find.text('ZZ Änderung?'), findsNothing);
      expect(freigaben.aktuell, isNull);
      expect(freigaben.testfreigaben, 0);
    });
  }

  testWidgets(
    'wechselt den Listener bei Profilwechsel auch mit offenem Dialog',
    (tester) async {
      final alt = Freigaben(Protokoll());
      final neu = Freigaben(Protokoll());
      await tester.pumpWidget(_fenster(alt));
      alt.anfragen(_anfrage('Altes Profil'));
      await tester.pumpAndSettle();
      expect(find.text('Altes Profil'), findsOneWidget);

      await tester.pumpWidget(_fenster(neu));
      await tester.pumpAndSettle();
      expect(find.text('Altes Profil'), findsNothing);
      alt.entscheiden(false);
      neu.anfragen(_anfrage('Neues Profil'));
      await tester.pumpAndSettle();

      expect(find.text('Neues Profil'), findsOneWidget);
      neu.entscheiden(false);
    },
  );
}
