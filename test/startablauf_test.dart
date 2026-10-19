import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/anmeldung.dart';

void main() {
  test('gebundenes Debug-Testprofil meldet sich vor wartender Einrichtung an', () async {
    final aufrufe = <String>[];

    final bereit = await testprofilVorEinrichtungStarten(
      gebunden: true,
      anmelden: () async => aufrufe.add('anmelden'),
      einrichtungPruefen: () async {
        aufrufe.add('einrichtung');
        return false;
      },
    );

    expect(bereit, isFalse);
    expect(aufrufe, ['anmelden', 'einrichtung']);
  });

  test('normaler Start meldet sich erst nach erfolgreicher Einrichtung an', () async {
    final aufrufe = <String>[];

    final bereit = await testprofilVorEinrichtungStarten(
      gebunden: false,
      anmelden: () async => aufrufe.add('anmelden'),
      einrichtungPruefen: () async {
        aufrufe.add('einrichtung');
        return true;
      },
    );

    expect(bereit, isTrue);
    expect(aufrufe, ['einrichtung', 'anmelden']);
  });

  test('abgelehnte Einrichtung startet kein ungebundenes Testprofil', () async {
    final aufrufe = <String>[];

    final bereit = await testprofilVorEinrichtungStarten(
      gebunden: false,
      anmelden: () async => aufrufe.add('anmelden'),
      einrichtungPruefen: () async {
        aufrufe.add('einrichtung');
        return false;
      },
    );

    expect(bereit, isFalse);
    expect(aufrufe, ['einrichtung']);
  });
}
