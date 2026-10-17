// Die macOS-Zweige: Einstellungsordner (auf jedem Rechner prüfbar), die
// Einzelstart-Sperre über den Unix-Socket (Mac und Linux) und die Suche nach
// den KI-Werkzeugen unter macOS (nur auf dem Mac, dort gilt POSIX-Pfadrecht).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/einrichtung.dart';
import 'package:moocp/einstellungen_ort.dart';
import 'package:moocp/einzelstart.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Einstellungsordner', () {
    test('auf dem Mac unter Application Support, mit HOME', () {
      expect(
        einstellungenOrdnerFuer({'HOME': '/Users/x'}, macos: true),
        p.join('/Users/x', 'Library', 'Application Support', 'moocp'),
      );
    });

    test('unter Windows unter APPDATA', () {
      expect(
        einstellungenOrdnerFuer({'APPDATA': r'C:\Users\x\AppData\Roaming'}, macos: false),
        p.join(r'C:\Users\x\AppData\Roaming', 'moocp'),
      );
    });
  });

  group('Einzelstart', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('einzel'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('zweiter Start bekommt keine Sperre, die erste meldet das Fokus-Signal', () async {
      final erster = await Einzelstart.sichern(tmp.path, macos: true);
      expect(erster, isNotNull);
      final fokus = expectLater(erster!.fokus.first, completes);

      final zweiter = await Einzelstart.sichern(tmp.path, macos: true);
      expect(zweiter, isNull);
      await fokus;
      await erster.schliessen();
    });

    test('eine liegengebliebene Socket-Datei ohne Zuhörer wird ersetzt', () async {
      // Was ein Absturz hinterlässt: der Pfad ist belegt, aber niemand hört zu.
      File(p.join(tmp.path, 'moocp.sock')).writeAsStringSync('tot');
      final e = await Einzelstart.sichern(tmp.path, macos: true);
      expect(e, isNotNull);
      await e!.schliessen();
    });

    test('ohne macOS keine Sperre und kein Ordner', () async {
      final ordner = p.join(tmp.path, 'nicht');
      final e = await Einzelstart.sichern(ordner, macos: false);
      expect(e, isNotNull);
      expect(Directory(ordner).existsSync(), isFalse);
    });
  }, skip: Platform.isWindows ? 'Unix-Socket-Sperre gibt es nur auf dem Mac' : null);

  group('KI-Werkzeuge unter macOS', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('kiwerk'));
    tearDown(() => tmp.deleteSync(recursive: true));

    void programm(String pfad) {
      File(pfad)
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\n');
    }

    test('claude im PATH, Trennung mit Doppelpunkt, ohne .exe', () {
      programm(p.join(tmp.path, 'bin', 'claude'));
      final gefunden = claudeFinden({'HOME': p.join(tmp.path, 'heim'), 'PATH': '/gibtsnicht:${p.join(tmp.path, 'bin')}'});
      expect(gefunden, p.join(tmp.path, 'bin', 'claude'));
    });

    test('claude unter ~/.local/bin', () {
      final heim = p.join(tmp.path, 'heim');
      programm(p.join(heim, '.local', 'bin', 'claude'));
      expect(claudeFinden({'HOME': heim, 'PATH': ''}), p.join(heim, '.local', 'bin', 'claude'));
    });

    test('Claude Code liest die Konfiguration unter HOME', () {
      final heim = p.join(tmp.path, 'heim');
      expect(ClaudeCode({'HOME': heim}).konfiguration.path, p.join(heim, '.claude.json'));
    });

    test('Codex CLI findet codex im PATH ohne Endung', () {
      programm(p.join(tmp.path, 'bin', 'codex'));
      final codex = CodexCli({'HOME': p.join(tmp.path, 'heim'), 'PATH': p.join(tmp.path, 'bin')});
      expect(codex.exe, p.join(tmp.path, 'bin', 'codex'));
      expect(codex.heim.path, p.join(tmp.path, 'heim', '.codex'));
    });

    test('LM Studio wird unter macOS nicht angeboten, auch mit Bionic-Ordner', () {
      final heim = p.join(tmp.path, 'heim');
      Directory(p.join(heim, '.lmstudio', 'apps', 'bionic')).createSync(recursive: true);
      expect(LmStudio({'HOME': heim}, bruecke: p.join(tmp.path, 'x')).gefunden, isFalse);
    });
  }, skip: Platform.isMacOS ? null : 'Suche nach Programmen unter macOS nur auf dem Mac');
}
