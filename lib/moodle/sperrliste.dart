// Datenschutz: die Sperrliste. Adressen, die personenbezogene Daten zeigen --
// Bewertungen, Abgaben, Versuche, Profile, Protokolle. Nie anfragen.
//
// Die Positivliste in moodle_zugang.dart lässt ohnehin nur wenige Adressen
// durch. Die Sperrliste gilt trotzdem, und zwar VOR ihr: Die Positivliste
// wächst mit jedem neuen Werkzeug, und eine zu weit gefasste Regel dort
// (etwa „jede Datei unter pluginfile.php") fiele sonst durch kein Netz. Beide
// Listen ergänzen sich; ein Test hält sie gegeneinander (keine Adresse, die
// ein Werkzeug braucht, darf gesperrt sein).
//
// Übernommen aus den Browser-Skills (gemeinsam/schutz.js, Stand 22.09.2026),
// samt der Prüffälle (test/sperrliste_test.dart). Dazugekommen sind die
// Dateibereiche unter pluginfile.php, die Abgaben und Profilbilder ausliefern:
// Die Skills haben nie selbst Dateien geholt, die App tut es.
//
// Geprüft wird Pfad samt Query, nicht nur der Pfad: /mod/assign/view.php ist
// der Aufgabentext, dieselbe Adresse mit &action=grading die
// Bewertungsübersicht mit allen Namen.

/// Die Regel, die den ganzen Notenbereich sperrt. Sie steht einzeln da, weil
/// genau sie -- und nur sie -- eine Ausnahme hat ([bewertungsschema]).
final RegExp _notenRegel = RegExp(r'/grade/');

/// Alle Dateien unter user/ (Profilbild, private Dateien, Sicherungen).
final RegExp _nutzerDateien = RegExp(r'^/pluginfile\.php/\d+/user/');

/// Die eine Ausnahme bei den Nutzerdateien: die Sicherungsdatei, die Moodle
/// nach einer Aktivitätssicherung bereitstellt. Ob sie ohne Nutzerdaten ist,
/// prüft der Ablauf vor dem Herunterladen (bestaetigungFehler in
/// moodle/sicherung_regeln.dart). Nur mit genau diesem Pfad und forcedownload=1,
/// nicht mit einem Prefix.
/// Gemessen: der Link trägt kein itemid-Segment (`user/backup/<datei>`). Das
/// Segment bleibt optional, falls Moodle es anderswo mit einer Zahl setzt.
final RegExp _sicherungDatei = RegExp(r'^/pluginfile\.php/\d+/user/backup/(?:\d+/)?[^/?#]+\.mbz\?forcedownload=1$');

final List<RegExp> _gesperrt = [
  // Bewertungen, Abgaben, Versuche
  _notenRegel,
  RegExp(r'/mod/assign/(grader|grade)\.php'),
  RegExp(r'[?&]action=grad(ing|er|e)\b'),
  RegExp(r'/mod/[a-z0-9]+/report\.php'),
  // mod_checklist hängt den Teilnehmer an die Adresse; report.php sperrt die
  // Regel darüber, dies fängt jede andere Seite zu einer einzelnen Person.
  RegExp(r'[?&]studentid='),
  RegExp(r'/mod/[a-z0-9]+/submissions\.php'),
  // mod_wiki: Die Seiten sind Kursinhalt; WER sie schrieb, steht im Verlauf,
  // in den Kommentaren und in zwei Ansichten der Wiki-Struktur (option=1
  // Mitwirkung, option=6 Aktualisierte Seiten -- beide mit Namen, gemessen
  // 22.09.2026). Ein persönliches Wiki trägt uid=<userid> in der Adresse,
  // mit Gruppen groupanduser=<groupid>-<userid> (mod/wiki/renderer.php,
  // wiki_print_subwiki_selector).
  RegExp(r'/mod/wiki/(history|diff|viewversion|comments|editcomments|lock)\.php'),
  RegExp(r'/mod/wiki/map\.php\?.*[?&]option=[16](&|$)'),
  RegExp(r'/mod/wiki/admin\.php\?.*[?&]option=2(&|$)'),
  RegExp(r'/mod/wiki/.*[?&]uid=(?!0(&|$))\d'),
  RegExp(r'/mod/wiki/.*[?&]groupanduser='),
  // mod_board: Notizen sind Beiträge einzelner Personen; der Export nennt sie
  // mit Namen, ownerid=<userid> ist das Board EINER Person.
  RegExp(r'/mod/board/(export|download_board|download_submissions)\.php'),
  RegExp(r'/mod/board/.*[?&]ownerid=(?!0(&|$))\d'),
  // mod_kanban: persönliche Boards und der Export mit Erstellern.
  RegExp(r'/mod/kanban/export\.php'),
  RegExp(r'/mod/kanban/.*[?&]userid=(?!0(&|$))\d'),
  RegExp(r'/mod/[a-z0-9]+/overrides?(edit)?\.php'),
  RegExp(r'/mod/quiz/(review|attempt|summary|startattempt|processattempt|comment|reviewquestion)\.php'),
  RegExp(r'/mod/feedback/(show_entries|analysis)\.php'),
  RegExp(r'/mod/choice/report\.php'),
  RegExp(r'/mod/forum/user\.php'),
  RegExp(r'/question/bank/comment/'),
  // STACK: „Antworten analysieren" wertet echte Abgaben aus. questiontestrun,
  // deploy und caschat arbeiten nur mit der Frage und bleiben offen.
  RegExp(r'/question/type/stack/questiontestreport\.php'),
  // Personen
  RegExp(r'/user/(view|profile|index|files|editadvanced)\.php'),
  RegExp(r'/course/user\.php'),
  RegExp(r'/message/'),
  RegExp(r'/badges/'),
  // Protokolle und Berichte
  RegExp(r'/report/'),
  // Einschreibung, Gruppen, Serververwaltung
  RegExp(r'/enrol/'),
  RegExp(r'/group/(members|index|overview)\.php'),
  RegExp(r'/cohort/'),
  RegExp(r'/admin/'),
  // Dateien, die Personen gehören oder von ihnen stammen (pluginfile.php/
  // <Kontext>/<Komponente>/<Bereich>/…). Die Namen der Bereiche sind die des
  // Moodle-Kerns. Der eigene Entwurfsbereich liegt unter draftfile.php und
  // bleibt offen; die Dateien einer Aktivität (mod_page/content,
  // mod_assign/intro, mod_folder/content …) ebenso.
  _nutzerDateien, // Profilbild, private Dateien
  RegExp(r'^/pluginfile\.php/\d+/assign(submission|feedback)_'), // Abgaben, Feedback
  RegExp(r'^/pluginfile\.php/\d+/question/response_'), // Antworten im Test
  RegExp(r'^/pluginfile\.php/\d+/mod_forum/(post|attachment)/'), // Forenbeiträge
  RegExp(r'^/pluginfile\.php/\d+/mod_workshop/(submission_|overallfeedback_)'),
  RegExp(r'^/pluginfile\.php/\d+/mod_data/content/'), // Datenbankeinträge
  RegExp(r'^/pluginfile\.php/\d+/mod_lesson/essay_'), // Freitextantworten
];

/// Die eine gemessene Ausnahme: die DEFINITION von Bewertungsschemata.
///
/// Eine Rubrik ist das Raster, nicht die Bewertung. Auf der Zielinstanz
/// nachgesehen: Der Inhaltsbereich dieser Seiten ist so personenfrei wie die
/// Kursseite. Ausgefüllte Rubriken liegen unter
/// /mod/assign/view.php?…&action=grading und bleiben gesperrt.
///
/// Die Ausnahme hebt NUR [_notenRegel] auf, nicht die Prüfung insgesamt --
/// ein einfaches „erlaubt" hätte auch …/manage.php?…&action=grading
/// durchgelassen.
final List<RegExp> _bewertungsschema = [
  RegExp(r'/grade/grading/manage\.php'),
  RegExp(r'/grade/grading/pick\.php'),
  RegExp(r'/grade/grading/form/[a-z_]+/edit\.php'),
];

/// Die Regel, die [uri] sperrt, oder null. Nur Pfad und Query zählen.
String? sperrregel(Uri uri) {
  final u = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
  final schema = _bewertungsschema.any((r) => r.hasMatch(u));
  final sicherung = _sicherungDatei.hasMatch(u);
  for (final r in _gesperrt) {
    if (schema && identical(r, _notenRegel)) continue;
    if (sicherung && identical(r, _nutzerDateien)) continue;
    if (r.hasMatch(u)) return r.pattern;
  }
  return null;
}

bool gesperrt(Uri uri) => sperrregel(uri) != null;

/// Die Adresse für ein Protokoll: Pfad und die NAMEN der Parameter, nie ihre
/// Werte. Aus id=14084&studentid=45 wird id=…&studentid=… -- der Name ist der
/// Befund, der Wert wäre das Datum, um das es geht.
String adresseOhneWerte(Uri uri) {
  if (!uri.hasQuery) return uri.path;
  final namen = uri.query.split('&').map((p) => '${p.split('=').first}=…');
  return '${uri.path}?${namen.join('&')}';
}

/// Feldnamen, die Personendaten tragen und in keine Ausgabe gehören.
/// 'idnumber' gehört NICHT hierher: Bei Aktivitäten und Fragen ist das eine
/// Sachnummer.
const Set<String> personenfelder = {
  'author', 'createdby', 'modifiedby', 'creatorname', 'modifiername', 'createdbyname', //
  'ownerid', 'firstname', 'lastname', 'fullname', 'email', 'username', 'userid',
};

/// Entfernt [personenfelder] rekursiv aus JSON-Daten, bevor sie abgelegt oder
/// ausgegeben werden.
Object? ohnePersonenfelder(Object? o) => switch (o) {
      // Schlüssel als Text: Wer das Ergebnis als Map<String, Object?> prüft,
      // soll es auch als solche bekommen.
      Map() => <String, Object?>{
          for (final e in o.entries)
            if (!personenfelder.contains(e.key)) '${e.key}': ohnePersonenfelder(e.value),
        },
      List() => [for (final x in o) ohnePersonenfelder(x)],
      _ => o,
    };
