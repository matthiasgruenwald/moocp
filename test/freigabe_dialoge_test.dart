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
