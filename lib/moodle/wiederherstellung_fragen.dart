// Fragenherkunft vor einer Quiz-Wiederherstellung und Fragenvergleich danach
// (Issue #20, Teil von E9/E17). Reine Regeln ohne Netz. Die Quelle liefert das
// Archiv (verwendete Fragen), das Ziel die Zusammenstellung des Testes
// (test_lesen). Was nicht sicher auflösbar ist, wird Prüflücke, nie Gleichheit.
//
// Regeln:
//   - Sachnummern werden mit der angegebenen Zielsammlung verglichen. Selbst
//     gleiche Nummern belegen ohne Quellprofil, Quellsammlung und Kontext keine
//     eigene Quellherkunft. Eine leere Sammlung ist ebenfalls kein Nachweis.
//   - Fremde oder unbekannte Herkunft wird mit den Namen der Fragen benannt, vor dem
//     Start. Der XML-Import in eine neue Testzusammenstellung ist nur ein Vorschlag.
//   - Zufallsfragen und Fragen ohne Sachnummer: Prüflücke, kein Gleichheitsvergleich.
//   - Vergleich nur über Anzahl und Namen. Fehlt die Quelle oder das Ziel, ist
//     das Prüflücke. Das Vorhandensein des Quiz oder ein erfolgreicher
//     Hintergrundauftrag geht nie in die Verifikation ein.
//
// Das Archivformat folgt dem offiziellen Moodle-Builder (siehe quizFragenAusXml),
// nicht einer Messung auf der Instanz. Ob die Quellfragen quizlokal waren, liest
// der Parser nicht aus; siehe TODO.md.

import 'package:xml/xml.dart';

/// Eine tatsächlich verwendete Frage aus der Quelle.
///
/// [lokal]: true, wenn die Kategorie der Frage im Archiv denselben Kontext hat wie das
/// Quiz (quizlokale Fragen, mit dem Quiz gesichert); false bei einem anderen Kontext;
/// null, wenn der Archivaufbau das nicht eindeutig hergibt.
typedef QuizFrage = ({String name, String? sachnummer, bool zufall, bool? lokal});

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

/// Vergleich der verwendeten Quellfragen mit Sachnummern der angegebenen
/// Zielsammlung. Ohne belegte Quellidentität bleibt Gleichheit eine Prüflücke.
/// [verwendet] null heißt: die Quelle wurde nicht gelesen.
/// Befund 7: Herkunft darf nur in verified einfließen, wenn jedes Quiz eigene
/// Fragen nachweist. Eine Prüflücke oder eine fremde Herkunft genügt zum Nein.
bool herkunftVerifiziert(List<HerkunftBefund> befunde) =>
    befunde.isNotEmpty && befunde.every((b) => b.art == HerkunftArt.eigene);

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
  final fremdLokal = [for (final f in verwendet) if (f.lokal == false) f.name];
  if (fremdLokal.isNotEmpty) {
    return HerkunftBefund(HerkunftArt.fremdOderUnbekannt,
        'Fragen aus einem anderen Kontext als dem Quiz (geteilte Sammlung): ${fremdLokal.join(', ')}. '
        'Ein Fragenimport in eine neue Testzusammenstellung ist eine Alternative, nicht automatisch.',
        nichtEigene: fremdLokal);
  }
  if (verwendet.every((f) => f.lokal == true)) {
    return HerkunftBefund(HerkunftArt.eigene,
        'Alle Fragen liegen im Kontext des Quiz und werden mit ihm gesichert.');
  }
  final ohneNummer = [for (final f in verwendet) if (f.lokal != true && f.sachnummer == null) f.name];
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
    return HerkunftBefund(HerkunftArt.pruefluecke,
        'Die Sachnummern kommen auch in der angegebenen Zielsammlung vor. Das belegt keine eigene Quellherkunft: '
        'Quellprofil, Quellsammlung und Kontext sind nicht nachgewiesen (Prüflücke).');
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
  if (quelle == null || quelle.isEmpty || quelle.any((f) => f.sachnummer == null)) {
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

/// Die Fragen eines Quiz aus dem Archiv: activities/quiz_*/quiz.xml (question_instance
/// mit question_reference/questionbankentryid, oder question_set_reference für Zufall)
/// und die Fragenbank questions.xml. Aufbau nach dem offiziellen Moodle-Builder
/// (backup_stepslib.php, 5.1/5.2): question_bank_entry/question_version/question_versions
/// mit version, status und questions/question/name. Eine Referenzversion NULL steht als
/// `$@NULL@$` im Archiv und heißt: jüngste Version, die kein Entwurf ist. Leer, 0 oder
/// eine fehlende Version bleibt eine Prüflücke. [questionsXml] null: keine Fragenbank,
/// dann hat keine Frage eine Sachnummer.
List<QuizFrage> quizFragenAusXml(String quizXml, String? questionsXml) {
  final bank = <String, ({String? idnummer, String? kontext, Map<int, String> versionen, Set<int> entwuerfe})>{};
  final quizKontext = XmlDocument.parse(quizXml).rootElement.getAttribute('contextid');
  if (questionsXml != null) {
    final kategorieKontexte = <String, String>{};
    for (final k in XmlDocument.parse(questionsXml).findAllElements('question_category')) {
      final id = k.getAttribute('id');
      final kontext = k.getElement('contextid')?.innerText.trim();
      if (id != null && kontext != null && kontext.isNotEmpty) kategorieKontexte[id] = kontext;
    }
    for (final e in XmlDocument.parse(questionsXml).findAllElements('question_bank_entry')) {
      final id = e.getAttribute('id') ?? '';
      final kategorie = e.getElement('questioncategoryid')?.innerText.trim();
      final kontext = kategorie == null || kategorie.isEmpty ? null : kategorieKontexte[kategorie];
      final idnummer = e.getElement('idnumber')?.innerText.trim();
      final versionen = <int, String>{};
      final entwuerfe = <int>{};
      final doppelt = <int>{};
      for (final v in e.findAllElements('question_versions')) {
        final nummer = int.tryParse(v.getElement('version')?.innerText.trim() ?? '');
        final name = v.findAllElements('question').map((q) => q.getElement('name')?.innerText.trim()).firstOrNull;
        if (nummer == null || name == null || name.isEmpty) continue;
        // Doppelte Versionsnummern sind keine eindeutige Quelle.
        if (versionen.containsKey(nummer)) doppelt.add(nummer);
        versionen[nummer] = name;
        if (v.getElement('status')?.innerText.trim() == 'draft') entwuerfe.add(nummer);
      }
      versionen.removeWhere((n, _) => doppelt.contains(n));
      bank[id] = (idnummer: idnummer == null || idnummer.isEmpty ? null : idnummer, kontext: kontext, versionen: versionen, entwuerfe: entwuerfe);
    }
  }
  final fragen = <QuizFrage>[];
  for (final qi in XmlDocument.parse(quizXml).findAllElements('question_instance')) {
    if (qi.findAllElements('question_set_reference').isNotEmpty) {
      fragen.add((name: 'Zufallsfrage', sachnummer: null, zufall: true, lokal: null));
      continue;
    }
    final ref = qi.findAllElements('questionbankentryid').map((n) => n.innerText.trim()).toList();
    final id = ref.isEmpty ? '' : ref.first;
    final eintrag = bank[id];
    final version = qi.findAllElements('version').map((n) => n.innerText.trim()).firstOrNull;
    String? name;
    if (eintrag != null && version != null) {
      if (version == r'$@NULL@$') {
        final frei = eintrag.versionen.keys.where((n) => !eintrag.entwuerfe.contains(n));
        if (frei.isNotEmpty) name = eintrag.versionen[frei.reduce((a, b) => a > b ? a : b)];
      } else {
        final nummer = int.tryParse(version);
        if (nummer != null && nummer > 0) name = eintrag.versionen[nummer];
      }
    }
    if (eintrag == null) {
      fragen.add((name: 'Frage Nr. $id (nicht in questions.xml)', sachnummer: null, zufall: false, lokal: null));
    } else if (name == null || name.isEmpty) {
      fragen.add((name: 'Frage Nr. $id (Version nicht auflösbar, Prüflücke)', sachnummer: null, zufall: false, lokal: null));
    } else {
      final lokal = quizKontext == null || eintrag.kontext == null ? null : quizKontext == eintrag.kontext;
      fragen.add((name: name, sachnummer: eintrag.idnummer, zufall: false, lokal: lokal));
    }
  }
  return fragen;
}

/// Die Quellfragen je Quiz-Titel. Ein Titel, der im Archiv mehrfach vorkommt oder zu dem
/// kein Ordner bekannt ist, bekommt keine Quelle (Prüflücke bei der Zuordnung). Kennt das
/// Archiv keine Ordner, aber nur ein Quiz, gilt dessen Titel für die einzige Quelle.
Map<String, List<QuizFrage>> quizQuellenNachTitel({
  required Map<String, List<QuizFrage>> quizFragen,
  required Map<String, String> quizTitel,
  required List<String> archivQuizTitel,
}) {
  final quellen = <String, List<QuizFrage>>{};
  for (final e in quizFragen.entries) {
    final titel = quizTitel[e.key];
    if (titel == null || archivQuizTitel.where((t) => t == titel).length != 1) continue;
    quellen[titel] = e.value;
  }
  if (quellen.isEmpty && quizTitel.isEmpty && quizFragen.length == 1 && archivQuizTitel.length == 1) {
    quellen[archivQuizTitel.single] = quizFragen.values.single;
  }
  return quellen;
}

/// Ein Quiz aus dem Archiv und sein Gegenstück im Kurs. [luecke] nennt den Grund, wenn
/// die Zuordnung nicht eindeutig ist; dann gibt es keinen Vergleich.
typedef QuizZuordnung = ({String titel, List<QuizFrage>? quelle, int? zielCmid, String? luecke});

/// Ordnet jedes Quiz im Archiv genau einem neuen Quiz im Kurs zu: über den Titel, und
/// bei genau einem Quiz auf jeder Seite auch ohne gleichen Titel. Mehrdeutiges bleibt
/// eine Prüflücke je Quiz, nie ein Raten.
List<QuizZuordnung> quizZuordnen({
  required List<String> archivQuizTitel,
  required Map<String, List<QuizFrage>>? quellen,
  required List<({int cmid, String name})> neueQuizze,
}) {
  QuizZuordnung luecke(String titel, String grund) => (titel: titel, quelle: null, zielCmid: null, luecke: grund);
  final einzeln = archivQuizTitel.length == 1 && neueQuizze.length == 1;
  return [
    for (final titel in archivQuizTitel)
      () {
        final quelle = einzeln && quellen != null && quellen.length == 1 ? quellen.values.single : quellen?[titel];
        if (quelle == null) {
          return luecke(titel, 'Quellfragen nicht aufgenommen oder Titel im Archiv nicht eindeutig.');
        }
        final ziele = einzeln ? neueQuizze : [for (final q in neueQuizze) if (q.name == titel) q];
        if (ziele.length != 1) {
          return luecke(titel, 'im Kurs ${ziele.isEmpty ? 'kein' : 'mehrere'} neues Quiz mit diesem Titel.');
        }
        return (titel: titel, quelle: quelle, zielCmid: ziele.single.cmid, luecke: null);
      }(),
  ];
}
