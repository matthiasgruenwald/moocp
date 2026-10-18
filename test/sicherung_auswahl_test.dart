// Offline prüfbar: die Regeln der Auswahl-Sicherung (sichern_auswahl) aus
// moodle/sicherung_regeln.dart. Die Formularwerte sind Nachbildungen der
// Felder aus dem Sicherungsassistenten (/backup/backup.php?id=<kurs>); der
// Ablauf gegen Moodle ist nicht geprüft.
import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/sicherung_regeln.dart';

MapEntry<String, String> e(String k, String v) => MapEntry(k, v);

/// Die Schema-Seite (Schritt 2) mit zwei Abschnitten und drei Aktivitäten
/// (Seite 2384, Textfeld 2385, Glossar 2390). Alles zunächst aus.
List<MapEntry<String, String>> schema({String stage = '2'}) => [
      e('_qf__backup_schema_form', '1'),
      e('sesskey', 'abc'),
      e('stage', stage),
      e('setting_root_users', '0'),
      e('setting_root_enrolments', '0'),
      e('setting_section_section_50_included', '0'),
      e('setting_section_section_51_included', '0'),
      e('setting_activity_page_2384_included', '0'),
      e('setting_activity_page_2384_userinfo', '0'),
      e('setting_activity_label_2385_included', '0'),
      e('setting_activity_glossary_2390_included', '0'),
      e('setting_activity_glossary_2390_userinfo', '0'),
    ];

/// Die Bestätigungsseite (Schritt 4) zu einer Auswahl: die Felder mit den
/// gewählten Werten, Schritt 4.
List<MapEntry<String, String>> bestaetigung({
  Set<int> cmids = const {},
  Set<int> abschnitte = const {},
  String stage = '4',
}) {
  final wahl = schemaWahl(schema(), cmids: cmids, abschnitte: abschnitte)!;
  return [for (final x in wahl) e(x.key, x.key == 'stage' ? stage : x.value)];
}

void main() {
  group('Schema-Auswahl (mehrere Aktivitäten, Abschnitte)', () {
    test('genau die gewählten Teile ein, alle anderen aus, Nutzerdaten aus', () {
      final neu = schemaWahl(schema(), cmids: {2384, 2390}, abschnitte: {50})!;
      final w = letzteWerte(neu);
      expect(w['setting_activity_page_2384_included'], '1');
      expect(w['setting_activity_glossary_2390_included'], '1');
      expect(w['setting_activity_label_2385_included'], '0');
      expect(w['setting_section_section_50_included'], '1');
      expect(w['setting_section_section_51_included'], '0');
      expect(ohneNutzerdaten(neu), isTrue);
    });

    test('Jedes Feld behält seine Stelle; das versteckte Feld und das Kästchen bekommen denselben Wert', () {
      final f = [e('setting_activity_page_2384_included', '0'), e('setting_activity_page_2384_included', '1')];
      final neu = schemaWahl([...f], cmids: {2384}, abschnitte: {})!;
      expect(neu.map((x) => x.key).toList(), ['setting_activity_page_2384_included', 'setting_activity_page_2384_included']);
      expect(neu.map((x) => x.value).toList(), ['1', '1']);
    });

    test('eine Aktivität oder ein Abschnitt fehlt auf der Seite: null', () {
      expect(schemaWahl(schema(), cmids: {9999}, abschnitte: {}), isNull);
      expect(schemaWahl(schema(), cmids: {2384}, abschnitte: {52}), isNull);
    });

    test('ohne Angaben: alles aus, aber gültig', () {
      final neu = schemaWahl(schema(), cmids: {}, abschnitte: {})!;
      final w = letzteWerte(neu);
      expect(w.entries.where((x) => x.key.startsWith('setting_') && x.value == '1'), isEmpty);
    });
  });

  group('Bestätigung der Auswahl gegen die Bestellung', () {
    test('genau die bestellten Teile, keine Nutzerdaten: in Ordnung', () {
      expect(bestaetigungWahlFehler(bestaetigung(cmids: {2384, 2390}, abschnitte: {50}),
          cmids: {2384, 2390}, abschnitte: {50}), isNull);
    });

    test('eine Aktivität mehr als bestellt: Abbruch, die Nummer wird genannt', () {
      final fehler = bestaetigungWahlFehler(bestaetigung(cmids: {2384, 2390}),
          cmids: {2384}, abschnitte: {});
      expect(fehler, isNotNull);
      expect(fehler, contains('2390'));
    });

    test('eine bestellte Aktivität fehlt auf der Bestätigung: Abbruch', () {
      final fehler = bestaetigungWahlFehler(bestaetigung(cmids: {2384}),
          cmids: {2384, 2390}, abschnitte: {});
      expect(fehler, contains('2390'));
    });

    test('ein Abschnitt weicht ab: Abbruch', () {
      expect(bestaetigungWahlFehler(bestaetigung(cmids: {2384}, abschnitte: {50}),
          cmids: {2384}, abschnitte: {51}), isNotNull);
    });

    test('Nutzerdaten eingeschaltet: Abbruch', () {
      final f = bestaetigung(cmids: {2384})..removeWhere((x) => x.key == 'setting_root_users');
      f.add(e('setting_root_users', '1'));
      expect(bestaetigungWahlFehler(f, cmids: {2384}, abschnitte: {}), contains('Nutzerdaten'));
    });

    test('falsche Stufe: Abbruch', () {
      expect(bestaetigungWahlFehler(bestaetigung(cmids: {2384}, stage: '2'),
          cmids: {2384}, abschnitte: {}), isNotNull);
    });
  });

  group('Inhaltslücken je Modultyp', () {
    test('nennt nur die Typen, die Lernende füllen, ohne Doppelte', () {
      final l = inhaltsLuecken(['glossary', 'label', 'page', 'glossary', 'forum']);
      expect(l, ['Glossar: Einträge der Lernenden', 'Forum: alle Beiträge']);
    });

    test('ohne solche Typen: leer', () {
      expect(inhaltsLuecken(['label', 'page', 'resource', 'url', 'subsection']), isEmpty);
    });
  });

  group('Art der Sicherung und Dateiname', () {
    test('Kurs ohne Einschränkung, Kurs eingeschränkt, Auswahl', () {
      expect(auswahlArt(ganzerKurs: true, nurGenannte: false), AuswahlArt.ganzerKurs);
      expect(auswahlArt(ganzerKurs: true, nurGenannte: true), AuswahlArt.ganzerKursEingeschraenkt);
      expect(auswahlArt(ganzerKurs: false, nurGenannte: true), AuswahlArt.auswahl);
    });

    test('Der Kurs bleibt Kurs, auch mit einer einzigen Aktivität', () {
      expect(auswahlArt(ganzerKurs: true, nurGenannte: true).text, contains('eingeschränkt'));
      expect(auswahlArt(ganzerKurs: true, nurGenannte: true), isNot(AuswahlArt.auswahl));
    });

    test('Dateiname: Kursnummer und Zeit, sonst nichts', () {
      expect(kursSicherungsName(41, DateTime(2026, 10, 18, 9, 5, 7)), 'kurs-k41-2026-10-18_090507.mbz');
    });
  });
}
