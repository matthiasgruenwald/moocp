import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/anmeldedaten.dart';
import 'package:moocp/profil.dart';

void main() {
  test(
    'Testzugang gilt nur für die zugeordnete Profilkennung und Moodle-Adresse',
    () {
      const zuordnung = <String, ({String datei, String adresse})>{
        'testprofil': (
          datei: 'testzugang.env',
          adresse: 'https://moodle.schule.example/',
        ),
      };
      final testprofil = Profil(
        kennung: 'testprofil',
        name: 'Test',
        adresse: 'https://moodle.schule.example',
        port: 47811,
        mcpName: 'test',
      );
      final produktivprofil = testprofil.copyWith(
        adresse: 'https://produktiv.schule.example',
      );
      final anderesProfil = Profil(
        kennung: 'anderes-profil',
        name: 'Anderes Profil',
        adresse: testprofil.adresse,
        port: 47812,
        mcpName: 'anderes',
      );

      expect(
        Anmeldedaten.testzugangZuordnungPasst(testprofil, zuordnung),
        isTrue,
      );
      expect(
        Anmeldedaten.testzugangZuordnungPasst(produktivprofil, zuordnung),
        isFalse,
      );
      expect(
        Anmeldedaten.testzugangZuordnungPasst(anderesProfil, zuordnung),
        isFalse,
      );
    },
  );
}
