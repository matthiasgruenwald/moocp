// Bildschirmfotos für die README, aus den echten Fenstern der App mit
// erfundenen Daten (Muster-Adresse, e.mustermann, erfundene Kursnummern).
// Kein Moodle, kein Netz, keine echten Anmeldedaten.
//
// Neu erzeugen, wenn sich die Oberfläche geändert hat:
//   flutter test tool/bilder_test.dart --update-goldens
// Ergebnis: docs/bilder/hauptfenster.png, docs/bilder/freigabe.png
//
// Liegt unter tool/, nicht unter test/: Ein normales `flutter test` soll die
// Bilder nicht vergleichen -- die Schriften kommen aus Windows, und auf einem
// anderen Rechner sähen sie um Pixel anders aus.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/arbeitsordner.dart';
import 'package:moocp/einrichtung.dart';
import 'package:moocp/einstellungen.dart';
import 'package:moocp/freigabe.dart';
import 'package:moocp/main.dart';
import 'package:moocp/mcp/mcp_dienst.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/moodle/zeilenvergleich.dart';
import 'package:moocp/profil.dart';
import 'package:moocp/protokoll.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class _Angemeldet extends MoodleZugang {
  _Angemeldet(super.protokoll);
  @override
  bool get angemeldet => true;
}

class _Laeuft extends McpDienst {
  _Laeuft(super.einstellungen, super.moodle, super.protokoll, super.freigaben, super.arbeitsordner, {required super.profil});
  @override
  bool get laeuft => true;
}

Future<void> _schrift(String familie, List<String> dateien) async {
  final l = FontLoader(familie);
  for (final d in dateien) {
    final b = File(d).readAsBytesSync();
    l.addFont(Future.value(ByteData.view(b.buffer)));
  }
  await l.load();
}

const _vorher = '''<h3>Der Vorwiderstand</h3>
<p>Eine Leuchtdiode (LED) darf nur mit begrenztem Strom betrieben werden, weshalb ein Vorwiderstand in Reihe geschaltet wird, dessen Wert sich aus der Differenz von Betriebs- und Durchlassspannung, geteilt durch den Nennstrom, ergibt.</p>
<h4>Beispiel</h4>
<p>5 V, rote LED (2 V), 20 mA: R = 150 Ω</p>''';

const _nachher = '''<h3>Der Vorwiderstand</h3>
<p>Eine LED verträgt nur wenig Strom. Der Vorwiderstand bremst ihn.</p>
<p><img class="img-fluid" src="@@PLUGINFILE@@/led-vorwiderstand.svg" alt="Schaltung: Spannungsquelle 5 V, Vorwiderstand und LED in Reihe" width="480"></p>
<p>So rechnen Sie den Wert aus:</p>
<ol><li>Spannung am Widerstand: 5 V − 2 V = 3 V</li><li>Strom: 20 mA = 0,02 A</li><li>R = 3 V : 0,02 A = 150 Ω</li></ol>
<h4>Beispiel</h4>
<p>5 V, rote LED (2 V), 20 mA: R = 150 Ω</p>''';

void main() {
  setUpAll(() async {
    // flutter_tester liegt unter <flutter>/bin/cache/artifacts/engine/<plattform>/.
    final artefakte = p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable)));
    if (Platform.isMacOS) {
      // Die Schriften des Mac. Die Bilder in docs/bilder/ stammen von Windows
      // und sehen hier anders aus; zum Nachsehen reicht das.
      const fonts = '/System/Library/Fonts';
      await _schrift('Segoe UI', ['$fonts/Supplemental/Arial.ttf', '$fonts/Supplemental/Arial Bold.ttf']);
      await _schrift('Consolas', ['$fonts/Menlo.ttc']);
    } else {
      const fonts = r'C:\Windows\Fonts';
      await _schrift('Segoe UI', ['$fonts\\segoeui.ttf', '$fonts\\seguisb.ttf', '$fonts\\segoeuib.ttf']);
      await _schrift('Consolas', ['$fonts\\consola.ttf']);
    }
    await _schrift('MaterialIcons', [p.join(artefakte, 'material_fonts', 'MaterialIcons-Regular.otf')]);
    // Ein Test, nur eben unter tool/ (siehe oben) -- das weiß der Analyzer nicht.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'anmeldung.merken': true, 'anmeldung.benutzer': 'e.mustermann'});
    // Sonst stünde „Version nicht lesbar" im Protokoll des Bildes: Die App
    // liest ihre Version beim Start (Update-Prüfung), und im Test gibt es
    // das Plugin dafür nicht.
    // ignore: invalid_use_of_visible_for_testing_member
    PackageInfo.setMockInitialValues(
        appName: 'moocp',
        packageName: 'moocp',
        version: '0.9.4',
        buildNumber: '1',
        buildSignature: '');
  });

  testWidgets('Hauptfenster und Freigabe', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    debugDisableShadows = false;
    tester.view.physicalSize = const Size(1280 * 1.5, 780 * 1.5);
    tester.view.devicePixelRatio = 1.5;
    try {
      final einstellungen = Einstellungen(
        moodleAdresse: 'https://moodle.schule.example',
        schluessel: 'erfunden',
      );
      // Nur der Pfad; geleert wird er erst beim Beenden, und das kommt hier nicht vor.
      const arbeitsordner = Arbeitsordner(r'C:\Users\Lehrkraft\AppData\Local\Temp\moocp_arbeitsordner');
      var sekunde = 0;
      final protokoll = Protokoll(uhr: () => DateTime(2026, 9, 24, 10, 15, 3 * sekunde++));
      final moodle = _Angemeldet(protokoll);
      final freigaben = Freigaben(protokoll);
      final dienst = _Laeuft(einstellungen, moodle, protokoll, freigaben, arbeitsordner.pfad, profil: Profil.migriert('https://moodle.schule.example'));

      for (final (art, text) in [
        (Art.info, 'App gestartet'),
        (Art.anmeldung, 'Angemeldet bei moodle.schule.example'),
        (Art.werkzeug, 'kurs_uebersicht({"kurs":12})'),
        (Art.moodle, 'POST /lib/ajax/service.php?sesskey=…&info=core_courseformat_get_state → 200'),
        (Art.info, 'kurs_uebersicht: Kurs 12 · 6 Abschnitte, 41 Aktivitäten'),
        (Art.werkzeug, 'aktivitaet_lesen({"cmid":815})'),
        (Art.moodle, 'GET /course/modedit.php?update=815 → 200'),
        (Art.moodle, 'GET /draftfile.php/5/user/draft/318824593/ohmsches-gesetz.png → 200'),
        (Art.info, 'aktivitaet_lesen: Textseite „Info: Der Vorwiderstand" gelesen, 1 Datei, 2 Befunde'),
        (Art.werkzeug, 'aendern({"ordner":"cm-815"})'),
        (Art.moodle, 'GET /course/modedit.php?update=815 → 200'),
        (Art.info, 'Freigabe angefragt: Änderung speichern? (Frist 30 min)'),
      ]) {
        protokoll.eintrag(art, text);
      }

      // Alles eingerichtet: Die echte Prüfung sähe auf diesem Rechner nach, und
      // stünde dort etwas nicht, zeigte der Dialog den echten Pfad im Bild.
      Future<Einrichtungsstand> eingerichtet() async => Einrichtungsstand(werkzeuge: [
            Werkzeugstand(
                werkzeug: ClaudeCode(const {}),
                gewaehlt: true,
                verbindung: Verbindung.aktuell,
                skills: const [],
                stand: const {},
                entfernen: const {}),
          ], skills: const [], python: true);
      await tester.pumpWidget(MoocpApp(einstellungen, protokoll, moodle, dienst, freigaben, arbeitsordner,
          einrichtungsstand: eingerichtet));
      await tester.pumpAndSettle();

      final v = zeilenVergleich(_vorher, _nachher);
      final anfrage = FreigabeAnfrage(
        titel: 'Änderung speichern?',
        punkte: [
          'Textseite „Info: Der Vorwiderstand" (cmid 815, Kurs 12)',
          'page: ${v.neu} Zeile(n) neu, ${v.weg} Zeile(n) weg',
          'Neue Dateien: led-vorwiderstand.svg',
          'Alles andere bleibt, wie es ist.',
        ],
        vergleich: [const Zeile(ZeilenArt.ausgelassen, '──── page ────'), ...v.zeilen],
      );
      final kontext = tester.element(find.byType(Hauptseite));
      showDialog<bool>(
        context: kontext,
        barrierDismissible: false,
        builder: (_) => FreigabeDialog(anfrage, freigaben),
      );
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('../docs/bilder/freigabe.png'));

      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      for (final (art, text) in [
        (Art.schreiben, 'Freigabe erteilt'),
        (Art.schreiben, 'POST /repository/repository_ajax.php?action=upload (led-vorwiderstand.svg) → 200'),
        (Art.schreiben, 'POST /course/modedit.php → 303'),
        (Art.moodle, 'GET /course/modedit.php?update=815 → 200'),
        (Art.info, 'aendern: gespeichert und zurückgelesen, 2 von 2 gleich (verified: true)'),
      ]) {
        protokoll.eintrag(art, text);
      }
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('../docs/bilder/hauptfenster.png'));
    } finally {
      debugDefaultTargetPlatformOverride = null;
      debugDisableShadows = true;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
