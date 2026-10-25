// Die Registry der Moodle-Instanzen (E31): je Profil (profil.dart) genau
// ein MoodleZugang mit eigenen Cookies und eigenem sesskey. Zwei Profile teilen
// sich nichts an Sitzung; ein Ablauf der einen Sitzung berührt die andere nicht,
// weil jeder Zugang seine Anmeldung selbst hält (moodle_zugang.dart).
//
// Die Sperrliste und die Positivliste gelten je Zugang, also je Adresse des
// Profils; dass die Registry sie nicht umgeht, folgt daraus, dass jede Anfrage
// nur über den Zugang des Profils läuft.

import '../profil.dart';
import '../protokoll.dart';
import 'moodle_zugang.dart';

class MoodleInstanzen {
  MoodleInstanzen(this.protokoll);

  final Protokoll protokoll;
  final Map<String, MoodleZugang> _zugaenge = {};

  /// Der Zugang zu einem Profil, bei Bedarf angelegt; derselbe Zugang kommt
  /// bei jeder Anfrage nach derselben Kennung zurück. Sein Protokoll nennt
  /// den Profilnamen (Protokoll.fuer).
  MoodleZugang zugang(Profil profil) => _zugaenge.putIfAbsent(
      profil.kennung, () => MoodleZugang(protokoll.fuer(profil.name)));

  /// Ob es für die Kennung schon einen Zugang gibt; ohne Anlegen.
  bool hat(String kennung) => _zugaenge.containsKey(kennung);

  /// Meldet das Profil ab und vergisst den Zugang, etwa nach dem Entfernen
  /// des Profils. Die übrigen Zugänge bleiben angemeldet.
  void entfernen(String kennung) {
    _zugaenge.remove(kennung)?.abmelden(stillschweigend: true);
  }
}
