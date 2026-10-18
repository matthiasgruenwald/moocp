// Wo die Einstellungen liegen, ohne Flutter: Das braucht außer der App auch
// die Brücke (mcp/bruecke.dart), ein eigenes Programm ohne Flutter.
// einstellungen.dart selbst hängt über freigabe.dart an Flutter.
import 'dart:io';

import 'package:path/path.dart' as p;

const standardPort = 47811;

/// `%APPDATA%\moocp` unter Windows, `~/Library/Application Support/moocp` auf
/// dem Mac: Einstellungen und Protokoll.
String get einstellungenOrdner => einstellungenOrdnerFuer(
  Platform.environment,
  macos: Platform.isMacOS,
);

/// Der Ordner für eine gegebene Umgebung; getrennt, damit sich der Pfad auch
/// ohne den Rechner prüfen lässt, auf dem er gebraucht wird.
String einstellungenOrdnerFuer(
  Map<String, String> umgebung, {
  required bool macos,
}) {
  if (macos) {
    final heim = umgebung['HOME'] ?? Directory.systemTemp.path;
    return p.join(heim, 'Library', 'Application Support', 'moocp');
  }
  return p.join(umgebung['APPDATA'] ?? Directory.systemTemp.path, 'moocp');
}

File get einstellungenDatei => File(p.join(einstellungenOrdner, 'einstellungen.json'));

/// Der Ordner für Sicherungen einer Aktivität (E29): außerhalb des Arbeitsordners,
/// der beim Start und Beenden geleert wird. Unter Windows `%APPDATA%\moocp\sicherungen`,
/// auf dem Mac `~/Library/Application Support/moocp/sicherungen`.
String get sicherungenOrdner => sicherungenOrdnerFuer(Platform.environment, macos: Platform.isMacOS);

String sicherungenOrdnerFuer(Map<String, String> umgebung, {required bool macos}) =>
    p.join(einstellungenOrdnerFuer(umgebung, macos: macos), 'sicherungen');
