import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/board.dart';

void main() {
  group('Board: Rückleseprobe', () {
    final vorher = [
      BoardSpalte(1, 'ZZ Ideen', false, 1, [(11, 'ZZ Start', 'Erster Gedanke')]),
      BoardSpalte(2, 'ZZ Fragen', false, 0, const []),
    ];

    test('jede Aktion wird am Endstand geprüft', () {
      final nachher = [
        BoardSpalte(1, 'ZZ Einfälle', true, 2, [(11, 'ZZ Start', 'Neuer Gedanke'), (12, 'ZZ Neu', '<p>Text  hier</p>')]),
        BoardSpalte(3, 'ZZ Antworten &amp; mehr', false, 0, const []),
      ];
      final probe = boardPruefen([
        {'art': 'spalte_umbenennen', 'spalte': 1, 'name': 'ZZ Einfälle'},
        {'art': 'spalte_sperren', 'spalte': 1, 'gesperrt': true},
        {'art': 'spalte_loeschen', 'spalte': 2},
        {'art': 'spalte_neu', 'name': 'ZZ Antworten & mehr'},
        {'art': 'notiz_aendern', 'notiz': 11, 'inhalt': 'Neuer Gedanke'},
        {'art': 'notiz_neu', 'spalte': 1, 'titel': 'ZZ Neu', 'inhalt': 'Text hier'},
        {'art': 'spalte_verschieben', 'spalte': 3, 'position': 1},
      ], vorher, nachher);
      expect(probe.ok, isTrue, reason: probe.text);
      expect(probe.gesamt, 7);
    });

    test('nicht Angekommenes ist eine Abweichung', () {
      final probe = boardPruefen([
        {'art': 'notiz_neu', 'spalte': 2, 'titel': 'ZZ Neu', 'inhalt': ''},
        {'art': 'spalte_umbenennen', 'spalte': 1, 'name': 'ZZ Einfälle'},
        {'art': 'spalte_loeschen', 'spalte': 2},
        {'art': 'notiz_loeschen', 'notiz': 11},
      ], vorher, vorher);
      expect(probe.ok, isFalse);
      // notiz_neu in Spalte 2 ist überholt: die spätere Aktion löscht die Spalte.
      expect(probe.gesamt, 3);
      expect(probe.abweichend, hasLength(3));
    });

    test('eine spätere Aktion am selben Ziel überholt die frühere', () {
      final nachher = [BoardSpalte(1, 'ZZ Zweiter Name', false, 1, vorher.first.eigene)];
      final probe = boardPruefen([
        {'art': 'spalte_umbenennen', 'spalte': 1, 'name': 'ZZ Erster Name'},
        {'art': 'spalte_umbenennen', 'spalte': 1, 'name': 'ZZ Zweiter Name'},
        {'art': 'notiz_aendern', 'notiz': 11, 'titel': 'ZZ Weg'},
        {'art': 'notiz_loeschen', 'notiz': 11},
      ], vorher, nachher);
      expect(probe.gesamt, 2);
      expect(probe.abweichend, ['Notiz 11 ist noch da']);
    });
  });

  group('Kanban: Rückleseprobe', () {
    KanbanKarte karte(int id, String titel, int spalte, [String beschreibung = '']) =>
        KanbanKarte(id, titel, spalte, beschreibung, false, false);
    final vorher = [
      (1, 'ZZ Offen', [karte(11, 'ZZ A', 1), karte(12, 'ZZ B', 1)]),
      (2, 'ZZ Fertig', <KanbanKarte>[]),
    ];

    test('Positionen werden geprüft, wo die Aktion eine nennt', () {
      final nachher = [
        (2, 'ZZ Erledigt', [karte(11, 'ZZ A', 2), karte(12, 'ZZ B neu', 2, '<p>Mit  Text</p>')]),
        (1, 'ZZ Offen', [karte(13, 'ZZ C', 1)]),
      ];
      final probe = kanbanPruefen([
        {'art': 'spalte_umbenennen', 'spalte': 2, 'titel': 'ZZ Erledigt'},
        {'art': 'spalte_verschieben', 'spalte': 2, 'nach': 0},
        {'art': 'karte_verschieben', 'karte': 11, 'spalte': 2},
        {'art': 'karte_verschieben', 'karte': 12, 'spalte': 2, 'nach': 11},
        {'art': 'karte_aendern', 'karte': 12, 'titel': 'ZZ B neu', 'beschreibung': 'Mit Text'},
        {'art': 'karte_neu', 'spalte': 1, 'titel': 'ZZ C'},
      ], vorher, nachher);
      expect(probe.ok, isTrue, reason: probe.text);
      expect(probe.gesamt, 6);
    });

    test('falsche Stelle und Verbliebenes sind Abweichungen', () {
      final probe = kanbanPruefen([
        {'art': 'spalte_verschieben', 'spalte': 2, 'nach': 0},
        {'art': 'karte_verschieben', 'karte': 12, 'spalte': 1, 'nach': 99},
        {'art': 'karte_loeschen', 'karte': 11},
        {'art': 'spalte_neu', 'titel': 'ZZ Neu'},
      ], vorher, vorher);
      expect(probe.abweichend, hasLength(4));
    });

    test('löscht eine spätere Aktion das nach-Ziel, zählt nur die Spalte', () {
      final nachher = [
        (1, 'ZZ Offen', <KanbanKarte>[]),
        (2, 'ZZ Fertig', [karte(12, 'ZZ B', 2)]),
      ];
      final probe = kanbanPruefen([
        {'art': 'karte_verschieben', 'karte': 11, 'spalte': 2},
        {'art': 'karte_verschieben', 'karte': 12, 'spalte': 2, 'nach': 11},
        {'art': 'karte_loeschen', 'karte': 11},
      ], vorher, nachher);
      expect(probe.ok, isTrue, reason: probe.text);
      expect(probe.gesamt, 2);
    });
  });
}
