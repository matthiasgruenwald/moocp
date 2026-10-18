import 'dart:io';

import 'package:path/path.dart' as p;

import 'plattform.dart';

/// macOS: Browser im Programmbündel in /Applications oder im Benutzerordner;
/// Richtlinien über die verwalteten Einstellungen; Prozesse über `ps` und
/// `kill`.
class MacBrowser implements PlattformBrowser {
  @override
  List<BrowserArt> get arten => BrowserArt.values;

  @override
  Future<String?> programm(BrowserArt art) async {
    final (app, programm) = switch (art) {
      BrowserArt.edge => ('Microsoft Edge', 'Microsoft Edge'),
      BrowserArt.chrome => ('Google Chrome', 'Google Chrome'),
      BrowserArt.chromium => ('Chromium', 'Chromium'),
    };
    final home = Platform.environment['HOME'] ?? '';
    for (final ordner in ['/Applications', p.join(home, 'Applications')]) {
      final pfad = p.join(ordner, '$app.app', 'Contents', 'MacOS', programm);
      if (File(pfad).existsSync()) return pfad;
    }
    return null;
  }

  /// Die Richtlinie kommt als verwaltete Einstellung der Domäne des Browsers
  /// (Profil oder MDM), in /Library/Managed Preferences. Fehlt sie, ist die
  /// Fernsteuerung erlaubt, wie unter Windows ohne Schlüssel.
  @override
  Future<bool> fernsteuerungVerboten(BrowserArt art) async {
    final domaene = switch (art) {
      BrowserArt.edge => 'com.microsoft.Edge',
      BrowserArt.chrome => 'com.google.Chrome',
      BrowserArt.chromium => 'org.chromium.Chromium',
    };
    final benutzer = Platform.environment['USER'];
    final orte = [
      p.join('/Library/Managed Preferences', domaene),
      if (benutzer != null && benutzer.isNotEmpty) p.join('/Library/Managed Preferences', benutzer, domaene),
    ];
    for (final ort in orte) {
      try {
        final r = await Process.run('defaults', ['read', ort, 'RemoteDebuggingAllowed']);
        if (r.exitCode == 0 && '${r.stdout}'.trim() == '0') return true;
      } on ProcessException {
        // Ohne defaults gibt es keine Richtlinie zu lesen.
      }
    }
    return false;
  }

  /// `ps` nennt die Prozesse mit ihrem Aufruf; die mit dem Profil im Aufruf
  /// bekommen ein `kill -9`. Fremde Browserprozesse haben ein anderes Profil
  /// und bleiben unberührt.
  @override
  Future<int> prozesseBeenden(Directory profil, String programm) async {
    try {
      final r = await Process.run('ps', ['-axww', '-o', 'pid=,command=']);
      final pids = <String>[];
      for (final zeile in '${r.stdout}'.split('\n')) {
        final m = RegExp(r'^\s*(\d+)\s(.*)$').firstMatch(zeile);
        if (m == null || !m.group(2)!.contains(profil.path)) continue;
        pids.add(m.group(1)!);
      }
      for (final pid in pids) {
        await Process.run('kill', ['-9', pid]);
      }
      return pids.length;
    } on ProcessException {
      return -1;
    }
  }
}
