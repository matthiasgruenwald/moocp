// Was der Browser des Werkzeugs bildschirmfoto anfragen darf
// (bildschirmfoto.dart).
//
// Ein Browser lädt viel mehr als die Seite: Stylesheets, Skripte, Schriften,
// Bilder, MathJax und Hintergrundabfragen (Mitteilungen, Benachrichtigungen,
// Blöcke). Jede dieser Anfragen hält die App an und entscheidet hier:
//
//   - Anfragen an Moodle stellt die App selbst, mit ihrer Sitzung und über
//     MoodleZugang (Protokoll wie jede andere Anfrage); der Browser bekommt
//     nur die Antwort und nie das Sitzungscookie.
//   - MathJax lädt der Browser selbst, aber nur von der Adresse, die die
//     Seite dafür einstellt (Filter MathJax) -- ein fremder Rechner, der
//     keine Moodle-Sitzung braucht.
//   - Zeichnungen in STACK-Fragen (JSXGraph) laufen in einem abgeschotteten
//     Rahmen ohne eigene Herkunft und holen ihre Skripte aus corsscripts/ von
//     STACK ([stackSkriptDatei]). Ohne Access-Control-Allow-Origin lädt der
//     Rahmen die Module nicht; bildschirmfoto.dart setzt die Kopfzeile für
//     genau diese Antworten.
//   - Alles andere wird gesperrt. Eine gesperrte Hintergrundabfrage
//     hinterlässt höchstens eine Lücke auf der Seite.
//
// Die Sperrliste gilt vor allem anderen, wie überall (sperrliste.dart):
// Profilbilder unter pluginfile.php/<ctx>/user/ bleiben gesperrt, auch wenn
// eine Seite sie einbinden will.
//
// Seiten (Dokumente) nur aus [ansichtErlaubt]: Ansichten, die Inhalte zeigen
// und keine Personen -- und davon nur die eine, die aufgenommen wird, samt
// ihrer Umleitung. Auch ein eingebetteter Rahmen (iframe) ist ein Dokument;
// ohne diese Grenze holte er jede andere erlaubte Ansicht ins Bild, etwa die
// Seite eines Wikis, das bildschirmfoto.dart abgewiesen hätte. Die Ausnahme
// sind interaktive Elemente ([elementDokument]): Dateien des Inhalts, keine
// Ansichten. Was von der
// Seite auf dem Bild landet, schneidet bildschirmfoto.dart auf den Inhalt
// zu, und die Lehrkraft sieht jedes Bild, bevor es weitergeht.

import 'dart:convert';

import 'sperrliste.dart';

enum BrowserWeg {
  /// Die App stellt die Anfrage selbst und reicht die Antwort durch.
  ueberApp,

  /// Der Browser darf sie selbst stellen (MathJax vom fremden Rechner).
  direkt,

  gesperrt,
}

/// Ob [s] nur aus Ziffern besteht (Kurs-, Modul- und Fragen-Nummern in Adressen und Formularen).
bool istZahl(String? s) => s != null && RegExp(r'^\d+$').hasMatch(s);

bool _nur(Map<String, String> q, Set<String> erlaubt) =>
    q.keys.every(erlaubt.contains);

/// Die Seite, die der Browser als Dokument laden darf, mit kurzer
/// Beschreibung -- oder null.
String? ansichtErlaubt(Uri uri) {
  final q = uri.queryParameters;
  return switch (uri.path) {
    '/mod/page/view.php' when q.length == 1 && istZahl(q['id']) => 'Textseite',
    '/mod/learningmap/view.php' when q.length == 1 && istZahl(q['id']) =>
      'Lernlandkarte',
    '/mod/book/view.php'
        when _nur(q, {'id', 'chapterid'}) &&
            istZahl(q['id']) &&
            (q['chapterid'] == null || istZahl(q['chapterid'])) =>
      'Buchkapitel',
    // Nur über pageid: bildschirmfoto.dart prüft vorher, dass die Seite zu
    // einem gemeinsamen Wiki gehört (wiki.dart, wikiAnsicht).
    '/mod/wiki/view.php' when q.length == 1 && istZahl(q['pageid']) =>
      'Wikiseite',
    // Die Vorschau legt beim ersten Aufruf einen Vorschauversuch an und
    // leitet auf dieselbe Adresse mit previewid um.
    '/question/bank/previewquestion/preview.php'
        when _nur(q, {
              'id',
              'cmid',
              'courseid',
              'previewid',
              'restartversion',
            }) &&
            istZahl(q['id']) &&
            q.values.every(istZahl) =>
      'Fragenvorschau',
    _ => null,
  };
}

/// Ein interaktives Element: eine HTML-Datei aus dem Dateibereich eines
/// Editorfelds (`pluginfile.php/<ctx>/<komponente>/<bereich>/…/<name>.html`),
/// das Dokument eines Rahmens in der Seite (elemente.dart). Inhalt wie ein
/// Bild der Seite; was es selbst lädt, geht wieder über diese Liste.
bool elementDokument(Uri uri) => RegExp(
  r'^/pluginfile\.php/\d+/(?:mod_[a-z0-9]+|course)/[a-z_]+/.+\.html?$',
  caseSensitive: false,
).hasMatch(uri.path);

/// Moodle-Dienste, die nur Vorlagen, Sprachtexte und Symbole liefern.
const Set<String> browserDienste = {
  'core_output_load_template',
  'core_output_load_template_with_dependencies',
  'core_get_string',
  'core_get_strings',
  'core_output_load_fontawesome_icon_map',
  'core_output_load_fontawesome_icon_system_map',
};

/// Statische Dateien von Theme und Moodle: Stylesheets, Skripte, Bilder,
/// Schriften, Dateien aus Kursinhalten.
final RegExp _statisch = RegExp(
  r'^/(theme/(styles|yui_combo|image|font|javascript|jquery)\.php'
  r'|lib/(javascript|requirejs)\.php'
  r'|pluginfile\.php/\d+/)',
);

/// Der Grund für Dateien aus corsscripts/ von STACK; bildschirmfoto.dart
/// erkennt daran die Antworten, die Access-Control-Allow-Origin brauchen.
const stackSkript = 'STACK-Skript';

final RegExp _corsDatei = RegExp(
  r'^[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*(\.[A-Za-z0-9_-]+)*\.(js|css)$',
);

/// Ein Skript oder Stylesheet, das STACK seinen Zeichnungen mitgibt (JSXGraph,
/// die Brücke zu den Eingabefeldern): seit 2024 über `cors.php?name=<datei>`,
/// in älteren Versionen direkt aus dem Ordner. Nur Dateinamen, kein „..".
bool stackSkriptDatei(Uri uri) {
  const ordner = '/question/type/stack/corsscripts/';
  if (uri.path == '${ordner}cors.php') {
    final q = uri.queryParameters;
    return q.length == 1 && _corsDatei.hasMatch(q['name'] ?? '');
  }
  return uri.path.startsWith(ordner) &&
      !uri.hasQuery &&
      _corsDatei.hasMatch(uri.path.substring(ordner.length));
}

/// Ob ein Dienstaufruf (JSON-Rumpf: Liste von {methodname, args}) nur
/// [browserDienste] enthält.
bool _nurBrowserDienste(String? rumpf) {
  if (rumpf == null) return false;
  try {
    final l = jsonDecode(rumpf);
    return l is List &&
        l.isNotEmpty &&
        l.every((a) => a is Map && browserDienste.contains(a['methodname']));
  } catch (_) {
    return false;
  }
}

/// Die Adresse, unter der MathJax liegt, aus dem Quelltext einer Seite: bis
/// einschließlich des Ordners, dessen Name „mathjax" enthält (etwa
/// https://cdn.jsdelivr.net/npm/mathjax@3.2.2/). Der Filter schreibt sie als
/// JSON in die Seite, mit „\/" statt „/". null: keine.
String? mathjaxQuelle(String html) {
  final m = RegExp(
    r'https:(?:\\?/){2}[^"'
    "'"
    r'\s]*?mathjax[^"'
    "'"
    r'\s]*',
  ).firstMatch(html);
  if (m == null) return null;
  final adresse = m.group(0)!.replaceAll(r'\/', '/');
  final i = adresse.toLowerCase().indexOf('mathjax');
  final ende = adresse.indexOf('/', i);
  return ende < 0 ? null : adresse.substring(0, ende + 1);
}

/// Der Grund, wenn eine Anfrage an Moodle nur nicht auf der Liste steht.
const nichtAufDerListe = 'nicht auf der Liste für Bildschirmfotos';

/// Ob eine nicht geladene Anfrage das Bild verändern kann und deshalb in den
/// Freigabedialog und die Antwort an die KI gehört: jede Datenschutz-Sperre,
/// jeder fremde Rechner (Schriften, fremde Bilder), jede andere Seite, auch im
/// Rahmen; von dem, was nur nicht auf der Liste steht, Stylesheets, Bilder,
/// Schriften und Medien ([art]: resourceType des DevTools-Protokolls).
/// Skripte und Hintergrundabfragen für Kopfzeile und Plugins ändern am Inhalt
/// nichts -- sie stehen nur im Protokoll.
bool veraendertBild(String grund, String? art) =>
    grund != nichtAufDerListe ||
    const {'Stylesheet', 'Image', 'Font', 'Media'}.contains(art);

/// Entscheidet über eine Anfrage des Browsers. [dokument]: eine Seite, keine
/// Datei in ihr. [basis]: die Moodle-Instanz der Sitzung. [seiten]: die
/// Adressen, die als Seite geladen werden dürfen (die aufgenommene und ihre
/// Umleitungsziele).
(BrowserWeg, String) browserPruefen(
  String methode,
  Uri uri, {
  required Uri basis,
  required Set<String> seiten,
  bool dokument = false,
  String? rumpf,
  String? mathjax,
}) {
  if (uri.scheme == 'data' || uri.scheme == 'blob')
    return (BrowserWeg.direkt, 'eingebettet');
  if (uri.host != basis.host || uri.scheme != 'https') {
    final a = uri.toString();
    if (!dokument &&
        methode == 'GET' &&
        mathjax != null &&
        a.startsWith(mathjax) &&
        !a.contains('..')) {
      return (BrowserWeg.direkt, 'MathJax');
    }
    return (BrowserWeg.gesperrt, 'fremder Rechner');
  }
  final regel = sperrregel(uri);
  if (regel != null)
    return (BrowserWeg.gesperrt, 'Datenschutz-Sperre (Regel $regel)');
  if (dokument) {
    if (methode == 'GET' && elementDokument(uri))
      return (BrowserWeg.ueberApp, 'Element');
    final a = ansichtErlaubt(uri);
    if (methode != 'GET' || a == null)
      return (BrowserWeg.gesperrt, 'keine erlaubte Ansicht');
    return seiten.contains(uri.toString())
        ? (BrowserWeg.ueberApp, a)
        : (BrowserWeg.gesperrt, 'nicht die aufgenommene Seite');
  }
  if (methode == 'GET' && _statisch.hasMatch(uri.path))
    return (BrowserWeg.ueberApp, 'Datei');
  if (methode == 'GET' && stackSkriptDatei(uri))
    return (BrowserWeg.ueberApp, stackSkript);
  final dienst = RegExp(r'^/lib/ajax/service(-nologin)?\.php$')
      .hasMatch(uri.path);
  if (dienst &&
      methode == 'GET' &&
      browserDienste.contains(uri.queryParameters['info'])) {
    return (BrowserWeg.ueberApp, 'Dienst ${uri.queryParameters['info']}');
  }
  if (dienst && methode == 'POST' && _nurBrowserDienste(rumpf))
    return (BrowserWeg.ueberApp, 'Dienst');
  return (BrowserWeg.gesperrt, nichtAufDerListe);
}
