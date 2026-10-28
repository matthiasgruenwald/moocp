// E29: Status von Sicherung und Wiederherstellung.
//
// Geprüft werden die Aufrufe, die die MCP-Werkzeuge sicherung_status und
// wiederherstellung_status ausführen, gegen einen Vorgangsspeicher in einem
// Testordner. Die Moodle-Grenze ist ein Doppel (MoodleZugang mit vorgegebenen
// Antworten), die Uhr läuft mit der Wartezeit: schlafen heißt weiterzählen.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/moodle/sicherung.dart';
import 'package:moocp/moodle/sicherung_regeln.dart';
import 'package:moocp/moodle/wiederherstellung.dart';
import 'package:moocp/moodle/wiederherstellung_regeln.dart';
import 'package:moocp/protokoll.dart';

/// Moodle-Doppel: liefert die Fortschrittsantworten der Reihe nach, danach die letzte.
class _Moodle extends MoodleZugang {
  _Moodle(this.antworten) : super(Protokoll());

  final List<Object?> antworten;
  int abfragen = 0;

  @override
  Future<Object?> dienst(String name, Map<String, Object?> args) async {
    // Der Zielkurs ist leer: Gegenlesen findet nichts Neues.
    if (name == 'core_courseformat_get_state') return {'cm': <Object?>[], 'section': <Object?>[]};
    final i = abfragen < antworten.length ? abfragen : antworten.length - 1;
    abfragen++;
    if (antworten[i] is Exception || antworten[i] is Error) throw antworten[i]!;
    return antworten[i];
  }

  @override
  Future<Antwort> lesen(String pfadMitQuery) async {
    return Antwort(200, Uri.parse('http://127.0.0.1/'), Uint8List.fromList(utf8.encode('<html></html>')), 'text/html');
  }
}

Map<String, Object?> _fortschritt(double progress, {String? fehler, int? status, String id = 'b-1'}) => {
      'backupid': id,
      'progress': progress,
      'status': ?status,
      'error': ?fehler,
    };

void main() {
  late DateTime nun;
  late Directory ordner;

  setUp(() {
    nun = DateTime(2026, 10, 18, 10, 0);
    ordner = Directory.systemTemp.createTempSync('stillstand');
    jetzt = () => nun;
    schlafe = (d) async => nun = nun.add(d);
  });

  tearDown(() {
    jetzt = DateTime.now;
    schlafe = (d) => Future<void>.delayed(d);
    ordner.deleteSync(recursive: true);
  });

  /// Eine laufende Sicherung, Fortschritt 50 Prozent, zuletzt geändert vor [seit].
  Future<Vorgang> laufendeSicherung(Vorgaenge vg, {required Duration seit}) async {
    final v = await vg.neu(kurs: 12, cmid: 5, datei: 'a.mbz');
    await vg.aktualisieren(v, stand: SicherungStand.laufend, backupid: 'b-1', kontext: 77);
    v.fortschritt = 0.5;
    v.fortschrittSeit = nun.subtract(seit);
    await vg.aktualisieren(v);
    return v;
  }

  Future<Vorgang> laufendeWiederherstellung(Vorgaenge vg, {required Duration seit}) async {
    final v = await vg.neuWiederherstellung(kurs: 12, datei: 'b.mbz');
    await vg.aktualisieren(v,
        wiederherstellung: WiederherstellungStand.laufend, backupid: 'r-1', kontext: 77);
    v.fortschritt = 0.5;
    v.fortschrittSeit = nun.subtract(seit);
    await vg.aktualisieren(v);
    return v;
  }

  test('ausdrücklicher Fehler hat Vorrang vor unvollständigem Fortschritt', () async {
    final vg = Vorgaenge(ordner.path);
    final v = await laufendeSicherung(vg, seit: const Duration(minutes: 1));
    final moodle = _Moodle([_fortschritt(0.5, fehler: 'boom')]);

    final text = await sicherungStatus(moodle, vg, id: v.id);

    expect(text, contains('fehlgeschlagen'));
    expect(text, isNot(contains('Stillstand')));
  });

  test('unbekannte Antwort wird als unklar gemeldet, nicht als Erfolg', () async {
    final vg = Vorgaenge(ordner.path);
    final v = await laufendeSicherung(vg, seit: const Duration(minutes: 1));
    final moodle = _Moodle(['kaputt']);

    final text = await sicherungStatus(moodle, vg, id: v.id);

    expect(text, contains('Unklar'));
    expect(text, isNot(contains('fertig')));
  });

  test('Zeitlimit: Warten endet, der Vorgang bleibt laufend und die letzte Beobachtung steht im Text', () async {
    final vg = Vorgaenge(ordner.path);
    final v = await laufendeSicherung(vg, seit: const Duration(minutes: 1));
    final moodle = _Moodle([_fortschritt(0.5)]);

    final text = await sicherungStatus(moodle, vg, id: v.id);

    expect(text, contains('läuft noch'));
    expect(text, contains('sicherung_status'));
    expect(text, contains('50 %'));
    expect(text, isNot(contains('Stillstand')));
    expect((await vg.finde(v.id))!.stand, SicherungStand.laufend);
  });

  test('Stillstand nach 15 Minuten ohne Fortschritt: Beobachtung und Unsicherheit, kein Fehler, kein Erfolg', () async {
    final vg = Vorgaenge(ordner.path);
    final v = await laufendeSicherung(vg, seit: const Duration(minutes: 16));
    final moodle = _Moodle([_fortschritt(0.5)]);

    final text = await sicherungStatus(moodle, vg, id: v.id);

    expect(text, contains('Stillstand'));
    expect(text, contains('50 %'));
    expect(text, contains('nicht belegt'));
    expect(text, contains('Cron'));
    expect(text, contains('Upgrade'));
    expect(text, contains('sicherung_status'));
    expect(text, isNot(contains('fehlgeschlagen')));
    expect(text, isNot(contains('fertig')));
    expect((await vg.finde(v.id))!.stand, SicherungStand.laufend);
  });

  test('Frist ist genau 15 Minuten: 14 Minuten ohne Fortschritt sind noch kein Stillstand', () async {
    final vg = Vorgaenge(ordner.path);
    final v = await laufendeSicherung(vg, seit: const Duration(minutes: 14));
    final moodle = _Moodle([_fortschritt(0.5)]);

    final text = await sicherungStatus(moodle, vg, id: v.id);

    // Die Wartezeit läuft mit der Uhr: nach 10 Minuten endet das Warten (Zeitlimit).
    expect(text, contains('läuft noch'));
    expect(text, isNot(contains('Stillstand')));
  });

  test('späterer Erfolg wird über dieselbe Nummer nach Zeitlimit und Neustart abgeholt', () async {
    final vg = Vorgaenge(ordner.path);
    final v = await laufendeSicherung(vg, seit: const Duration(minutes: 1));
    final erstesMal = await sicherungStatus(_Moodle([_fortschritt(0.5)]), vg, id: v.id);
    expect(erstesMal, contains('läuft noch'));

    // Neustart: neuer Speicher über dieselbe Datei, Moodle meldet inzwischen Ende.
    final nach = Vorgaenge(ordner.path);
    final gespeichert = await nach.finde(v.id);
    expect(gespeichert, isNotNull);
    expect(gespeichert!.fortschritt, 0.5);
    expect(gespeichert.fortschrittSeit, v.fortschrittSeit);

    final moodle = _Moodle([_fortschritt(1.0, status: 1000)]);
    final text = await sicherungStatus(moodle, nach, id: v.id);

    expect(moodle.abfragen, 1, reason: 'dieselbe Sicherung wird über ihre Nummer abgefragt');
    expect(text, isNot(contains('läuft noch')));
    expect(text, isNot(contains('Stillstand')));
    expect(text, contains(v.id));
  });

  test('Neustart mitten im Stillstand: der Hinweis kommt aus dem gespeicherten Stand', () async {
    final vg = Vorgaenge(ordner.path);
    final v = await laufendeSicherung(vg, seit: const Duration(minutes: 20));
    final nach = Vorgaenge(ordner.path);

    final text = await sicherungStatus(_Moodle([_fortschritt(0.5)]), nach, id: v.id);

    expect(text, contains('Stillstand'));
  });

  test('Wiederherstellung: Stillstand nennt wiederherstellung_status, Cron und Ad-hoc-Aufgaben, nicht als Fehler', () async {
    final vg = Vorgaenge(ordner.path);
    final v = await laufendeWiederherstellung(vg, seit: const Duration(minutes: 16));

    final text = await wiederherstellungStatus(_Moodle([_fortschritt(0.5, id: 'r-1')]), vg, id: v.id);

    expect(text, contains('Stillstand'));
    expect(text, contains('wiederherstellung_status'));
    expect(text, contains('Ad-hoc'));
    expect(text, contains('Cron'));
    expect(text, contains('nicht belegt'));
    expect(text, isNot(contains('fehlgeschlagen')));
    expect(text, isNot(contains('verifiziert')));
  });

  test('Wiederherstellung: ausdrücklicher Fehler hat Vorrang', () async {
    final vg = Vorgaenge(ordner.path);
    final v = await laufendeWiederherstellung(vg, seit: const Duration(minutes: 1));

    final text = await wiederherstellungStatus(_Moodle([_fortschritt(0.5, fehler: 'boom', id: 'r-1')]), vg, id: v.id);

    // Das Fehlerfeld entscheidet nicht: Der Zielkurs wird geprüft. Er ist leer und das Ende des
    // Prozesses nicht belegt, also bleibt der Vorgang gesperrt und die Verwaltung wird gefragt.
    expect(text, contains('Moodle meldet einen Fehler'));
    expect(text, contains('nicht als beendet belegt'));
    expect(text, contains('Hintergrundauftrag'));
    expect(text, contains('gesperrt'));
    expect(text, isNot(contains('fehlgeschlagen')));
    expect((await vg.finde(v.id))!.wiederherstellung, WiederherstellungStand.unklar);
  });

  test('Wiederherstellung: Stillstand wird auch während derselben Abfrageschleife erkannt', () async {
    final vg = Vorgaenge(ordner.path);
    final v = await laufendeWiederherstellung(vg, seit: const Duration(minutes: 14));
    final moodle = _Moodle([_fortschritt(0.5, id: 'r-1', status: 700)]);
    final anfang = nun;
    final text = await wiederherstellungStatus(moodle, vg, id: v.id);
    expect(text, contains('Stillstand'));
    expect(nun.difference(anfang), const Duration(minutes: 1));
    expect((await vg.finde(v.id))!.wiederherstellung, WiederherstellungStand.laufend);
  });

  test('Wiederherstellung: unerwartete Hintergrundexception bleibt mit Phase gespeichert', () async {
    final vg = Vorgaenge(ordner.path);
    final v = await laufendeWiederherstellung(vg, seit: const Duration(minutes: 1));
    await expectLater(wiederherstellungStatus(_Moodle([StateError('nicht speichern')]), vg, id: v.id),
        throwsA(isA<StateError>()));
    final gelesen = (await Vorgaenge(ordner.path).finde(v.id))!;
    expect(gelesen.wiederherstellung, WiederherstellungStand.unklar);
    expect(gelesen.text, contains('Phase: Moodle-Fortschritt'));
    expect(gelesen.text, contains('StateError'));
    expect(gelesen.text, isNot(contains('nicht speichern')));
    // Die aktive Markierung wurde entfernt: eine neue reine Abfrage erreicht Moodle.
    final erneut = _Moodle(['unbekannt']);
    await wiederherstellungStatus(erneut, vg, id: v.id);
    expect(erneut.abfragen, 1);
  });

  test('erste Beobachtung setzt den Zeitpunkt auch ohne Fortschrittswert', () {
    final t = DateTime(2026, 10, 18, 10);
    expect(fortschrittNeuBeobachtet(null, null, null), isTrue);
    expect(fortschrittNeuBeobachtet(null, null, t), isFalse);
    expect(fortschrittNeuBeobachtet(0.5, 0.5, t), isFalse);
    expect(fortschrittNeuBeobachtet(0.5, 0.6, t), isTrue);
  });

  test('Frist und Fortschrittswert: Wert wird aus der Moodle-Antwort gelesen, Frist ist 15 Minuten', () {
    expect(stillstandsFrist, const Duration(minutes: 15));
    expect(fortschrittswert([_fortschritt(0.25)], 'b-1'), 0.25);
    expect(fortschrittswert([_fortschritt(0.25)], 'anderer'), isNull);
    expect(fortschrittswert('kaputt', 'b-1'), isNull);
  });
}
