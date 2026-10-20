// Übertragung in einem Auftrag: Prüfung der Ziele, Wiederholungsschutz,
// das Übertragungsprotokoll uebertragungen.json und der Ablauf je Ziel.
//
// Reine Logik: Moodle wird nur über die übergebene Funktion [ZielLauf]
// angesprochen. Die Tests (test/uebertragung_lauf_test.dart) geben Fakes hinein
// und prüfen Planung, Wiederholungsschutz und einen teilweise fehlgeschlagenen
// Lauf, bei dem die erfolgreichen Ziele nicht noch einmal laufen.
//
// Ein Ziel liegt immer auf derselben Instanz wie das Werkzeug (E31). Ziele auf
// einer anderen Instanz bedient die KI mit zwei Aufrufen (Skill moodle).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'moodle/wiederherstellung_regeln.dart';

/// Der Stand eines Ziels nach einem Lauf. [abgelehnt] stoppt den Lauf: die
/// Lehrkraft hat in der App nein gesagt, die übrigen Ziele beginnen nicht.
/// [nichtBegonnen] steht nur im Bericht, nie im Protokoll.
enum ZielStand {
  fertig('fertig'),
  fehlgeschlagen('fehlgeschlagen'),
  unklar('unklar'),
  abgelehnt('abgelehnt'),
  nichtBegonnen('nicht begonnen');

  const ZielStand(this.text);

  final String text;

  static ZielStand? aus(Object? t) {
    for (final s in values) {
      if (s.text == t) return s;
    }
    return null;
  }
}

/// Der Stand eines Ziels aus dem Stand seines Wiederherstellungs-Vorgangs.
/// Alles, was weder fertig noch fehlgeschlagen ist, gilt als unklar: dann
/// wird nicht erneut gesendet, sondern zuerst geprüft.
ZielStand zielStandAus(WiederherstellungStand? stand) => switch (stand) {
  WiederherstellungStand.fertig => ZielStand.fertig,
  WiederherstellungStand.fehlgeschlagen => ZielStand.fehlgeschlagen,
  _ => ZielStand.unklar,
};

/// Der Stand der Lernlandkarten eines Ziels, getrennt vom Stand des
/// Kopierens. [ausstehend] steht im Protokoll, sobald das Kopieren fertig ist und
/// die Karten noch verknüpft werden: Ein Abbruch dazwischen bleibt sichtbar und
/// löst keinen neuen Lauf aus. Nur [verknuepft] heißt: zurückgelesen und
/// vollständig verknüpft; alles andere bestätigt keine vollständige Verknüpfung.
enum KartenStand {
  ausstehend('ausstehend'),
  verknuepft('verknüpft'),
  offen('offen'),
  unklar('unklar');

  const KartenStand(this.text);

  final String text;

  static KartenStand? aus(Object? t) {
    for (final s in values) {
      if (s.text == t) return s;
    }
    return null;
  }
}

/// Eine Zielangabe, wie die KI sie schickt. [weg] ist der Name des Zielwegs,
/// nicht geprüft. [loeschend] muss bei löschenden Wegen true sein und sonst
/// fehlen; sonst kommt eine Rückfrage, bevor etwas geschieht.
class ZielAngabe {
  const ZielAngabe({
    required this.kurs,
    required this.name,
    this.weg,
    this.loeschend = false,
  });

  final int kurs;
  final String name;
  final String? weg;
  final bool loeschend;
}

/// Ein geprüftes Ziel: Kurs, Name zur Bestätigung und der aufgelöste Zielweg.
class PlanZiel {
  const PlanZiel({required this.kurs, required this.name, required this.weg});

  final int kurs;
  final String name;
  final Zielweg weg;
}

/// Ergebnis der Prüfung: die geprüften Ziele oder eine Rückfrage. Keine
/// Rückfrage wird geraten (A5, „nie raten").
sealed class Planung {
  const Planung();
}

class PlanungOk extends Planung {
  const PlanungOk(this.ziele);

  final List<PlanZiel> ziele;
}

class PlanungRueckfrage extends Planung {
  const PlanungRueckfrage(this.text);

  final String text;
}

/// Prüft die Zielangaben, bevor etwas geschieht. [quellkurs] ist der Kurs, aus
/// dem gesichert wird (nur ohne Datei); er darf kein Ziel sein, weil ein
/// löschender Weg sonst die Quelle leert.
Planung pruefeZiele(List<ZielAngabe> ziele, {int? quellkurs}) {
  if (ziele.isEmpty) {
    return const PlanungRueckfrage(
      'Welche Kurse sollen die Übertragung bekommen? Je Ziel braucht es kurs, name und weg.',
    );
  }
  final gesehen = <int>{};
  final geprueft = <PlanZiel>[];
  for (final z in ziele) {
    if (z.kurs <= 0) {
      return const PlanungRueckfrage(
        'Eine Kursnummer der Ziele ist keine gültige Kurs-ID.',
      );
    }
    if (!gesehen.add(z.kurs)) {
      return PlanungRueckfrage(
        'Der Kurs ${z.kurs} steht zweimal unter den Zielen.',
      );
    }
    if (quellkurs != null && z.kurs == quellkurs) {
      return PlanungRueckfrage(
        'Der Kurs ${z.kurs} ist Quelle und Ziel zugleich. Welcher Kurs ist das Ziel?',
      );
    }
    final text = z.weg;
    if (text == null || text.trim().isEmpty) {
      return PlanungRueckfrage(
        'Für Kurs ${z.kurs} fehlt der Zielweg. Welcher soll es sein? Möglich sind: ${Zielweg.optionen}. Nichts wird geraten.',
      );
    }
    final weg = Zielweg.aus(text);
    if (weg == null) {
      return PlanungRueckfrage(
        'Der Weg „$text" ist unbekannt. Möglich sind: ${Zielweg.optionen}. Nichts wird geraten.',
      );
    }
    if (!weg.brauchtKurs) {
      return PlanungRueckfrage(
        'Für Kurs ${z.kurs}: uebertragen legt keinen neuen Kurs an. Dafür wiederherstellen_datei mit neuer_kurs verwenden.',
      );
    }
    if (z.name.trim().isEmpty) {
      return PlanungRueckfrage(
        'Für Kurs ${z.kurs} fehlt der Kursname (name), wie er jetzt in Moodle steht.',
      );
    }
    if (weg.loescht && !z.loeschend) {
      return PlanungRueckfrage(
        'Für Kurs ${z.kurs} löscht der Weg ${weg.nennung} vorhandene Inhalte. Dafür braucht es loeschend: true '
        'in diesem Ziel. Nichts wird geraten.',
      );
    }
    if (z.loeschend && !weg.loescht) {
      return PlanungRueckfrage(
        'Für Kurs ${z.kurs} gilt loeschend nur für die löschenden Wege. Bitte loeschend weglassen. Nichts wird geraten.',
      );
    }
    geprueft.add(PlanZiel(kurs: z.kurs, name: z.name, weg: weg));
  }
  return PlanungOk(List.unmodifiable(geprueft));
}

/// Ein Eintrag im Übertragungsprotokoll. [datei] ist der Name der Sicherungsdatei;
/// [quellkurs] der Kurs, aus dem frisch gesichert wurde, damit ein Lauf auch
/// nach einer neuen Sicherung gegen einen schon reservierten Zielkurs gesperrt ist.
class UebertragungsEintrag {
  const UebertragungsEintrag({
    required this.datei,
    required this.profil,
    required this.kurs,
    required this.stand,
    required this.zeit,
    this.quellkurs,
    this.vorgang,
    this.karten,
  });

  final String datei;
  final String profil;
  final int kurs;
  final ZielStand stand;
  final DateTime zeit;
  final int? quellkurs;
  final String? vorgang;

  /// Stand der Lernlandkarten dieses Ziels; null, wenn der Auftrag keine hatte.
  final KartenStand? karten;

  Map<String, Object?> toJson() => {
    'datei': datei,
    'profil': profil,
    'kurs': kurs,
    'stand': stand.text,
    'zeit': zeit.toIso8601String(),
    if (quellkurs != null) 'quellkurs': quellkurs,
    if (vorgang != null) 'vorgang': vorgang,
    if (karten != null) 'karten': karten!.text,
  };

  static UebertragungsEintrag? ausJson(Object? j) {
    if (j is! Map) return null;
    final datei = j['datei'];
    final profil = j['profil'];
    final kurs = j['kurs'];
    final stand = ZielStand.aus(j['stand']);
    final zeit = j['zeit'] is String
        ? DateTime.tryParse(j['zeit'] as String)
        : null;
    final quellkurs = j['quellkurs'];
    final vorgang = j['vorgang'];
    final karten = KartenStand.aus(j['karten']);
    if (j['karten'] != null && karten == null) return null;
    if (datei is! String ||
        profil is! String ||
        kurs is! int ||
        stand == null ||
        zeit == null) {
      return null;
    }
    if (quellkurs != null && quellkurs is! int) return null;
    if (vorgang != null && vorgang is! String) return null;
    return UebertragungsEintrag(
      datei: datei,
      profil: profil,
      kurs: kurs,
      stand: stand,
      zeit: zeit,
      quellkurs: quellkurs as int?,
      vorgang: vorgang as String?,
      karten: karten,
    );
  }
}

/// Der Wiederholungsschutz: Ist für dieses Ziel schon etwas übertragen oder
/// versucht worden, gibt es eine Rückfrage statt eines erneuten Imports.
/// Die Datei oder derselbe Quellkurs trifft den Eintrag.
/// Abgelehnte Versuche zählen nicht: nichts wurde geschrieben. Eine bewusste
/// Wiederholung geht nicht über uebertragen, sondern über wiederherstellen_datei
/// mit wiederholung_von.
String? wiederholungsRueckfrage(
  List<UebertragungsEintrag> protokoll, {
  required String profil,
  required int kurs,
  String? datei,
  int? quellkurs,
}) {
  final treffer = [
    for (final e in protokoll)
      if (e.profil == profil &&
          e.kurs == kurs &&
          e.stand != ZielStand.abgelehnt &&
          ((datei != null && e.datei == datei) ||
              (quellkurs != null && e.quellkurs == quellkurs)))
        e,
  ];
  if (treffer.isEmpty) return null;
  final e = treffer.last;
  final nummer = e.vorgang == null ? '' : ' (Nummer ${e.vorgang})';
  final karten = e.karten == null || e.karten == KartenStand.verknuepft
      ? ''
      : ' Die Lernlandkarten dieses Ziels sind „${e.karten!.text}": nicht verifiziert; Sichtbarkeit in Moodle prüfen. '
            'Sie werden nicht durch eine Wiederholung, sondern mit aktivitaet_lesen und '
            'lernlandkarte_verknuepfungen_setzen geklärt.';
  return 'Für Kurs $kurs ist schon einmal übertragen worden: Stand „${e.stand.text}", '
      'am ${e.zeit.toIso8601String()}$nummer.$karten Nichts wird erneut importiert. Erst den Stand klären '
      '(wiederherstellung_status mit der Nummer). Will die Lehrkraft die Wiederholung trotzdem, für diesen Kurs '
      'wiederherstellen_datei mit wiederholung_von=${e.vorgang ?? '<Nummer>'} und nach Freigabe.';
}

/// Das Übertragungsprotokoll uebertragungen.json im Einstellungsordner. Jeder
/// Eintrag wird sofort und atomar geschrieben, damit ein Abbruch mitten im
/// Lauf nichts Erledigtes verliert.
class Uebertragungsprotokoll {
  Uebertragungsprotokoll._(this._datei, this.eintraege);

  final File _datei;
  final List<UebertragungsEintrag> eintraege;

  static Future<Uebertragungsprotokoll> laden(String pfad) async {
    final datei = File(pfad);
    if (!await datei.exists()) return Uebertragungsprotokoll._(datei, []);
    final Object? j;
    try {
      j = jsonDecode(await datei.readAsString());
    } on FormatException {
      throw StateError('uebertragungen.json ist beschädigt. Nichts geändert.');
    }
    if (j is! List) {
      throw StateError('uebertragungen.json ist beschädigt. Nichts geändert.');
    }
    final liste = <UebertragungsEintrag>[];
    for (final e in j) {
      final x = UebertragungsEintrag.ausJson(e);
      if (x == null) {
        throw StateError(
          'uebertragungen.json ist beschädigt. Nichts geändert.',
        );
      }
      liste.add(x);
    }
    return Uebertragungsprotokoll._(datei, liste);
  }

  // Alle Sitzungen teilen diese Datei; ein alter Snapshot darf neuere Einträge nicht ersetzen.
  static final Map<String, Future<void>> _schreibend = {};

  Future<void> reservieren(UebertragungsEintrag e) =>
      _schreiben(e, reservieren: true);

  Future<void> eintragen(UebertragungsEintrag e) => _schreiben(e);

  Future<void> _schreiben(UebertragungsEintrag e, {bool reservieren = false}) {
    final schluessel = p.normalize(p.absolute(_datei.path));
    final vorher = _schreibend[schluessel] ?? Future<void>.value();
    final schreiben = vorher
        .catchError((Object _) {
          // Der frühere Aufruf meldet seinen Fehler selbst; frisch lesen prüft die Datei erneut.
        })
        .then((_) async {
          final aktuell = await laden(_datei.path);
          final liste = [...aktuell.eintraege];
          if (reservieren) {
            final rueckfrage = wiederholungsRueckfrage(
              liste,
              profil: e.profil,
              kurs: e.kurs,
              datei: e.datei,
              quellkurs: e.quellkurs,
            );
            if (rueckfrage != null) throw StateError(rueckfrage);
            liste.add(e);
          } else {
            final index = liste.lastIndexWhere(
              (alt) =>
                  alt.stand == ZielStand.unklar &&
                  alt.vorgang == null &&
                  alt.profil == e.profil &&
                  alt.kurs == e.kurs &&
                  alt.datei == e.datei &&
                  alt.quellkurs == e.quellkurs,
            );
            if (index < 0) {
              liste.add(e);
            } else {
              liste[index] = e;
            }
          }
          await _datei.parent.create(recursive: true);
          final tmp = File('${_datei.path}.tmp');
          await tmp.writeAsString(
            jsonEncode([for (final x in liste) x.toJson()]),
            flush: true,
          );
          await tmp.rename(_datei.path);
          eintraege
            ..clear()
            ..addAll(liste);
        });
    _schreibend[schluessel] = schreiben;
    return schreiben;
  }
}

/// Das Ergebnis eines Ziels aus [ZielLauf]: Stand, Nummer des Vorgangs (wenn
/// einer angelegt wurde) und der Text für den Bericht.
class ZielErgebnis {
  const ZielErgebnis(this.stand, {this.vorgang, this.text = ''});

  final ZielStand stand;
  final String? vorgang;
  final String text;
}

/// Führt ein Ziel aus (Wiederherstellung über Moodle). Im Produkt die Verdrahtung
/// in mcp_dienst.dart; in den Tests ein Fake.
typedef ZielLauf = Future<ZielErgebnis> Function(PlanZiel ziel);

/// Das Ergebnis der Lernlandkarten eines Ziels aus [KartenLauf].
class KartenErgebnis {
  const KartenErgebnis(this.stand, this.text, {this.freigabeAbgelehnt = false});

  final KartenStand stand;
  final String text;
  final bool freigabeAbgelehnt;
}

/// Verknüpft die Lernlandkarten eines Ziels, nachdem das Kopieren dort fertig
/// ist ([restore] ist dessen Ergebnis). Null: der Auftrag hat keine Karten. Im
/// Produkt die Verdrahtung in mcp_dienst.dart; in den Tests ein Fake.
typedef KartenLauf = Future<KartenErgebnis?> Function(
  PlanZiel ziel,
  ZielErgebnis restore,
);

class ZielBericht {
  const ZielBericht(
    this.ziel,
    this.stand,
    this.vorgang,
    this.text, {
    this.karten,
    this.kartenText = '',
  });

  final PlanZiel ziel;
  final ZielStand stand;
  final String? vorgang;
  final String text;
  final KartenStand? karten;
  final String kartenText;
}

/// Führt die Ziele nacheinander aus. Jedes Ziel bekommt seinen eigenen Lauf
/// und sein eigenes Ergebnis und wird sofort im Protokoll festgehalten. Ein
/// fehlgeschlagenes oder unklares Ziel stoppt die übrigen nicht; eine
/// Ablehnung schon. Bereits gelaufene Ziele werden nie wieder angefasst.
Future<List<ZielBericht>> uebertragungAusfuehren(
  List<PlanZiel> ziele, {
  required String datei,
  required String profil,
  int? quellkurs,
  required Uebertragungsprotokoll protokoll,
  required ZielLauf lauf,
  KartenLauf? kartenLauf,
}) async {
  final berichte = <ZielBericht>[];
  var abgelehnt = false;
  for (final z in ziele) {
    if (abgelehnt) {
      berichte.add(ZielBericht(z, ZielStand.nichtBegonnen, null, ''));
      continue;
    }
    await protokoll.reservieren(
      UebertragungsEintrag(
        datei: datei,
        profil: profil,
        kurs: z.kurs,
        stand: ZielStand.unklar,
        zeit: DateTime.now(),
        quellkurs: quellkurs,
      ),
    );
    ZielErgebnis e;
    try {
      e = await lauf(z);
    } catch (_) {
      // Die Meldung einer Ausnahme kann Namen enthalten (E11): nur der Stand zählt.
      e = const ZielErgebnis(
        ZielStand.unklar,
        text: 'Unerwarteter Fehler. Den Kurs in Moodle prüfen, bevor es erneut versucht wird.',
      );
    }
    // Mit Karten steht das Ziel schon als „ausstehend" im Protokoll, bevor sie
    // verknüpft werden: Ein Abbruch oder Neustart dazwischen doppelt nichts.
    final mitKarten = kartenLauf != null && e.stand == ZielStand.fertig;
    await protokoll.eintragen(
      UebertragungsEintrag(
        datei: datei,
        profil: profil,
        kurs: z.kurs,
        stand: e.stand,
        zeit: DateTime.now(),
        quellkurs: quellkurs,
        vorgang: e.vorgang,
        karten: mitKarten ? KartenStand.ausstehend : null,
      ),
    );
    KartenErgebnis? k;
    if (mitKarten) {
      try {
        k = await kartenLauf(z, e);
      } catch (_) {
        k = const KartenErgebnis(
          KartenStand.unklar,
          'Unerwarteter Fehler bei den Lernlandkarten. Die Karte in Moodle prüfen, bevor etwas erneut versucht wird.',
        );
      }
      // Ohne Karten im Auftrag (k ist null) bleibt „ausstehend" nicht stehen.
      await protokoll.eintragen(
        UebertragungsEintrag(
          datei: datei,
          profil: profil,
          kurs: z.kurs,
          stand: e.stand,
          zeit: DateTime.now(),
          quellkurs: quellkurs,
          vorgang: e.vorgang,
          karten: k?.stand,
        ),
      );
      if (k?.freigabeAbgelehnt == true) abgelehnt = true;
    }
    berichte.add(
      ZielBericht(
        z,
        e.stand,
        e.vorgang,
        e.text,
        karten: k?.stand,
        kartenText: k?.text ?? '',
      ),
    );
    if (e.stand == ZielStand.abgelehnt) abgelehnt = true;
  }
  return berichte;
}

/// Der Bericht an die KI: je Ziel der Stand, die Nummer und der Prüfbericht.
/// Auch ein abgeschlossener Lauf kann unverifizierte Inhalte enthalten. Die Hinweise sagen, was nicht zugesagt ist.
String uebertragungsBericht(List<ZielBericht> berichte) {
  final zeilen = <String>[];
  final anzahl = {for (final s in ZielStand.values) s: 0};
  final kartenAnzahl = {for (final s in KartenStand.values) s: 0};
  for (final b in berichte) {
    anzahl[b.stand] = anzahl[b.stand]! + 1;
    final nummer = b.vorgang == null ? '' : ', Nummer ${b.vorgang}';
    final text = b.text.isEmpty ? '' : ' ${b.text}';
    final karten = b.karten == null
        ? ''
        : '\n  Lernlandkarten: ${b.karten!.text}. ${b.kartenText}'.trimRight();
    zeilen.add(
      '„${b.ziel.name}" (Kurs ${b.ziel.kurs}): ${b.stand.text}$nummer.$text$karten',
    );
    if (b.karten != null) {
      kartenAnzahl[b.karten!] = kartenAnzahl[b.karten!]! + 1;
    }
  }
  final kopf =
      'Übertragung: ${anzahl[ZielStand.fertig]} fertig, '
      '${anzahl[ZielStand.fehlgeschlagen]! + anzahl[ZielStand.unklar]!} fehlgeschlagen oder unklar, '
      '${anzahl[ZielStand.abgelehnt]} abgelehnt, ${anzahl[ZielStand.nichtBegonnen]} nicht begonnen.';
  final mitKarten = berichte.any((b) => b.karten != null);
  final kartenKopf = !mitKarten
      ? null
      : 'Lernlandkarten je Ziel: ${kartenAnzahl[KartenStand.verknuepft]} verknüpft, '
            '${kartenAnzahl[KartenStand.offen]} offen, ${kartenAnzahl[KartenStand.unklar]! + kartenAnzahl[KartenStand.ausstehend]!} unklar.';
  final hinweise = [
    if (kartenAnzahl[KartenStand.offen]! +
            kartenAnzahl[KartenStand.unklar]! +
            kartenAnzahl[KartenStand.ausstehend]! >
        0)
      'Offene oder unklare Lernlandkarten bleiben unverifiziert; bei unbelegter Zuordnung die Sichtbarkeit in Moodle prüfen. Nichts wird automatisch wiederholt oder '
          'zusätzlich kopiert; die ungelösten Zuordnungen entscheidet die Lehrkraft, danach lernlandkarte_verknuepfungen_setzen.',
    if (anzahl[ZielStand.fertig]! > 0)
      'Einfüge-Wiederherstellung: Ein erneuter Lauf legt Inhalte ein zweites Mal an (Dubletten). '
          'Ein Aktualisieren bestehender Inhalte ist nicht zugesagt.',
    if (anzahl[ZielStand.fehlgeschlagen]! + anzahl[ZielStand.unklar]! > 0) 'Nicht erneut gesendet. Stand je Ziel mit wiederherstellung_status und der Nummer klären.',
    if (anzahl[ZielStand.abgelehnt]! > 0)
      'Die Lehrkraft hat abgelehnt; die übrigen Ziele wurden nicht begonnen.',
  ];
  return [kopf, ?kartenKopf, ...zeilen, ...hinweise].join('\n');
}
