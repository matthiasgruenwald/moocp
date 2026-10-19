import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/profil.dart';
import 'package:moocp/profile_dialog.dart';

void main() {
  testWidgets(
    'Lehrkraft kann ein Profil anlegen und der Servername kommt aus dem Namen',
    (tester) async {
      Profil? ergebnis;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => ergebnis = await showDialog<Profil>(
                context: context,
                builder: (_) => const ProfileDialog(),
              ),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Öffnen'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('profile-name')),
        'Moodle Test',
      );
      await tester.enterText(
        find.byKey(const Key('profile-address')),
        'https://test.schule.example',
      );
      await tester.tap(find.text('Hinzufügen'));
      await tester.pumpAndSettle();

      expect(ergebnis?.name, 'Moodle Test');
      expect(ergebnis?.adresse, 'https://test.schule.example');
      expect(ergebnis?.mcpName, 'moodle-test');
    },
  );

  testWidgets(
    'Bearbeiten ändert Namen und Adresse, behält aber den MCP-Namen',
    (tester) async {
      final profil = Profil(
        kennung: 'abc12345',
        name: 'Moodle Test',
        adresse: 'https://alt.schule.example',
        port: 47812,
        mcpName: 'moodle-test',
      );
      Profil? ergebnis;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => ergebnis = await showDialog<Profil>(
                context: context,
                builder: (_) => ProfileDialog(profil: profil),
              ),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Öffnen'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('profile-name')),
        'Test Moodle',
      );
      await tester.enterText(
        find.byKey(const Key('profile-address')),
        'https://neu.schule.example',
      );
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();

      expect(ergebnis?.name, 'Test Moodle');
      expect(ergebnis?.adresse, 'https://neu.schule.example');
      expect(ergebnis?.mcpName, 'moodle-test');
    },
  );
}
