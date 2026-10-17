# E26 Zugangsdaten auf dem Mac im Schlüsselbund des Benutzers

Seit 0.9.23 (2026-10-17). Status: gilt. Ergänzt [E7](0007-anmeldedaten.md) für macOS; unter Windows gilt E7 unverändert. Die Kurzfassung steht im Index der [CLAUDE.md](../../CLAUDE.md).

## Entscheidung

Auf dem Mac liegt das Passwort im Schlüsselbund des Benutzers, über `flutter_secure_storage` mit `usesDataProtectionKeychain: false` (`lib/anmeldedaten.dart`). Der Haken und der Benutzername liegen wie unter Windows in `shared_preferences`. Es gelten dieselben Grenzen wie in E7: gespeichert wird nur nach einer erfolgreichen Anmeldung, und das Passwort geht nie über MCP hinaus und nie ins Protokoll (A2).

Gründe nach dem Kommentar in `lib/anmeldedaten.dart`: Die Datenschutz-Schlüsselbundgruppe verlangt eine Team-ID zum Signieren, und ein Entwicklerbau ohne Konto hat keine. Die Entscheidung ist für den Entwicklerbau getroffen; ob sie für eine Veröffentlichung hält, ist nicht geprüft.

## Folgen

- Ein Release-Bau für den Mac braucht eine Prüfung, ob der alte Schlüsselbund dort ebenso gilt. Das steht in [TODO.md](../../TODO.md).

## Verworfen

Das Passwort als Datei im Einstellungsordner: Das wäre Klartext auf dem Datenträger, und die DPAPI-Schutzwirkung gäbe es dort nicht. Die Datenschutz-Schlüsselbundgruppe: Sie braucht eine Team-ID, die der Entwicklerbau nicht hat.
