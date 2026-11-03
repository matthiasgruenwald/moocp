// frage_ersetzen: eine Frage durch eine neu importierte ersetzen, in den
// genannten Tests an derselben Stelle, mit einer Freigabe.
//
// Gebraucht, wo das Formular der Frage nicht reicht: Aufbau geändert
// (weitere Antwort, Knoten, Eingabe), STACK-Testfälle geändert, oder das
// Formular wird abgewiesen (Schutzdienst vor der Instanz, Programmcode als
// Text). Sonst ist aendern der bessere Weg: neue Version, Tests folgen von
// selbst, Versuche bleiben bei ihrer Version.
//
// Reihenfolge so, dass bis zum Löschen nichts verloren geht: erst prüfen
// (Namen, Plätze, XML, Sachnummern), dann Freigabe, dann importieren und die
// Nachweise laufen lassen (STACK-Fragetests, CodeRunner-Musterlösung) --
// scheitert einer, kommt die neue Frage in keinen Test. Dann je Test der
// Platztausch (platzErsetzen, test.dart), dann erst das Löschen der alten
// Frage. Moodle hält Sachnummern eindeutig je Kategorie; trägt die neue
// Frage die der alten, wird sie ohne importiert und nach dem Löschen über
// das Formular gesetzt. Hält ein Schutzdienst dieses Formular an, bleibt die
// neue Frage ohne Sachnummer -- die Antwort sagt es.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../freigabe.dart';
import 'formular.dart';
import 'formular_schreiben.dart';
import 'fragen.dart';
import 'fragen_xml.dart';
import 'kurs.dart';
import 'moodle_zugang.dart';
import 'test.dart';

/// Leert die Sachnummer [idnummer] in den Fragen des XML (nicht in
/// Kategorien, die eine eigene tragen können).
String ohneSachnummer(String xml, String idnummer) {
  final doc = XmlDocument.parse(xml);
  for (final q in doc.rootElement.findElements('question')) {
    if (q.getAttribute('type') == 'category') continue;
    final e = q.getElement('idnumber');
    if (e != null && e.innerText.trim() == idnummer) e.innerText = '';
  }
  return doc.toXmlString();
}

Future<String> frageErsetzen(
  MoodleZugang moodle,
  Freigaben freigaben,
  String arbeitsordner, {
  required int sammlung,
  required String kategorie,
  required int frage,
  required String name,
  required String datei,
  required List<(int, String)> tests,
  required bool loeschen,
  required Future<String> Function(int frage) stackTesten,
}) async {
  // --- Prüfen; nichts wird geschrieben -----------------------------------
  if (tests.isEmpty) {
    throw MoodleFehler('tests: mindestens ein Test, in dem die Frage ersetzt wird. Nur importieren und löschen '
        'geht mit fragen_importieren und fragen_loeschen.');
  }
  if ({for (final (c, _) in tests) c}.length != tests.length) throw MoodleFehler('Ein Test ist doppelt genannt.');
  final alt = (await loeschenPruefen(moodle, sammlung, [(frage, name)])).single;

  final pfad = imArbeitsordner(datei, arbeitsordner);
  if (!File(pfad).existsSync()) throw MoodleFehler('Datei $pfad gibt es nicht.');
  var (xml, neu) =
      fragenXmlPruefen(await File(pfad).readAsString(encoding: utf8), dateiordner: p.join(p.dirname(pfad), 'dateien'));
  if (neu.length != 1) {
    throw MoodleFehler('Die Datei enthält ${neu.length} Fragen; zum Ersetzen genau eine.');
  }
  final ersatz = neu.single;

  final kats = await kategorienLesen(moodle, sammlung);
  final k = kategorieWaehlen(kats, kategorie);
  final inKategorie = fragenAusXml(await exportieren(moodle, sammlung, k));
  if (!inKategorie.any((f) => f.id == alt.id)) {
    throw MoodleFehler('Abgebrochen, nichts geändert: Frage ${alt.id} „${alt.name}" steht nicht in Kategorie '
        '„${k.name}". Die neue Frage kommt in die Kategorie der alten (fragen_lesen nennt sie).');
  }
  // Sachnummer: Trägt die neue die der alten, kommt sie nach dem Löschen.
  // Gehört sie einer anderen Frage der Kategorie, verwürfe Moodle sie still.
  final idn = ersatz.idnummer;
  final nachher = idn != null && idn == alt.idnummer;
  if (idn != null && !nachher) {
    final belegt = inKategorie.where((f) => f.idnummer == idn).toList();
    if (belegt.isNotEmpty) {
      throw MoodleFehler('Abgebrochen, nichts geändert: Die Sachnummer $idn trägt in „${k.name}" schon '
          '„${belegt.first.name}" (${belegt.first.id}).');
    }
  }
  if (nachher) xml = ohneSachnummer(xml, idn);

  final plaene = <(TestAufbau, KursAktivitaet, List<Platz>)>[];
  for (final (cmid, testname) in tests) {
    final (t, c) = await testMitNamen(moodle, cmid, testname);
    final plaetze = t.plaetze.where((x) => x.frage == alt.id).toList();
    if (plaetze.isEmpty) {
      throw MoodleFehler('Abgebrochen, nichts geändert: Frage ${alt.id} steht nicht in Test „${c.name}" '
          '(cmid $cmid). Plätze und questionids zeigt test_lesen.');
    }
    plaene.add((t, c, plaetze));
  }

  // --- Freigabe ----------------------------------------------------------
  final ja = await freigaben.anfragen(FreigabeAnfrage(
    titel: 'Frage ersetzen?',
    punkte: [
      'Fragensammlung cmid $sammlung, Kategorie „${k.name}"',
      'Alt: „${alt.name}" (${alt.typ}, questionid ${alt.id}${alt.idnummer == null ? '' : ', ${alt.idnummer}'})',
      'Neu aus ${p.basename(pfad)}: „${ersatz.name}" (${ersatz.typ}${idn == null ? '' : ', $idn'})',
      for (final (t, c, plaetze) in plaene)
        for (final x in plaetze)
          'Test „${c.name}" (cmid ${t.cmid}${t.kurs == null ? '' : ', ${await kursBezeichnung(moodle, t.kurs!)}'}): '
              'Platz ${t.plaetze.indexOf(x) + 1}, Seite ${x.seite ?? '?'}, ${_p(x.punkte)} Punkte -- die neue Frage an '
              'dieselbe Stelle mit denselben Punkten',
      for (final (t, c, _) in plaene)
        if (t.hatVersuche) 'ACHTUNG: Zu „${c.name}" gibt es bereits Versuche -- der Tausch verschiebt Bewertungen.',
      loeschen
          ? 'Danach die alte Frage endgültig löschen, mit allen Versionen. Steckt sie noch in einem anderen Test, '
              'verbirgt Moodle sie nur.'
          : 'Die alte Frage bleibt in der Sammlung.',
      if (nachher)
        loeschen
            ? 'Die Sachnummer $idn geht nach dem Löschen an die neue Frage.'
            : 'Die Sachnummer $idn bleibt bei der alten Frage; die neue kommt ohne.',
    ],
    vergleich: const [],
    knopf: 'Ersetzen',
    ohneEntscheidung: 'wird nichts geändert',
  ));
  if (!ja) return 'Nicht ersetzt: in der App abgelehnt oder nicht rechtzeitig freigegeben. Nichts geändert.';

  // --- Ausführen ---------------------------------------------------------
  final b = StringBuffer();
  final i = await importAusfuehren(moodle, sammlung, k, p.basename(pfad), xml, 1);
  b.write(i.text);
  if (!i.ok || i.neu.length != 1 || i.neu.single.id == null) {
    return '${b}Abgebrochen nach dem Import: Tests und alte Frage unverändert. verified: false';
  }
  final n = await importNachweise(moodle, sammlung, i.neu, stackTesten);
  b.write(n.text);
  if (!n.ok) {
    return '$b\nAbgebrochen: Ein Nachweis ist nicht bestanden, deshalb steht die neue Frage in keinem Test. '
        'Tests und alte Frage unverändert; die neue (${i.neu.single.id}) liegt in „${k.name}". Sie mit '
        'fragen_loeschen entfernen, die Datei nachbessern und frage_ersetzen erneut aufrufen -- ein neuer Aufruf '
        'importiert neu. verified: false';
  }
  var neueId = n.neueIds[i.neu.single.id] ?? i.neu.single.id!;

  // Was vom Auftrag abweicht; die Plätze stimmen hier schon alle.
  final abweichend = <String>[];
  b.writeln('\nPlätze:');
  for (final (t0, c, plaetze) in plaene) {
    var t = t0;
    for (final x in plaetze) {
      final (t1, zeile, gut) = await platzErsetzen(moodle, t, x, neueId);
      t = t1;
      b.writeln('  Test „${c.name}": $zeile');
      if (!gut) {
        return '$b\nAbgebrochen nach diesem Platz: Die übrigen Tests sind unverändert, die alte Frage ist nicht '
            'gelöscht. verified: false\n\n${t.text()}';
      }
    }
    final f = t.befunde();
    if (f.isNotEmpty) b.writeln('  Befunde zu „${c.name}": ${f.join(' ')}');
  }

  var weg = false;
  if (loeschen) {
    final (zeilen, alleWeg) = await loeschenOhneFreigabe(moodle, arbeitsordner, sammlung, [alt]);
    weg = alleWeg;
    if (!alleWeg) abweichend.add('alte Frage nicht gelöscht');
    b.writeln('\nAlte Frage:\n$zeilen'.trimRight());
  }

  if (nachher) {
    if (!weg) {
      b.writeln('\nSachnummer $idn: bleibt bei der alten Frage, die neue ($neueId) hat keine.');
    } else {
      try {
        final f = await formularHolen(moodle, '/question/bank/editquestion/question.php?cmid=$sammlung&id=$neueId');
        if (wertIn(f.felder, 'idnumber') == null) throw MoodleFehler('Das Formular hat kein Feld idnumber.');
        setze(f.felder, 'idnumber', idn);
        await absenden(moodle, f, knoepfe: const ['submitbutton']);
        // Speichern legt eine neue Version an; die Sachnummer findet sie.
        final mit = fragenAusXml(await exportieren(moodle, sammlung, k)).where((x) => x.idnummer == idn).toList();
        final gesetzt = mit.length == 1;
        if (gesetzt) neueId = mit.single.id ?? neueId;
        if (!gesetzt) abweichend.add('Sachnummer nicht gesetzt');
        b.writeln('\nSachnummer $idn an die neue Frage: ${gesetzt ? 'gesetzt (neue Version $neueId)' : 'NICHT gefunden'}');
      } on MoodleFehler catch (x) {
        abweichend.add('Sachnummer nicht gesetzt');
        b.writeln('\nSachnummer $idn NICHT gesetzt: ${x.meldung}. Die neue Frage ($neueId) ist sonst fertig und '
            'steht in den Tests; die Sachnummer setzt die Lehrkraft im Formular der Frage.');
      }
    }
  }
  b.writeln('\nNeue Frage: questionid $neueId, in allen genannten Tests an der Stelle der alten. '
      '${abweichend.isEmpty ? '' : 'Abweichend vom Auftrag: ${abweichend.join('; ')}. '}verified: ${abweichend.isEmpty}');
  return b.toString();
}

String _p(double? x) => x == null ? '?' : (x == x.roundToDouble() ? x.toInt().toString() : x.toString());
