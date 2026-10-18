// Befund 1 und 2 (Review): Zwei gleichzeitige Aufrufe mit derselben Datei und
// demselben Zielweg dürfen nur einen Freigabedialog erzeugen. Der zweite Aufruf
// wartet nicht auf die Freigabe des ersten, er wird sofort abgewiesen.
//
// Die Moodle-Grenze ist ein Doppel; die Freigabe zählt ihre Anfragen.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/freigabe.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/moodle/sicherung.dart';
import 'package:moocp/moodle/wiederherstellung.dart';
import 'package:moocp/protokoll.dart';
import 'package:path/path.dart' as p;

Uint8List _mbz(Map<String, List<int>> dateien) {
  final archiv = Archive();
  dateien.forEach((name, inhalt) => archiv.addFile(ArchiveFile.bytes(name, inhalt)));
  final tar = TarEncoder().encodeBytes(archiv);
  return Uint8List.fromList(GZipEncoder().encodeBytes(tar));
}

Uint8List _sicherung() => _mbz({
      'moodle_backup.xml': utf8.encode('<moodle_backup><information><format>moodle2</format><type>activity</type></information><activities><activity><modulename>page</modulename>'
          '<title>Infoblatt</title><directory>activities/page_7</directory></activity></activities></moodle_backup>'),
      'activities/page_7/inforef.xml': utf8.encode('<inforef></inforef>'),
      'files.xml': utf8.encode('<files></files>'),
    });

/// Moodle-Doppel: Kursliste, Kursstruktur und Kursseite mit Kontext.
class _Moodle extends MoodleZugang {
  _Moodle() : super(Protokoll());

  @override
  Future<Object?> dienst(String name, Map<String, Object?> args) async {
    if (name == 'core_course_get_enrolled_courses_by_timeline_classification') {
      return {
        'courses': [
          {'id': 1, 'fullname': 'Testkurs', 'shortname': 'ZZ', 'hidden': false},
        ],
      };
    }
    if (name == 'core_courseformat_get_state') {
      return {
        'cm': <Map<String, Object?>>[],
        'section': [
          {'id': 1, 'cmlist': <int>[]},
        ],
      };
    }
    throw MoodleFehler('Unerwarteter Dienst im Test: $name');
  }

  @override
  Future<Antwort> lesen(String pfadMitQuery) async => Antwort(
      200,
      Uri.parse('http://127.0.0.1/'),
      Uint8List.fromList(utf8.encode('M.cfg = {"courseId":1,"contextid":"55"};')),
      'text/html');
}

/// Zählt die Anfragen, die bei der Freigabe ankommen.
class _ZaehlFreigaben extends Freigaben {
  _ZaehlFreigaben(super.protokoll);

  int gezaehlt = 0;

  @override
  Future<bool> anfragen(FreigabeAnfrage a) {
    gezaehlt++;
    return super.anfragen(a);
  }
}

void main() {
  test('zwei gleichzeitige Aufrufe mit derselben Datei: nur einer fragt, der andere wird abgewiesen', () async {
    final ordner = Directory.systemTemp.createTempSync('wh_gleichzeitig_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    File(p.join(ordner.path, 'sicherung.mbz')).writeAsBytesSync(_sicherung());

    final moodle = _Moodle();
    final vorgaenge = Vorgaenge(ordner.path);
    final freigaben = _ZaehlFreigaben(Protokoll());

    Future<String> aufruf() => wiederherstellen(
          moodle,
          freigaben,
          vorgaenge,
          datei: 'sicherung.mbz',
          instanz: 'Test',
          weg: 'aktueller_kurs_verschmelzen',
          kurs: 1,
          name: 'Testkurs',
        );

    final erster = aufruf().then<Object>((v) => v, onError: (Object e) => e);
    final zweiter = aufruf().then<Object>((v) => v, onError: (Object e) => e);

    // Genau einer erreicht die Freigabe; welcher zuerst das Archiv liest, ist offen.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(freigaben.gezaehlt, 1, reason: 'Der zweite Aufruf darf keinen zweiten Dialog erzeugen.');

    freigaben.entscheiden(false);
    final ergebnisse = await Future.wait([erster, zweiter]);
    expect(ergebnisse.whereType<MoodleFehler>(), hasLength(1));
    expect(ergebnisse.whereType<String>().single, contains('Nicht wiederhergestellt'));

  });
}
