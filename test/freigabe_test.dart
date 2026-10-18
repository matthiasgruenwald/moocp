// Freigaben: die Frist, die Entscheidung und die Stufe der Bestätigungen --
// wer fragt, wer durchläuft, und was im Protokoll steht. Geprüft wird die eine
// Stelle, an der das entschieden wird (Freigaben.anfragen), damit kein
// Werkzeug die Einstellung übersehen kann, und das Feld in der Titelzeile;
// dazu, dass eine Anfrage verfällt, wenn der Client nicht mehr wartet, und
// dass weitere Anfragen sich sichtbar einreihen (Protokoll, Zähler im Dialog),
// ihre Frist ab der Anfrage läuft und immer nur ein Dialog offen ist.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/einstellungen.dart';
import 'package:moocp/freigabe.dart';
import 'package:moocp/main.dart';
import 'package:moocp/protokoll.dart';

FreigabeAnfrage anfrage({Bestaetigungen ab = Bestaetigungen.mittel, String titel = 'Änderung speichern?'}) =>
    FreigabeAnfrage(titel: titel, punkte: const [], vergleich: const [], ab: ab);

void main() {
  test('Vorgabe ist mittel, und Unbekanntes wird nie zu „keine"', () {
    expect(Bestaetigungen.vorgabe, Bestaetigungen.mittel);
    expect(anfrage().ab, Bestaetigungen.mittel);
    expect(Freigaben(Protokoll()).stufe, Bestaetigungen.mittel);
    for (final t in [null, '', 'KEINE', 'viel', 'alles']) {
      expect(Bestaetigungen.ausText(t), Bestaetigungen.mittel, reason: 'aus „$t"');
    }
    for (final x in Bestaetigungen.values) {
      expect(Bestaetigungen.ausText(x.text), x);
    }
  });

  test('Die Reihenfolge der Stufen ist die Mechanik', () {
    expect(Bestaetigungen.keine.index, lessThan(Bestaetigungen.mittel.index));
    expect(Bestaetigungen.mittel.index, lessThan(Bestaetigungen.alle.index));
  });

  test('Wer bei welcher Stufe gefragt wird', () {
    final erwartet = {
      // Stufe -> (fragt bei einer Anfrage ab mittel, fragt bei einer ab alle)
      Bestaetigungen.keine: (false, false),
      Bestaetigungen.mittel: (true, false),
      Bestaetigungen.alle: (true, true),
    };
    for (final e in erwartet.entries) {
      final f = Freigaben(Protokoll(), stufe: e.key);
      expect(f.fragt(anfrage()), e.value.$1, reason: 'Stufe ${e.key.text}, Anfrage ab mittel');
      expect(f.fragt(anfrage(ab: Bestaetigungen.alle)), e.value.$2,
          reason: 'Stufe ${e.key.text}, Anfrage ab alle');
    }
  });

  test('Unterhalb der Stufe läuft es durch, mit Eintrag im Protokoll', () async {
    final prot = Protokoll();
    final f = Freigaben(prot, stufe: Bestaetigungen.keine);
    final a = anfrage(titel: 'Endgültig löschen?');
    expect(await f.anfragen(a), isTrue);
    expect(f.aktuell, isNull, reason: 'es gab keinen Dialog');
    expect(a.offen, isFalse);
    expect(f.ausgelassen, 1);
    expect(prot.eintraege.single.art, Art.schreiben);
    expect(prot.eintraege.single.text, 'Ohne Freigabe (Bestätigungen: keine): Endgültig löschen?');
  });

  test('Bei „mittel" zählt nur, was ab „alle" fragt', () async {
    final f = Freigaben(Protokoll(), stufe: Bestaetigungen.mittel);
    expect(await f.anfragen(anfrage(ab: Bestaetigungen.alle)), isTrue);
    expect(f.ausgelassen, 1);
  });

  test('Ab der Stufe wird gefragt und entschieden', () async {
    final prot = Protokoll();
    final f = Freigaben(prot, stufe: Bestaetigungen.alle);
    final a = anfrage(ab: Bestaetigungen.alle, titel: 'Verborgen anlegen?');
    final antwort = f.anfragen(a);
    await Future<void>.delayed(Duration.zero);
    expect(f.aktuell, same(a), reason: 'die Anfrage wartet auf den Dialog');
    expect(f.ausgelassen, 0);
    f.entscheiden(true);
    expect(await antwort, isTrue);
    expect(prot.eintraege.map((e) => e.text),
        containsAllInOrder(['Freigabe angefragt: Verborgen anlegen? (Frist 30 min)', 'Freigabe erteilt']));
  });

  test('Abgelehnt bleibt abgelehnt, auch bei Stufe „alle"', () async {
    final f = Freigaben(Protokoll(), stufe: Bestaetigungen.alle);
    final antwort = f.anfragen(anfrage());
    await Future<void>.delayed(Duration.zero);
    f.entscheiden(false);
    expect(await antwort, isFalse);
  });

  test('Die Frist gilt weiter: ohne Entscheidung nichts geschrieben', () async {
    final prot = Protokoll();
    // Kurze Frist statt 30 Minuten -- geprüft wird, DASS sie abläuft.
    final f = Freigaben(prot, frist: const Duration(milliseconds: 20), stufe: Bestaetigungen.alle);
    expect(await f.anfragen(anfrage()), isFalse);
    expect(f.ausgelassen, 0, reason: 'abgelaufen ist nicht ausgelassen');
    expect(prot.eintraege.last.text, 'Frist abgelaufen -- nicht gespeichert');
  });

  test('Wartet der Client nicht mehr, schließt sich der Dialog: nichts geschrieben', () async {
    final prot = Protokoll();
    final f = Freigaben(prot);
    final abbruch = Completer<void>();
    final antwort = Freigaben.mitAbbruch(abbruch.future, () => f.anfragen(anfrage()));
    await Future<void>.delayed(Duration.zero);
    expect(f.aktuell, isNotNull, reason: 'der Dialog ist offen');
    abbruch.complete();
    expect(await antwort, isFalse);
    expect(f.aktuell, isNull, reason: 'der Dialog hat sich geschlossen');
    expect(prot.eintraege.last.text, 'Die KI wartet nicht mehr -- nicht gespeichert');
    f.entscheiden(true);
    expect(prot.eintraege.last.text, 'Die KI wartet nicht mehr -- nicht gespeichert',
        reason: 'eine späte Freigabe erteilt nichts mehr');
  });

  test('Weitere Anfragen reihen sich ein: Zähler, Protokoll, Reihenfolge', () async {
    final prot = Protokoll();
    final f = Freigaben(prot);
    final gemeldet = <int>[];
    f.addListener(() => gemeldet.add(f.wartend));
    final antworten = [for (final t in ['Erste?', 'Zweite?', 'Dritte?']) f.anfragen(anfrage(titel: t))];
    await Future<void>.delayed(Duration.zero);
    expect(f.wartend, 2);
    expect(prot.eintraege.map((e) => e.text), [
      'Freigabe angefragt: Erste? (Frist 30 min)',
      'Freigabe wartet hinter einer anderen: Zweite?',
      'Freigabe wartet hinter 2 anderen: Dritte?',
    ]);
    // Dran ist, wer zuerst kam; der Zähler sinkt mit jeder Entscheidung.
    for (final (titel, wartend) in [('Erste?', 2), ('Zweite?', 1), ('Dritte?', 0)]) {
      expect(f.aktuell?.titel, titel);
      expect(f.wartend, wartend, reason: 'während „$titel" offen ist');
      f.entscheiden(titel != 'Zweite?');
      await Future<void>.delayed(Duration.zero);
    }
    expect(await Future.wait(antworten), [true, false, true]);
    expect(f.aktuell, isNull);
    expect(f.wartend, 0);
    expect(gemeldet, containsAllInOrder([1, 2, 1, 0]), reason: 'der Dialog erfährt jede Änderung');
  });

  test('Abgebrochen, während eine andere Anfrage offen ist: gar nicht erst gefragt', () async {
    final prot = Protokoll();
    final f = Freigaben(prot);
    final erste = f.anfragen(anfrage(titel: 'Erste?'));
    await Future<void>.delayed(Duration.zero);
    final abbruch = Completer<void>();
    final zweite = Freigaben.mitAbbruch(abbruch.future, () => f.anfragen(anfrage(titel: 'Zweite?')));
    await Future<void>.delayed(Duration.zero);
    expect(f.wartend, 1);
    abbruch.complete();
    expect(await zweite, isFalse, reason: 'ohne auf die erste zu warten');
    expect(f.wartend, 0, reason: 'sie wartet nicht mehr');
    expect(f.aktuell?.titel, 'Erste?');
    expect(prot.eintraege.last.text, 'Die KI wartet nicht mehr -- nicht gefragt, nicht gespeichert: Zweite?');
    f.entscheiden(true);
    expect(await erste, isTrue, reason: 'die erste bleibt unberührt');
    expect(prot.eintraege.map((e) => e.text), isNot(contains('Freigabe angefragt: Zweite? (Frist 30 min)')));
  });

  test('Die Frist läuft ab der Anfrage, auch während sie wartet', () async {
    // Sonst endete sie bei einer wartenden Anfrage nach dem Zeitlimit des
    // Clients, das ab dem Werkzeugaufruf läuft.
    final prot = Protokoll();
    final f = Freigaben(prot, frist: const Duration(milliseconds: 400));
    final vorher = DateTime.now();
    final a2 = anfrage(titel: 'Zweite?');
    final erste = f.anfragen(anfrage(titel: 'Erste?'));
    final zweite = f.anfragen(a2);
    expect(a2.ablauf!.difference(vorher).inMilliseconds, inInclusiveRange(400, 450), reason: 'ab der Anfrage');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    f.entscheiden(true);
    expect(f.aktuell, same(a2), reason: 'gleich dran, ohne Lücke');
    final offen = Stopwatch()..start();
    expect(await zweite, isFalse);
    expect(offen.elapsedMilliseconds, lessThan(300), reason: 'nicht die volle Frist ab dem Öffnen');
    expect(await erste, isTrue);
    expect(prot.eintraege.last.text, 'Frist abgelaufen -- nicht gespeichert');
  });

  test('Ohne Abbruch bleibt alles, wie es war; ein Abbruch nach der Entscheidung ändert nichts', () async {
    final f = Freigaben(Protokoll());
    final abbruch = Completer<void>();
    final antwort = Freigaben.mitAbbruch(abbruch.future, () => f.anfragen(anfrage()));
    await Future<void>.delayed(Duration.zero);
    f.entscheiden(true);
    expect(await antwort, isTrue);
    abbruch.complete();
    await Future<void>.delayed(Duration.zero);
    expect(f.aktuell, isNull);
  });

  testWidgets('Der Dialog zeigt, wie viele Anfragen dahinter warten', (tester) async {
    // pumpAndSettle statt pump: Abbruch und Entscheidung kommen über
    // Microtasks an, der Zähler erst im Frame danach.
    final f = Freigaben(Protokoll());
    final erste = f.anfragen(anfrage(titel: 'Erste?'));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FreigabeDialog(f.aktuell!, f))));
    final zaehler = find.textContaining('weitere Anfrage');
    expect(zaehler, findsNothing, reason: 'allein kein Zähler');

    final zweite = f.anfragen(anfrage(titel: 'Zweite?'));
    await tester.pumpAndSettle();
    expect(find.text('1 weitere Anfrage wartet.'), findsOneWidget);

    final abbruch = Completer<void>();
    final dritte = Freigaben.mitAbbruch(abbruch.future, () => f.anfragen(anfrage(titel: 'Dritte?')));
    await tester.pumpAndSettle();
    expect(find.text('2 weitere Anfragen warten.'), findsOneWidget);

    abbruch.complete();
    await tester.pumpAndSettle();
    expect(find.text('1 weitere Anfrage wartet.'), findsOneWidget, reason: 'die abgebrochene zählt nicht mehr');

    f.entscheiden(true);
    await tester.pumpAndSettle();
    expect(f.aktuell?.titel, 'Zweite?');
    expect(zaehler, findsNothing, reason: 'hinter der zweiten wartet keine');
    f.entscheiden(true);
    await tester.pumpAndSettle();
    expect([await erste, await zweite, await dritte], [true, true, false]);
  });

  testWidgets('Der kleine Dialog hat Platz für den Zähler, auch bei 125 % Schriftgröße', (tester) async {
    // Löschen, Sichtbarkeit, Verschieben: kein Zeilenvergleich, aber eine
    // volle Liste der Mitbetroffenen. Ein Überlauf schnitte den Zähler ab.
    final f = Freigaben(Protokoll());
    final punkte = [for (var i = 1; i <= 30; i++) 'Mitbetroffen: Textseite $i'];
    final erste = f.anfragen(FreigabeAnfrage(titel: 'Endgültig löschen?', punkte: punkte, vergleich: const []));
    final zweite = f.anfragen(anfrage());
    for (final skala in [1.0, 1.25]) {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(skala)),
            child: Scaffold(body: FreigabeDialog(f.aktuell!, f)),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'kein Überlauf bei ${(skala * 100).round()} %');
      expect(find.text('1 weitere Anfrage wartet.'), findsOneWidget);
    }
    f.entscheiden(false);
    f.entscheiden(false);
    expect([await erste, await zweite], [false, false]);
  });

  testWidgets('Schließt die App die offene Anfrage, ist danach nur der Dialog der nächsten offen', (tester) async {
    final f = Freigaben(Protokoll());
    final vorn = <bool>[];
    Bestaetigungen? gewaehlt;
    await tester.pumpWidget(MaterialApp(
      home: FreigabeDialoge(
        freigaben: f,
        nachVorn: (an) async => vorn.add(an),
        child: Scaffold(
          appBar: AppBar(actions: [BestaetigungenFeld(stufe: f.stufe, aendern: (x) async => gewaehlt = x)]),
        ),
      ),
    ));
    final abbruch = Completer<void>();
    final erste = Freigaben.mitAbbruch(abbruch.future, () => f.anfragen(anfrage(titel: 'Erste?')));
    final zweite = f.anfragen(anfrage(titel: 'Zweite?'));
    await tester.pumpAndSettle();
    expect(find.byType(FreigabeDialog), findsOneWidget);
    expect(find.text('Erste?'), findsOneWidget);

    // Der Dialog sperrt die Titelzeile: Solange eine Anfrage offen ist oder
    // wartet, lässt sich die Stufe nicht umstellen.
    await tester.tap(find.byType(BestaetigungenFeld), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('alle'), findsNothing, reason: 'das Menü der Stufen geht nicht auf');
    expect(gewaehlt, isNull);

    // Wie nach der Frist: Die App beantwortet die erste selbst, und die zweite
    // kommt im selben Zug dran.
    abbruch.complete();
    await tester.pumpAndSettle();
    expect(await erste, isFalse);
    expect(find.byType(FreigabeDialog), findsOneWidget, reason: 'der Dialog der ersten ist zu');
    expect(find.text('Zweite?'), findsOneWidget);

    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(await zweite, isTrue);
    expect(find.byType(FreigabeDialog), findsNothing);
    expect(vorn, [true, true, false], reason: 'nach vorn, solange ein Dialog offen ist');
  });

  testWidgets('Das Feld zeigt die Stufe, bei „keine" in Warnfarbe', (tester) async {
    Bestaetigungen? gewaehlt;
    Future<void> zeigen(Bestaetigungen s) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [BestaetigungenFeld(stufe: s, aendern: (x) async => gewaehlt = x)],
            ),
          ),
        ));
    Color? grund() => tester
        .widget<Material>(
            find.descendant(of: find.byType(BestaetigungenFeld), matching: find.byType(Material)).first)
        .color;
    final fehlerfarbe = ThemeData().colorScheme.error;

    await zeigen(Bestaetigungen.mittel);
    expect(find.text('Bestätigungen: mittel'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    expect(grund(), isNot(fehlerfarbe));

    await zeigen(Bestaetigungen.keine);
    expect(find.text('Bestätigungen: keine'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget, reason: 'Warnung sichtbar');
    expect(grund(), fehlerfarbe, reason: 'das ganze Feld in Warn-Rot');

    // Umstellen über das Menü: Jede Stufe steht darin mit ihrem Kurztext.
    await tester.tap(find.byType(BestaetigungenFeld));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alle').last);
    await tester.pumpAndSettle();
    expect(gewaehlt, Bestaetigungen.alle);
  });

  test('Die Stufe steht in den Einstellungen und kommt unverändert zurück', () {
    for (final x in Bestaetigungen.values) {
      final e = Einstellungen(schluessel: 'x', bestaetigungen: x);
      expect(e.bestaetigungen, x);
      expect(Bestaetigungen.ausText(e.bestaetigungen.text), x);
    }
    expect(Einstellungen(schluessel: 'x').bestaetigungen, Bestaetigungen.mittel);
  });
}
