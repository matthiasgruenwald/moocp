// Übertragung von Kursen zwischen Instanzprofilen (Projektkontext): der Projektkontext
// (Quellkurs und Durchführungskurse), die Richtung eines Auftrags und die
// Zusammenfassung vor dem ersten Schreibschritt.
//
// Diese Datei kennt weder Moodle noch das Netz. Sie ist reine Logik, damit
// sie offline testbar ist (test/uebertragung_test.dart). Die Namen der Kurse
// liest die Aufruferseite aus Moodle und übergibt sie an
// [uebertragungsZusammenfassung]; hier wird nichts gelesen.
//
// Die Richtung ist eine feste Annahme, keine Vermutung: Ohne Angabe gilt
// Quelle → Ziel. Die Gegenrichtung gibt es nur mit `gegenrichtung: true`, also
// nur, wenn der Auftrag sie ausdrücklich verlangt. Jede fehlende oder
// widersprüchliche Zuordnung ergibt eine Rückfrage mit Text, nie eine
// stillschweigende Annahme (A5, A3).

import 'profil.dart';

/// Ein Kurs in einer Instanz: das Profil (über seine Kennung) und die
/// Kursnummer, also die Zahl hinter course/view.php?id=. Die Kursnummern
/// gehören nur in die Nutzerdaten, nie ins Repository (A11).
class Kursbezug {
  const Kursbezug(this.profilKennung, this.kurs);

  final String profilKennung;
  final int kurs;

  Map<String, Object?> toJson() => {'profil': profilKennung, 'kurs': kurs};

  /// Null bei einer unbrauchbaren Angabe; der Projektkontext fällt dann auf
  /// das Fehlende zurück, statt die ganze Einstellungsdatei zu verwerfen.
  static Kursbezug? ausJson(Object? j) {
    if (j is! Map) return null;
    final profil = j['profil'];
    final kurs = j['kurs'];
    if (profil is! String || profil.isEmpty) return null;
    if (kurs is! int || kurs <= 0) return null;
    return Kursbezug(profil, kurs);
  }

  @override
  bool operator ==(Object other) =>
      other is Kursbezug && other.profilKennung == profilKennung && other.kurs == kurs;

  @override
  int get hashCode => Object.hash(profilKennung, kurs);
}

/// Der Projektkontext: der übliche Quellkurs und ein oder mehrere
/// Durchführungskurse. Gespeichert in den Einstellungen (einstellungen.dart),
/// überdauert also einen Neustart.
class Projektkontext {
  const Projektkontext({this.quelle, this.durchfuehrung = const []});

  /// Der Quellkurs; null, solange er nicht gesetzt ist.
  final Kursbezug? quelle;

  /// Die Durchführungskurse, in der Reihenfolge, in der die Lehrkraft sie
  /// angegeben hat.
  final List<Kursbezug> durchfuehrung;

  Map<String, Object?> toJson() => {
        if (quelle != null) 'quelle': quelle!.toJson(),
        'durchfuehrung': [for (final k in durchfuehrung) k.toJson()],
      };

  static Projektkontext? ausJson(Object? j) {
    if (j is! Map) return null;
    final liste = j['durchfuehrung'];
    return Projektkontext(
      quelle: Kursbezug.ausJson(j['quelle']),
      durchfuehrung: liste is List
          ? [for (final k in liste) ?Kursbezug.ausJson(k)]
          : const [],
    );
  }
}

/// Ein Kurs, aufgelöst zu seinem Profil: die Zuordnung, die eine Übertragung
/// braucht. Gleichheit über Kennung und Kursnummer.
class Endpunkt {
  const Endpunkt(this.profil, this.kurs);

  final Profil profil;
  final int kurs;

  @override
  bool operator ==(Object other) =>
      other is Endpunkt && other.profil.kennung == profil.kennung && other.kurs == kurs;

  @override
  int get hashCode => Object.hash(profil.kennung, kurs);
}

/// Das Ergebnis der Richtungsbestimmung: entweder ein Plan oder eine Rückfrage.
sealed class Richtungsentscheidung {
  const Richtungsentscheidung();
}

/// Die eindeutige Richtung: aus [quelle] wird in jeden der [ziele] kopiert.
/// [gegenrichtung] ist nur true, wenn der Auftrag es ausdrücklich verlangt.
class Plan extends Richtungsentscheidung {
  const Plan({required this.quelle, required this.ziele, this.gegenrichtung = false});

  final Endpunkt quelle;
  final List<Endpunkt> ziele;
  final bool gegenrichtung;
}

/// Die Angaben reichen nicht für eine eindeutige Richtung. [text] ist die
/// Frage an die Lehrkraft, konkret genug, dass sie direkt antworten kann.
class Rueckfrage extends Richtungsentscheidung {
  const Rueckfrage(this.text);

  final String text;
}

/// Bestimmt die Richtung eines Auftrags aus den Profilrollen und dem
/// Projektkontext. Keine Netz- und keine Moodle-Anfrage.
///
/// Prüfungen, in dieser Reihenfolge; die erste, die greift, gibt eine
/// Rückfrage zurück:
/// - kein Projektkontext, kein Quellkurs, keine Durchführungskurse;
/// - Rolle Quelle fehlt oder steht bei mehr als einem Profil;
/// - der Quellkurs liegt nicht im Profil mit der Rolle Quelle;
/// - ein Durchführungskurs gehört zu keinem bekannten Profil, oder sein Profil
///   ist weder Quellprofil noch hat die Rolle Ziel;
/// - ein Durchführungskurs hat dieselbe Kursnummer wie der Quellkurs in
///   demselben Profil, oder steht doppelt in der Liste.
/// Mit [gegenrichtung] braucht es genau einen Durchführungskurs als Quelle;
/// Ziel ist dann der Quellkurs.
Richtungsentscheidung bestimmeRichtung(
  List<Profil> profile,
  Projektkontext? kontext, {
  bool gegenrichtung = false,
}) {
  if (kontext == null) {
    return const Rueckfrage(
        'Es ist noch kein Projektkontext gesetzt. Welcher Kurs ist der Quellkurs, und welche Kurse sind die Durchführungskurse?');
  }
  final quellen = [for (final p in profile) if (p.rolle == Rolle.quelle) p];
  if (quellen.isEmpty) {
    return const Rueckfrage(
        'Kein Profil hat die Rolle Quelle. Welches Profil ist die Quelle der Übertragung?');
  }
  if (quellen.length > 1) {
    final namen = quellen.map((p) => '„${p.name}"').join(', ');
    return Rueckfrage(
        'Mehrere Profile haben die Rolle Quelle ($namen). Welches davon ist die Quelle?');
  }
  final qp = quellen.single;

  final kq = kontext.quelle;
  if (kq == null) {
    return Rueckfrage(
        'Im Projektkontext fehlt der Quellkurs. Welche Kursnummer hat der Quellkurs in „${qp.name}"?');
  }
  if (kq.profilKennung != qp.kennung) {
    return Rueckfrage(
        'Der Quellkurs ${kq.kurs} gehört zu keinem Profil mit der Rolle Quelle, sondern zu einem anderen. '
        'Liegt er in „${qp.name}"?');
  }
  final quelle = Endpunkt(qp, kq.kurs);

  if (kontext.durchfuehrung.isEmpty) {
    return const Rueckfrage(
        'Es ist kein Durchführungskurs gesetzt. Welche Kurse sollen die Übertragung bekommen, und in welcher Instanz liegen sie?');
  }

  final ziele = <Endpunkt>[];
  for (final z in kontext.durchfuehrung) {
    Profil? zp;
    for (final p in profile) {
      if (p.kennung == z.profilKennung) zp = p;
    }
    if (zp == null) {
      return Rueckfrage(
          'Der Durchführungskurs ${z.kurs} gehört zu keinem bekannten Profil. In welcher Instanz liegt er?');
    }
    if (zp.kennung != qp.kennung && zp.rolle != Rolle.ziel) {
      return Rueckfrage(
          'Der Durchführungskurs ${z.kurs} liegt in „${zp.name}", und dieses Profil hat weder die Rolle Ziel '
          'noch ist es die Quelle. Soll „${zp.name}" als Ziel gelten?');
    }
    final ziel = Endpunkt(zp, z.kurs);
    if (ziel == quelle) {
      return Rueckfrage(
          'Der Durchführungskurs ${z.kurs} ist in „${zp.name}" derselbe Kurs wie der Quellkurs. '
          'Welche Kursnummer hat das Ziel?');
    }
    if (ziele.contains(ziel)) {
      return Rueckfrage('Der Durchführungskurs ${z.kurs} in „${zp.name}" steht zweimal im Projektkontext.');
    }
    ziele.add(ziel);
  }

  if (!gegenrichtung) return Plan(quelle: quelle, ziele: ziele);

  if (ziele.length != 1) {
    return Rueckfrage(
        'Für die Gegenrichtung braucht es genau einen Durchführungskurs als Quelle, im Projektkontext stehen ${ziele.length}. '
        'Welcher soll die Quelle sein?');
  }
  return Plan(quelle: ziele.single, ziele: [quelle], gegenrichtung: true);
}

/// Die Richtung in einem Satz, für Werkzeugantworten. Die Namen der Kurse
/// fehlen hier absichtlich: Sie stehen in [uebertragungsZusammenfassung].
String richtungText(Richtungsentscheidung e) => switch (e) {
      Plan(:final quelle, :final ziele, :final gegenrichtung) =>
        '${gegenrichtung ? 'Gegenrichtung (ausdrücklich verlangt)' : 'Standardrichtung'}: '
            'Quelle „${quelle.profil.name}" Kurs ${quelle.kurs} → '
            '${ziele.map((z) => '„${z.profil.name}" Kurs ${z.kurs}').join(', ')}',
      Rueckfrage(:final text) => 'Rückfrage: $text',
    };

/// Der Text vor dem ersten Schreibschritt (Punkt 4). Nennt die
/// Quellinstanz, den Quellkurs, die Inhaltsauswahl, alle Zielkurse mit
/// Instanz und den Wiederherstellungsweg. Die Wege zeigen ihn in der
/// Freigabe.
///
/// [kursnamen] muss jeden Endpunkt der [plan] enthalten; der Name kommt aus
/// Moodle, und die Aufruferseite liest ihn dort. Fehlt einer, bricht die
/// Funktion ab, statt eine Zusammenfassung mit einer Lücke zu liefern: Ein
/// falsches „ok" ist schlimmer als ein Fehler (A3).
///
/// [inhalt] und [wiederherstellung] sind Angaben des Auftrags. Die Funktion
/// prüft sie nicht; leere Angaben bricht sie ab.
String uebertragungsZusammenfassung(
  Plan plan, {
  required Map<Endpunkt, String> kursnamen,
  required String inhalt,
  required String wiederherstellung,
}) {
  if (inhalt.trim().isEmpty) {
    throw ArgumentError.value(inhalt, 'inhalt', 'Die Inhaltsauswahl fehlt.');
  }
  if (wiederherstellung.trim().isEmpty) {
    throw ArgumentError.value(wiederherstellung, 'wiederherstellung', 'Der Wiederherstellungsweg fehlt.');
  }
  String name(Endpunkt e) {
    final n = kursnamen[e];
    if (n == null || n.trim().isEmpty) {
      throw StateError('Kein Kursname für Kurs ${e.kurs} in „${e.profil.name}" übergeben.');
    }
    return n;
  }

  String instanz(Profil p) {
    final host = Uri.tryParse(p.adresse)?.host ?? '';
    return host.isEmpty ? '„${p.name}"' : '„${p.name}" ($host)';
  }

  final q = plan.quelle;
  final zeilen = <String>[
    'Richtung: ${plan.gegenrichtung ? 'Gegenrichtung (ausdrücklich verlangt)' : 'Standardrichtung, Quelle → Ziel'}',
    'Quellinstanz: ${instanz(q.profil)}',
    'Quellkurs: „${name(q)}" (Kurs ${q.kurs})',
    'Inhaltsauswahl: $inhalt',
    'Zielkurse (${plan.ziele.length}):',
    for (final z in plan.ziele) '  - „${name(z)}" (Kurs ${z.kurs}) in ${instanz(z.profil)}',
    'Wiederherstellung: $wiederherstellung',
  ];
  return zeilen.join('\n');
}
