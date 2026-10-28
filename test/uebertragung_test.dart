// Tests der Übertragung Richtung, Rückfragen, Zusammenfassung und
// das Speichern von Rolle und Projektkontext. Nur erfundene Daten (A11):
// Adressen mit .example, Kursnummern 12 und 34.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/einstellungen.dart';
import 'package:moocp/profil.dart';
import 'package:moocp/uebertragung.dart';

Profil _p(String kennung, String name, {Rolle? rolle}) => Profil(
      kennung: kennung,
      name: name,
      adresse: 'https://$kennung.schule-a.example',
      port: 47811,
      mcpName: kennung,
      rolle: rolle,
    );

void main() {
  final quelle = _p('quelle', 'Quelle', rolle: Rolle.quelle);
  final ziel = _p('ziel', 'Ziel', rolle: Rolle.ziel);
  final profile = [quelle, ziel];

  Projektkontext kontext({Kursbezug? q, List<Kursbezug> dk = const []}) =>
      Projektkontext(quelle: q ?? const Kursbezug('quelle', 12), durchfuehrung: dk);

  Plan plan(Richtungsentscheidung e) {
    if (e is Rueckfrage) fail('Unerwartete Rückfrage: ${e.text}');
    return e as Plan;
  }

  String rueckfrage(Richtungsentscheidung e) {
    expect(e, isA<Rueckfrage>());
    return (e as Rueckfrage).text;
  }

  group('bestimmeRichtung', () {
    test('Standardrichtung ist Quelle → Ziel', () {
      final p = plan(bestimmeRichtung(profile, kontext(dk: const [Kursbezug('ziel', 34)])));
      expect(p.gegenrichtung, isFalse);
      expect(p.quelle, Endpunkt(quelle, 12));
      expect(p.ziele, [Endpunkt(ziel, 34)]);
    });

    test('Gegenrichtung nur mit Angabe, mit einem Ziel tauscht sie die Seiten', () {
      final p = plan(bestimmeRichtung(profile, kontext(dk: const [Kursbezug('ziel', 34)]), gegenrichtung: true));
      expect(p.gegenrichtung, isTrue);
      expect(p.quelle, Endpunkt(ziel, 34));
      expect(p.ziele, [Endpunkt(quelle, 12)]);
    });

    test('Gegenrichtung mit zwei Zielen ist eine Rückfrage', () {
      final e = bestimmeRichtung(
        [...profile, _p('dritt', 'Dritt', rolle: Rolle.ziel)],
        kontext(dk: const [Kursbezug('ziel', 34), Kursbezug('dritt', 56)]),
        gegenrichtung: true,
      );
      expect(rueckfrage(e), contains('genau einen Durchführungskurs'));
    });

    test('Derselbe Quellprofil mit anderer Kursnummer ist ein gültiges Ziel', () {
      final p = plan(bestimmeRichtung(profile, kontext(dk: const [Kursbezug('quelle', 34)])));
      expect(p.ziele, [Endpunkt(quelle, 34)]);
    });

    test('ohne Projektkontext fragt die Richtung zurück', () {
      expect(rueckfrage(bestimmeRichtung(profile, null)), contains('Projektkontext'));
    });

    test('keine Rolle Quelle fragt zurück', () {
      final ohne = [_p('quelle', 'Quelle'), ziel];
      expect(rueckfrage(bestimmeRichtung(ohne, kontext(dk: const [Kursbezug('ziel', 34)]))),
          contains('Rolle Quelle'));
    });

    test('zwei Profile mit Rolle Quelle fragen zurück und nennen beide', () {
      final doppelt = [quelle, _p('zwei', 'Zwei', rolle: Rolle.quelle), ziel];
      final text = rueckfrage(bestimmeRichtung(doppelt, kontext(dk: const [Kursbezug('ziel', 34)])));
      expect(text, contains('Quelle'));
      expect(text, contains('„Quelle"'));
      expect(text, contains('„Zwei"'));
    });

    test('fehlender Quellkurs fragt zurück', () {
      final e = bestimmeRichtung(profile, const Projektkontext(durchfuehrung: [Kursbezug('ziel', 34)]));
      expect(rueckfrage(e), contains('Quellkurs'));
    });

    test('Quellkurs in einem anderen Profil ist ein Widerspruch und fragt zurück', () {
      final e = bestimmeRichtung(profile, kontext(q: const Kursbezug('ziel', 12), dk: const [Kursbezug('ziel', 34)]));
      expect(rueckfrage(e), contains('gehört zu keinem Profil mit der Rolle Quelle'));
    });

    test('kein Durchführungskurs fragt zurück', () {
      expect(rueckfrage(bestimmeRichtung(profile, kontext())), contains('Durchführungskurs'));
    });

    test('Durchführungskurs in unbekanntem Profil fragt zurück', () {
      final e = bestimmeRichtung(profile, kontext(dk: const [Kursbezug('gibt-es-nicht', 34)]));
      expect(rueckfrage(e), contains('keinem bekannten Profil'));
    });

    test('Ziel ohne Rolle Ziel fragt zurück und nennt das Profil', () {
      final ohne = [quelle, _p('ziel', 'Ziel')];
      final text = rueckfrage(bestimmeRichtung(ohne, kontext(dk: const [Kursbezug('ziel', 34)])));
      expect(text, contains('„Ziel"'));
      expect(text, contains('Rolle Ziel'));
    });

    test('Durchführungskurs ist derselbe Kurs wie der Quellkurs fragt zurück', () {
      final e = bestimmeRichtung(profile, kontext(dk: const [Kursbezug('quelle', 12)]));
      expect(rueckfrage(e), contains('derselbe Kurs wie der Quellkurs'));
    });

    test('doppelter Durchführungskurs fragt zurück', () {
      final e = bestimmeRichtung(profile, kontext(dk: const [Kursbezug('ziel', 34), Kursbezug('ziel', 34)]));
      expect(rueckfrage(e), contains('zweimal'));
    });

    test('mehrere Ziele in einer Richtung bleiben als Liste erhalten', () {
      final dritt = _p('dritt', 'Dritt', rolle: Rolle.ziel);
      final p = plan(bestimmeRichtung(
        [...profile, dritt],
        kontext(dk: const [Kursbezug('ziel', 34), Kursbezug('dritt', 56)]),
      ));
      expect(p.ziele, [Endpunkt(ziel, 34), Endpunkt(dritt, 56)]);
    });
  });

  group('uebertragungsZusammenfassung', () {
    final plan0 = plan(bestimmeRichtung(profile, kontext(dk: const [Kursbezug('ziel', 34)])));
    final namen = {
      Endpunkt(quelle, 12): 'Biologie Quelle',
      Endpunkt(ziel, 34): 'Biologie Ziel',
    };

    test('nennt Richtung, Instanzen, Kurse, Inhalt und Wiederherstellung', () {
      final text = uebertragungsZusammenfassung(
        plan0,
        kursnamen: namen,
        inhalt: 'Alle Aufgaben',
        wiederherstellung: 'Sicherung im Arbeitsordner',
      );
      expect(text, contains('Standardrichtung'));
      expect(text, contains('Quellinstanz: „Quelle" (quelle.schule-a.example)'));
      expect(text, contains('Quellkurs: „Biologie Quelle" (Kurs 12)'));
      expect(text, contains('Inhaltsauswahl: Alle Aufgaben'));
      expect(text, contains('„Biologie Ziel" (Kurs 34) in „Ziel" (ziel.schule-a.example)'));
      expect(text, contains('Wiederherstellung: Sicherung im Arbeitsordner'));
    });

    test('Gegenrichtung steht ausdrücklich im Text', () {
      final gegen = plan(bestimmeRichtung(profile, kontext(dk: const [Kursbezug('ziel', 34)]), gegenrichtung: true));
      final text = uebertragungsZusammenfassung(
        gegen,
        kursnamen: namen,
        inhalt: 'Alle',
        wiederherstellung: 'Sicherung',
      );
      expect(text, contains('Gegenrichtung (ausdrücklich verlangt)'));
    });

    test('fehlender Kursname bricht ab, statt eine Lücke zu zeigen', () {
      expect(
        () => uebertragungsZusammenfassung(
          plan0,
          kursnamen: {Endpunkt(quelle, 12): 'Biologie Quelle'},
          inhalt: 'Alle',
          wiederherstellung: 'Sicherung',
        ),
        throwsStateError,
      );
    });

    test('leerer Inhalt oder Wiederherstellungsweg bricht ab', () {
      expect(
        () => uebertragungsZusammenfassung(plan0, kursnamen: namen, inhalt: ' ', wiederherstellung: 'Sicherung'),
        throwsArgumentError,
      );
      expect(
        () => uebertragungsZusammenfassung(plan0, kursnamen: namen, inhalt: 'Alle', wiederherstellung: ''),
        throwsArgumentError,
      );
    });
  });

  group('richtungText', () {
    test('Rückfrage wird als Rückfrage ausgegeben', () {
      expect(richtungText(const Rueckfrage('Welcher Kurs?')), 'Rückfrage: Welcher Kurs?');
    });
  });

  group('Speichern', () {
    test('Projektkontext überlebt JSON-Roundtrip', () {
      final k = const Projektkontext(
        quelle: Kursbezug('quelle', 12),
        durchfuehrung: [Kursbezug('ziel', 34), Kursbezug('ziel', 56)],
      );
      final zurueck = Projektkontext.ausJson(jsonDecode(jsonEncode(k.toJson())));
      expect(zurueck?.quelle, const Kursbezug('quelle', 12));
      expect(zurueck?.durchfuehrung, [const Kursbezug('ziel', 34), const Kursbezug('ziel', 56)]);
    });

    test('unbrauchbare Kursangaben werden übergangen, nicht die ganze Datei verworfen', () {
      final k = Projektkontext.ausJson({
        'quelle': {'profil': '', 'kurs': 12},
        'durchfuehrung': [
          {'profil': 'ziel', 'kurs': 'zwölf'},
          {'profil': 'ziel', 'kurs': 34},
        ],
      });
      expect(k?.quelle, isNull);
      expect(k?.durchfuehrung, [const Kursbezug('ziel', 34)]);
    });

    test('Rolle und Projektkontext überleben Speichern und Laden der Einstellungen', () {
      final standard = Einstellungen(schluessel: 'testschluessel');
      final e = Einstellungen(
        profile: [_p('quelle', 'Quelle'), _p('ziel', 'Ziel')],
        schluessel: 'testschluessel',
        projektkontext: const Projektkontext(
          quelle: Kursbezug('quelle', 12),
          durchfuehrung: [Kursbezug('ziel', 34)],
        ),
      );
      expect(e.rolleSetzen('quelle', Rolle.quelle), isTrue);
      expect(e.rolleSetzen('ziel', Rolle.ziel), isTrue);
      expect(e.rolleSetzen('gibt-es-nicht', Rolle.ziel), isFalse);

      final geladen = Einstellungen.aus(
        jsonDecode(jsonEncode(e.zuJson())) as Map<String, dynamic>,
        standard,
      );
      final rollen = {for (final p in geladen.profile) p.kennung: p.rolle};
      expect(rollen, {'quelle': Rolle.quelle, 'ziel': Rolle.ziel});
      expect(geladen.projektkontext?.quelle, const Kursbezug('quelle', 12));
      expect(geladen.projektkontext?.durchfuehrung, [const Kursbezug('ziel', 34)]);
    });

    test('Rolle entfernen (keine) wird gespeichert', () {
      final e = Einstellungen(
        profile: [_p('quelle', 'Quelle', rolle: Rolle.quelle)],
        schluessel: 'testschluessel',
      );
      expect(e.rolleSetzen('quelle', null), isTrue);
      final geladen = Einstellungen.aus(
        jsonDecode(jsonEncode(e.zuJson())) as Map<String, dynamic>,
        Einstellungen(schluessel: 'testschluessel'),
      );
      expect(geladen.profile.single.rolle, isNull);
    });

    test('ohne Projektkontext steht kein Schlüssel in der Datei', () {
      final e = Einstellungen(profile: [_p('quelle', 'Quelle')], schluessel: 'testschluessel');
      expect(e.zuJson().containsKey('projektkontext'), isFalse);
    });
  });
}
