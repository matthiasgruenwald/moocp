import 'dart:io';

import 'anmeldedaten.dart';
import 'freigabe.dart';
import 'mcp/mcp_dienst.dart';
import 'moodle/moodle_zugang.dart';
import 'profil.dart';
import 'protokoll.dart';
import 'testzugang.dart';

/// Ein Profil zur Laufzeit: Zugang, Freigaben und MCP-Server (E31).
class Instanz {
  const Instanz(this.moodle, this.freigaben, this.dienst);
  final MoodleZugang moodle;
  final Freigaben freigaben;
  final McpDienst dienst;
}

/// Eingaben einer Anmeldung, festgehalten bevor sie asynchron beginnt.
class AnmeldeAuftrag {
  const AnmeldeAuftrag({
    required this.instanz,
    required this.profil,
    required this.adresse,
    required this.benutzer,
    required this.passwort,
    required this.merken,
  });
  final Instanz instanz;
  final Profil profil;
  final String adresse;
  final String benutzer;
  final String passwort;
  final bool merken;
}

/// Gibt gespeicherte Zugangsdaten nur zurück, wenn das Profil nach dem Laden
/// noch ausgewählt ist.
Future<Anmeldedaten?> gespeicherteAnmeldedatenVerwenden({
  required Future<Anmeldedaten> Function() laden,
  required bool Function() zielIstAktiv,
  required void Function(Anmeldedaten) anwenden,
}) async {
  final daten = await laden();
  if (!zielIstAktiv()) return null;
  anwenden(daten);
  return daten;
}

/// Meldet gebundene Debug-Testprofile unabhängig von der sichtbaren Auswahl an.
Future<void> testprofileStarten(
  List<Instanz> instanzen,
  Protokoll protokoll,
) async {
  for (final instanz in instanzen) {
    final profil = instanz.dienst.profil;
    if (Testzugang.fuer(profil) == null) continue;
    try {
      final daten = await Anmeldedaten.laden(
        kennung: profil.kennung,
        adresse: profil.adresse,
      );
      if (daten.benutzer == null || daten.passwort == null) {
        throw StateError('Gebundener Testzugang fehlt');
      }
      await instanz.moodle.anmelden(
        profil.adresse,
        daten.benutzer!,
        daten.passwort!,
      );
      await instanz.dienst.starten();
      protokoll.eintrag(
        Art.anmeldung,
        'Testprofil „${profil.name}“: Anmeldung und MCP-Server bereit [${profil.kennung}]',
      );
    } catch (e) {
      // Feste Kategorien nennen Voraussetzungen, ohne Dateiinhalte oder Eingaben zu übernehmen.
      final grund = switch (e) {
        FileSystemException() => 'Zugangsdatei fehlt oder ist nicht lesbar; Pfad und Dateirechte prüfen',
        StateError() => 'Zugangsdatei unvollständig; TEACHER_USERNAME und TEACHER_PASSWORD müssen gesetzt sein',
        MoodleNichtErreichbar() => 'Moodle nicht erreichbar; Instanzadresse und Netzwerkzugang prüfen',
        MoodleFehler() => 'Moodle-Anmeldung abgelehnt; Dateizugang und Anmeldemöglichkeit prüfen',
        SocketException() => 'MCP-Port nicht verfügbar; Portbelegung prüfen',
        _ => 'Startvoraussetzung fehlgeschlagen (${e.runtimeType})',
      };
      protokoll.eintrag(Art.fehler, 'Testprofil „${profil.name}“ nicht bereit: $grund');
    }
  }
}
