// Offline prüfbar: die Regeln der Auswahl-Sicherung (sichern_auswahl) aus
// moodle/sicherung_regeln.dart. Die Formularwerte folgen der gemessenen
// Feldreihenfolge des Sicherungsassistenten (/backup/backup.php?id=KURS), Seite 2
// auf dem Spike-Kurs: Abschnittsfeld, dann die Aktivitäten, die darin liegen.
// Der Ablauf gegen Moodle ist nicht geprüft.
import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/sicherung_regeln.dart';

MapEntry<String, String> e(String k, String v) => MapEntry(k, v);

/// Die Schema-Seite (Schritt 2) in gemessener Reihenfolge: Abschnitt 200 mit
/// Forum 1889 und Seite 1892, dann die Abschnitte 201 bis 204 (hier ohne
/// Aktivitäten). Jedes Feld mit `_userinfo`. Alles zunächst aus.
List<MapEntry<String, String>> schema({String stage = '2'}) => [
      e('_qf__backup_schema_form', '1'),
      e('sesskey', 'abc'),
      e('stage', stage),
      e('setting_root_users', '0'),
      e('setting_root_enrolments', '0'),
      e('setting_section_section_200_included', '0'),
      e('setting_section_section_200_userinfo', '0'),
      e('setting_activity_forum_1889_included', '0'),
      e('setting_activity_forum_1889_userinfo', '0'),
      e('setting_activity_page_1892_included', '0'),
      e('setting_activity_page_1892_userinfo', '0'),
      e('setting_section_section_201_included', '0'),
      e('setting_section_section_201_userinfo', '0'),
      e('setting_section_section_202_included', '0'),
      e('setting_section_section_202_userinfo', '0'),
      e('setting_section_section_203_included', '0'),
      e('setting_section_section_203_userinfo', '0'),
      e('setting_section_section_204_included', '0'),
      e('setting_section_section_204_userinfo', '0'),
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

/// Den Wert eines Feldes an seiner Stelle ändern; die Reihenfolge bleibt, wie sie gemessen ist.
List<MapEntry<String, String>> setze(List<MapEntry<String, String>> f, String k, String v) =>
    [for (final x in f) x.key == k ? e(k, v) : x];

/// Die eingeschalteten Setting-Felder einer Liste als Schlüssel-Menge.
Set<String> eingeschaltet(List<MapEntry<String, String>> f) =>
    {for (final x in letzteWerte(f).entries) if (x.key.startsWith('setting_') && x.value == '1') x.key};

void main() {
  group('Schema-Auswahl (mehrere Aktivitäten, Abschnitte)', () {
    test('genau die gewählten Teile ein, alle anderen aus, Nutzerdaten aus', () {
      final neu = schemaWahl(schema(), cmids: {1889}, abschnitte: {201})!;
      final w = letzteWerte(neu);
      expect(w['setting_activity_forum_1889_included'], '1');
      expect(w['setting_activity_page_1892_included'], '0');
      expect(w['setting_section_section_201_included'], '1');
      expect(w['setting_section_section_202_included'], '0');
      expect(ohneNutzerdaten(neu), isTrue);
    });

    test('eine Aktivität schaltet ihren Abschnitt als Rahmen ein, nicht die übrigen Aktivitäten', () {
      final neu = schemaWahl(schema(), cmids: {1892}, abschnitte: {})!;
      final w = letzteWerte(neu);
      expect(w['setting_section_section_200_included'], '1');
      expect(w['setting_activity_page_1892_included'], '1');
      expect(w['setting_activity_forum_1889_included'], '0');
      expect(w['setting_section_section_201_included'], '0');
    });

    test('ein gewählter Abschnitt nimmt seine Aktivitäten mit', () {
      final neu = schemaWahl(schema(), cmids: {}, abschnitte: {200})!;
      final w = letzteWerte(neu);
      expect(w['setting_section_section_200_included'], '1');
      expect(w['setting_activity_forum_1889_included'], '1');
      expect(w['setting_activity_page_1892_included'], '1');
    });

    test('_userinfo ist immer 0, auch bei Abschnitten und wenn es vorher 1 war', () {
      final f = [
        e('setting_section_section_200_included', '0'),
        e('setting_section_section_200_userinfo', '1'),
        e('setting_activity_page_1892_included', '0'),
        e('setting_activity_page_1892_userinfo', '1'),
      ];
      final neu = schemaWahl(f, cmids: {1892}, abschnitte: {200})!;
      expect(letzteWerte(neu)['setting_section_section_200_userinfo'], '0');
      expect(letzteWerte(neu)['setting_activity_page_1892_userinfo'], '0');
      expect(ohneNutzerdaten(neu), isTrue);
    });

    test('Jedes Feld behält seine Stelle; das versteckte Feld und das Kästchen bekommen denselben Wert', () {
      final f = [
        e('setting_section_section_200_included', '0'),
        e('setting_activity_page_1892_included', '0'),
        e('setting_activity_page_1892_included', '1'),
      ];
      final neu = schemaWahl([...f], cmids: {1892}, abschnitte: {})!;
      expect(neu.map((x) => x.key).toList(), [
        'setting_section_section_200_included',
        'setting_activity_page_1892_included',
        'setting_activity_page_1892_included',
      ]);
      expect(neu.map((x) => x.value).toList(), ['1', '1', '1']);
    });

    test('eine Aktivität oder ein Abschnitt fehlt auf der Seite: null', () {
      expect(schemaWahl(schema(), cmids: {9999}, abschnitte: {}), isNull);
      expect(schemaWahl(schema(), cmids: {1892}, abschnitte: {52}), isNull);
    });

    test('eine Aktivität vor dem ersten Abschnittsfeld hat keinen Abschnitt: null', () {
      final f = [e('setting_activity_forum_1889_included', '0')];
      expect(schemaWahl(f, cmids: {1889}, abschnitte: {}), isNull);
    });

    test('ohne Angaben: alles aus, aber gültig', () {
      final neu = schemaWahl(schema(), cmids: {}, abschnitte: {})!;
      final w = letzteWerte(neu);
      expect(w.entries.where((x) => x.key.startsWith('setting_') && x.value == '1'), isEmpty);
    });
  });

  group('Abschnitt je Aktivität aus der Feldreihenfolge', () {
    test('jede Aktivität gehört zum nächsten Abschnittsfeld davor', () {
      expect(abschnittJeAktivitaet(schema()), {1889: 200, 1892: 200});
    });

    test('genannte Abschnitte: gewählte Aktivität bringt ihren Abschnitt, gewählter Abschnitt seine Aktivitäten', () {
      expect(genannteAbschnitte(schema(), cmids: {1892}, abschnitte: {}), {200});
      expect(genannteAktivitaeten(schema(), cmids: {}, abschnitte: {200}), {1889, 1892});
    });
  });

  group('Bestätigung der Auswahl gegen die Bestellung', () {
    test('genau die bestellten Teile, keine Nutzerdaten: in Ordnung', () {
      expect(bestaetigungWahlFehler(bestaetigung(cmids: {1889}, abschnitte: {201}),
          cmids: {1889}, abschnitte: {201}), isNull);
    });

    test('eine Aktivität mit Rahmenabschnitt: in Ordnung, der Rahmen wird erwartet', () {
      expect(bestaetigungWahlFehler(bestaetigung(cmids: {1892}), cmids: {1892}, abschnitte: {}), isNull);
    });

    test('Moodle verwirft die Aktivität, weil der Abschnitt aus ist: Abbruch', () {
      final f = setze(bestaetigung(cmids: {1892}), 'setting_section_section_200_included', '0');
      final fehler = bestaetigungWahlFehler(f, cmids: {1892}, abschnitte: {});
      expect(fehler, isNotNull);
      expect(fehler, contains('Abschnitten'));
    });

    test('ganzer Abschnitt gewählt, eine seiner Aktivitäten fehlt auf der Bestätigung: Abbruch', () {
      final f = bestaetigung(cmids: {1889, 1892}, abschnitte: {200});
      final ohne = [
        for (final x in f)
          if (x.key != 'setting_activity_page_1892_included') x,
      ];
      final fehler = bestaetigungWahlFehler(ohne, cmids: {1889, 1892}, abschnitte: {200});
      expect(fehler, contains('1892'));
    });

    test('eine Aktivität mehr als bestellt: Abbruch, die Nummer wird genannt', () {
      final fehler = bestaetigungWahlFehler(bestaetigung(cmids: {1889, 1892}),
          cmids: {1889}, abschnitte: {});
      expect(fehler, isNotNull);
      expect(fehler, contains('1892'));
    });

    test('eine bestellte Aktivität fehlt auf der Bestätigung: Abbruch', () {
      final fehler = bestaetigungWahlFehler(bestaetigung(cmids: {1889}),
          cmids: {1889, 1892}, abschnitte: {});
      expect(fehler, contains('1892'));
    });

    test('ein Abschnitt zu viel auf der Bestätigung: Abbruch, die Nummer wird genannt', () {
      final f = setze(bestaetigung(cmids: {1892}), 'setting_section_section_201_included', '1');
      final fehler = bestaetigungWahlFehler(f, cmids: {1892}, abschnitte: {});
      expect(fehler, contains('201'));
    });

    test('Nutzerdaten eingeschaltet: Abbruch', () {
      final f = setze(bestaetigung(cmids: {1889}), 'setting_root_users', '1');
      expect(bestaetigungWahlFehler(f, cmids: {1889}, abschnitte: {}), contains('Nutzerdaten'));
    });

    test('Abschnitts-_userinfo eingeschaltet: Abbruch', () {
      final f = setze(bestaetigung(cmids: {1889}), 'setting_section_section_200_userinfo', '1');
      expect(bestaetigungWahlFehler(f, cmids: {1889}, abschnitte: {}), contains('Nutzerdaten'));
    });

    test('falsche Stufe: Abbruch', () {
      expect(bestaetigungWahlFehler(bestaetigung(cmids: {1889}, stage: '2'),
          cmids: {1889}, abschnitte: {}), isNotNull);
    });

    test('Die Menge der eingeschalteten Felder entspricht der Auswahl plus Rahmen', () {
      expect(eingeschaltet(bestaetigung(cmids: {1892})), {
        'setting_section_section_200_included',
        'setting_activity_page_1892_included',
      });
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
