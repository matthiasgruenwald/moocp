// Fragenherkunft vor einer Quiz-Wiederherstellung und Fragenvergleich danach
// (Issue #20, Teil von E9/E17). Reine Regeln ohne Netz. Die Quelle liefert das
// Archiv (verwendete Fragen), das Ziel die Zusammenstellung des Testes
// (test_lesen). Was nicht sicher auflösbar ist, wird Prüflücke, nie Gleichheit.
//
// Regeln:
//   - Eigene Herkunft nur, wenn alle tatsächlich verwendeten Fragen über ihre
//     Sachnummer in der eigenen Sammlung liegen UND die eigene Sammlung nicht leer
//     ist. Eine leere eigene Sammlung ist kein Nachweis.
//   - Fremde oder unbekannte Herkunft wird mit den Namen der Fragen benannt, vor dem
//     Start. Der XML-Import in eine neue Testzusammenstellung ist nur ein Vorschlag.
//   - Zufallsfragen und Fragen ohne Sachnummer: Prüflücke, kein Gleichheitsvergleich.
//   - Vergleich nur über Anzahl und Namen. Fehlt die Quelle oder das Ziel, ist
//     das Prüflücke. Das Vorhandensein des Quiz oder ein erfolgreicher
//     Hintergrundauftrag geht nie in die Verifikation ein.
//
// UNGEMESSEN: wie Moodle die verwendeten Fragen im Archiv (quiz.xml, questions.xml)
// und im Ziel (Platzliste) benennt. Die Eingaben kommen daher vom Aufrufer; siehe
// TODO.md.

/// Eine tatsächlich verwendete Frage aus der Quelle.
typedef QuizFrage = ({String name, String? sachnummer, bool zufall});

/// Eine Frage in der Zusammenstellung des Ziels.
typedef ZielFrage = ({String name, bool zufall});

enum HerkunftArt { eigene, fremdOderUnbekannt, pruefluecke }

class HerkunftBefund {
  HerkunftBefund(this.art, this.text, {this.nichtEigene = const []});

  final HerkunftArt art;

  /// Text für die Freigabe und die Antwort.
  final String text;

  /// Namen der Fragen, die nicht in der eigenen Sammlung liegen.
  final List<String> nichtEigene;
}

/// Herkunft aus den tatsächlich verwendeten Fragen. [verwendet] null heißt: die
/// Quelle wurde nicht gelesen.
HerkunftBefund herkunftPruefen({
  required List<QuizFrage>? verwendet,
  required Set<String> eigeneSachnummern,
  required int eigeneAnzahl,
}) {
  if (verwendet == null || verwendet.isEmpty) {
    return HerkunftBefund(HerkunftArt.pruefluecke,
        'Herkunft nicht geprüft: keine verwendeten Fragen in der Quelle ermittelt.');
  }
  final zufall = [for (final f in verwendet) if (f.zufall) f.name];
  if (zufall.isNotEmpty) {
    return HerkunftBefund(HerkunftArt.pruefluecke,
        'Herkunft nicht festlegbar: Zufallsfragen (${zufall.join(', ')}).');
  }
  final ohneNummer = [for (final f in verwendet) if (f.sachnummer == null) f.name];
  if (ohneNummer.isNotEmpty) {
    return HerkunftBefund(HerkunftArt.pruefluecke,
        'Zuordnung nicht auflösbar, Frage ohne Sachnummer: ${ohneNummer.join(', ')}.');
  }
  if (eigeneAnzahl == 0) {
    return HerkunftBefund(HerkunftArt.fremdOderUnbekannt,
        'Eigene Sammlung ist leer; das ist kein Herkunftsnachweis. Herkunft unbekannt.',
        nichtEigene: [for (final f in verwendet) f.name]);
  }
  final fremd = [
    for (final f in verwendet)
      if (!eigeneSachnummern.contains(f.sachnummer)) f.name,
  ];
  if (fremd.isEmpty) {
    return HerkunftBefund(HerkunftArt.eigene, 'Alle verwendeten Fragen stammen aus der eigenen Sammlung.');
  }
  return HerkunftBefund(HerkunftArt.fremdOderUnbekannt,
      'Geteilte oder unbekannte Herkunft, nicht in der eigenen Sammlung: ${fremd.join(', ')}. '
      'Ein Fragenimport in eine neue Testzusammenstellung ist eine Alternative, nicht automatisch.',
      nichtEigene: fremd);
}

enum VergleichArt { gleich, abweichung, pruefluecke }

class FragenVergleich {
  FragenVergleich(this.art, this.text, {this.fehlend = const [], this.zusaetzlich = const []});

  final VergleichArt art;
  final String text;

  /// Namen aus der Quelle, die im Ziel fehlen.
  final List<String> fehlend;

  /// Namen im Ziel, die in der Quelle nicht vorkommen.
  final List<String> zusaetzlich;
}

/// Vergleich von Anzahl und Namen. [quelle] null: Quelle nicht aufgenommen.
/// [ziel] null: Zusammenstellung nicht gelesen.
FragenVergleich fragenVergleichen({
  required List<QuizFrage>? quelle,
  required List<ZielFrage>? ziel,
}) {
  if (quelle == null || quelle.isEmpty) {
    return FragenVergleich(VergleichArt.pruefluecke,
        'Vergleich nicht möglich: keine belastbare Aufnahme der Quellfragen.');
  }
  if (ziel == null) {
    return FragenVergleich(VergleichArt.pruefluecke,
        'Vergleich nicht möglich: die Zusammenstellung im Ziel wurde nicht gelesen.');
  }
  final zufall = [
    for (final f in quelle) if (f.zufall) f.name,
    for (final f in ziel) if (f.zufall) f.name,
  ];
  if (zufall.isNotEmpty) {
    return FragenVergleich(VergleichArt.pruefluecke,
        'Vergleich nicht möglich: Zufallsfragen (${zufall.join(', ')}) erzeugen keine festen Namen.');
  }
  final quellNamen = [for (final f in quelle) f.name];
  final zielNamen = [for (final f in ziel) f.name];
  final fehlend = _rest(quellNamen, zielNamen);
  final zusaetzlich = _rest(zielNamen, quellNamen);
  if (quellNamen.length == zielNamen.length && fehlend.isEmpty && zusaetzlich.isEmpty) {
    return FragenVergleich(VergleichArt.gleich,
        'Fragenzahl und Fragennamen stimmen mit der Quelle überein (${quellNamen.length}).');
  }
  final teile = <String>[
    'Im Ziel ${zielNamen.length} von ${quellNamen.length} Fragen.',
    if (fehlend.isNotEmpty) 'Fehlend: ${fehlend.join(', ')}.',
    if (zusaetzlich.isNotEmpty) 'Zusätzlich: ${zusaetzlich.join(', ')}.',
    'Keine Vollständigkeit bestätigt; bitte prüfen.',
  ];
  return FragenVergleich(VergleichArt.abweichung, teile.join(' '),
      fehlend: fehlend, zusaetzlich: zusaetzlich);
}

/// Ob der Vergleich die Wiederherstellung als vollständig bestätigt. Nur der
/// Vergleich selbst zählt.
bool quizVerifiziert(FragenVergleich v) => v.art == VergleichArt.gleich;

/// Elemente von [a], die (mit Vielfachheit) nicht in [b] vorkommen.
List<String> _rest(List<String> a, List<String> b) {
  final frei = [...b];
  final rest = <String>[];
  for (final x in a) {
    if (!frei.remove(x)) rest.add(x);
  }
  return rest;
}
