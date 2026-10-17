// Die App läuft auf dem Mac nur einmal je Benutzer, wie unter Windows
// (windows/runner/main.cpp, dort ein benannter Mutex). Eine zweite teilte
// Einstellungen und Arbeitsordner mit der ersten (lib/arbeitsordner.dart).
//
// Die Sperre ist ein Unix-Socket im Einstellungsordner. Ein Socket mit
// bind() gibt es nur einmal; läuft eine App, nimmt sie Verbindungen an. Eine
// zweite meldet sich dort, und die erste holt ihr Fenster nach vorn. Stirbt
// die App (Absturz, kill -9), bleibt die Datei liegen, aber niemand hört mehr
// zu: Der nächste Start merkt das an der abgelehnten Verbindung und macht die
// Datei neu. So gibt es keine Sperrdatei, die nach einem Absturz den Start
// blockiert.
//
// Ein flock(2) hätte dasselbe geleistet, braucht aber einen Dateideskriptor,
// den Dart nicht herausgibt, und damit den FFI-Aufruf von open(2) mit seinem
// variadischen mode-Argument, das auf dem Mac anders übergeben wird.
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

const _socketName = 'moocp.sock';

class Einzelstart {
  Einzelstart._(this._server, this.fokus);

  final ServerSocket? _server;

  /// Eine zweite Anmeldung hat die App aufgerufen, das Fenster soll nach vorn.
  /// Der Strom puffert, bis jemand zuhört: Die Anfrage kann vor dem ersten
  /// Bild kommen.
  final Stream<void> fokus;

  /// Liefert null, wenn schon eine moocp läuft; deren Fenster ist dann nach
  /// vorn geholt worden, und diese Anmeldung soll enden. Sonst die Sperre, die
  /// bis zum Ende des Prozesses gilt. Außerhalb des Mac gibt es nichts zu
  /// sperren (unter Windows prüft main.cpp): Dann immer die Sperre ohne Socket.
  static Future<Einzelstart?> sichern(
    String ordner, {
    bool? macos,
  }) async {
    if (!(macos ?? Platform.isMacOS)) return Einzelstart._(null, const Stream.empty());
    await Directory(ordner).create(recursive: true);
    final pfad = p.join(ordner, _socketName);
    final kanal = StreamController<void>();
    for (var versuch = 0; versuch < 3; versuch++) {
      try {
        final server = await ServerSocket.bind(
          InternetAddress(pfad, type: InternetAddressType.unix),
          0,
        );
        server.listen((verbindung) {
          verbindung.destroy();
          kanal.add(null);
        });
        return Einzelstart._(server, kanal.stream);
      } on SocketException {
        if (await _laeuftSchon(pfad)) return null;
        // Von einem früheren Lauf übrig: bind() schlägt fehl, aber niemand
        // antwortet. Weg damit, dann noch einmal binden.
        try {
          File(pfad).deleteSync();
        } on FileSystemException {
          // Fehlt schon: der nächste Versuch sieht es.
        }
      }
    }
    // Der Socket ließ sich nicht anlegen: Die App startet dann ohne Sperre,
    // wie vor dieser Änderung, statt gar nicht.
    return Einzelstart._(null, const Stream.empty());
  }

  /// Ob eine laufende App den Socket annimmt. Die Verbindung selbst ist die
  /// Anfrage; mehr ist nicht zu sagen.
  static Future<bool> _laeuftSchon(String pfad) async {
    try {
      final s = await Socket.connect(
        InternetAddress(pfad, type: InternetAddressType.unix),
        0,
        timeout: const Duration(seconds: 1),
      );
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Gibt den Socket frei; für die Tests, die in einem Prozess zwei Starts
  /// nachstellen. Die App selbst beendet sich mit dem Prozess.
  Future<void> schliessen() async {
    await _server?.close();
  }
}
