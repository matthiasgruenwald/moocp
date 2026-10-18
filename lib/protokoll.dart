// Das Protokoll der App: was die App tut, sichtbar für die Lehrkraft.
//
// Hinein kommt, welches Werkzeug aufgerufen wurde, welche Moodle-Adresse
// angefragt wurde und was bei der Anmeldung passiert ist. Nicht hinein
// kommen Passwörter, Formularwerte, Cookies oder Inhalte.
//
// Jeder Eintrag geht zusätzlich in eine Datei (%APPDATA%\moocp\
// protokoll.log), damit sich ein Vorfall auch nach einem Neustart der App
// nachvollziehen lässt. Über 1 MB wird die Datei einmal umbenannt (.1).
// Und an den Logger „protokoll" (log.dart), also auf die Konsole.

import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

enum Art { werkzeug, moodle, schreiben, anmeldung, gesperrt, fehler, info }

class Eintrag {
  Eintrag(this.zeit, this.art, this.text);
  final DateTime zeit;
  final Art art;
  final String text;
}

class Protokoll extends ChangeNotifier {
  Protokoll({this.datei, DateTime Function()? uhr}) : _uhr = uhr ?? DateTime.now;

  /// Liefert die Zeit eines Eintrags; austauschbar, damit Bilder und Tests
  /// feste Uhrzeiten zeigen.
  final DateTime Function() _uhr;

  static final Logger _log = Logger('protokoll');

  static const int dateiHoechstens = 1024 * 1024;

  // Ohne Obergrenze: Fiele vorn der älteste heraus, rückte die angehaltene
  // Ansicht (ProtokollAnsicht) mit jedem neuen Eintrag um eine Zeile weiter.
  // Ein Eintrag sind ein paar hundert Byte; zu viel wird es erst nach
  // Zehntausenden, und dafür gibt es „Leeren".
  final List<Eintrag> _eintraege = [];

  /// Protokolldatei; null in Tests.
  final File? datei;

  /// Älteste zuerst, der neueste Eintrag ist der letzte. Keine Kopie, die
  /// Ansicht liest bei jedem Eintrag hier.
  List<Eintrag> get eintraege => UnmodifiableListView(_eintraege);

  void eintrag(Art art, String text) {
    final e = Eintrag(_uhr(), art, text);
    _eintraege.add(e);
    _schreiben(e);
    _log.log(
        switch (art) {
          Art.fehler => Level.SEVERE,
          Art.gesperrt => Level.WARNING,
          _ => Level.INFO,
        },
        '${art.name}: $text');
    notifyListeners();
  }

  void _schreiben(Eintrag e) {
    final d = datei;
    if (d == null) return;
    try {
      if (d.existsSync() && d.lengthSync() > dateiHoechstens) {
        d.renameSync('${d.path}.1');
      }
      d.writeAsStringSync('${e.zeit.toIso8601String()}  ${e.art.name.padRight(9)}  ${e.text}\n',
          mode: FileMode.append, flush: true);
    } catch (_) {
      // Das Protokoll in der App bleibt; die Datei ist Zugabe.
    }
  }

  void leeren() {
    _eintraege.clear();
    notifyListeners();
  }

  /// Eine Sicht auf dieses Protokoll für ein Instanzprofil (Issue #4): Jeder
  /// Eintrag bekommt den Profilnamen voran, damit man ihn Moodle zuordnen kann.
  /// Die Einträge landen im selben Protokoll und in derselben Datei.
  Protokoll fuer(String profil) => _ProfilProtokoll(this, profil);
}

/// Die Sicht aus [Protokoll.fuer]. Sie hat keinen eigenen Speicher; Zuhörer
/// hängen am Protokoll selbst.
class _ProfilProtokoll extends Protokoll {
  _ProfilProtokoll(this._wurzel, this._profil);

  final Protokoll _wurzel;
  final String _profil;

  @override
  void eintrag(Art art, String text) => _wurzel.eintrag(art, '[$_profil] $text');

  @override
  List<Eintrag> get eintraege => _wurzel.eintraege;

  @override
  void leeren() => _wurzel.leeren();
}
