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

import 'package:flutter/foundation.dart';
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

  /// Nur Entwicklerbau: Zugangsdaten aus einer Datei im Format `SCHLUESSEL=WERT`,
  /// deren Ort die Umgebungsvariable `MOOCP_TESTZUGANG` nennt. Die Datei liegt
  /// außerhalb des Repos (E2E-Zugang der Spike-Instanz, `TEACHER_USERNAME` und
  /// `TEACHER_PASSWORD`). Dann kein Schlüsselbund und keine Abfrage des
  /// Mac-Passworts; im Release-Bau gibt es das nicht.
  static String? get _testdatei {
    if (!kDebugMode) return null;
    final v = Platform.environment['MOOCP_TESTZUGANG'];
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Ob der Testzugang aus einer Datei gilt; dann liegt nichts im Schlüsselbund.
  static bool get testzugangAktiv => _testdatei != null;

  static Future<(String, String)?> _testzugang() async {
    final pfad = _testdatei;
    if (pfad == null) return null;
    // Nur die Namen stehen in Fehlermeldungen, nie die Werte.
    final werte = <String, String>{};
    for (final zeile in await File(pfad).readAsLines()) {
      final t = zeile.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final gleich = t.indexOf('=');
      if (gleich < 0) continue;
      final wert = t.substring(gleich + 1).trim();
      werte[t.substring(0, gleich).trim()] = wert.replaceAll(RegExp(r'''^["']|["']$'''), '');
    }
    final benutzer = werte['TEACHER_USERNAME'];
    final passwort = werte['TEACHER_PASSWORD'];
    if (benutzer == null || passwort == null) {
      throw StateError('Testzugang: TEACHER_USERNAME oder TEACHER_PASSWORD fehlt in $pfad');
    }
    return (benutzer, passwort);
  }

  static Future<Anmeldedaten> laden() async {
    final prefs = await SharedPreferences.getInstance();
    final merken = prefs.getBool(_merken) ?? false;
    if (!merken) return const Anmeldedaten(false, null, null);
    final test = await _testzugang();
    if (test != null) return Anmeldedaten(true, test.$1, test.$2);
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
    if (_testdatei == null) await _sicher.write(key: _passwort, value: passwort);
  }

  /// Entfernt Benutzername und Passwort ausdrücklich -- shared_preferences
  /// kennt kein „auf null setzen", remove ist genau das.
  static Future<void> loeschen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_merken, false);
    await prefs.remove(_benutzer);
    if (_testdatei == null) await _sicher.delete(key: _passwort);
  }
}
