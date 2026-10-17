// Offline prüfbar: die Einrichtung der KI-Werkzeuge an einem nachgebauten
// Ordnerbaum -- Werkzeuge finden, die MCP-Einträge von Claude Code, Codex
// und LM Studio prüfen und schreiben, Skills vergleichen und installieren.
//
// Nur unter Windows: Die Fälle sind mit Windows-Pfaden (C:\…, .exe, „;" im
// PATH) geschrieben, und p.join baut auf dem Mac POSIX-Pfade. Der macOS-Zweig
// steht in test/macos_test.dart.
@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/einrichtung.dart';
import 'package:moocp/freigabe.dart';
import 'package:path/path.dart' as p;

late Directory tmp;

File datei(String rel, [String inhalt = 'x']) {
  final f = File(p.joinAll([tmp.path, ...rel.split('/')]));
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(inhalt);
  return f;
}

List<int> zip(Map<String, String> dateien) {
  final a = Archive();
  dateien.forEach((name, inhalt) => a.addFile(ArchiveFile.bytes(name, utf8.encode(inhalt))));
  return ZipEncoder().encodeBytes(a);
}

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('einrichtung_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('claude.exe finden', () {
    const desktop = 'lokal/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude/claude-code';

    test('Claude Desktop (MSIX): höchste Version, als Zahl verglichen', () {
      datei('$desktop/2.1.9/claude.exe');
      datei('$desktop/2.1.10/claude.exe');
      datei('$desktop/2.1.11/anderes.txt'); // Ordner ohne claude.exe zählt nicht
      datei('$desktop/neu/claude.exe'); // keine Versionsnummer
      datei('lokal/Packages/Claude_fremd/LocalCache/Roaming/Claude/claude-code/9.9.9/claude.exe');
      final gefunden = claudeFinden({'LOCALAPPDATA': p.join(tmp.path, 'lokal')});
      expect(gefunden, p.join(tmp.path, 'lokal', 'Packages', 'Claude_pzs8sxrjxfjjc', 'LocalCache', 'Roaming',
          'Claude', 'claude-code', '2.1.10', 'claude.exe'));
    });

    test('Reihenfolge: Claude Desktop vor klassischem Installer vor VS Code', () {
      datei('roaming/Claude/claude-code/3.0.0/claude.exe');
      datei('heim/.vscode/extensions/anthropic.claude-code-2.1.282-win32-x64/resources/native-binary/claude.exe');
      final u = {
        'LOCALAPPDATA': p.join(tmp.path, 'lokal'),
        'APPDATA': p.join(tmp.path, 'roaming'),
        'USERPROFILE': p.join(tmp.path, 'heim'),
      };
      expect(claudeFinden(u), endsWith(p.join('3.0.0', 'claude.exe')));
      datei('$desktop/2.1.281/claude.exe');
      expect(claudeFinden(u), endsWith(p.join('2.1.281', 'claude.exe')));
    });

    test('VS-Code-Erweiterung und Suchpfad', () {
      datei('heim/.vscode/extensions/anthropic.claude-code-2.1.9-win32-x64/resources/native-binary/claude.exe');
      datei('heim/.vscode/extensions/anthropic.claude-code-2.1.10-win32-x64/resources/native-binary/claude.exe');
      expect(claudeFinden({'USERPROFILE': p.join(tmp.path, 'heim')}), contains('2.1.10'));
      datei('bin/claude.exe');
      expect(claudeFinden({'USERPROFILE': p.join(tmp.path, 'heim'), 'PATH': 'C:\\gibtsnicht;${p.join(tmp.path, 'bin')}'}),
          p.join(tmp.path, 'bin', 'claude.exe'));
    });

    test('nichts da, leere Umgebung', () {
      expect(claudeFinden({'LOCALAPPDATA': p.join(tmp.path, 'lokal')}), isNull);
      expect(claudeFinden({}), isNull);
    });
  });

  test('Versionen vergleichen', () {
    expect(versionVergleichen([2, 10], [2, 9]), greaterThan(0));
    expect(versionVergleichen([2, 1, 281], [2, 1, 280]), greaterThan(0));
    expect(versionVergleichen([2, 1], [2, 1, 0]), 0);
  });

  Map eintrag(String url, String schluessel, {String? typ = 'http'}) => {
        'mcpServers': {
          'moodle': {
            'type': ?typ,
            'url': url,
            'headers': {'Authorization': 'Bearer $schluessel'},
          },
        },
      };

  group('Claude Code: MCP-Eintrag', () {
    ClaudeCode claude() => ClaudeCode({'USERPROFILE': tmp.path});
    File konfig(Object inhalt) => datei('.claude.json', inhalt is String ? inhalt : jsonEncode(inhalt));

    test('aktuell, veraltet, fehlt, unlesbar', () {
      expect(claude().verbindung(47811, 'abc'), Verbindung.fehlt);
      konfig({'mcpServers': {}});
      expect(claude().verbindung(47811, 'abc'), Verbindung.fehlt);
      konfig(eintrag('http://127.0.0.1:47811/mcp', 'abc'));
      expect(claude().verbindung(47811, 'abc'), Verbindung.aktuell);
      konfig(eintrag('http://127.0.0.1:47811/mcp', 'alt'));
      expect(claude().verbindung(47811, 'abc'), Verbindung.veraltet);
      konfig(eintrag('http://127.0.0.1:47812/mcp', 'abc'));
      expect(claude().verbindung(47811, 'abc'), Verbindung.veraltet);
      konfig('{"mcpServers": {"moodle": ');
      expect(claude().verbindung(47811, 'abc'), Verbindung.unlesbar);
    });

    test('der Header geht als ein Argument an claude mcp add', () {
      final a = claude().addArgumente(47811, 'abc');
      expect(a, containsAllInOrder(['mcp', 'add', '--scope', 'user', 'moodle', 'http://127.0.0.1:47811/mcp']));
      expect(a.last, 'Authorization: Bearer abc');
    });

    test('CLAUDE_CONFIG_DIR verlegt Einstellungen und Skills', () {
      final o = ClaudeCode({'USERPROFILE': 'C:\\Users\\x', 'CLAUDE_CONFIG_DIR': 'D:\\claude'});
      expect(o.konfiguration.path, p.join('D:\\claude', '.claude.json'));
      expect(o.skillOrdner.path, p.join('D:\\claude', 'skills'));
      final n = ClaudeCode({'USERPROFILE': 'C:\\Users\\x'});
      expect(n.konfiguration.path, p.join('C:\\Users\\x', '.claude.json'));
      expect(n.skillOrdner.path, p.join('C:\\Users\\x', '.claude', 'skills'));
    });
  });

  group('Codex CLI: der Block in config.toml', () {
    const url = 'http://127.0.0.1:47811/mcp';
    const kopf = 'Bearer abc';
    const unser = '[mcp_servers.moodle]\nurl = "$url"\nhttp_headers = { Authorization = "$kopf" }\n';

    test('in eine leere oder fehlende Datei', () {
      expect(tomlBlockSetzen('', 'moodle', url, kopf), unser);
      expect(tomlBlockSetzen('\n\n', 'moodle', url, kopf), unser);
    });

    test('angehängt: alles andere bleibt Zeichen für Zeichen', () {
      const alt = 'model = "gpt-5"\n\n# mein Server\n[mcp_servers.github]\nurl = "https://example.com/mcp"\n';
      final neu = tomlBlockSetzen(alt, 'moodle', url, kopf);
      expect(neu, '$alt\n$unser');
      expect(tomlBlockEntfernen(neu, 'moodle'), alt);
    });

    test('ersetzt samt Unterblock; Kommentar über dem nächsten Block bleibt', () {
      const alt = 'model = "gpt-5"\n\n'
          '[mcp_servers.moodle]\nurl = "http://127.0.0.1:1/mcp"\n'
          '[mcp_servers.moodle.http_headers]\nAuthorization = "Bearer alt"\n\n'
          '# mein Server\n[mcp_servers.github]\nurl = "https://example.com/mcp"\n';
      final neu = tomlBlockSetzen(alt, 'moodle', url, kopf);
      expect(
          neu,
          'model = "gpt-5"\n\n$unser\n'
          '# mein Server\n[mcp_servers.github]\nurl = "https://example.com/mcp"\n');
      expect(tomlBlockEntfernen(neu, 'moodle'),
          'model = "gpt-5"\n\n# mein Server\n[mcp_servers.github]\nurl = "https://example.com/mcp"\n');
    });

    test('ein Server mit ähnlichem Namen bleibt unberührt', () {
      const alt = '[mcp_servers.moodle2]\nurl = "x"\n';
      expect(tomlBlock(alt, 'moodle'), isNull);
      expect(tomlBlockSetzen(alt, 'moodle', url, kopf), '$alt\n$unser');
      expect(tomlBlockEntfernen(alt, 'moodle'), alt);
    });

    test('Anführungszeichen im Kopf: [mcp_servers."moodle"]', () {
      expect(tomlBlock('[mcp_servers."moodle"]\nurl = "x"\n', 'moodle'), isNotNull);
    });

    test('CRLF bleibt CRLF', () {
      const alt = 'model = "gpt-5"\r\n';
      final neu = tomlBlockSetzen(alt, 'moodle', url, kopf);
      expect(neu, 'model = "gpt-5"\r\n\r\n${unser.replaceAll('\n', '\r\n')}');
      expect(neu.replaceAll('\r\n', ''), isNot(contains('\n')));
      expect(tomlBlockEntfernen(neu, 'moodle'), alt);
    });

    test('Block allein entfernt ergibt eine leere Datei', () {
      expect(tomlBlockEntfernen(unser, 'moodle'), '');
    });

    test('Verbindung: fehlt, aktuell, veraltet, Unterblock, token_url ist nicht url', () async {
      final codex = CodexCli({'USERPROFILE': tmp.path});
      expect(codex.verbindung(47811, 'abc'), Verbindung.fehlt);
      expect(await codex.eintragen(47811, 'abc'), isNull);
      expect(codex.verbindung(47811, 'abc'), Verbindung.aktuell);
      expect(codex.verbindung(47811, 'neu'), Verbindung.veraltet);
      expect(codex.verbindung(47812, 'abc'), Verbindung.veraltet);

      codex.konfiguration.writeAsStringSync(
          '[mcp_servers.moodle]\nurl = "$url"\n[mcp_servers.moodle.http_headers]\nAuthorization = "$kopf"\n');
      expect(codex.verbindung(47811, 'abc'), Verbindung.aktuell);

      codex.konfiguration.writeAsStringSync('[mcp_servers.moodle]\ntoken_url = "$url"\n');
      expect(codex.verbindung(47811, 'abc'), Verbindung.veraltet);

      expect(await codex.austragen(), isNull);
      expect(codex.verbindung(47811, 'abc'), Verbindung.fehlt);
    });

    test('CODEX_HOME verlegt Konfiguration und Skills', () {
      final c = CodexCli({'USERPROFILE': 'C:\\Users\\x', 'CODEX_HOME': 'D:\\codex'});
      expect(c.konfiguration.path, p.join('D:\\codex', 'config.toml'));
      expect(c.skillOrdner.path, p.join('D:\\codex', 'skills'));
      expect(CodexCli({'USERPROFILE': 'C:\\Users\\x'}).skillOrdner.path, p.join('C:\\Users\\x', '.codex', 'skills'));
    });
  });

  group('LM Studio (Bionic): die Brücke in Bionics Liste', () {
    late String exe;
    setUp(() => exe = datei('app/moocp-bruecke.exe').path);
    const pfad = '.lmstudio/apps/bionic/.internal/ng-mcp.json';
    File liste(List<Map<String, Object?>> server, {Map<String, Object?> mehr = const {}}) =>
        datei(pfad, jsonEncode({'servers': server, ...mehr}));
    final zeitlimit = bionicZeitlimit.inMilliseconds;
    Map<String, Object?> server(String befehl, List<String> args,
            {String name = 'moodle', String id = 'x', Object? timeoutMs = 'wie eingetragen'}) =>
        {
          'id': id,
          'name': name,
          'enabled': true,
          'connection': {
            'type': 'stdio',
            'command': befehl,
            'args': args,
            'env': {},
            if (timeoutMs != null) 'timeoutMs': timeoutMs == 'wie eingetragen' ? zeitlimit : timeoutMs,
          },
        };
    List gelesen() => (jsonDecode(File(p.join(tmp.path, pfad)).readAsStringSync()) as Map)['servers'] as List;
    LmStudio lm() => LmStudio({'USERPROFILE': tmp.path}, bruecke: exe);

    test('fehlt, aktuell, veraltet, unlesbar', () {
      expect(lm().verbindung(0, ''), Verbindung.fehlt);
      liste([server('cmd', ['/c', 'uvx', 'blender-mcp'], name: 'blender')]);
      expect(lm().verbindung(0, ''), Verbindung.fehlt, reason: 'nur ein fremder Server');
      liste([server(exe, [])]);
      expect(lm().verbindung(0, ''), Verbindung.aktuell);
      liste([server(datei('app/moocp.exe').path, ['--mcp-stdio'])]);
      expect(lm().verbindung(0, ''), Verbindung.veraltet, reason: 'die App selbst ist nicht die Brücke');
      liste([server('cmd', ['/c', 'npx', '-y', 'mcp-remote', 'http://127.0.0.1:47811/mcp'])]);
      expect(lm().verbindung(0, ''), Verbindung.veraltet, reason: 'moodle, aber nicht über die Brücke');
      liste([server(p.join(tmp.path, 'weg', 'moocp-bruecke.exe'), [])]);
      expect(lm().verbindung(0, ''), Verbindung.veraltet, reason: 'die Brücke gibt es dort nicht mehr');
      liste([server(exe, [], timeoutMs: null)]);
      expect(lm().verbindung(0, ''), Verbindung.veraltet, reason: 'ohne Zeitlimit: Bionics 60 Sekunden');
      liste([server(exe, [], timeoutMs: 120000)]);
      expect(lm().verbindung(0, ''), Verbindung.veraltet, reason: 'ein anderes Zeitlimit');
      datei(pfad, '{"servers": [');
      expect(lm().verbindung(0, ''), Verbindung.unlesbar);
    });

    test('eintragen: neue Liste, Brücke ohne Schlüssel, keine Zwischendatei übrig', () async {
      expect(await lm().eintragen(47811, 'geheim'), isNull);
      expect(lm().verbindung(0, ''), Verbindung.aktuell);
      final e = gelesen().single as Map;
      expect(e['id'], matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(e['connection'], {
        'type': 'stdio',
        'command': exe,
        'args': [],
        'env': {},
        'timeoutMs': zeitlimit,
      });
      expect(File(p.join(tmp.path, pfad)).readAsStringSync(), isNot(contains('geheim')));
      expect(File(p.join(tmp.path, '$pfad.moocp')).existsSync(), isFalse);
    });

    test('eintragen: Fremdes bleibt, ein alter „moodle" wird ersetzt und behält seine id', () async {
      liste([
        server('cmd', ['/c', 'uvx', 'blender-mcp'], name: 'blender', id: 'b'),
        server('cmd', ['/c', 'npx', 'mcp-remote'], id: 'alt'),
      ], mehr: {'version': 3});
      expect(await lm().eintragen(47811, 'abc'), isNull);
      final s = gelesen();
      expect(s.map((e) => (e as Map)['name']), ['blender', 'moodle']);
      expect((s.last as Map)['id'], 'alt');
      expect((s.first as Map)['connection'], (jsonDecode(jsonEncode(server('cmd', ['/c', 'uvx', 'blender-mcp']))) as Map)['connection']);
      expect((jsonDecode(File(p.join(tmp.path, pfad)).readAsStringSync()) as Map)['version'], 3);
      expect(lm().verbindung(0, ''), Verbindung.aktuell);
    });

    test('Bionics Zeitlimit: länger als die Frist einer Freigabe', () {
      expect(bionicZeitlimit, greaterThan(Freigaben.fristVorgabe));
    });

    test('ohne Brücke neben der App: nichts eintragen, sondern es sagen', () async {
      final ohne = LmStudio({'USERPROFILE': tmp.path}, bruecke: p.join(tmp.path, 'weg', 'moocp-bruecke.exe'));
      expect(await ohne.eintragen(47811, 'abc'), contains('moocp-bruecke.exe fehlt'));
      expect(File(p.join(tmp.path, pfad)).existsSync(), isFalse);
    });

    test('eine unlesbare Liste wird nicht überschrieben', () async {
      final f = datei(pfad, '{"servers": [');
      expect(await lm().eintragen(47811, 'abc'), contains('nicht angefasst'));
      expect(await lm().austragen(), contains('nicht angefasst'));
      expect(f.readAsStringSync(), '{"servers": [');
    });

    test('austragen: nur „moodle" geht, Fremdes bleibt', () async {
      expect(await lm().austragen(), isNull, reason: 'keine Liste, nichts zu tun');
      liste([server('cmd', ['/c', 'uvx', 'blender-mcp'], name: 'blender'), server(exe, [])]);
      expect(await lm().austragen(), isNull);
      expect(gelesen().map((e) => (e as Map)['name']), ['blender']);
      expect(lm().verbindung(0, ''), Verbindung.fehlt);
    });
  });

  group('gefunden', () {
    test('an Konfigurationsordnern oder Programmen', () {
      final u = {'USERPROFILE': p.join(tmp.path, 'heim'), 'LOCALAPPDATA': p.join(tmp.path, 'lokal')};
      expect(gefundeneWerkzeuge(u), isEmpty);
      Directory(p.join(tmp.path, 'heim', '.codex')).createSync(recursive: true);
      expect(gefundeneWerkzeuge(u).map((w) => w.id), ['codex']);
      Directory(p.join(tmp.path, 'heim', '.lmstudio')).createSync(recursive: true);
      expect(gefundeneWerkzeuge(u).map((w) => w.id), ['codex'], reason: 'LM Studio, aber Bionic lief nie');
      Directory(p.join(tmp.path, 'heim', '.lmstudio', 'apps', 'bionic')).createSync(recursive: true);
      datei('heim/.claude.json', '{}');
      expect(gefundeneWerkzeuge(u).map((w) => w.id), ['claude', 'codex', 'lmstudio']);
    });

    test('Codex auch nur über npm', () {
      datei('roaming/npm/codex.cmd');
      expect(CodexCli({'USERPROFILE': p.join(tmp.path, 'heim'), 'APPDATA': p.join(tmp.path, 'roaming')}).gefunden,
          isTrue);
    });
  });

  group('Skills', () {
    final paket = SkillPaket.ausZip(
        'moodle',
        zip({
          'moodle/SKILL.md': 'Skill',
          'moodle/references/lesen.md': 'Lesen',
          'anderes/SKILL.md': 'gehört nicht dazu',
        }));

    test('Paket liest nur den eigenen Ordner', () {
      expect(paket.dateien.keys, unorderedEquals(['SKILL.md', 'references/lesen.md']));
    });

    test('vergleichen, installieren, Verwaistes entfernen', () {
      final ziel = Directory(p.join(tmp.path, 'skills', 'moodle'));
      expect(skillVergleichen(paket, ziel).text, 'nicht installiert');

      expect(skillInstallieren(paket, ziel), isEmpty);
      expect(skillVergleichen(paket, ziel).aktuell, isTrue);
      expect(File(p.join(ziel.path, 'references', 'lesen.md')).readAsStringSync(), 'Lesen');

      // Handänderung, überzählige Datei, fehlende Datei
      File(p.join(ziel.path, 'SKILL.md')).writeAsStringSync('von Hand geändert');
      datei('skills/moodle/scripts/page-helpers.js');
      File(p.join(ziel.path, 'references', 'lesen.md')).deleteSync();
      final s = skillVergleichen(paket, ziel);
      expect((s.abweichend, s.ueberzaehlig, s.fehlend), (1, 1, 1));
      expect(s.text, 'muss aktualisiert werden');

      expect(skillInstallieren(paket, ziel), isEmpty);
      expect(skillVergleichen(paket, ziel).aktuell, isTrue);
      expect(Directory(p.join(ziel.path, 'scripts')).existsSync(), isFalse, reason: 'leer gewordener Ordner');
    });
  });

  group('Einrichtungsstand', () {
    final paket = SkillPaket('moodle', {'SKILL.md': utf8.encode('Skill')});
    late String heim;
    late Map<String, String> u;
    setUp(() {
      heim = p.join(tmp.path, 'heim');
      u = {'USERPROFILE': heim, 'LOCALAPPDATA': p.join(tmp.path, 'lokal')};
    });
    void claudeEintrag() => datei('heim/.claude.json', jsonEncode(eintrag('http://127.0.0.1:47811/mcp', 'abc')));
    Directory skills(String werkzeug, String name) => Directory(p.join(heim, werkzeug, 'skills', name));
    Future<Einrichtungsstand> pruefen({Set<String> abgewaehlt = const {}, bool python = true}) => einrichtungPruefen(
        umgebung: u,
        port: 47811,
        schluessel: 'abc',
        skills: [paket],
        abgewaehlt: abgewaehlt,
        python: () async => python);

    test('Dialog nur, wenn etwas zu tun ist -- fehlendes Python allein zählt nicht', () async {
      claudeEintrag();
      datei('lokal/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude/claude-code/2.1.281/claude.exe');
      var s = await pruefen(python: false);
      expect(s.brauchtEtwas, isTrue, reason: 'Skill fehlt');
      skillInstallieren(paket, skills('.claude', 'moodle'));
      s = await pruefen(python: false);
      expect(s.brauchtEtwas, isFalse);
      expect(s.bereit, isTrue);
      expect(s.python, isFalse);

      Directory(p.join(tmp.path, 'lokal')).deleteSync(recursive: true);
      s = await pruefen();
      expect((s.werkzeuge.single.werkzeug as ClaudeCode).exe, isNull);
      expect(s.brauchtEtwas, isFalse, reason: 'Eintrag stimmt schon, claude.exe braucht es nur zum Eintragen');
    });

    test('Ohne claude.exe einrichtbar sind nur die Skills', () async {
      datei('heim/.claude/skills/fremd/SKILL.md'); // Claude Code wird benutzt
      var s = await pruefen();
      expect(s.werkzeuge.single.verbindung, Verbindung.fehlt);
      expect(s.einrichtbar, isTrue, reason: 'die Skills gehen auch ohne claude.exe');
      expect(s.werkzeuge.single.werkzeug.hindernis, isNotNull);
      skillInstallieren(paket, skills('.claude', 'moodle'));
      s = await pruefen();
      expect(s.einrichtbar, isFalse, reason: 'nur noch die Verbindung, und die braucht claude.exe');
      skillEntfernen(skills('.claude', 'moodle'));

      claudeEintrag();
      s = await pruefen();
      expect(s.brauchtEtwas, isTrue, reason: 'Skill fehlt');
      expect(s.einrichtbar, isTrue, reason: 'Skills gehen ohne claude.exe');
    });

    test('kein Werkzeug gefunden: nicht bereit, nichts einzurichten', () async {
      final s = await pruefen();
      expect(s.werkzeuge, isEmpty);
      expect(s.bereit, isFalse);
      expect(s.brauchtEtwas, isTrue, reason: 'ohne Werkzeug läuft die App nicht');
      expect(s.einrichtbar, isFalse);
    });

    test('eines eingerichtet reicht zum Laufen; ein neues Werkzeug wird trotzdem angeboten', () async {
      claudeEintrag();
      skillInstallieren(paket, skills('.claude', 'moodle'));
      Directory(p.join(heim, '.codex')).createSync(recursive: true);
      var s = await pruefen();
      expect(s.werkzeuge.map((w) => w.werkzeug.id), ['claude', 'codex']);
      expect(s.bereit, isTrue);
      expect(s.brauchtEtwas, isTrue, reason: 'Codex ist gewählt und noch nicht eingerichtet');
      expect(s.einrichtbar, isTrue);

      // Abgewählt und nichts von uns darin: nichts zu tun.
      s = await pruefen(abgewaehlt: {'codex'});
      expect(s.brauchtEtwas, isFalse);

      // Eingerichtet: auch nichts.
      final codex = s.werkzeuge.last.werkzeug;
      expect(await codex.eintragen(47811, 'abc'), isNull);
      skillInstallieren(paket, skills('.codex', 'moodle'));
      s = await pruefen();
      expect(s.werkzeuge.every((w) => w.fertig), isTrue);
      expect(s.brauchtEtwas, isFalse);
    });

    test('ein abgewähltes Werkzeug wird geräumt: Eintrag und alle Skills', () async {
      claudeEintrag();
      skillInstallieren(paket, skills('.claude', 'moodle'));
      final codex = CodexCli(u);
      expect(await codex.eintragen(47811, 'abc'), isNull);
      skillInstallieren(paket, skills('.codex', 'moodle'));

      var s = await pruefen(abgewaehlt: {'codex'});
      final w = s.werkzeuge.firstWhere((x) => x.werkzeug.id == 'codex');
      expect(w.gewaehlt, isFalse);
      expect(w.entfernen, {'moodle'});
      expect(w.brauchtEtwas, isTrue);
      expect(s.bereit, isTrue, reason: 'Claude ist eingerichtet');

      expect(await codex.austragen(), isNull);
      skillEntfernen(skills('.codex', 'moodle'));
      s = await pruefen(abgewaehlt: {'codex'});
      expect(s.brauchtEtwas, isFalse);
    });

    test('LM Studio abgewählt: Eintrag und Skills werden geräumt', () async {
      claudeEintrag();
      skillInstallieren(paket, skills('.claude', 'moodle'));
      final exe = datei('app/moocp-bruecke.exe').path;
      datei('heim/.lmstudio/apps/bionic/.internal/ng-mcp.json', jsonEncode({
        'servers': [
          {
            'name': 'moodle',
            'connection': {
              'type': 'stdio',
              'command': exe,
              'args': [],
              'timeoutMs': bionicZeitlimit.inMilliseconds,
            },
          },
        ],
      }));
      skillInstallieren(paket, skills('.lmstudio', 'moodle'));

      var s = await pruefen(abgewaehlt: {'lmstudio'});
      var w = s.werkzeuge.firstWhere((x) => x.werkzeug.id == 'lmstudio');
      expect(w.verbindung, Verbindung.aktuell);
      expect((w.brauchtEtwas, w.machbar), (true, true));
      skillEntfernen(skills('.lmstudio', 'moodle'));
      expect(await w.werkzeug.austragen(), isNull);
      s = await pruefen(abgewaehlt: {'lmstudio'});
      w = s.werkzeuge.firstWhere((x) => x.werkzeug.id == 'lmstudio');
      expect(w.brauchtEtwas, isFalse);
      expect(s.brauchtEtwas, isFalse);
    });

    test('alles abgewählt: nicht bereit, auch wenn alles stimmt', () async {
      claudeEintrag();
      skillInstallieren(paket, skills('.claude', 'moodle'));
      final s = await pruefen(abgewaehlt: {'claude'});
      expect(s.bereit, isFalse);
      expect(s.brauchtEtwas, isTrue);
    });
  });

  test('Wählbare Skills: nur gewählt installiert, abgewählt entfernt, Vorgabe aus dem Bestand', () async {
    final heim = p.join(tmp.path, 'heim');
    datei('heim/.claude.json', jsonEncode(eintrag('http://127.0.0.1:47811/mcp', 'abc')));
    final u = {'USERPROFILE': heim};
    final claude = ClaudeCode(u);
    final moodle = SkillPaket('moodle', {'SKILL.md': utf8.encode('Kurs')});
    final ls = SkillPaket('lernsituation', {'SKILL.md': utf8.encode('Lernsituation')});
    Directory ziel(String n) => Directory(p.join(claude.skillOrdner.path, n));
    Future<Einrichtungsstand> pruefen(Set<String> gewaehlt) => einrichtungPruefen(
        umgebung: u, port: 47811, schluessel: 'abc', skills: [moodle, ls], gewaehlt: gewaehlt, python: () async => true);
    Set<String> entfernen(Einrichtungsstand s) => s.werkzeuge.single.entfernen;

    // Neu angefangen: nichts gewählt, lernsituation gehört nicht dazu.
    expect(gewaehltVorgabe(u), isEmpty);
    skillInstallieren(moodle, ziel('moodle'));
    var s = await pruefen(gewaehltVorgabe(u));
    expect(s.gewollt.map((x) => x.name), ['moodle']);
    expect(s.brauchtEtwas, isFalse, reason: 'nicht gewählt und nicht installiert: nichts zu tun');

    // Gewählt, aber nicht installiert.
    s = await pruefen({'lernsituation'});
    expect(s.brauchtEtwas, isTrue);
    skillInstallieren(ls, ziel('lernsituation'));
    expect((await pruefen({'lernsituation'})).brauchtEtwas, isFalse);

    // Wer ihn schon hat und noch nichts gewählt hat, behält ihn.
    expect(gewaehltVorgabe(u), {'lernsituation'});

    // Abgewählt: installiert, also entfernen.
    s = await pruefen({});
    expect(entfernen(s), {'lernsituation'});
    expect(s.brauchtEtwas, isTrue);
    expect(skillEntfernen(ziel('lernsituation')), isEmpty);
    s = await pruefen({});
    expect(entfernen(s), isEmpty);
    expect(s.brauchtEtwas, isFalse);
    expect(ziel('lernsituation').existsSync(), isFalse);
  });

  group('Entfernen beim Deinstallieren', () {
    const desktop = 'lokal/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude/claude-code';
    const fremd = {'type': 'http', 'url': 'http://127.0.0.1:2/mcp'};
    late Map<String, String> umgebung;
    late File konfig;
    setUp(() {
      umgebung = {
        'CLAUDE_CONFIG_DIR': p.join(tmp.path, 'cfg'),
        'LOCALAPPDATA': p.join(tmp.path, 'lokal'),
        'USERPROFILE': p.join(tmp.path, 'heim'),
      };
      konfig = datei(
          'cfg/.claude.json',
          jsonEncode({
            'mcpServers': {
              'moodle': {'type': 'http', 'url': 'http://127.0.0.1:1/mcp'},
              'anderer': fremd,
            },
          }));
      datei('cfg/skills/moodle/SKILL.md');
      datei('cfg/skills/moodle/references/a.md');
      datei('cfg/skills/lernsituation/SKILL.md');
      datei('cfg/skills/fremd/SKILL.md');
    });

    // Tut, was `claude mcp remove moodle` tut, und merkt sich den Aufruf.
    final aufrufe = <List<String>>[];
    Future<int> claudeAttrappe(String programm, List<String> argumente) async {
      aufrufe.add([programm, ...argumente]);
      konfig.writeAsStringSync(jsonEncode({
        'mcpServers': {'anderer': fremd},
      }));
      return 0;
    }

    setUp(aufrufe.clear);

    List<KiWerkzeug> werkzeuge({Future<int> Function(String, List<String>)? ausfuehren}) =>
        [ClaudeCode(umgebung)..ausfuehren = ausfuehren ?? claudeAttrappe, CodexCli(umgebung), LmStudio(umgebung)];

    test('Eintrag über claude.exe, Skills der App gelöscht, fremde bleiben', () async {
      final exe = datei('$desktop/2.1.9/claude.exe').path;
      final e = await einrichtungEntfernen(umgebung: umgebung, skills: ['moodle', 'lernsituation'], werkzeuge: werkzeuge());
      expect(aufrufe, [
        [exe, 'mcp', 'remove', 'moodle', '--scope', 'user'],
      ]);
      expect(e.code, 0);
      expect(Directory(p.join(tmp.path, 'cfg/skills/moodle')).existsSync(), isFalse);
      expect(Directory(p.join(tmp.path, 'cfg/skills/lernsituation')).existsSync(), isFalse);
      expect(File(p.join(tmp.path, 'cfg/skills/fremd/SKILL.md')).existsSync(), isTrue);
    });

    test('ohne claude.exe: Eintrag bleibt und wird gemeldet, Skills trotzdem weg', () async {
      final e = await einrichtungEntfernen(umgebung: umgebung, skills: ['moodle'], werkzeuge: werkzeuge());
      expect(aufrufe, isEmpty);
      expect(e.eintragBleibt, ['claude']);
      expect(e.code, 1);
      expect(Directory(p.join(tmp.path, 'cfg/skills/moodle')).existsSync(), isFalse);
    });

    test('Exit-Code 0 von claude.exe zählt nicht, nur der Eintrag danach', () async {
      datei('$desktop/2.1.9/claude.exe');
      final e = await einrichtungEntfernen(
          umgebung: umgebung, skills: const [], werkzeuge: werkzeuge(ausfuehren: (_, _) async => 0));
      expect(e.code, 1);
    });

    test('ohne Eintrag wird claude.exe gar nicht gesucht', () async {
      konfig.writeAsStringSync(jsonEncode({'mcpServers': {}}));
      final e = await einrichtungEntfernen(umgebung: umgebung, skills: ['nicht-da'], werkzeuge: werkzeuge());
      expect(aufrufe, isEmpty);
      expect(e.code, 0);
    });

    test('Codex und LM Studio: Einträge und Skills weg, Fremdes bleibt', () async {
      konfig.writeAsStringSync(jsonEncode({'mcpServers': {}}));
      final toml = datei('heim/.codex/config.toml', 'model = "gpt-5"\n');
      await CodexCli(umgebung).eintragen(47811, 'abc');
      datei('heim/.codex/skills/moodle/SKILL.md');
      final liste = datei('heim/.lmstudio/apps/bionic/.internal/ng-mcp.json', jsonEncode({
        'servers': [
          {'name': 'blender', 'connection': {'type': 'stdio', 'command': 'cmd'}},
          {
            'name': 'moodle',
            'connection': {
              'type': 'stdio',
              'command': datei('app/moocp-bruecke.exe').path,
              'args': [],
            },
          },
        ],
      }));
      datei('heim/.lmstudio/skills/moodle/SKILL.md');
      datei('heim/.lmstudio/skills/fremd/SKILL.md');

      final e = await einrichtungEntfernen(umgebung: umgebung, skills: ['moodle'], werkzeuge: werkzeuge());
      expect(e.code, 0);
      expect(toml.readAsStringSync(), 'model = "gpt-5"\n');
      expect(((jsonDecode(liste.readAsStringSync()) as Map)['servers'] as List).map((s) => (s as Map)['name']),
          ['blender']);
      expect(Directory(p.join(tmp.path, 'heim/.codex/skills/moodle')).existsSync(), isFalse);
      expect(Directory(p.join(tmp.path, 'heim/.lmstudio/skills/moodle')).existsSync(), isFalse);
      expect(File(p.join(tmp.path, 'heim/.lmstudio/skills/fremd/SKILL.md')).existsSync(), isTrue);
    });
  });
}
