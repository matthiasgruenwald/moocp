// Entwicklerversion: startet die App mit flutter run und lädt Änderungen am
// Code im laufenden Betrieb nach (Hot Reload). Die Anmeldung bei Moodle
// bleibt dabei bestehen -- die Lehrkraft meldet sich einmal an, nicht nach
// jeder Änderung.
//
//   dart run tool/dev.dart <steuerdatei> <logdatei>
//
// Gesteuert wird über die Steuerdatei: Inhalt „r" = Änderungen nachladen,
// „R" = App neu starten (Anmeldung weg), „q" = beenden. Die Ausgabe der App
// (logging, siehe lib/log.dart) und von flutter run steht in der Logdatei.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('Aufruf: dart run tool/dev.dart <steuerdatei> <logdatei>');
    exit(2);
  }
  final steuer = File(args[0]);
  if (steuer.existsSync()) steuer.deleteSync();
  final log = File(args[1]).openWrite(mode: FileMode.append);
  void schreib(String s) =>
      log.writeln('${DateTime.now().toIso8601String().substring(11, 19)} $s');

  final geraet = Platform.isMacOS ? 'macos' : 'windows';
  final p = await Process.start('flutter', ['run', '-d', geraet, '--machine'], runInShell: true);
  String? appId;
  var id = 0;

  p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((z) {
    if (!z.startsWith('[{')) return schreib(z);
    try {
      for (final e in jsonDecode(z) as List) {
        final m = e as Map;
        final ereignis = m['event'];
        final params = m['params'] as Map?;
        if (ereignis == 'app.start' || ereignis == 'app.started') {
          appId ??= params?['appId'] as String?;
          schreib('$ereignis ($appId)');
        } else if (ereignis == 'app.log') {
          schreib('APP ${params?['log']}');
        } else if (ereignis == 'app.progress') {
          if (params?['message'] != null) schreib('… ${params!['message']}');
        } else if (m.containsKey('id')) {
          schreib('Antwort ${m['id']}: ${jsonEncode(m['result'] ?? m['error'])}');
        } else if (ereignis != 'daemon.log' && ereignis != 'app.webLaunchUrl') {
          schreib(jsonEncode(m));
        }
      }
    } catch (_) {
      schreib(z);
    }
  });
  p.stderr.transform(utf8.decoder).listen((s) => schreib('ERR $s'));
  unawaited(p.exitCode.then((c) async {
    schreib('flutter run beendet ($c)');
    await log.flush();
    exit(0);
  }));

  Timer.periodic(const Duration(milliseconds: 400), (_) {
    if (!steuer.existsSync()) return;
    final befehl = steuer.readAsStringSync().trim();
    steuer.deleteSync();
    final app = appId;
    if (app == null) return schreib('Befehl „$befehl" ignoriert: App läuft noch nicht');
    id++;
    final Map<String, Object> aufruf = befehl == 'q'
        ? {'id': id, 'method': 'app.stop', 'params': {'appId': app}}
        : {
            'id': id,
            'method': 'app.restart',
            'params': {'appId': app, 'fullRestart': befehl == 'R', 'pause': false, 'reason': 'manual'}
          };
    p.stdin.writeln(jsonEncode([aufruf]));
    schreib('Befehl $id: ${aufruf['method']} ${befehl == 'R' ? '(Neustart)' : befehl == 'q' ? '' : '(Hot Reload)'}');
  });
}
