// Fragenherkunft und Fragenvergleich vor und nach einer Quiz-Wiederherstellung
// (Issue #20). Reine Regeln ohne Netz; die Aufruftests mit dem HTTP-Doppel
// folgen, sobald das Archivformat der Fragen gemessen ist (TODO.md).

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/wiederherstellung_fragen.dart';

void main() {
  group('Herkunft vor dem Start', () {
    test('gleiche Sachnummern belegen ohne Quellkontext keine eigene Herkunft', () {
      final b = herkunftPruefen(
        verwendet: [
          (name: 'Frage A', sachnummer: 'ZZ-A', zufall: false, lokal: null),
          (name: 'Frage B', sachnummer: 'ZZ-B', zufall: false, lokal: null),
        ],
        eigeneSachnummern: {'ZZ-A', 'ZZ-B', 'ZZ-C'},
        eigeneAnzahl: 3,
      );
      expect(b.art, HerkunftArt.pruefluecke);
      expect(b.nichtEigene, isEmpty);
    });

    test('Frage nicht in der eigenen Sammlung: fremd oder unbekannt, mit Namen', () {
      final b = herkunftPruefen(
        verwendet: [
          (name: 'Frage A', sachnummer: 'ZZ-A', zufall: false, lokal: null),
          (name: 'Frage X', sachnummer: 'ZZ-X', zufall: false, lokal: null),
        ],
        eigeneSachnummern: {'ZZ-A'},
        eigeneAnzahl: 1,
      );
      expect(b.art, HerkunftArt.fremdOderUnbekannt);
      expect(b.nichtEigene, ['Frage X']);
      expect(b.text, contains('Frage X'));
    });

    test('leere eigene Sammlung ist kein Herkunftsnachweis', () {
      final b = herkunftPruefen(
        verwendet: [(name: 'Frage A', sachnummer: 'ZZ-A', zufall: false, lokal: null)],
        eigeneSachnummern: const {},
        eigeneAnzahl: 0,
      );
      expect(b.art, isNot(HerkunftArt.eigene));
      expect(b.art, HerkunftArt.fremdOderUnbekannt);
      expect(b.text, contains('kein Herkunftsnachweis'));
    });

    test('keine verwendeten Fragen ermittelt: Prüflücke, nie eigene Herkunft', () {
      final b = herkunftPruefen(
        verwendet: null,
        eigeneSachnummern: {'ZZ-A'},
        eigeneAnzahl: 1,
      );
      expect(b.art, HerkunftArt.pruefluecke);
    });

    test('Zufallsfrage: Prüflücke, Herkunft nicht festlegbar', () {
      final b = herkunftPruefen(
        verwendet: [
          (name: 'Frage A', sachnummer: 'ZZ-A', zufall: false, lokal: null),
          (name: 'Zufall', sachnummer: null, zufall: true, lokal: null),
        ],
        eigeneSachnummern: {'ZZ-A'},
        eigeneAnzahl: 1,
      );
      expect(b.art, HerkunftArt.pruefluecke);
      expect(b.text, contains('Zufall'));
    });

    test('Frage ohne Sachnummer: Zuordnung nicht auflösbar, Prüflücke', () {
      final b = herkunftPruefen(
        verwendet: [(name: 'Ohne Nummer', sachnummer: null, zufall: false, lokal: null)],
        eigeneSachnummern: {'ZZ-A'},
        eigeneAnzahl: 1,
      );
      expect(b.art, HerkunftArt.pruefluecke);
      expect(b.text, contains('Ohne Nummer'));
    });
  });

  group('Vergleich nach Wiederherstellung', () {
    test('gleiche Anzahl und gleiche Namen: gleich, verifizierbar', () {
      final v = fragenVergleichen(
        quelle: [
          (name: 'Frage A', sachnummer: 'ZZ-A', zufall: false, lokal: null),
          (name: 'Frage B', sachnummer: 'ZZ-B', zufall: false, lokal: null),
        ],
        ziel: [
          (name: 'Frage B', zufall: false),
          (name: 'Frage A', zufall: false),
        ],
      );
      expect(v.art, VergleichArt.gleich);
      expect(quizVerifiziert(v), isTrue);
    });

    test('fehlende Frage: Abweichung mit Zahl und Namen, nicht verifiziert', () {
      final v = fragenVergleichen(
        quelle: [
          (name: 'Frage A', sachnummer: 'ZZ-A', zufall: false, lokal: null),
          (name: 'Frage B', sachnummer: 'ZZ-B', zufall: false, lokal: null),
        ],
        ziel: [(name: 'Frage A', zufall: false)],
      );
      expect(v.art, VergleichArt.abweichung);
      expect(v.fehlend, ['Frage B']);
      expect(v.text, contains('1 von 2'));
      expect(quizVerifiziert(v), isFalse);
    });

    test('anderer Name bei gleicher Zahl: Abweichung', () {
      final v = fragenVergleichen(
        quelle: [(name: 'Frage A', sachnummer: 'ZZ-A', zufall: false, lokal: null)],
        ziel: [(name: 'Frage Anders', zufall: false)],
      );
      expect(v.art, VergleichArt.abweichung);
      expect(v.zusaetzlich, ['Frage Anders']);
      expect(v.fehlend, ['Frage A']);
    });

    test('Quelle nicht aufgenommen: Prüflücke statt Gleichheit', () {
      final v = fragenVergleichen(
        quelle: null,
        ziel: [(name: 'Frage A', zufall: false)],
      );
      expect(v.art, VergleichArt.pruefluecke);
      expect(quizVerifiziert(v), isFalse);
    });

    test('Zufallsfrage im Ziel: Prüflücke, kein falscher Gleichheitsvergleich', () {
      final v = fragenVergleichen(
        quelle: [(name: 'Frage A', sachnummer: 'ZZ-A', zufall: false, lokal: null)],
        ziel: [(name: 'Zufall', zufall: true)],
      );
      expect(v.art, VergleichArt.pruefluecke);
      expect(quizVerifiziert(v), isFalse);
    });

    test('Zufallsfrage in der Quelle: Prüflücke', () {
      final v = fragenVergleichen(
        quelle: [(name: 'Zufall', sachnummer: null, zufall: true, lokal: null)],
        ziel: [(name: 'Zufall', zufall: false)],
      );
      expect(v.art, VergleichArt.pruefluecke);
    });

    test('Vorhandensein des Quiz allein verifiziert nicht', () {
      // Ohne Quelle und ohne Ziellesung gibt es keinen Vergleich; ein bloßes
      // Quiz oder ein erfolgreicher Hintergrundauftrag geht nicht in die Regel ein.
      final v = fragenVergleichen(quelle: null, ziel: null);
      expect(v.art, VergleichArt.pruefluecke);
      expect(quizVerifiziert(v), isFalse);
    });
  });

  // Befund 7: Herkunft fließt nur bei lauter eigenen Fragen in verified ein.
  group('herkunftVerifiziert', () {
    test('alle Quizze eigene Herkunft: verifiziert', () {
      expect(herkunftVerifiziert([HerkunftBefund(HerkunftArt.eigene, 'ok')]), isTrue);
    });

    test('eine Prüflücke genügt, um nicht zu verifizieren', () {
      expect(
        herkunftVerifiziert([
          HerkunftBefund(HerkunftArt.eigene, 'ok'),
          HerkunftBefund(HerkunftArt.pruefluecke, 'Zufallsfragen'),
        ]),
        isFalse,
      );
    });

    test('fremde Herkunft verifiziert nicht', () {
      expect(herkunftVerifiziert([HerkunftBefund(HerkunftArt.fremdOderUnbekannt, 'fremd')]), isFalse);
    });

    test('kein Quiz geprüft: nicht verifiziert', () {
      expect(herkunftVerifiziert(const []), isFalse);
    });
  });

  group('quizZuordnen', () {
    const q = <QuizFrage>[(name: 'F', sachnummer: 'ZZ-1', zufall: false, lokal: true)];

    test('zwei Quizze werden über den Titel zugeordnet', () {
      final z = quizZuordnen(
        archivQuizTitel: ['A', 'B'],
        quellen: {'A': q, 'B': q},
        neueQuizze: [(cmid: 8, name: 'B'), (cmid: 7, name: 'A')],
      );
      expect([for (final x in z) x.zielCmid], [7, 8]);
      expect(z.every((x) => x.luecke == null), isTrue);
    });

    test('ohne gleichnamiges Quiz im Kurs: Prüflücke, bei einem Quiz je Seite aber Zuordnung', () {
      final z = quizZuordnen(archivQuizTitel: ['A', 'B'], quellen: {'A': q, 'B': q}, neueQuizze: [(cmid: 7, name: 'A')]);
      expect(z[0].luecke, isNull);
      expect(z[1].luecke, isNotNull);
      final einzeln = quizZuordnen(archivQuizTitel: ['A'], quellen: {'A': q}, neueQuizze: [(cmid: 9, name: 'Anders')]);
      expect(einzeln.single.zielCmid, 9);
    });

    test('doppelter Titel im Archiv bekommt keine Quelle', () {
      final quellen = quizQuellenNachTitel(
        quizFragen: {'quiz_1': q, 'quiz_2': q},
        quizTitel: {'quiz_1': 'A', 'quiz_2': 'A'},
        archivQuizTitel: ['A', 'A'],
      );
      expect(quellen, isEmpty);
    });
  });
}
