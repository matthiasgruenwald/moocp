import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/anmeldedaten.dart';
import 'package:moocp/einstellungen.dart';
import 'package:moocp/freigabe.dart';
import 'package:moocp/main.dart'
    show AnmeldeAuftrag, Instanz, gespeicherteAnmeldedatenVerwenden;
import 'package:moocp/mcp/mcp_dienst.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/profil.dart';
import 'package:moocp/protokoll.dart';

void main() {
  test(
    'verwendet gespeicherte Zugangsdaten nach Profilwechsel nicht weiter',
    () async {
      final begonnen = Completer<void>();
      final fortsetzen = Completer<void>();
      var aktivesProfil = 'profil-a';
      final felderVonB = <String>['lehrkraft-b:passwort-b'];

      final laden = gespeicherteAnmeldedatenVerwenden(
        laden: () async {
          begonnen.complete();
          await fortsetzen.future;
          return const Anmeldedaten(true, 'lehrkraft-a', 'passwort-a');
        },
        zielIstAktiv: () => aktivesProfil == 'profil-a',
        anwenden: (daten) =>
            felderVonB.add('${daten.benutzer}:${daten.passwort}'),
      );
      await begonnen.future;
      aktivesProfil = 'profil-b';
      fortsetzen.complete();
      await laden;

      expect(felderVonB, ['lehrkraft-b:passwort-b']);
    },
  );

  test(
    'behält Profil und Formulareingaben während einer verzögerten Anmeldung',
    () async {
      final protokoll = Protokoll();
      final einstellungen = Einstellungen(schluessel: 'test');
      final freigaben = Freigaben(protokoll);
      final moodle = MoodleZugang(protokoll);
      final profil = Profil(
        kennung: 'profil-a',
        name: 'A',
        adresse: 'https://a.schule.example',
        port: 47811,
        mcpName: 'a',
      );
      final instanz = Instanz(
        moodle,
        freigaben,
        McpDienst(
          einstellungen,
          moodle,
          protokoll,
          freigaben,
          'test-arbeitsordner',
          profil: profil,
        ),
      );
      final auftrag = AnmeldeAuftrag(
        instanz: instanz,
        profil: profil,
        adresse: profil.adresse,
        benutzer: 'lehrkraft-a',
        passwort: 'passwort-a',
        merken: true,
      );
      final begonnen = Completer<void>();
      final fortsetzen = Completer<void>();
      var ausgewaehltesProfil = 'profil-a';

      final anmeldung = () async {
        begonnen.complete();
        await fortsetzen.future;
        expect(auftrag.instanz, same(instanz));
        expect(auftrag.profil.kennung, 'profil-a');
        expect(auftrag.adresse, 'https://a.schule.example');
        expect(auftrag.benutzer, 'lehrkraft-a');
        expect(auftrag.passwort, 'passwort-a');
        expect(auftrag.merken, isTrue);
      }();
      await begonnen.future;
      ausgewaehltesProfil = 'profil-b';
      fortsetzen.complete();
      await anmeldung;

      expect(ausgewaehltesProfil, 'profil-b');
    },
  );
}
