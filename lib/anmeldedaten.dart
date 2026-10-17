// Gespeicherte Anmeldedaten -- nur, wenn die Lehrkraft den Haken setzt.
//
// Wo was liegt:
//   - Haken und Benutzername: shared_preferences (Klartext-JSON unter
//     %APPDATA%\moocp\moocp\). Kein Geheimnis.
//   - Passwort: flutter_secure_storage, unter Windows mit DPAPI verschlüsselt
//     (flutter_secure_storage.dat im selben Ordner). Entschlüsseln kann nur
//     Ihr Windows-Konto; eine Kopie der Datei, ein Backup oder ein anderes
//     Konto sieht Datensalat.
//
// Grenze: Ein Programm, das unter demselben Windows-Konto läuft, kann das
// Passwort gezielt entschlüsseln -- das gilt für jede Speicherung, die ohne
// Rückfrage auskommt. Das Passwort geht nie über MCP hinaus und nie ins
// Protokoll.
//
// Gespeichert wird nur nach einer ERFOLGREICHEN Anmeldung, damit sich kein
// Tippfehler festsetzt. Nimmt die Lehrkraft den Haken weg, werden
// Benutzername und Passwort sofort entfernt.

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Anmeldedaten {
  static const _merken = 'anmeldung.merken';
  static const _benutzer = 'anmeldung.benutzer';
  static const _passwort = 'moodle.passwort';

  /// Wo das Passwort verschlüsselt liegt, für Protokoll und Hinweise. Auf dem
  /// Mac ist es der Schlüsselbund, unter Windows DPAPI.
  static String get schutz => Platform.isMacOS
      ? 'verschlüsselt im macOS-Schlüsselbund'
      : 'verschlüsselt mit Windows-DPAPI';

  /// Wer das Passwort wieder lesen kann.
  static String get lesbarFuer => Platform.isMacOS
      ? 'nur mit Ihrem Benutzerkonto lesbar'
      : 'nur mit Ihrem Windows-Konto lesbar';

  // Ohne Rückgriff auf die Windows-Anmeldeinformationsverwaltung älterer
  // Paketversionen: nur die DPAPI-verschlüsselte Datei. Auf dem Mac der alte
  // Schlüsselbund statt der Datenschutz-Schlüsselbundgruppe: Die verlangt eine
  // Team-ID zum Signieren, die ein Entwicklerbau ohne Konto nicht hat.
  static const _sicher = FlutterSecureStorage(
    wOptions: WindowsOptions(useBackwardCompatibility: false),
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  final bool merken;
  final String? benutzer;
  final String? passwort;

  const Anmeldedaten(this.merken, this.benutzer, this.passwort);

  static Future<Anmeldedaten> laden() async {
    final prefs = await SharedPreferences.getInstance();
    final merken = prefs.getBool(_merken) ?? false;
    if (!merken) return const Anmeldedaten(false, null, null);
    String? passwort;
    try {
      passwort = await _sicher.read(key: _passwort);
    } catch (_) {
      // Nicht zu entschlüsseln (etwa anderes Windows-Konto): dann eben eintippen.
    }
    return Anmeldedaten(true, prefs.getString(_benutzer), passwort);
  }

  /// Merkt sich den Haken.
  static Future<void> merkenSetzen(bool an) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_merken, an);
    if (!an) await loeschen();
  }

  /// Nach erfolgreicher Anmeldung, nur mit gesetztem Haken.
  static Future<void> speichern(String benutzer, String passwort) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_merken, true);
    await prefs.setString(_benutzer, benutzer);
    await _sicher.write(key: _passwort, value: passwort);
  }

  /// Entfernt Benutzername und Passwort ausdrücklich -- shared_preferences
  /// kennt kein „auf null setzen", remove ist genau das.
  static Future<void> loeschen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_merken, false);
    await prefs.remove(_benutzer);
    await _sicher.delete(key: _passwort);
  }
}
