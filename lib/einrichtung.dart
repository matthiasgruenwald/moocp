// Einrichtung der KI-Werkzeuge: die Verbindung zur App und die Skills.
//
// Damit ein KI-Werkzeug mit der App arbeitet, braucht es zweierlei: einen
// MCP-Eintrag „moodle" mit Adresse und Schlüssel dieser App, und die Skills in
// genau der Version, die zu dieser App gehört -- ändert sich ein Werkzeug,
// ändert sich der Skill mit. Beides prüft die App beim Start für jedes
// gefundene KI-Werkzeug; geschrieben wird erst nach einem Klick im Dialog
// „KI-Werkzeuge einrichten", wie bei den Freigaben. Beim Deinstallieren
// entfernt die App beides wieder ([einrichtungEntfernen]).
//
// Eingerichtet werden Claude Code, Codex CLI und LM Studio. Alle drei sind
// MCP-Clients, die auf demselben Rechner laufen, Skills im Format
// `SKILL.md` laden und eigene Werkzeuge für Dateien haben -- mehr braucht
// diese App von einem Client nicht. Die ChatGPT-App gehört nicht dazu: Sie
// erreicht nur öffentliche HTTPS-Server, und der Weg über OpenAIs Tunnel
// führte unsere Werkzeuge aus dem Netz erreichbar heraus (E6) und brächte
// trotzdem keinen Zugriff auf den Arbeitsordner (E5). Ollama ist ein
// Modellserver und gar kein MCP-Client.
//
// Hier steht nur die Logik, ohne Oberfläche, damit sie sich an einem
// nachgebauten Ordnerbaum prüfen lässt (test/einrichtung_test.dart).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Die Skills, die die App mitbringt, liegen als Pakete von skills/build.py
/// unter diesem Asset-Pfad (pubspec.yaml).
const skillAssets = 'skills/dist/';

/// Der Name des MCP-Eintrags in jedem KI-Werkzeug.
const mcpName = 'moodle';

/// Skills, die die Lehrkraft im Dialog „KI-Werkzeuge einrichten" wählt, mit
/// dem Satz, der dort dabeisteht. Alle anderen Skills der App sind immer
/// dabei. lernsituation ist für berufsbildende Schulen gebaut; anderswo
/// stünde er nur im Weg, denn seine Beschreibung zieht bei jedem
/// „Arbeitsblatt".
const wahlSkills = {
  'lernsituation': 'Für berufsbildende Schulen: Lernsituationen mit SchuCu-Tabelle, Ablaufplan, Arbeits- '
      'und Informationsblättern entwerfen.',
};

String? _v(Map<String, String> umgebung, String name) {
  final w = umgebung[name];
  return w == null || w.trim().isEmpty ? null : w;
}

/// Die Verzeichnisse aus PATH, in der Reihenfolge, in der Windows sucht.
List<String> _pfad(Map<String, String> umgebung) =>
    [for (final d in (_v(umgebung, 'PATH') ?? '').split(';')) if (d.trim().isNotEmpty) d.trim()];

// ---------------------------------------------------------------------------
// Die Verbindung: der MCP-Eintrag „moodle"
// ---------------------------------------------------------------------------

enum Verbindung { aktuell, fehlt, veraltet, unlesbar }

String mcpAdresse(int port) => 'http://127.0.0.1:$port/mcp';

String mcpKopf(String schluessel) => 'Bearer $schluessel';

// ---------------------------------------------------------------------------
// Ein KI-Werkzeug
// ---------------------------------------------------------------------------

/// Ein KI-Werkzeug, das die App einrichten kann. Je Werkzeug steht hier, wo
/// es liegt, wie sein MCP-Eintrag geprüft und geschrieben wird und wohin
/// seine Skills gehören. Alles Übrige -- Vergleich der Skills, Reihenfolge,
/// Dialog -- ist für alle gleich.
abstract class KiWerkzeug {
  KiWerkzeug(this.umgebung);

  final Map<String, String> umgebung;

  /// Kurzname, unter dem die Wahl in den Einstellungen steht.
  String get id;

  /// Name für die Anzeige.
  String get name;

  /// Wohin die Inhalte gehen, die dieses Werkzeug aus der App liest. Steht im
  /// Dialog neben dem Namen. Bewusst vom eingestellten Modell her gesagt,
  /// nicht vom Werkzeug: Claude Code und Codex lassen sich auf andere Anbieter
  /// umstellen, und LM Studio kann neben lokalen Modellen auch Cloud-Modelle
  /// benutzen. Der Hinweis zum Datenschutz (README, Installer) gilt deshalb
  /// für jedes Werkzeug, auch für LM Studio.
  String get datenziel;

  /// Ob das Werkzeug auf diesem Rechner benutzt wird. Nicht gefundene
  /// Werkzeuge erscheinen nicht im Dialog und werden nicht eingerichtet.
  bool get gefunden;

  /// Der Ordner, aus dem das Werkzeug persönliche Skills lädt.
  Directory get skillOrdner;

  /// Ob die App Eintrag und Austrag selbst vornehmen kann. Fehlt etwa die
  /// claude.exe, lässt sich bei Claude Code nichts eintragen -- die Skills
  /// aber schon.
  bool get bedienbar;

  /// Was fehlt, wenn [bedienbar] false ist; sonst null.
  String? get hindernis;

  /// Der Stand des MCP-Eintrags „moodle" in diesem Werkzeug.
  Verbindung verbindung(int port, String schluessel);

  /// Trägt die App ein. null bei Erfolg, sonst eine Beschreibung -- nie mit
  /// der Ausgabe eines Programms, denn die kann den Schlüssel enthalten.
  Future<String?> eintragen(int port, String schluessel);

  /// Entfernt den Eintrag „moodle" wieder. null bei Erfolg.
  Future<String?> austragen();


  /// Der Stand der Verbindung in Worten für den Dialog.
  String verbindungText(Verbindung v) => switch (v) {
        Verbindung.aktuell => 'aktuell',
        Verbindung.fehlt => 'nicht eingetragen',
        Verbindung.veraltet => 'Schlüssel muss aktualisiert werden',
        Verbindung.unlesbar => 'Konfiguration nicht lesbar, wird neu eingetragen',
      };
}

// ---------------------------------------------------------------------------
// Claude Code
// ---------------------------------------------------------------------------

// Claude Desktop gibt es als MSIX-Paket. Windows leitet dessen %APPDATA% in
// den Paketordner um: Was Claude Desktop unter %APPDATA%\Claude\claude-code
// ablegt, steht für jedes andere Programm unter
// %LOCALAPPDATA%\Packages\<Paket>\LocalCache\Roaming\Claude\claude-code.
// Der Paketname leitet sich aus Anthropics Signatur ab und ist auf allen
// Rechnern gleich; bewusst kein Platzhalter „Claude_*", der auch ein fremdes
// Paket träfe. Darunter liegt je Version ein Ordner (2.1.280, 2.1.281 …) --
// Claude Desktop lädt Claude Code nach und behält ältere Versionen.
const _claudeDesktopPaket = 'Claude_pzs8sxrjxfjjc';

/// Sucht die claude.exe: Claude Desktop (MSIX, dann klassischer Installer),
/// der Suchpfad, der eigenständige Installer, die VS-Code-Erweiterung --
/// jeweils die höchste Version. null, wenn nichts da ist.
String? claudeFinden(Map<String, String> umgebung) {
  final lokal = _v(umgebung, 'LOCALAPPDATA');
  final roaming = _v(umgebung, 'APPDATA');
  final heim = _v(umgebung, 'USERPROFILE');
  final kandidaten = <String?>[
    if (lokal != null)
      _neuesteVersion(p.join(lokal, 'Packages', _claudeDesktopPaket, 'LocalCache', 'Roaming', 'Claude', 'claude-code')),
    if (roaming != null) _neuesteVersion(p.join(roaming, 'Claude', 'claude-code')),
    for (final d in _pfad(umgebung)) p.join(d, 'claude.exe'),
    if (heim != null) p.join(heim, '.local', 'bin', 'claude.exe'),
    if (heim != null) _vsCode(p.join(heim, '.vscode', 'extensions')),
  ];
  for (final k in kandidaten) {
    if (k != null && File(k).existsSync()) return k;
  }
  return null;
}

/// Vergleicht Versionsnummern Stelle für Stelle als Zahlen: 2.10 kommt nach
/// 2.9, anders als beim Textvergleich.
int versionVergleichen(List<int> a, List<int> b) {
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

List<int>? _version(String text) {
  final teile = text.split('.');
  final zahlen = teile.map(int.tryParse).toList();
  return zahlen.any((z) => z == null) ? null : zahlen.cast<int>();
}

String? _neuesteVersion(String ordner) {
  final d = Directory(ordner);
  if (!d.existsSync()) return null;
  (List<int>, String)? beste;
  for (final e in d.listSync().whereType<Directory>()) {
    final ver = _version(p.basename(e.path));
    final exe = p.join(e.path, 'claude.exe');
    if (ver == null || !File(exe).existsSync()) continue;
    if (beste == null || versionVergleichen(ver, beste.$1) > 0) beste = (ver, exe);
  }
  return beste?.$2;
}

// Die Erweiterung legt je Version einen Ordner
// anthropic.claude-code-<Version>-win32-x64 an, die claude.exe darin unter
// resources\native-binary.
String? _vsCode(String erweiterungen) {
  final d = Directory(erweiterungen);
  if (!d.existsSync()) return null;
  final muster = RegExp(r'^anthropic\.claude-code-([0-9.]+)-win32-');
  (List<int>, String)? beste;
  for (final e in d.listSync().whereType<Directory>()) {
    final m = muster.firstMatch(p.basename(e.path));
    final ver = m == null ? null : _version(m.group(1)!);
    final exe = p.join(e.path, 'resources', 'native-binary', 'claude.exe');
    if (ver == null || !File(exe).existsSync()) continue;
    if (beste == null || versionVergleichen(ver, beste.$1) > 0) beste = (ver, exe);
  }
  return beste?.$2;
}

/// Claude Code. Eingetragen wird nur über die eigene Kommandozeile, nie durch
/// Schreiben in `.claude.json`: Die Datei gehört Claude Code und wird dort
/// ständig neu geschrieben. CLAUDE_CONFIG_DIR verlegt Konfiguration und
/// Skills; sonst liegen sie im Benutzerverzeichnis. MSIX leitet diese Orte
/// nicht um -- Claude Desktop und VS Code lesen dieselben.
class ClaudeCode extends KiWerkzeug {
  ClaudeCode(super.umgebung)
      : _eigen = umgebung['CLAUDE_CONFIG_DIR'],
        _heim = umgebung['USERPROFILE'] ?? '';

  final String? _eigen;
  final String _heim;

  @override
  String get id => 'claude';
  @override
  String get name => 'Claude Code';
  @override
  String get datenziel => 'Inhalte gehen an das eingestellte Modell, in der Regel bei Anthropic';

  /// Pfad der claude.exe; null, wenn sie nicht gefunden wurde.
  String? get exe => _exe ??= claudeFinden(umgebung);
  String? _exe;

  File get konfiguration => File(p.join(_eigen ?? _heim, '.claude.json'));

  @override
  Directory get skillOrdner => Directory(p.join(_eigen ?? p.join(_heim, '.claude'), 'skills'));

  // Auch ohne claude.exe gefunden: Wer `.claude.json` hat, benutzt Claude
  // Code -- dann soll der Dialog es zeigen und sagen, was fehlt, statt es
  // stillschweigend auszulassen.
  @override
  bool get gefunden => exe != null || konfiguration.existsSync() || skillOrdner.existsSync();

  @override
  bool get bedienbar => exe != null;

  @override
  String? get hindernis => bedienbar
      ? null
      : 'Claude Code nicht gefunden. Claude Desktop installieren und dort einmal den Bereich '
          '„Code" öffnen, danach „Nochmal prüfen".';

  @override
  Verbindung verbindung(int port, String schluessel) {
    if (!konfiguration.existsSync()) return Verbindung.fehlt;
    try {
      final d = jsonDecode(konfiguration.readAsStringSync());
      final server = (d is Map) ? d['mcpServers'] : null;
      final e = (server is Map) ? server[mcpName] : null;
      if (e is! Map) return Verbindung.fehlt;
      final kopf = e['headers'] is Map ? (e['headers'] as Map)['Authorization'] : null;
      final passt = e['type'] == 'http' && e['url'] == mcpAdresse(port) && kopf == mcpKopf(schluessel);
      return passt ? Verbindung.aktuell : Verbindung.veraltet;
    } catch (_) {
      // Auch ein halb geschriebener Stand, wenn Claude Code gerade speichert.
      return Verbindung.unlesbar;
    }
  }

  /// Die Argumente für `claude mcp add`. Der Schlüssel steht darin -- sie
  /// gehen an die claude.exe, nie in Protokoll oder Anzeige.
  List<String> addArgumente(int port, String schluessel) => [
        'mcp', 'add', '--scope', 'user', '--transport', 'http', mcpName, mcpAdresse(port), //
        '--header', 'Authorization: ${mcpKopf(schluessel)}',
      ];

  @override
  Future<String?> eintragen(int port, String schluessel) async {
    if (exe == null) return 'claude.exe nicht gefunden';
    // Fehlt der Eintrag, endet remove mit Fehler; das ist hier der Normalfall.
    await ausfuehren(exe!, ['mcp', 'remove', mcpName, '--scope', 'user']);
    final code = await ausfuehren(exe!, addArgumente(port, schluessel));
    return code == 0 ? null : 'claude mcp add endete mit Code $code';
  }

  @override
  Future<String?> austragen() async {
    if (verbindung(0, '') == Verbindung.fehlt) return null;
    if (exe == null) return 'claude.exe nicht gefunden';
    final code = await ausfuehren(exe!, ['mcp', 'remove', mcpName, '--scope', 'user']);
    return code == 0 ? null : 'claude mcp remove endete mit Code $code';
  }

  /// Nur für die Tests: ersetzt das Starten der claude.exe.
  Future<int> Function(String programm, List<String> argumente) ausfuehren = _ausfuehren;
}

/// Startet ein Programm ohne Konsole und wartet höchstens eine Minute. Die
/// Ausgabe wird gelesen (sonst kann ein voller Puffer den Prozess anhalten)
/// und verworfen.
Future<int> _ausfuehren(String programm, List<String> argumente) async {
  final pr = await Process.start(programm, argumente);
  unawaited(pr.stdout.drain<void>());
  unawaited(pr.stderr.drain<void>());
  return pr.exitCode.timeout(const Duration(minutes: 1), onTimeout: () {
    pr.kill();
    return -1;
  });
}

// ---------------------------------------------------------------------------
// Codex CLI
// ---------------------------------------------------------------------------

/// Codex CLI von OpenAI. Der Eintrag wird in `~/.codex/config.toml`
/// geschrieben, nicht über `codex mcp add`: Dessen Kommandozeile kennt nur
/// `--bearer-token-env-var`, das den Schlüssel in eine dauerhafte
/// Umgebungsvariable zwänge, die jedes Programm des Benutzers liest. Ein
/// statischer Kopf (`http_headers`) steht dagegen nur in dieser Datei, die
/// Codex nicht von selbst neu schreibt. Angefasst wird ausschließlich der
/// Block `[mcp_servers.moodle]`; alles andere darin bleibt Zeichen für
/// Zeichen stehen.
class CodexCli extends KiWerkzeug {
  CodexCli(super.umgebung);

  @override
  String get id => 'codex';
  @override
  String get name => 'Codex CLI';
  @override
  String get datenziel => 'Inhalte gehen an das eingestellte Modell, in der Regel bei OpenAI';

  /// CODEX_HOME verlegt Konfiguration und Skills; sonst `~/.codex`.
  Directory get heim => Directory(_v(umgebung, 'CODEX_HOME') ?? p.join(umgebung['USERPROFILE'] ?? '', '.codex'));

  File get konfiguration => File(p.join(heim.path, 'config.toml'));

  @override
  Directory get skillOrdner => Directory(p.join(heim.path, 'skills'));

  /// Die codex.exe braucht die App nicht (sie schreibt die Konfiguration
  /// selbst), wohl aber einen Hinweis darauf, dass Codex benutzt wird. Über
  /// npm installiert, liegt nur ein .cmd im Suchpfad.
  String? get exe {
    for (final d in [..._pfad(umgebung), if (_v(umgebung, 'APPDATA') != null) p.join(umgebung['APPDATA']!, 'npm')]) {
      for (final n in const ['codex.exe', 'codex.cmd', 'codex.bat']) {
        if (File(p.join(d, n)).existsSync()) return p.join(d, n);
      }
    }
    return null;
  }

  @override
  bool get gefunden => heim.existsSync() || exe != null;

  @override
  bool get bedienbar => true;
  @override
  String? get hindernis => null;

  @override
  Verbindung verbindung(int port, String schluessel) {
    if (!konfiguration.existsSync()) return Verbindung.fehlt;
    final String text;
    try {
      text = konfiguration.readAsStringSync();
    } catch (_) {
      return Verbindung.unlesbar;
    }
    final block = tomlBlock(text, mcpName);
    if (block == null) return Verbindung.fehlt;
    final url = _tomlWert(block, 'url');
    final kopf = _tomlWert(block, 'Authorization');
    if (url == null || kopf == null) return Verbindung.veraltet;
    return url == mcpAdresse(port) && kopf == mcpKopf(schluessel) ? Verbindung.aktuell : Verbindung.veraltet;
  }

  @override
  Future<String?> eintragen(int port, String schluessel) async {
    try {
      final alt = konfiguration.existsSync() ? konfiguration.readAsStringSync() : '';
      final neu = tomlBlockSetzen(alt, mcpName, mcpAdresse(port), mcpKopf(schluessel));
      konfiguration.parent.createSync(recursive: true);
      konfiguration.writeAsStringSync(neu, flush: true);
      return null;
    } catch (x) {
      return 'config.toml nicht geschrieben (${x.runtimeType})';
    }
  }

  @override
  Future<String?> austragen() async {
    if (!konfiguration.existsSync()) return null;
    try {
      final alt = konfiguration.readAsStringSync();
      if (tomlBlock(alt, mcpName) == null) return null;
      konfiguration.writeAsStringSync(tomlBlockEntfernen(alt, mcpName), flush: true);
      return null;
    } catch (x) {
      return 'config.toml nicht geschrieben (${x.runtimeType})';
    }
  }
}

// Der Kopf eines Blocks: [mcp_servers.moodle] oder [mcp_servers."moodle"],
// auch mit Unterblöcken wie [mcp_servers.moodle.http_headers].
RegExp _tomlKopf(String name) =>
    RegExp(r'^[ \t]*\[[ \t]*mcp_servers[ \t]*\.[ \t]*"?' + RegExp.escape(name) + r'"?[ \t]*(\.[^\]]*)?\][ \t]*$');

bool _istKopf(String zeile) => RegExp(r'^[ \t]*\[').hasMatch(zeile);

bool _leerOderKommentar(String zeile) {
  final z = zeile.trim();
  return z.isEmpty || z.startsWith('#');
}

/// Der Text des Blocks `[mcp_servers.<name>]` samt seiner Unterblöcke, oder
/// null, wenn es ihn nicht gibt. Bewusst kein vollständiger TOML-Leser: Es
/// geht nur um einen Block, den diese App selbst geschrieben hat, und jede
/// Abhängigkeit müsste nach E14 auf ihre Lizenz geprüft werden.
String? tomlBlock(String text, String name) {
  final zeilen = text.replaceAll('\r\n', '\n').split('\n');
  final (von, bis) = _tomlGrenzen(zeilen, name);
  return von < 0 ? null : zeilen.sublist(von, bis).join('\n');
}

/// Erste und hinter der letzten Zeile des Blocks. Leerzeilen und Kommentare
/// vor dem nächsten Kopf gehören zu diesem, nicht zu unserem Block: Wer über
/// `[mcp_servers.github]` notiert hat, wofür er ist, soll das behalten.
(int, int) _tomlGrenzen(List<String> zeilen, String name) {
  final kopf = _tomlKopf(name);
  final von = zeilen.indexWhere(kopf.hasMatch);
  if (von < 0) return (-1, -1);
  var bis = von + 1;
  while (bis < zeilen.length && !(_istKopf(zeilen[bis]) && !kopf.hasMatch(zeilen[bis]))) {
    bis++;
  }
  while (bis > von + 1 && _leerOderKommentar(zeilen[bis - 1])) {
    bis--;
  }
  return (von, bis);
}

/// Liest einen Wert in Anführungszeichen aus einem Blocktext, gleich ob er
/// als eigener Schlüssel, in einer Inline-Tabelle oder in einem Unterblock
/// steht: `url = "…"`, `http_headers = { Authorization = "…" }` und
/// `[mcp_servers.moodle.http_headers]` mit `Authorization = "…"` ergeben
/// dasselbe. Der Schlüssel muss für sich stehen, `token_url` ist nicht `url`.
String? _tomlWert(String block, String schluessel) =>
    RegExp(r'(?<![\w-])' + RegExp.escape(schluessel) + r'[ \t]*=[ \t]*"([^"]*)"').firstMatch(block)?.group(1);

/// Wendet [aendern] auf die Zeilen an und behält die Zeilenenden der Datei:
/// Wer CRLF hat, bekommt CRLF zurück.
String _zeilenweise(String text, List<String> Function(List<String> zeilen) aendern) {
  final crlf = text.contains('\r\n');
  final neu = aendern(text.replaceAll('\r\n', '\n').split('\n')).join('\n');
  return crlf ? neu.replaceAll('\n', '\r\n') : neu;
}

/// Setzt den Block `[mcp_servers.<name>]` auf Adresse und Kopf dieser App und
/// lässt alles andere unberührt. Einen vorhandenen Block ersetzt er samt
/// Unterblöcken, sonst hängt er ihn an.
String tomlBlockSetzen(String text, String name, String url, String kopf) {
  final block = ['[mcp_servers.$name]', 'url = "$url"', 'http_headers = { Authorization = "$kopf" }'];
  return _zeilenweise(text, (zeilen) {
    final (von, bis) = _tomlGrenzen(zeilen, name);
    if (von >= 0) return [...zeilen.sublist(0, von), ...block, ...zeilen.sublist(bis)];
    while (zeilen.isNotEmpty && zeilen.last.trim().isEmpty) {
      zeilen.removeLast();
    }
    return [...zeilen, if (zeilen.isNotEmpty) '', ...block, ''];
  });
}

/// Entfernt den Block `[mcp_servers.<name>]` samt Unterblöcken und den
/// Leerzeilen, die davor standen.
String tomlBlockEntfernen(String text, String name) => _zeilenweise(text, (zeilen) {
      final (von, bis) = _tomlGrenzen(zeilen, name);
      if (von < 0) return zeilen;
      var anfang = von;
      while (anfang > 0 && zeilen[anfang - 1].trim().isEmpty) {
        anfang--;
      }
      final rest = [...zeilen.sublist(0, anfang), ...zeilen.sublist(bis)];
      while (rest.isNotEmpty && rest.last.trim().isEmpty) {
        rest.removeLast();
      }
      return rest.isEmpty ? [] : [...rest, ''];
    });

// ---------------------------------------------------------------------------
// LM Studio
// ---------------------------------------------------------------------------

/// LM Studio mit seinem Agenten Bionic, einem eigenen Programm
/// (`%LOCALAPPDATA%\Programs\Bionic\Bionic.exe`) neben dem klassischen LM
/// Studio; beide teilen den Datenordner `~/.lmstudio`. Gemessen:
/// - Bionic liest `~/.lmstudio/mcp.json` nicht (die gehört zum klassischen
///   LM Studio), sondern führt seine Server in
///   `apps/bionic/.internal/ng-mcp.json`:
///   `{"servers": [{id, name, enabled, connection: {type: "stdio", command, args, env, timeoutMs}}]}`.
/// - Sein Dialog kennt nur lokale Befehle (stdio). Darum kommt die Brücke
///   hinein (mcp/bruecke.dart): `moocp-bruecke.exe`, ohne Schlüssel.
/// - Weder `lmstudio://add_mcp` (geht an das klassische LM Studio) noch
///   `bionic://add_mcp` legen dort etwas an. Von Hand eintragen wäre der
///   dokumentierte Weg, ist aber für Lehrkräfte zu viel.
/// - Bionic liest die Liste im laufenden Betrieb neu: Ein Eintrag von außen
///   erscheint sofort und bleibt über einen Neustart.
/// - `timeoutMs` ist das Zeitlimit je Anfrage an den Server (in Bionic
///   „Request timeout" unter den erweiterten Optionen): fehlt es, 60
///   Sekunden; erlaubt ist jede positive ganze Zahl bis 2³¹−1. Danach bricht
///   Bionic den Werkzeugaufruf ab, auch während eine Freigabe offen ist --
///   darum trägt die App [bionicZeitlimit] ein.
/// - Bilder aus Werkzeugergebnissen gibt Bionic nicht ans Modell weiter,
///   weder als Bildinhalt noch als eingebettete Ressource (darum legt
///   `bildschirmfoto` Dateien ab).
/// - Bionic verlangt in jeder Sitzung eine Erlaubnis für den Arbeitsordner;
///   sie lässt sich nicht vorab eintragen.
/// - Die Skills liegen in `~/.lmstudio/skills`, wie bei den anderen Werkzeugen
///   im eigenen Ordner: Claude Code liest keinen gemeinsamen, und nur so
///   bleibt das Deinstallieren eindeutig.
///
/// Also schreibt die App selbst hinein, ohne dass Bionic beendet werden muss.
/// Weil die Datei intern und nicht dokumentiert ist, so vorsichtig wie
/// möglich: Angefasst werden nur Einträge namens „moodle", alles andere
/// bleibt; geschrieben wird über eine Zwischendatei, damit Bionic nie eine
/// halbe liest; eine Liste, die sich nicht lesen lässt, wird nicht
/// überschrieben. Ob Bionic den Eintrag auch annimmt, sieht die App erst an
/// der Verbindung („KI-Werkzeug verbunden" im Protokoll); der Dialog sagt
/// deshalb „eingetragen", nicht mehr.
/// Das Zeitlimit, das die App in ihren Eintrag in Bionic schreibt. Länger als
/// die Frist einer Freigabe (`Freigaben.fristVorgabe`), die wie das Zeitlimit
/// ab der Anfrage läuft, auch hinter einer anderen: So endet die Freigabe
/// zuerst und meldet das selbst, und nach einer späten Freigabe bleibt Zeit
/// zum Schreiben und Zurücklesen. Bionics Vorgabe von 60 Sekunden bräche
/// fast jede Freigabe ab.
const bionicZeitlimit = Duration(minutes: 35);

class LmStudio extends KiWerkzeug {
  LmStudio(super.umgebung, {String? bruecke})
      : bruecke = bruecke ?? p.join(p.dirname(Platform.resolvedExecutable), brueckeExe);

  /// Die Brücke, die eingetragen wird: die neben der laufenden moocp.exe.
  final String bruecke;

  @override
  String get id => 'lmstudio';
  @override
  String get name => 'LM Studio (Bionic)';
  @override
  String get datenziel => 'Inhalte gehen an das eingestellte Modell, lokal oder in der Cloud';

  Directory get heim => Directory(p.join(umgebung['USERPROFILE'] ?? '', '.lmstudio'));

  /// Bionics Liste der MCP-Server.
  File get liste => File(p.join(heim.path, 'apps', 'bionic', '.internal', 'ng-mcp.json'));

  @override
  Directory get skillOrdner => Directory(p.join(heim.path, 'skills'));

  /// Gefunden ist LM Studio, sobald Bionic einmal gelaufen ist: Erst dann
  /// gibt es seine Liste, und erst Bionic arbeitet mit Werkzeugen und Skills.
  @override
  bool get gefunden => Directory(p.join(heim.path, 'apps', 'bionic')).existsSync();

  @override
  bool get bedienbar => true;
  @override
  String? get hindernis => null;

  @override
  String verbindungText(Verbindung v) => switch (v) {
        Verbindung.aktuell => 'eingetragen',
        Verbindung.fehlt => 'nicht eingetragen',
        Verbindung.veraltet => 'der Eintrag „moodle" weicht ab, wird ersetzt',
        Verbindung.unlesbar => 'Liste der MCP-Server von Bionic nicht lesbar',
      };

  /// Liest Bionics Liste. Fehlt sie, ist sie leer; lässt sie sich nicht
  /// lesen, wirft es -- dann wird nichts geschrieben.
  Map<String, dynamic> _lesen() {
    if (!liste.existsSync()) return {'servers': []};
    final text = liste.readAsStringSync().trim();
    if (text.isEmpty) return {'servers': []};
    final d = jsonDecode(text);
    if (d is! Map || d['servers'] is! List) throw const FormatException('ng-mcp.json ohne servers');
    return d.cast<String, dynamic>();
  }

  /// Schreibt die Liste über eine Zwischendatei: Bionic beobachtet sie und
  /// soll nie eine halb geschriebene lesen. Eingerückt wie von Bionic selbst.
  void _schreiben(Map<String, dynamic> daten) {
    liste.parent.createSync(recursive: true);
    final zwischen = File('${liste.path}.moocp');
    zwischen.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(daten), flush: true);
    zwischen.renameSync(liste.path);
  }

  static bool _unser(Object? e) => e is Map && e['name'] == mcpName;

  /// Ob ein Eintrag so dasteht, wie [eintragen] ihn schreibt: ein lokaler
  /// Befehl, eine vorhandene [brueckeExe], [bionicZeitlimit]. Welche Brücke,
  /// ist gleich -- installierte App und eigener Bau teilen Einstellungen und
  /// Port, die Brücke der einen erreicht auch die andere. Ob der Eintrag in
  /// Bionic eingeschaltet ist, entscheidet die Lehrkraft dort; eingetragen
  /// ist er so oder so.
  bool _passt(Map e) {
    final c = e['connection'];
    if (c is! Map) return false;
    final befehl = c['command'];
    return (c['type'] ?? 'stdio') == 'stdio' &&
        befehl is String &&
        p.basename(befehl).toLowerCase() == brueckeExe &&
        File(befehl).existsSync() &&
        c['timeoutMs'] == bionicZeitlimit.inMilliseconds;
  }

  @override
  Verbindung verbindung(int port, String schluessel) {
    try {
      final e = [for (final x in _lesen()['servers'] as List) if (_unser(x)) x as Map];
      if (e.isEmpty) return Verbindung.fehlt;
      return e.any(_passt) ? Verbindung.aktuell : Verbindung.veraltet;
    } catch (_) {
      return Verbindung.unlesbar;
    }
  }

  /// Ersetzt alle Einträge namens „moodle" durch die Brücke, wie `claude mcp
  /// remove` und `add` es bei Claude Code tun. Die id eines vorhandenen
  /// bleibt, damit Bionic, was es daran hängt, nicht verliert.
  @override
  Future<String?> eintragen(int port, String schluessel) async {
    if (!File(bruecke).existsSync()) return '$brueckeExe fehlt neben moocp.exe: moocp neu installieren.';
    try {
      final d = _lesen();
      final server = d['servers'] as List;
      final id = server.where(_unser).map((e) => (e as Map)['id']).whereType<String>().firstOrNull;
      d['servers'] = [
        ...server.where((e) => !_unser(e)),
        {
          'id': id ?? _neueId(),
          'name': mcpName,
          'enabled': true,
          'connection': {
            'type': 'stdio',
            'command': bruecke,
            'args': <String>[],
            'env': <String, String>{},
            'timeoutMs': bionicZeitlimit.inMilliseconds,
          },
        },
      ];
      _schreiben(d);
      return null;
    } on FormatException {
      return 'Die Liste der MCP-Server von Bionic ist nicht lesbar und wurde nicht angefasst.';
    } catch (x) {
      return 'Bionics Liste nicht geschrieben (${x.runtimeType})';
    }
  }

  @override
  Future<String?> austragen() async {
    try {
      final d = _lesen();
      final server = d['servers'] as List;
      if (!server.any(_unser)) return null;
      d['servers'] = [...server.where((e) => !_unser(e))];
      _schreiben(d);
      return null;
    } on FormatException {
      return 'Die Liste der MCP-Server von Bionic ist nicht lesbar und wurde nicht angefasst.';
    } catch (x) {
      return 'Bionics Liste nicht geschrieben (${x.runtimeType})';
    }
  }
}

/// Eine zufällige UUID (Version 4), wie Bionic sie als id seiner Einträge
/// führt.
String _neueId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Alle Werkzeuge, in der Reihenfolge, in der sie im Dialog stehen.
List<KiWerkzeug> alleWerkzeuge(Map<String, String> umgebung) =>
    [ClaudeCode(umgebung), CodexCli(umgebung), LmStudio(umgebung)];

/// Nur die, die auf diesem Rechner benutzt werden.
List<KiWerkzeug> gefundeneWerkzeuge(Map<String, String> umgebung) =>
    [for (final w in alleWerkzeuge(umgebung)) if (w.gefunden) w];

/// Die gewählten Skills, solange die Lehrkraft noch nichts gewählt hat: die
/// wählbaren, die in einem der Werkzeuge schon installiert sind. So entfernt
/// ein Update nichts, was jemand bisher benutzt hat; wer neu anfängt, hat
/// keinen.
Set<String> gewaehltVorgabe(Map<String, String> umgebung) => {
      for (final n in wahlSkills.keys)
        if (gefundeneWerkzeuge(umgebung).any((w) => skillInstalliert(w, n))) n,
    };

/// Installiert heißt: SKILL.md ist da. Ein leerer Ordner, den ein laufendes
/// KI-Werkzeug offen hält, zählt nicht -- ohne SKILL.md lädt es nichts.
bool skillInstalliert(KiWerkzeug w, String name) => File(p.join(w.skillOrdner.path, name, 'SKILL.md')).existsSync();

// ---------------------------------------------------------------------------
// Die Skills
// ---------------------------------------------------------------------------

/// Ein Skill, wie ihn die App mitbringt: Name und Dateien (Pfad mit „/"
/// relativ zum Skill-Ordner, Inhalt).
class SkillPaket {
  SkillPaket(this.name, this.dateien);
  final String name;
  final Map<String, List<int>> dateien;

  /// Liest ein Paket von skills/build.py: ein ZIP mit dem Ordner `<name>/`.
  factory SkillPaket.ausZip(String name, List<int> zip) {
    final dateien = <String, List<int>>{};
    for (final f in ZipDecoder().decodeBytes(zip)) {
      if (!f.isFile || !f.name.startsWith('$name/')) continue;
      dateien[f.name.substring(name.length + 1)] = f.content;
    }
    return SkillPaket(name, dateien);
  }
}

class SkillStand {
  SkillStand({this.fehlend = 0, this.abweichend = 0, this.ueberzaehlig = 0, this.ordnerFehlt = false});
  final int fehlend;
  final int abweichend;
  final int ueberzaehlig;
  final bool ordnerFehlt;

  bool get aktuell => !ordnerFehlt && fehlend + abweichend + ueberzaehlig == 0;

  /// Für die Anzeige im Dialog, in Worten, die auch ohne Technikwissen
  /// verständlich sind -- ob eine Datei fehlt oder abweicht, ändert nichts
  /// daran, was zu tun ist.
  String get text {
    if (ordnerFehlt) return 'nicht installiert';
    if (aktuell) return 'aktuell';
    return 'muss aktualisiert werden';
  }
}

// Windows unterscheidet bei Pfaden nicht nach Groß- und Kleinschreibung.
String _schluessel(String rel) => rel.replaceAll('\\', '/').toLowerCase();

Map<String, File> _vorhandene(Directory ziel) => {
      for (final f in ziel.listSync(recursive: true).whereType<File>())
        _schluessel(p.relative(f.path, from: ziel.path)): f,
    };

bool _gleich(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Vergleicht den installierten Skill Datei für Datei mit dem Paket. Am
/// Inhalt, nicht an einer Versionsnummer: So fällt auch eine Handänderung
/// im installierten Ordner auf.
SkillStand skillVergleichen(SkillPaket paket, Directory ziel) {
  if (!ziel.existsSync()) return SkillStand(ordnerFehlt: true);
  final da = _vorhandene(ziel);
  var fehlend = 0, abweichend = 0;
  final gesehen = <String>{};
  for (final e in paket.dateien.entries) {
    final k = _schluessel(e.key);
    gesehen.add(k);
    final f = da[k];
    if (f == null) {
      fehlend++;
    } else if (!_gleich(f.readAsBytesSync(), e.value)) {
      abweichend++;
    }
  }
  return SkillStand(
      fehlend: fehlend, abweichend: abweichend, ueberzaehlig: da.keys.where((k) => !gesehen.contains(k)).length);
}

/// Installiert einen Skill so, wie ihn das Paket enthält. Datei für Datei
/// statt den Ordner zu löschen: Ein laufendes KI-Werkzeug hält den
/// Skill-Ordner offen, Löschen scheitert dann (WinError 32). Dateien, die
/// nicht zum Paket gehören (etwa aus der alten Browser-Version), werden
/// einzeln entfernt, leer gewordene Unterordner danach. Liefert die Pfade,
/// die sich nicht entfernen ließen.
List<String> skillInstallieren(SkillPaket paket, Directory ziel) {
  ziel.createSync(recursive: true);
  final gewollt = <String>{};
  for (final e in paket.dateien.entries) {
    final f = File(p.joinAll([ziel.path, ...e.key.split('/')]));
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(e.value, flush: true);
    gewollt.add(_schluessel(e.key));
  }
  return _aufraeumen(ziel, gewollt);
}

/// Entfernt einen installierten Skill: jede Datei einzeln, dann den Ordner,
/// wenn er leer ist -- ein laufendes KI-Werkzeug hält ihn offen, leer schadet
/// er nicht. Liefert die Dateien, die sich nicht löschen ließen.
List<String> skillEntfernen(Directory ziel) {
  if (!ziel.existsSync()) return const [];
  final geblieben = _aufraeumen(ziel, const {});
  try {
    if (ziel.listSync().isEmpty) ziel.deleteSync();
  } on FileSystemException {
    // bleibt leer stehen
  }
  return geblieben;
}

/// Löscht in [ziel] jede Datei, die nicht in [behalten] steht, einzeln, dann
/// die leer gewordenen Unterordner. Liefert die Dateien, die sich nicht
/// löschen ließen.
List<String> _aufraeumen(Directory ziel, Set<String> behalten) {
  final geblieben = <String>[];
  for (final e in _vorhandene(ziel).entries) {
    if (behalten.contains(e.key)) continue;
    try {
      e.value.deleteSync();
    } on FileSystemException {
      geblieben.add(e.key);
    }
  }
  final ordner = ziel.listSync(recursive: true).whereType<Directory>().toList()
    ..sort((a, b) => b.path.length.compareTo(a.path.length));
  for (final d in ordner) {
    try {
      if (d.listSync().isEmpty) d.deleteSync();
    } on FileSystemException {
      // bleibt eben stehen
    }
  }
  return geblieben;
}

// ---------------------------------------------------------------------------
// Entfernen, beim Deinstallieren
// ---------------------------------------------------------------------------

/// Der Schalter, mit dem die Deinstallation (installer/moocp.nsi) die
/// App aufruft: Einrichtung entfernen, ohne Fenster, dann enden (main.dart).
/// Steht auch in windows/runner/main.cpp: Dieser Aufruf läuft auch neben
/// einer laufenden App. Der alte Name bleibt, damit die Deinstallation einer
/// älteren Version weiter wirkt.
const claudeEntfernenSchalter = '--claude-entfernen';

/// Auskünfte der App über stdout, ohne Fenster (main.dart): die
/// Werkzeugliste für die Brücke (mcp/bruecke.dart) und die Version. Stehen
/// auch in windows/runner/main.cpp: ohne Einzelstart-Sperre und ohne
/// Konsole.
const werkzeuglisteSchalter = '--werkzeugliste';
const versionSchalter = '--version';

/// Die Brücke für KI-Werkzeuge, die MCP nur über stdio sprechen
/// (mcp/bruecke.dart): ein eigenes Programm neben moocp.exe, gebaut von
/// windows/bruecke.cmake.
const brueckeExe = 'moocp-bruecke.exe';

/// Was nach dem Entfernen noch da ist.
class Entfernt {
  Entfernt({required this.eintragBleibt, required this.dateienBleiben});

  /// Werkzeuge, in denen der Eintrag „moodle" noch steht.
  final List<String> eintragBleibt;

  /// Dateien der Skills, die noch da sind, mit Werkzeug davor.
  final List<String> dateienBleiben;

  /// Der Exit-Code für die Deinstallation: 0 alles entfernt, Bit 1 ein
  /// Eintrag „moodle" steht noch, Bit 2 Dateien der Skills sind noch da.
  /// Leere Skill-Ordner zählen nicht: Ohne SKILL.md lädt kein Werkzeug etwas.
  int get code => (eintragBleibt.isEmpty ? 0 : 1) | (dateienBleiben.isEmpty ? 0 : 2);
}

/// Entfernt, was die App in den KI-Werkzeugen eingerichtet hat: den Eintrag
/// „moodle" und die Skills [skills], in jedem Werkzeug. Danach wird
/// nachgesehen, statt dem Ergebnis zu glauben.
Future<Entfernt> einrichtungEntfernen({
  required Map<String, String> umgebung,
  required List<String> skills,
  List<KiWerkzeug>? werkzeuge,
}) async {
  final geblieben = <String>[];
  final eintraege = <String>[];
  for (final w in werkzeuge ?? alleWerkzeuge(umgebung)) {
    await w.austragen();
    for (final name in skills) {
      geblieben.addAll(skillEntfernen(Directory(p.join(w.skillOrdner.path, name))).map((f) => '${w.id}: $name/$f'));
    }
    if (await _eintragDa(w)) eintraege.add(w.id);
  }
  return Entfernt(eintragBleibt: eintraege, dateienBleiben: geblieben);
}

/// Ob der Eintrag „moodle" (noch) steht, gleich mit welcher Adresse. Einen
/// halb geschriebenen Stand liest es kurz danach noch einmal; bleibt er
/// unlesbar, zählt der Eintrag als vorhanden.
Future<bool> _eintragDa(KiWerkzeug w) async {
  for (var i = 0; i < 3; i++) {
    final v = w.verbindung(0, '');
    if (v != Verbindung.unlesbar) return v != Verbindung.fehlt;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return true;
}

// ---------------------------------------------------------------------------
// Python
// ---------------------------------------------------------------------------

/// Ob `python` läuft. Der Skill lernsituation ruft sein Prüfskript mit Python
/// auf; installieren kann die App Python nicht, nur darauf hinweisen. Der
/// Platzhalter „python.exe" aus dem Microsoft Store endet ohne Python mit
/// einem Fehlercode und zählt deshalb richtig als „fehlt".
Future<bool> pythonVorhanden() async {
  try {
    return await _ausfuehren('python', ['--version']) == 0;
  } catch (_) {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Alles zusammen
// ---------------------------------------------------------------------------

/// Der Stand eines Werkzeugs: was dort fehlt und was „Installieren" dort tun
/// würde.
class Werkzeugstand {
  Werkzeugstand({
    required this.werkzeug,
    required this.gewaehlt,
    required this.verbindung,
    required this.skills,
    required this.stand,
    required this.entfernen,
  });

  final KiWerkzeug werkzeug;

  /// Ob die Lehrkraft dieses Werkzeug eingerichtet haben will.
  final bool gewaehlt;

  final Verbindung verbindung;

  /// Die Skills, die hier installiert sein sollen.
  final List<SkillPaket> skills;

  /// Stand je Skill, auch der nicht gewollten.
  final Map<String, SkillStand> stand;

  /// Skills, die hier weg sollen: die abgewählten, und bei einem abgewählten
  /// Werkzeug alle.
  final Set<String> entfernen;

  bool get verbunden => verbindung == Verbindung.aktuell;

  /// Ob hier alles steht, was es braucht -- die Bedingung dafür, dass die
  /// App überhaupt läuft (eines reicht).
  bool get fertig => gewaehlt && verbunden && skills.every((s) => stand[s.name]!.aktuell) && entfernen.isEmpty;

  /// Ob die App einen Eintrag in diesem Werkzeug selbst entfernen kann
  /// (Claude Code nur mit claude.exe).
  bool get austragbar => werkzeug.bedienbar;

  /// Ob „Installieren" hier etwas zu tun hat. Bei einem abgewählten Werkzeug
  /// zählt ein Eintrag nur, wenn die App ihn auch entfernen kann; sonst stünde
  /// der Dialog bei jedem Start da, und niemand könnte ihn mit einem Klick
  /// erledigen. Der Dialog sagt trotzdem, was von Hand zu tun ist.
  bool get brauchtEtwas => gewaehlt
      ? !fertig
      : (verbindung != Verbindung.fehlt && austragbar) || entfernen.isNotEmpty;

  /// Ob „Installieren" hier etwas bewirken kann: die Verbindung, wenn die
  /// App sie selbst einträgt, die Skills immer.
  bool get machbar =>
      (gewaehlt ? !verbunden && werkzeug.bedienbar : verbindung != Verbindung.fehlt && austragbar) ||
      skills.any((s) => !stand[s.name]!.aktuell) ||
      entfernen.isNotEmpty;
}

class Einrichtungsstand {
  Einrichtungsstand({
    required this.werkzeuge,
    required this.skills,
    required this.python,
    this.gewaehlt = const {},
  });

  /// Je gefundenes KI-Werkzeug ein Stand; leer, wenn keines gefunden wurde.
  final List<Werkzeugstand> werkzeuge;

  /// Alle Skills, die die App mitbringt.
  final List<SkillPaket> skills;

  final bool python;

  /// Die gewählten unter den [wahlSkills].
  final Set<String> gewaehlt;

  /// Was installiert sein soll: jeder Skill, der nicht wählbar ist, und die
  /// gewählten.
  List<SkillPaket> get gewollt =>
      [for (final s in skills) if (!wahlSkills.containsKey(s.name) || gewaehlt.contains(s.name)) s];

  /// Ob mindestens ein Werkzeug fertig eingerichtet ist. Nur dann läuft die
  /// App (einrichtung_dialog.dart): Für Claude, Codex und LM Studio
  /// zusammen gilt, was E13 für Claude Code allein sagte -- einen Zustand
  /// „die App läuft, aber kein KI-Werkzeug kann mit ihr arbeiten" gibt es
  /// nicht.
  bool get bereit => werkzeuge.any((w) => w.fertig);

  /// Ob der Dialog erscheinen muss. Python allein zählt nicht: Das kann die
  /// App nicht beheben, der Hinweis stünde sonst bei jedem Start da.
  bool get brauchtEtwas => !bereit || werkzeuge.any((w) => w.brauchtEtwas);

  /// Ob „Installieren" etwas bewirken kann.
  bool get einrichtbar => werkzeuge.any((w) => w.brauchtEtwas && w.machbar);
}

Future<Einrichtungsstand> einrichtungPruefen({
  required Map<String, String> umgebung,
  required int port,
  required String schluessel,
  required List<SkillPaket> skills,
  Set<String> abgewaehlt = const {},
  Set<String> gewaehlt = const {},
  Future<bool> Function() python = pythonVorhanden,
  List<KiWerkzeug>? gefunden,
}) async {
  final gewollt = [for (final s in skills) if (!wahlSkills.containsKey(s.name) || gewaehlt.contains(s.name)) s];
  final liste = gefunden ?? gefundeneWerkzeuge(umgebung);
  // Gewählt ist jedes gefundene Werkzeug, das die Lehrkraft nicht abgewählt
  // hat. Wer ein KI-Werkzeug auf dem Rechner hat, soll damit auch in Moodle
  // arbeiten können, ohne es erst zu erlauben -- auch eines, das erst nach
  // der App dazukam. Abwählen kann es jeder im Dialog, und die Wahl bleibt.
  final gewaehlteWerkzeuge = {for (final w in liste) if (!abgewaehlt.contains(w.id)) w.id};
  return Einrichtungsstand(
    werkzeuge: [
      for (final w in liste)
        Werkzeugstand(
          werkzeug: w,
          gewaehlt: gewaehlteWerkzeuge.contains(w.id),
          verbindung: w.verbindung(port, schluessel),
          skills: gewaehlteWerkzeuge.contains(w.id) ? gewollt : const [],
          stand: {for (final s in skills) s.name: skillVergleichen(s, Directory(p.join(w.skillOrdner.path, s.name)))},
          entfernen: {
            for (final s in skills)
              if (skillInstalliert(w, s.name) && (!gewaehlteWerkzeuge.contains(w.id) || !gewollt.contains(s)))
                s.name,
          },
        ),
    ],
    skills: skills,
    python: await python(),
    gewaehlt: gewaehlt,
  );
}
