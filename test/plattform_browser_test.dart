// Offline prüfbar, ohne Betriebssystem: die Browserauswahl des Kerns gegen
// Fakes. Die Umsetzungen für Windows und macOS prüfen die Plattformtests.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/bildschirmfoto.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/plattform/plattform.dart';

class _Fake implements PlattformBrowser {
  _Fake({required this.arten, this.pfade = const {}, this.verboten = const {}});

  @override
  final List<BrowserArt> arten;
  final Map<BrowserArt, String> pfade;
  final Set<BrowserArt> verboten;

  @override
  Future<String?> programm(BrowserArt art) async => pfade[art];

  @override
  Future<bool> fernsteuerungVerboten(BrowserArt art) async => verboten.contains(art);

  @override
  Future<int> prozesseBeenden(Directory profil, String programm) async => 0;
}

void main() {
  test('nimmt den ersten Browser der Suchreihenfolge, der da ist', () async {
    final f = _Fake(
      arten: BrowserArt.values,
      pfade: {BrowserArt.chrome: '/x/Chrome', BrowserArt.chromium: '/x/Chromium'},
    );
    expect(await browserWaehlen(f), ('Google Chrome', '/x/Chrome'));
  });

  test('überspringt einen Browser mit abgeschalteter Fernsteuerung', () async {
    final f = _Fake(
      arten: BrowserArt.values,
      pfade: {BrowserArt.edge: '/x/Edge', BrowserArt.chrome: '/x/Chrome'},
      verboten: {BrowserArt.edge},
    );
    expect(await browserWaehlen(f), ('Google Chrome', '/x/Chrome'));
  });

  test('nennt die Richtlinie, wenn alle da sind, aber gesperrt', () async {
    final f = _Fake(
      arten: BrowserArt.values,
      pfade: {BrowserArt.edge: '/x/Edge'},
      verboten: {BrowserArt.edge},
    );
    expect(
      () => browserWaehlen(f),
      throwsA(isA<MoodleFehler>().having((e) => '$e', 'Text', contains('per Richtlinie abgeschaltet'))),
    );
  });

  test('zählt auf dieser Plattform nur die vorhandenen Arten auf', () async {
    final f = _Fake(arten: const [BrowserArt.edge, BrowserArt.chrome]);
    expect(
      () => browserWaehlen(f),
      throwsA(isA<MoodleFehler>().having(
          (e) => '$e', 'Text', contains('Weder Microsoft Edge noch Google Chrome ist zu finden'))),
    );
  });

  test('nennt bei drei Arten alle drei in der Meldung', () async {
    final f = _Fake(arten: BrowserArt.values);
    expect(
      () => browserWaehlen(f),
      throwsA(isA<MoodleFehler>().having(
          (e) => '$e', 'Text', contains('Weder Microsoft Edge, Google Chrome noch Chromium ist zu finden'))),
    );
  });
}
