// moocp -- lokale App, über die ein KI-Werkzeug (Claude Code, Codex CLI,
// LM Studio) mit Moodle-Kursen arbeitet: ohne
// Längengrenze, mit Sperr- und Positivliste im Code und einem Protokoll, das
// die Lehrkraft sieht.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'anmeldedaten.dart';
import 'arbeitsordner.dart';
import 'einrichtung.dart';
import 'einrichtung_dialog.dart';
import 'einstellungen.dart';
import 'einstellungen_dialog.dart';
import 'einstellungen_ort.dart';
import 'einzelstart.dart';
import 'freigabe.dart';
import 'profile_dialog.dart';
import 'log.dart';
import 'mcp/mcp_dienst.dart';
import 'moodle/instanzen.dart';
import 'moodle/moodle_zugang.dart';
import 'moodle/zeilenvergleich.dart';
import 'profil.dart';
import 'protokoll.dart';
import 'ueber.dart';
import 'update/update.dart';
import 'update/update_dialoge.dart';

Future<void> main(List<String> argumente) async {
  // Keine Ausgabe auf die Konsole, von niemandem: debugPrint schweigt -- auch
  // in Paketen, deren Fehlertexte Inhalte enthalten können (etwa der sichere
  // Speicher beim Entschlüsseln). Fehler gehen nur mit ihrem TYP ins
  // Protokoll, nie mit ihrem Text. So gerät das Passwort in keine Ausgabe.
  debugPrint = (String? message, {int? wrapWidth}) {};
  if (argumente.contains(claudeEntfernenSchalter)) {
    exit(await _claudeEntfernen());
  }
  if (argumente.contains(werkzeuglisteSchalter)) exit(await _werkzeugliste());
  if (argumente.contains(versionSchalter)) exit(await _version());
  lizenzAnmelden();
  // Die fertige Windows-App hat keine Konsole; print ginge dort ins Leere und
  // Windows meldet „Das Handle ist ungültig". Ausgabe also nur mit Konsole
  // (flutter run). Das Protokoll der App gibt es in beiden Fällen.
  if (!kReleaseMode) loggingEinrichten(stufe: Level.ALL);
  mcpLogsUmleiten();
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  // Vor allem, was Einstellungen und Arbeitsordner anfasst: Eine zweite App
  // holt hier nur die laufende nach vorn (einzelstart.dart). Unter Windows
  // hat windows/runner/main.cpp das schon geprüft und gibt immer eine Sperre
  // zurück.
  final einzel = await Einzelstart.sichern(einstellungenOrdner);
  if (einzel == null) exit(0);
  final einstellungen = await Einstellungen.laden();
  final protokoll = Protokoll(
    datei: File(p.join(einstellungenOrdner, 'protokoll.log')),
  );
  FlutterError.onError = (d) => protokoll.eintrag(
    Art.fehler,
    'Fehler in der Oberfläche: ${fehlerBeschreibung(d.exception, d.stack)}',
  );
  WidgetsBinding.instance.platformDispatcher.onError = (e, st) {
    protokoll.eintrag(
      Art.fehler,
      'Unerwarteter Fehler: ${fehlerBeschreibung(e, st)}',
    );
    return true;
  };
  protokoll.eintrag(Art.info, 'App gestartet');
  final (arbeitsordner, geblieben) = Arbeitsordner.einrichten();
  protokoll.eintrag(
    Art.info,
    geblieben == 0
        ? 'Arbeitsordner geleert: ${arbeitsordner.pfad}'
        : 'Arbeitsordner: ${arbeitsordner.pfad} -- $geblieben Einträge in Benutzung, nicht gelöscht',
  );
  // Schließen läuft über _beenden, damit der Arbeitsordner geleert wird.
  await windowManager.setPreventClose(true);
  // Je Instanzprofil ein Zugang, eine Freigabe und ein MCP-Server mit eigenem
  // Port und Servernamen (E31). Das erste Profil ist das Hauptprofil, dessen
  // Anmeldung die Oberfläche zeigt.
  final profile = einstellungen.profile.isEmpty
      ? [Profil.migriert('')]
      : einstellungen.profile;
  final register = MoodleInstanzen(protokoll);
  final instanzen = [
    for (final pr in profile)
      _instanzFuer(
        pr,
        einstellungen,
        register,
        protokoll,
        arbeitsordner,
        mehrere: profile.length > 1,
      ),
  ];
  Instanz instanzErstellen(Profil pr) => _instanzFuer(
    pr,
    einstellungen,
    register,
    protokoll,
    arbeitsordner,
    mehrere: true,
  );
  // Reste früherer Updates im Temp-Verzeichnis; der Installer, der die App
  // gerade neu gestartet hat, läuft noch und bleibt bis zum nächsten Start.
  resteWegraeumen();
  // Gestartet wird der MCP-Server erst, wenn die App eingerichtet und
  // angemeldet ist (_HauptseiteState._mcpStarten).
  final haupt = instanzen.first;
  runApp(
    MoocpApp(
      einstellungen,
      protokoll,
      haupt.moodle,
      haupt.dienst,
      haupt.freigaben,
      arbeitsordner,
      weitere: instanzen.sublist(1),
      instanzErstellen: instanzErstellen,
      updatefaehig: updateMoeglich(argumente, Platform.environment),
      fokus: einzel.fokus,
    ),
  );
}

/// Ein Instanzprofil mit allem, was daran hängt: Zugang, Freigaben und
/// MCP-Server. Mit mehreren Profilen bekommt jedes seinen Unterordner im
/// Arbeitsordner (nach der Kennung), damit Dateien nicht zusammenfallen; bei
/// einem Profil bleibt der Ordner wie bisher.
Instanz _instanzFuer(
  Profil pr,
  Einstellungen einstellungen,
  MoodleInstanzen register,
  Protokoll protokoll,
  Arbeitsordner arbeitsordner, {
  required bool mehrere,
}) {
  final ansicht = protokoll.fuer(pr.name);
  final zugang = register.zugang(pr);
  final ordner = mehrere
      ? (Directory(
          p.join(arbeitsordner.pfad, pr.kennung),
        )..createSync(recursive: true)).path
      : arbeitsordner.pfad;
  final freigaben = Freigaben(
    ansicht,
    stufe: pr.bestaetigungen,
    testmodus: Anmeldedaten.testzugangAktivFuer(pr),
  );
  return Instanz(
    zugang,
    freigaben,
    McpDienst(einstellungen, zugang, ansicht, freigaben, ordner, profil: pr),
  );
}

/// Ein Profil zur Laufzeit: Zugang, Freigaben und MCP-Server (E31).
class Instanz {
  const Instanz(this.moodle, this.freigaben, this.dienst);
  final MoodleZugang moodle;
  final Freigaben freigaben;
  final McpDienst dienst;
}

/// Eingaben einer Anmeldung, festgehalten bevor sie asynchron beginnt.
class AnmeldeAuftrag {
  const AnmeldeAuftrag({required this.instanz, required this.profil, required this.adresse,
    required this.benutzer, required this.passwort, required this.merken});
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

/// Aufruf durch die Deinstallation (installer/moocp.nsi): die
/// Einrichtung in den KI-Werkzeugen entfernen und mit dem Code aus [Entfernt]
/// enden. Ohne Fenster: Es erscheint erst mit dem ersten Bild
/// (windows/runner/flutter_window.cpp), und ohne runApp gibt es keins. Kein
/// MCP-Server, kein Protokoll -- die Deinstallation löscht dessen Ordner
/// ohnehin.
Future<int> _claudeEntfernen() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final skills = [
      for (final a in manifest.listAssets().where(
        (a) => a.startsWith(skillAssets) && a.endsWith('.skill'),
      ))
        p.basenameWithoutExtension(a),
    ];
    return (await einrichtungEntfernen(
      umgebung: Platform.environment,
      skills: skills,
    )).code;
  } catch (_) {
    return 3; // unbekannt, was geblieben ist: beides melden
  }
}

/// `moocp.exe --werkzeugliste`, für die Brücke (mcp/bruecke.dart), wenn die
/// App nicht angemeldet ist oder nicht läuft: die Werkzeugliste als eine
/// Zeile JSON nach stdout, dann enden. Ohne Fenster (wie _claudeEntfernen),
/// und ohne Einstellungen, Protokoll oder Arbeitsordner anzufassen -- die
/// Beschreibungen der Werkzeuge hängen an keinem davon, und neben einer
/// laufenden App verschränkten sich sonst die Zeilen im Protokoll. Eine
/// Ausnahme von E11 wie die Brücke selbst: Auf stdout stehen nur Namen,
/// Beschreibungen und Parameter der Werkzeuge. Meldungen von mcp_dart gehen
/// an den Logger, und dem hört hier niemand zu.
Future<int> _werkzeugliste() async {
  try {
    mcpLogsUmleiten();
    final protokoll = Protokoll();
    final dienst = McpDienst(
      Einstellungen(schluessel: ''),
      MoodleZugang(protokoll),
      protokoll,
      Freigaben(protokoll),
      '',
      profil: Profil.migriert(''),
    );
    stdout.writeln(jsonEncode(await dienst.werkzeugliste()));
    await stdout.flush();
    return 0;
  } catch (_) {
    return 1;
  }
}

/// `moocp.exe --version`: die Version wie im Dialog „Über" nach stdout, dann
/// enden. moocp.exe ist ein Windows-Programm ohne Konsole; lesbar ist die
/// Antwort über ein Rohr, etwa `moocp.exe --version | more`.
Future<int> _version() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    stdout.writeln(versionText(await PackageInfo.fromPlatform()));
    await stdout.flush();
    return 0;
  } catch (_) {
    return 1;
  }
}

class MoocpApp extends StatelessWidget {
  const MoocpApp(
    this.einstellungen,
    this.protokoll,
    this.moodle,
    this.dienst,
    this.freigaben,
    this.arbeitsordner, {
    this.weitere = const [],
    this.instanzErstellen,
    this.einrichtungsstand,
    this.updatefaehig = false,
    this.fokus,
    super.key,
  });
  final Einstellungen einstellungen;
  final Protokoll protokoll;
  final MoodleZugang moodle;
  final McpDienst dienst;
  final Freigaben freigaben;
  final Arbeitsordner arbeitsordner;

  /// Die weiteren Profile neben dem Hauptprofil (moodle, dienst, freigaben).
  final List<Instanz> weitere;
  final Instanz Function(Profil profil)? instanzErstellen;

  /// Ob diese App sich selbst aktualisieren kann (update.dart,
  /// updateMoeglich). Nur dann wird geprüft und überhaupt gefragt.
  final bool updatefaehig;

  /// Ersatz für die Prüfung der Einrichtung, nur für die README-Bilder
  /// (tool/bilder_test.dart): Die echte Prüfung sähe auf dem Rechner nach,
  /// und ihr Dialog zeigte den echten Pfad zur claude.exe im Bild.
  final Future<Einrichtungsstand> Function()? einrichtungsstand;

  /// Wenn eine zweite Anmeldung das Fenster verlangt (einzelstart.dart).
  final Stream<void>? fokus;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0851A0),
        useMaterial3: true,
      ),
      // Deutsch auch in den eingebauten Texten: Lizenzseite, Kontextmenü.
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Hauptseite(
        einstellungen,
        protokoll,
        moodle,
        dienst,
        freigaben,
        arbeitsordner,
        weitere: weitere,
        instanzErstellen: instanzErstellen,
        einrichtungsstand: einrichtungsstand,
        updatefaehig: updatefaehig,
        fokus: fokus,
      ),
    );
  }
}

class Hauptseite extends StatefulWidget {
  const Hauptseite(
    this.einstellungen,
    this.protokoll,
    this.moodle,
    this.dienst,
    this.freigaben,
    this.arbeitsordner, {
    this.weitere = const [],
    this.instanzErstellen,
    this.einrichtungsstand,
    this.updatefaehig = false,
    this.fokus,
    super.key,
  });
  final Einstellungen einstellungen;
  final Protokoll protokoll;
  final MoodleZugang moodle;
  final McpDienst dienst;
  final Freigaben freigaben;
  final Arbeitsordner arbeitsordner;
  final List<Instanz> weitere;
  final Instanz Function(Profil profil)? instanzErstellen;
  final Future<Einrichtungsstand> Function()? einrichtungsstand;
  final bool updatefaehig;
  final Stream<void>? fokus;

  @override
  State<Hauptseite> createState() => _HauptseiteState();
}

class _HauptseiteState extends State<Hauptseite> with WindowListener {
  late final List<Instanz> _instanzen = [
    Instanz(widget.moodle, widget.freigaben, widget.dienst),
    ...widget.weitere,
  ];
  int _profilIndex = 0;
  Instanz get _aktiv => _instanzen[_profilIndex];
  Profil _profilFuer(Instanz instanz) {
    for (final profil in widget.einstellungen.profile) {
      if (profil.kennung == instanz.dienst.profil.kennung) return profil;
    }
    return instanz.dienst.profil;
  }

  Profil get _profil => _profilFuer(_aktiv);

  MoodleZugang get _moodle => _aktiv.moodle;
  Freigaben get _freigaben => _aktiv.freigaben;
  McpDienst get _dienst => _aktiv.dienst;

  late final TextEditingController _adresse = TextEditingController(
    text: widget.einstellungen.moodleAdresse,
  );
  final _benutzer = TextEditingController();
  final _passwort = TextEditingController();
  bool _beschaeftigt = false;
  String? _meldung;

  /// Haken „Anmeldedaten speichern" (anmeldedaten.dart).
  bool _merken = false;

  /// Ob „KI-Werkzeuge einrichten" beim Start durch ist; vorher gibt es keine
  /// Anmeldung und keinen MCP-Server (_starten).
  bool _eingerichtet = false;

  /// Ob der MCP-Server schon zu starten versucht wurde. Bis dahin zeigt die
  /// Kopfzeile, dass er auf die Anmeldung wartet, danach, ob er läuft.
  bool _mcpVersucht = false;

  /// Gesetzt, sobald _beenden läuft.
  bool _beendet = false;

  /// Die laufende Version („0.9.4"), für die Update-Prüfung und die
  /// Einstellungen; leer, wenn sie sich nicht lesen lässt.
  String _version = '';

  // Anmeldestatus und Kopfzeile folgen dem Protokoll: Jede Neuanmeldung oder
  // jedes Verwerfen der Zugangsdaten schreibt dort einen Eintrag.
  void _aktualisieren() {
    if (mounted) setState(() {});
  }

  StreamSubscription<void>? _fokusAbo;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    widget.protokoll.addListener(_aktualisieren);
    _fokusAbo = widget.fokus?.listen((_) => _fensterZeigen());
    WidgetsBinding.instance.addPostFrameCallback((_) => _starten());
  }

  /// Eine zweite Anmeldung hat die App gestartet: Das Fenster kommt aus dem
  /// Hintergrund, auch aus der Minimierung. Anders als _nachVorn bleibt es
  /// nicht oben, sondern verhält sich wie jedes andere Fenster.
  Future<void> _fensterZeigen() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {
      // Ohne Fensterzugriff bleibt das Fenster, wie es ist.
    }
  }

  /// Der Start in fester Reihenfolge: Updates, KI-Werkzeuge einrichten,
  /// anmelden, dann der MCP-Server (_mcpStarten). Eine Anmeldung, während der
  /// Dialog „KI-Werkzeuge einrichten" offen ist, wäre umsonst, wenn die
  /// Lehrkraft „Beenden" wählt. Und die KI erreicht die Werkzeuge erst, wenn
  /// die Skills zur App passen (E13) und die Sitzung bei Moodle steht -- dann
  /// findet schon der erste Aufruf alles bereit.
  ///
  /// Die Update-Prüfung steht davor: Ein Update bringt auch neue Skills;
  /// würde die App vorher einrichten, installierte sie die Version, die
  /// gleich ersetzt wird. Und weil der MCP-Server zuletzt startet, hängt zu
  /// diesem Zeitpunkt noch keine Sitzung eines KI-Werkzeugs an der App.
  Future<void> _starten() async {
    // Eine Stufe, die Rückfragen abschaltet, soll nicht unbemerkt weitergelten:
    // Sie steht beim Start im Protokoll und dauerhaft rot in der Titelzeile.
    if (_freigaben.stufe != Bestaetigungen.mittel) {
      widget.protokoll.eintrag(
        _freigaben.stufe == Bestaetigungen.keine ? Art.gesperrt : Art.info,
        'Bestätigungen: ${_freigaben.stufe.text} -- ${_stufeKurz[_freigaben.stufe]!}',
      );
    }
    _version = await _eigeneVersion();
    if (_version.isNotEmpty) {
      await updateStandMelden(widget.einstellungen, _version, widget.protokoll);
      if (!mounted) return;
      if (widget.updatefaehig) {
        final beenden = await updateSchritt(
          context,
          einstellungen: widget.einstellungen,
          protokoll: widget.protokoll,
          eigene: _version,
        );
        if (beenden) {
          await _beenden();
          return;
        }
        if (!mounted) return;
      }
    }
    if (!await _einrichtungPruefen()) return;
    if (!mounted) return;
    setState(() => _eingerichtet = true);
    await _gespeichertAnmelden();
  }

  /// Ohne Version keine Update-Prüfung: Was sich mit nichts vergleichen
  /// lässt, wird nicht angeboten.
  Future<String> _eigeneVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (e) {
      widget.protokoll.eintrag(
        Art.fehler,
        'Version nicht lesbar (${e.runtimeType})',
      );
      return '';
    }
  }

  /// Der Dialog „Einstellungen" über das Zahnrad in der Titelzeile.
  Future<void> _einstellungenZeigen() async {
    final ergebnis = await showDialog<EinstellungenErgebnis>(
      context: context,
      builder: (_) => EinstellungenDialog(
        einstellungen: widget.einstellungen,
        protokoll: widget.protokoll,
        eigene: _version,
        updateMoeglich: widget.updatefaehig,
        sitzungLaeuft: _dienst.laeuft,
        profilname: _profil.name,
        mcpName: _profil.mcpName,
      ),
    );
    if (!mounted) return;
    switch (ergebnis) {
      case EinstellungenErgebnis.beenden:
        await _beenden();
      case EinstellungenErgebnis.einrichten:
        await _einrichtungPruefen(immer: true);
      case EinstellungenErgebnis.fertig:
      case null:
        break;
    }
  }

  /// Gespeichert heißt: gleich anmelden. Wer den Haken setzt, will sich
  /// nicht bei jedem Start erneut anmelden.
  Future<void> _gespeichertAnmelden() async {
    final instanz = _aktiv;
    final profil = _profil;
    bool zielIstAktiv() =>
        mounted && identical(_aktiv, instanz) && identical(_profil, profil);
    final Anmeldedaten d;
    try {
      final geladen = await gespeicherteAnmeldedatenVerwenden(
        laden: () => Anmeldedaten.laden(kennung: profil.kennung, adresse: profil.adresse),
        zielIstAktiv: zielIstAktiv,
        anwenden: (daten) => setState(() {
          _merken = daten.merken;
          if (daten.benutzer != null) _benutzer.text = daten.benutzer!;
          if (daten.passwort != null) _passwort.text = daten.passwort!;
        }),
      );
      if (geladen == null) return;
      d = geladen;
    } catch (e) {
      widget.protokoll.eintrag(
        Art.fehler,
        'Anmeldedaten: Speicher nicht erreichbar (${e.runtimeType})',
      );
      return;
    }
    if (!d.merken || d.benutzer == null || instanz.moodle.angemeldet) return;
    if (d.passwort == null) {
      // Etwa unter einem anderen Windows-Konto: DPAPI entschlüsselt nicht.
      // Ohne Eintrag bliebe die App still abgemeldet.
      widget.protokoll.eintrag(
        Art.anmeldung,
        'Gespeichertes Passwort nicht lesbar -- bitte in der App anmelden',
      );
      return;
    }
    widget.protokoll.eintrag(
      Art.anmeldung,
      'Melde mit gespeicherten Anmeldedaten an',
    );
    await _anmelden();
  }

  /// Startet den MCP-Server, sobald die App eingerichtet und angemeldet ist.
  /// Danach bleibt er an, auch nach „Abmelden": Ein Stopp risse laufenden
  /// Sitzungen der KI-Werkzeuge die Verbindung ab; die Werkzeuge melden dann „Nicht
  /// angemeldet".
  Future<void> _mcpStarten() async {
    if (!_eingerichtet) return;
    // Jedes Profil startet seinen Server, sobald es angemeldet ist (E31).
    for (final i in [..._instanzen]) {
      if (!i.moodle.angemeldet || i.dienst.laeuft) continue;
      try {
        await i.dienst.starten();
      } catch (e) {
        widget.protokoll.eintrag(
          Art.fehler,
          'MCP-Server (${i.dienst.profil.name}) startet nicht auf Port '
          '${i.dienst.profil.port}: $e',
        );
      }
    }
    if (mounted) setState(() => _mcpVersucht = true);
  }

  /// Prüft Verbindung und Skills (einrichtung.dart). Beim Start erscheint der
  /// Dialog nur, wenn etwas nicht passt, über den Knopf in der Titelzeile
  /// immer ([immer]); ohne Einrichtung läuft die App nicht
  /// (einrichtung_dialog.dart). Liefert, ob die App eingerichtet ist.
  Future<bool> _einrichtungPruefen({bool immer = false}) async {
    Einrichtungsstand? stand;
    try {
      stand = await _einrichtungsstand();
    } catch (e, st) {
      widget.protokoll.eintrag(
        Art.fehler,
        'KI-Werkzeuge einrichten: Prüfung fehlgeschlagen: ${fehlerBeschreibung(e, st)}',
      );
    }
    if (!mounted) return false;
    if (stand != null &&
        !stand.python &&
        stand.gewaehlt.contains('lernsituation')) {
      widget.protokoll.eintrag(
        Art.info,
        'Python nicht gefunden: Die Selbstprüfung des Skills lernsituation läuft nicht',
      );
    }
    if (!immer && stand != null && !stand.brauchtEtwas) {
      widget.protokoll.eintrag(
        Art.info,
        'KI-Werkzeuge einrichten: Verbindung und Skills aktuell',
      );
      return true;
    }
    final bereit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EinrichtungDialog(
        stand: stand,
        pruefen: _einrichtungsstand,
        einstellungen: widget.einstellungen,
        protokoll: widget.protokoll,
        port: _dienst.profil.port,
        servername: _dienst.profil.mcpName,
        profilname: _profil.name,
      ),
    );
    if (bereit != true) await _beenden();
    return bereit == true;
  }

  Future<Einrichtungsstand> _einrichtungsstand() async {
    if (widget.einrichtungsstand != null) return widget.einrichtungsstand!();
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final pakete = <SkillPaket>[
      for (final a in manifest.listAssets().where(
        (a) => a.startsWith(skillAssets) && a.endsWith('.skill'),
      ))
        SkillPaket.ausZip(
          p.basenameWithoutExtension(a),
          (await rootBundle.load(a)).buffer.asUint8List(),
        ),
    ];
    return einrichtungPruefen(
      umgebung: Platform.environment,
      port: _dienst.profil.port,
      name: _dienst.profil.mcpName,
      schluessel: widget.einstellungen.schluessel,
      skills: pakete,
      abgewaehlt: widget.einstellungen.werkzeugeAbgewaehlt,
      gewaehlt:
          widget.einstellungen.wahlSkills ??
          gewaehltVorgabe(Platform.environment),
    );
  }

  @override
  void onWindowClose() => unawaited(_beenden());

  /// Der einzige Weg aus der App, über das Fenster wie über den Dialog
  /// „KI-Werkzeuge einrichten": Arbeitsordner leeren, dann schließen. Was sich
  /// nicht löschen lässt, weil es in Benutzung ist, leert der nächste Start.
  ///
  /// Geschlossen wird auf dem Weg, den Windows selbst nimmt (WM_CLOSE, dann
  /// WM_DESTROY): Die Engine baut sich ab, solange die Nachrichtenschleife
  /// noch läuft. windowManager.destroy() beendet dagegen nur die Schleife;
  /// windows/runner/main.cpp ruft dann CoUninitialize, und erst danach baut
  /// sich die Engine ab. Das endet mit einer Zugriffsverletzung in
  /// flutter_windows.dll, und für den Fehlerbericht hält Windows das Fenster
  /// gut fünf Sekunden stehen. Auf dem Weg über WM_CLOSE ist die App nach
  /// einer halben Sekunde zu, ohne Absturz (gemessen).
  Future<void> _beenden() async {
    // close() unten meldet das Schließen noch einmal (onWindowClose).
    if (_beendet) return;
    _beendet = true;
    try {
      final geblieben = widget.arbeitsordner.leeren();
      widget.protokoll.eintrag(
        Art.info,
        geblieben == 0
            ? 'App beendet, Arbeitsordner geleert'
            : 'App beendet, $geblieben Einträge im Arbeitsordner in Benutzung, der nächste Start leert sie',
      );
    } catch (e, st) {
      widget.protokoll.eintrag(
        Art.fehler,
        'Arbeitsordner leeren: ${fehlerBeschreibung(e, st)}',
      );
    } finally {
      await windowManager.setPreventClose(false);
      await windowManager.close();
    }
  }

  /// Die Stufe der Bestätigungen umstellen (Feld in der Titelzeile).
  Future<void> _stufeAendern(Bestaetigungen s) async {
    if (s == _freigaben.stufe) return;
    setState(() {
      _freigaben.stufe = s;
      widget.einstellungen.bestaetigungen = s;
      final index = widget.einstellungen.profile.indexWhere(
        (p) => p.kennung == _profil.kennung,
      );
      if (index >= 0) {
        widget.einstellungen.profile[index] = _profil.mitBestaetigungen(s);
      } else {
        widget.einstellungen.profile = [_profil.mitBestaetigungen(s)];
      }
    });
    widget.protokoll.eintrag(
      s == Bestaetigungen.keine ? Art.gesperrt : Art.info,
      'Bestätigungen: ${s.text} -- ${_stufeKurz[s]!}',
    );
    try {
      await widget.einstellungen.speichern();
    } catch (e) {
      widget.protokoll.eintrag(
        Art.fehler,
        'Einstellungen nicht gespeichert (${e.runtimeType})',
      );
    }
  }

  Future<void> _merkenAendern(bool an) async {
    setState(() => _merken = an);
    try {
      await Anmeldedaten.merkenSetzen(an, kennung: _profil.kennung, adresse: _profil.adresse);
      widget.protokoll.eintrag(
        Art.anmeldung,
        an
            ? 'Anmeldedaten werden bei der nächsten erfolgreichen Anmeldung gespeichert'
            : 'Gespeicherte Anmeldedaten gelöscht',
      );
    } catch (e) {
      widget.protokoll.eintrag(
        Art.fehler,
        'Anmeldedaten: Speicher nicht erreichbar (${e.runtimeType})',
      );
    }
  }

  Future<void> _profilWaehlen(int index) async {
    setState(() {
      _profilIndex = index;
      _adresse.text = _profil.adresse;
      _benutzer.clear();
      _passwort.clear();
      _meldung = null;
      _merken = false;
    });
    final instanz = _aktiv;
    final profil = _profil;
    bool zielIstAktiv() => mounted && index == _profilIndex &&
        identical(_aktiv, instanz) && identical(_profil, profil);
    if (!await _einrichtungPruefen()) return;
    if (!zielIstAktiv()) return;
    final Anmeldedaten d;
    try {
      final geladen = await gespeicherteAnmeldedatenVerwenden(
        laden: () => Anmeldedaten.laden(kennung: profil.kennung, adresse: profil.adresse),
        zielIstAktiv: zielIstAktiv,
        anwenden: (daten) => setState(() {
          _merken = daten.merken;
          _benutzer.text = daten.benutzer ?? '';
          _passwort.text = daten.passwort ?? '';
        }),
      );
      if (geladen == null) return;
      d = geladen;
    } catch (e) {
      if (mounted) {
        widget.protokoll.eintrag(
          Art.fehler,
          'Anmeldedaten: Speicher nicht erreichbar (${e.runtimeType})',
        );
      }
      return;
    }
    if (d.merken &&
        d.benutzer != null &&
        d.passwort != null &&
        !instanz.moodle.angemeldet) {
      await _anmelden();
    }
  }

  Future<void> _profilBearbeiten({bool neu = false}) async {
    if (_beschaeftigt) return;
    final aktuell = neu ? null : _profil;
    var port = standardPort;
    while (_instanzen.any((i) => i.dienst.profil.port == port) ||
        widget.einstellungen.profile.any((p) => p.port == port)) {
      port++;
    }
    final geaendert = await showDialog<Profil>(
      context: context,
      builder: (_) => ProfileDialog(profil: aktuell, port: port),
    );
    if (geaendert == null || !mounted) return;
    final profile = widget.einstellungen.profile.isEmpty
        ? <Profil>[_profil]
        : List<Profil>.of(widget.einstellungen.profile);
    final index = profile.indexWhere((p) => p.kennung == geaendert.kennung);
    var hinzugefuegt = false;
    if (index < 0) {
      var name = geaendert.mcpName;
      var zaehler = 2;
      while (profile.any((p) => p.mcpName == name)) {
        name = '${geaendert.mcpName}-${zaehler++}';
      }
      var naechsterPort = standardPort;
      while (_instanzen.any((i) => i.dienst.profil.port == naechsterPort) ||
          profile.any((p) => p.port == naechsterPort)) {
        naechsterPort++;
      }
      final neuProfil = geaendert.copyWith(mcpName: name, port: naechsterPort);
      profile.add(neuProfil);
      final instanz = widget.instanzErstellen?.call(neuProfil);
      if (instanz == null) return;
      _instanzen.add(instanz);
      _profilIndex = _instanzen.length - 1;
      hinzugefuegt = true;
    } else {
      final laufend = _instanzen.firstWhere((i) => i.dienst.profil.kennung == geaendert.kennung);
      if (laufend.moodle.angemeldet && laufend.dienst.profil.adresse != geaendert.adresse) {
        setState(() => _meldung = 'Die Moodle-Adresse kann während einer Anmeldung nicht geändert werden.');
        return;
      }
      profile[index] = geaendert;
      laufend.dienst.profil = geaendert;
      laufend.freigaben.testmodus = Anmeldedaten.testzugangAktivFuer(geaendert);
    }
    widget.einstellungen.profile = profile;
    try {
      await widget.einstellungen.speichern();
    } catch (e) {
      widget.protokoll.eintrag(
        Art.fehler,
        'Einstellungen nicht gespeichert (${e.runtimeType})',
      );
    }
    setState(() {
      _adresse.text = _profil.adresse;
      _meldung = null;
    });
    if (hinzugefuegt && _eingerichtet) {
      if (await _einrichtungPruefen(immer: true) && mounted) {
        await _profilWaehlen(_profilIndex);
      }
    }
  }

  Future<void> _nachVorn(bool an) async {
    try {
      if (an) {
        await windowManager.show();
        await windowManager.setAlwaysOnTop(true);
        await windowManager.focus();
      } else {
        await windowManager.setAlwaysOnTop(false);
      }
    } catch (_) {
      // Ohne Fensterzugriff bleibt der Dialog trotzdem offen.
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    widget.protokoll.removeListener(_aktualisieren);
    _fokusAbo?.cancel();
    _adresse.dispose();
    _benutzer.dispose();
    _passwort.dispose();
    super.dispose();
  }

  Future<void> _anmelden() async {
    if (_beschaeftigt) return;
    final auftrag = AnmeldeAuftrag(instanz: _aktiv, profil: _profil, adresse: _adresse.text.trim(),
        benutzer: _benutzer.text.trim(), passwort: _passwort.text, merken: _merken);
    final moodle = auftrag.instanz.moodle;
    final dienst = auftrag.instanz.dienst;
    final freigaben = auftrag.instanz.freigaben;
    final profil = auftrag.profil;
    final adresse = auftrag.adresse;
    final benutzer = auftrag.benutzer;
    final passwort = auftrag.passwort;
    final merken = auftrag.merken;
    freigaben.testmodus = Anmeldedaten.testzugangAktivFuer(profil.copyWith(adresse: adresse));
    setState(() {
      _beschaeftigt = true;
      _meldung = null;
    });
    var feldLeeren = true;
    try {
      final profile = widget.einstellungen.profile.isEmpty
          ? <Profil>[profil]
          : List<Profil>.of(widget.einstellungen.profile);
      final index = profile.indexWhere((p) => p.kennung == profil.kennung);
      if (index < 0) {
        profile.add(profil.copyWith(adresse: adresse));
      } else {
        profile[index] = profile[index].copyWith(adresse: adresse);
      }
      widget.einstellungen.profile = profile;
      await widget.einstellungen.speichern();
      dienst.profil = profil.copyWith(adresse: adresse);
      await moodle.anmelden(adresse, benutzer, passwort);
      _meldung = 'Angemeldet.';
      if (merken) {
        try {
          await Anmeldedaten.speichern(
            benutzer,
            passwort,
            kennung: profil.kennung,
            adresse: adresse,
          );
          widget.protokoll.eintrag(
            Art.anmeldung,
            Anmeldedaten.testzugangAktivFuer(profil.copyWith(adresse: adresse))
                // Testzugang aus einer Datei: das Passwort liegt nirgends
                // gespeichert, der Eintrag soll nicht den Schlüsselbund nennen.
                ? 'Anmeldedaten gespeichert (Testzugang aus Datei, nicht im Schlüsselbund)'
                : 'Anmeldedaten gespeichert (Passwort ${Anmeldedaten.schutz})',
          );
        } catch (e) {
          _meldung =
              'Angemeldet. Die Anmeldedaten konnten nicht gespeichert werden '
              '(${e.runtimeType}).';
        }
      }
    } on MoodleNichtErreichbar catch (e) {
      // Das Passwort ist nicht bei Moodle angekommen; es bleibt im Feld, und
      // „Anmelden" versucht es erneut. Sonst wäre nach einer gescheiterten
      // automatischen Anmeldung das gespeicherte Passwort neu zu tippen.
      _meldung = '${e.meldung} „Anmelden" versucht es erneut.';
      feldLeeren = false;
    } on MoodleFehler catch (e) {
      _meldung = e.meldung;
    } catch (e) {
      // Nur der Typ: Ein Fehlertext könnte Eingaben enthalten.
      _meldung = 'Anmeldung fehlgeschlagen (${e.runtimeType}).';
    } finally {
      // Sonst bleibt das Passwort nicht im Eingabefeld stehen; die App hält es
      // nur intern im Arbeitsspeicher, für die automatische Neuanmeldung.
      if (feldLeeren) _passwort.clear();
      if (mounted) setState(() => _beschaeftigt = false);
    }
    await _mcpStarten();
  }

  void _abmelden() {
    _moodle.abmelden();
    setState(() => _meldung = 'Abgemeldet.');
  }

  @override
  Widget build(BuildContext context) {
    // Je Profil ein Freigabe-Dialog: Anfragen eines weiteren Profils erscheinen
    // sonst bei niemandem und liefen nur bis zur Frist.
    return Stack(
      children: [
        for (final i in _instanzen)
          FreigabeDialoge(
            key: ValueKey(i.dienst.profil.kennung),
            freigaben: i.freigaben,
            profilname: _profilFuer(i).name,
            mcpName: _profilFuer(i).mcpName,
            nachVorn: _nachVorn,
            child: const SizedBox.shrink(),
          ),
        _seite(context),
      ],
    );
  }

  Widget _seite(BuildContext context) {
    final angemeldet = _moodle.angemeldet;
    final klein = Theme.of(context).textTheme.bodySmall;
    return Scaffold(
      appBar: AppBar(
        title: Text('$appName — ${_profil.name} (${_profil.mcpName})'),
        actions: [
          BestaetigungenFeld(stufe: _freigaben.stufe, aendern: _stufeAendern),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Was die Stufen bedeuten',
            onPressed: () => bestaetigungenHilfe(
              context,
              profilname: _profil.name,
              mcpName: _profil.mcpName,
            ),
          ),
          // Die beiden Anzeigen dürfen schrumpfen: Sonst läuft die Titelzeile
          // über, sobald jemand das Fenster schmaler zieht als die 1280 px,
          // mit denen es startet. Der Text wird dann gekürzt, der Tooltip
          // zeigt ihn ganz; das Feld links daneben bleibt unangetastet.
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _anzeige(
                Icon(
                  _dienst.laeuft
                      ? Icons.lan
                      : _mcpVersucht
                      ? Icons.error_outline
                      : Icons.hourglass_empty,
                  size: 18,
                ),
                _dienst.laeuft
                    ? 'MCP ${_profil.mcpName} auf 127.0.0.1:${_profil.port}'
                    : _mcpVersucht
                    ? 'MCP-Server läuft nicht'
                    : 'MCP startet nach der Anmeldung',
              ),
            ),
          ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _anzeige(
                Icon(
                  angemeldet ? Icons.check_circle : Icons.cancel,
                  size: 18,
                  color: angemeldet ? Colors.green : Colors.red,
                ),
                angemeldet ? 'bei Moodle angemeldet' : 'nicht angemeldet',
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Einstellungen: Updates, KI-Werkzeuge einrichten',
            onPressed: _einstellungenZeigen,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Über $appName',
              onPressed: () => ueberZeigen(context),
            ),
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 460,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_instanzen.length > 1 || widget.instanzErstellen != null)
                  _karte('Moodle-Profil', [
                    DropdownButtonFormField<int>(
                      initialValue: _profilIndex,
                      decoration: const InputDecoration(labelText: 'Instanz'),
                      items: [
                        for (var i = 0; i < _instanzen.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(
                              '${_profilFuer(_instanzen[i]).name} (${_profilFuer(_instanzen[i]).mcpName})',
                            ),
                          ),
                      ],
                      onChanged: _beschaeftigt
                          ? null
                          : (i) {
                              if (i != null) _profilWaehlen(i);
                            },
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _beschaeftigt || widget.instanzErstellen == null
                              ? null
                              : () => _profilBearbeiten(neu: true),
                          icon: const Icon(Icons.add),
                          label: const Text('Profil hinzufügen'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _beschaeftigt ? null : () => _profilBearbeiten(),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Profil bearbeiten'),
                        ),
                      ],
                    ),
                  ]),
                _karte('Moodle-Anmeldung', [
                  TextField(
                    controller: _adresse,
                    enabled: !_beschaeftigt && !_moodle.angemeldet,
                    decoration: const InputDecoration(
                      labelText: 'Moodle-Adresse',
                      hintText: 'https://…',
                    ),
                  ),
                  TextField(
                    controller: _benutzer,
                    decoration: const InputDecoration(
                      labelText: 'Benutzername',
                    ),
                  ),
                  TextField(
                    controller: _passwort,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Passwort'),
                    onSubmitted: (_) {
                      if (_eingerichtet &&
                          !_beschaeftigt &&
                          !_moodle.angemeldet) {
                        _anmelden();
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      InkWell(
                        onTap: _beschaeftigt ? null : () => _merkenAendern(!_merken),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _merken,
                              onChanged: (v) => _merkenAendern(v ?? false),
                            ),
                            const Text('Anmeldedaten speichern'),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                      FilledButton(
                        // Erst nach „KI-Werkzeuge einrichten" (_starten).
                        onPressed: !_eingerichtet || _beschaeftigt || angemeldet
                            ? null
                            : _anmelden,
                        child: Text(_beschaeftigt ? 'Melde an …' : 'Anmelden'),
                      ),
                      OutlinedButton(
                        onPressed: angemeldet ? _abmelden : null,
                        child: const Text('Abmelden'),
                      ),
                      if (kDebugMode)
                        TextButton(
                          onPressed: angemeldet
                              ? _moodle.sitzungVerwerfen
                              : null,
                          child: const Text('Sitzung verwerfen (Test)'),
                        ),
                    ],
                  ),
                  if (_meldung != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_meldung!),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Ohne Haken bleiben Benutzername und Passwort nur im Arbeitsspeicher, solange '
                    'die App läuft -- für die automatische Neuanmeldung, wenn die Sitzung abläuft. '
                    'Mit Haken speichert die App sie nach einer erfolgreichen Anmeldung -- den '
                    'Benutzernamen in ihren Einstellungen, das Passwort '
                    '${Anmeldedaten.schutz} (${Anmeldedaten.lesbarFuer}) -- und meldet sich beim Start '
                    'selbst an. Haken weg: beides wird sofort gelöscht. Das Passwort geht nie an '
                    'die KI und in kein Protokoll.',
                    style: klein,
                  ),
                ]),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: ProtokollAnsicht(widget.protokoll)),
        ],
      ),
    );
  }

  /// Eine Anzeige in der Titelzeile. Der Text wird gekürzt, wenn der Platz
  /// nicht reicht, und steht dann im Tooltip.
  Widget _anzeige(Icon symbol, String text) => Tooltip(
    message: text,
    child: Chip(
      avatar: symbol,
      label: Text(text, overflow: TextOverflow.ellipsis),
    ),
  );

  Widget _karte(String titel, List<Widget> inhalt) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titel, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...inhalt,
        ],
      ),
    ),
  );
}

/// Ein Satz je Stufe, fürs Protokoll.
const _stufeKurz = {
  Bestaetigungen.keine: 'Änderungen in Moodle laufen ohne Rückfrage',
  Bestaetigungen.mittel:
      'Freigabe vor Ändern, Verschieben, Sichtbarkeit, Löschen',
  Bestaetigungen.alle:
      'Freigabe vor jedem Schreibvorgang, auch verborgen Angelegtem',
};

/// Das Feld in der Titelzeile: welche Bestätigungen die Lehrkraft vor
/// Änderungen in Moodle will. Bei „keine" ist das ganze Feld in Warnfarbe --
/// abgeschaltete Rückfragen sollen man im Vorbeigehen sehen.
class BestaetigungenFeld extends StatelessWidget {
  const BestaetigungenFeld({
    required this.stufe,
    required this.aendern,
    super.key,
  });

  final Bestaetigungen stufe;
  final Future<void> Function(Bestaetigungen) aendern;

  @override
  Widget build(BuildContext context) {
    final warnung = stufe == Bestaetigungen.keine;
    final farbe = Theme.of(context).colorScheme;
    final vorn = warnung ? farbe.onError : farbe.onSurface;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: warnung ? farbe.error : farbe.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: warnung ? farbe.error : farbe.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Bestaetigungen>(
              value: stufe,
              isDense: true,
              // Ohne feste Zeilenhöhe: Die Einträge im Menü sind zweizeilig
              // (Name und Kurztext) und passen nicht in die Vorgabe von 48.
              itemHeight: null,
              borderRadius: BorderRadius.circular(8),
              focusColor: Colors.transparent,
              iconEnabledColor: vorn,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: vorn),
              // Im geöffneten Menü steht jede Stufe mit ihrem Kurztext; im Feld
              // selbst ist nur Platz für ihren Namen.
              selectedItemBuilder: (_) => [
                for (final x in Bestaetigungen.values)
                  Row(
                    children: [
                      if (x == Bestaetigungen.keine) ...[
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: vorn,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        'Bestätigungen: ${x.text}',
                        style: TextStyle(
                          color: vorn,
                          fontWeight: x == Bestaetigungen.keine
                              ? FontWeight.bold
                              : null,
                        ),
                      ),
                    ],
                  ),
              ],
              items: [
                for (final x in Bestaetigungen.values)
                  DropdownMenuItem(
                    value: x,
                    child: SizedBox(
                      width: 320,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            x.text,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: x == Bestaetigungen.keine
                                  ? farbe.error
                                  : null,
                            ),
                          ),
                          Text(
                            _stufeKurz[x]!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              onChanged: (x) {
                if (x != null) aendern(x);
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Der Hilfe-Dialog hinter dem Fragezeichen neben dem Feld.
Future<void> bestaetigungenHilfe(
  BuildContext context, {
  String profilname = 'Moodle',
  String mcpName = 'moodle',
}) => showDialog<void>(
  context: context,
  builder: (context) {
    final klein = Theme.of(context).textTheme.bodySmall;
    final farbe = Theme.of(context).colorScheme;
    Widget stufe(String name, Color? ton, String was, String wofuer) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: ton),
          ),
          const SizedBox(height: 2),
          Text(was),
          const SizedBox(height: 2),
          Text(wofuer, style: klein),
        ],
      ),
    );
    return AlertDialog(
      title: Text('$profilname ($mcpName) — Bestätigungen vor Änderungen'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bevor die App etwas in Moodle schreibt, zeigt sie Ihnen in einem Fenster, was '
                'geschieht -- mit Kurs, Namen und, wo es Text gibt, einem Vergleich vorher/nachher. '
                'Hier stellen Sie ein, wie oft das sein soll. Ohne Entscheidung innerhalb von '
                '30 Minuten geschieht nichts.',
                style: klein,
              ),
              const Divider(height: 28),
              stufe(
                'alle',
                null,
                'Jeder Vorgang, der in Moodle etwas schreibt, wird gezeigt -- auch verborgen '
                    'Angelegtes und was die KI gleich danach hineinschreibt, Kopien, neue Fragenkategorien '
                    'und importierte Fragen.',
                'Für den Anfang, solange Sie sehen wollen, was die KI tut. Rechnen Sie mit vielen '
                    'Fenstern: Eine Lernsituation mit zwölf Blättern bedeutet zwölf Bestätigungen.',
              ),
              stufe(
                'mittel',
                null,
                'Gezeigt wird, was Bestehendes anfasst oder sofort für Lernende sichtbar wird: '
                    'Ändern, Verschieben, Sichtbarkeit, Löschen, sichtbar Anlegen.',
                'Die Voreinstellung. Neues entsteht verborgen und ohne Rückfrage, ebenso was die KI '
                    'gleich danach hineinschreibt, etwa die Spalten eines neuen Boards -- sehen kann es '
                    'nur, wer den Kurs bearbeiten darf, und sichtbar wird es erst mit Ihrer Freigabe.',
              ),
              stufe(
                'keine',
                farbe.error,
                'Es wird nichts mehr gezeigt. Alles läuft sofort, auch Löschen.',
                'Nur für den Fall, dass Sie sich sicher sind und zügig arbeiten wollen. Das Feld ist '
                    'dann rot. Was bleibt: Die KI kommt an keine Daten von Lernenden, nennt vor jedem '
                    'Verschieben, Verbergen und Löschen den Namen, wie er jetzt in Moodle steht, und '
                    'bricht ab, wenn er nicht passt. Jeder Vorgang steht im Protokoll. Die Freigabe je '
                    'Bildschirmfoto bleibt in jedem Fall: Sie entscheidet nicht über eine Änderung, '
                    'sondern darüber, welches Bild aus Ihrem Kurs an die KI geht.',
              ),
              const Divider(height: 28),
              Text(
                'Die Einstellung bleibt über einen Neustart hinweg. Die KI kann sie nicht ändern und '
                'erfährt nur, welche gilt -- damit sie keine Rückfrage ankündigt, die nicht kommt.',
                style: klein,
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Schließen'),
        ),
      ],
    );
  },
);

/// Zeigt die offene Freigabeanfrage als Dialog, immer genau einen. Die
/// Entscheidung geht an das wartende Werkzeug; beantwortet die App die Anfrage
/// selbst (Frist, Abbruch), schließt sich der Dialog, und die nächste
/// wartende Anfrage öffnet ihren.
class FreigabeDialoge extends StatefulWidget {
  const FreigabeDialoge({
    super.key,
    required this.freigaben,
    required this.nachVorn,
    required this.child,
    this.profilname = 'Moodle',
    this.mcpName = 'moodle',
  });
  final Freigaben freigaben;
  final String profilname;
  final String mcpName;

  /// Nach vorn und dort bleiben, solange ein Dialog offen ist -- ein Dialog
  /// hinter anderen Fenstern wird übersehen, und dann läuft nur die Frist ab.
  final Future<void> Function(bool an) nachVorn;

  final Widget child;

  @override
  State<FreigabeDialoge> createState() => _FreigabeDialogeState();
}

class _FreigabeDialogeState extends State<FreigabeDialoge> {
  FreigabeAnfrage? _gezeigt;
  Route<bool>? _dialog;

  @override
  void initState() {
    super.initState();
    widget.freigaben.addListener(_zeigen);
  }

  @override
  void didUpdateWidget(covariant FreigabeDialoge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final freigabenGewechselt = oldWidget.freigaben != widget.freigaben;
    final profilGewechselt = oldWidget.profilname != widget.profilname || oldWidget.mcpName != widget.mcpName;
    if (!freigabenGewechselt && !profilGewechselt) return;
    if (freigabenGewechselt) {
      oldWidget.freigaben.removeListener(_zeigen);
      widget.freigaben.addListener(_zeigen);
    }
    _gezeigt = null;
    final alt = _dialog;
    _dialog = null;
    if (alt != null && alt.isActive) {
      alt.navigator!.removeRoute(alt);
      widget.nachVorn(false);
    }
    _zeigen();
  }

  @override
  void dispose() {
    widget.freigaben.removeListener(_zeigen);
    super.dispose();
  }

  void _zeigen() {
    final a = widget.freigaben.aktuell;
    if (identical(a, _gezeigt)) return;
    // Die App hat die gezeigte Anfrage selbst beantwortet: genau deren Dialog
    // schließen. Ein pop() träfe, was gerade oben liegt, oder bliebe ganz
    // aus, wenn sich darüber inzwischen etwas geändert hat -- und die nächste
    // Anfrage kommt im selben Zug.
    final alt = _dialog;
    _gezeigt = null;
    _dialog = null;
    if (alt != null && alt.isActive) alt.navigator!.removeRoute(alt);
    if (a == null || !mounted) {
      if (alt != null) widget.nachVorn(false);
      return;
    }
    _gezeigt = a;
    widget.nachVorn(true);
    // Eine eigene Route statt showDialog, damit sich genau sie wieder
    // entfernen lässt; eingestellt wie bei showDialog.
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<bool>(
      context: context,
      builder: (_) => FreigabeDialog(
        a,
        widget.freigaben,
        profilname: widget.profilname,
        mcpName: widget.mcpName,
      ),
      barrierDismissible: false,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    );
    _dialog = route;
    navigator.push(route).then((ja) {
      // Oben entfernt: Die Anfrage ist schon beantwortet.
      if (!identical(_dialog, route)) return;
      _gezeigt = null;
      _dialog = null;
      widget.nachVorn(false);
      if (identical(widget.freigaben.aktuell, a)) {
        widget.freigaben.entscheiden(ja ?? false);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class FreigabeDialog extends StatelessWidget {
  const FreigabeDialog(
    this.anfrage,
    this.freigaben, {
    this.profilname = 'Moodle',
    this.mcpName = 'moodle',
    super.key,
  });
  final FreigabeAnfrage anfrage;
  final String profilname;
  final String mcpName;

  /// Für die Frist und den Zähler der wartenden Anfragen, der sich ändert,
  /// während der Dialog offen ist.
  final Freigaben freigaben;

  /// Was von der Frist bleibt: Sie läuft ab der Anfrage, und wer gewartet
  /// hat, hat weniger. Ohne [FreigabeAnfrage.ablauf] (nicht über
  /// Freigaben.anfragen gestellt, etwa im Bild fürs Handbuch) die volle.
  String _restfrist() {
    final rest = anfrage.ablauf?.difference(DateTime.now()) ?? freigaben.frist;
    final minuten = (rest.inSeconds / 60).round();
    return minuten <= 1 ? 'einer Minute' : '$minuten Minuten';
  }

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(fontFamily: 'Consolas', fontSize: 12);
    Widget zeile(Zeile z) {
      final (zeichen, farbe) = switch (z.art) {
        ZeilenArt.weg => ('− ', const Color(0x33E53935)),
        ZeilenArt.neu => ('+ ', const Color(0x3343A047)),
        ZeilenArt.gleich => ('  ', Colors.transparent),
        ZeilenArt.ausgelassen => ('  ', Colors.transparent),
      };
      return Container(
        color: farbe,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          '$zeichen${z.text}',
          style: z.art == ZeilenArt.ausgelassen
              ? mono.copyWith(fontStyle: FontStyle.italic, color: Colors.grey)
              : mono,
        ),
      );
    }

    final gross = anfrage.vergleich.isNotEmpty || anfrage.bilder.isNotEmpty;
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(anfrage.titel),
          Text(
            '$profilname ($mcpName)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
      // Der kleine Dialog braucht Platz für eine volle Liste, den Satz zur
      // Frist und den Zähler darunter, auch bei 125 % Schriftgröße
      // (freigabe_test.dart); die großen fangen den Zähler im Zeilenvergleich
      // oder in den Bildern auf.
      content: SizedBox(
        width: gross ? 900 : 620,
        height: anfrage.bilder.isNotEmpty
            ? 680
            : gross
            ? 560
            : 264,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (anfrage.grund != null) ...[
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Wozu: ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: anfrage.grund),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            // Bei einer Sammelfreigabe viele Punkte: Sie scrollen für sich,
            // damit der Zeilenvergleich darunter sichtbar bleibt.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: gross ? 200 : 180),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final p in anfrage.punkte) Text('•  $p')],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (anfrage.vergleich.isNotEmpty) ...[
              Text(
                'Quelltext, vorher (−) und nachher (+):',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                  ),
                  child: SelectionArea(
                    child: ListView(
                      children: [for (final z in anfrage.vergleich) zeile(z)],
                    ),
                  ),
                ),
              ),
            ] else if (anfrage.bilder.isNotEmpty) ...[
              Text(
                'Genau diese Bilder gehen weiter:',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                  ),
                  child: ListView(
                    children: [
                      for (final b in anfrage.bilder)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Image.memory(b, fit: BoxFit.fitWidth),
                        ),
                    ],
                  ),
                ),
              ),
            ] else
              const Spacer(),
            const SizedBox(height: 8),
            Text(
              'Ohne Entscheidung innerhalb von ${_restfrist()} ${anfrage.ohneEntscheidung}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            // Nach der Entscheidung kommt der nächste Dialog -- die Lehrkraft
            // soll das vorher wissen, nicht erst überrascht werden.
            ListenableBuilder(
              listenable: freigaben,
              builder: (context, _) => switch (freigaben.wartend) {
                0 => const SizedBox.shrink(),
                final n => Text(
                  n == 1
                      ? '1 weitere Anfrage wartet.'
                      : '$n weitere Anfragen warten.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              },
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(anfrage.ablehnen),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(anfrage.knopf),
        ),
      ],
    );
  }
}

/// Das Protokoll im Fenster, der neueste Eintrag unten. Steht die Liste ganz
/// unten, folgt sie neuen Einträgen; wer hochscrollt, hält sie an, bis er
/// wieder ganz unten ist.
class ProtokollAnsicht extends StatefulWidget {
  const ProtokollAnsicht(this.protokoll, {super.key});
  final Protokoll protokoll;

  @override
  State<ProtokollAnsicht> createState() => _ProtokollAnsichtState();
}

class _ProtokollAnsichtState extends State<ProtokollAnsicht> {
  static const _symbole = {
    Art.werkzeug: (Icons.smart_toy_outlined, Colors.indigo),
    Art.moodle: (Icons.public, Colors.blueGrey),
    Art.schreiben: (Icons.edit_note, Colors.deepPurple),
    Art.anmeldung: (Icons.key, Colors.teal),
    Art.gesperrt: (Icons.block, Colors.red),
    Art.fehler: (Icons.error_outline, Colors.orange),
    Art.info: (Icons.info_outline, Colors.grey),
  };

  String _zeit(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  final _scroll = ScrollController();

  // Ob die Liste folgt, ändert sich mit jeder Bewegung (Mausrad,
  // Scrollbalken, Ziehen, eigener Sprung ans Ende). Ein neuer Eintrag ist
  // keine Bewegung: Er verschiebt nur das Ende, und die Liste folgt weiter.
  bool _folgen = true;

  bool get _unten =>
      _scroll.position.pixels >= _scroll.position.maxScrollExtent - 1;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => _folgen = _unten);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // Kommt nach dem Bild, in dem sich Länge oder Höhe der Liste geändert
  // haben (neuer Eintrag, Leeren, Fenstergröße). Die Länge ist nur geschätzt,
  // solange nicht alle Einträge gebaut sind; landet der Sprung zu früh, kommt
  // die nächste Meldung und springt weiter.
  bool _groesseGeaendert(ScrollMetricsNotification _) {
    if (!_scroll.hasClients) return false;
    if (_unten) {
      _folgen = true;
    } else if (_folgen) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Text('Protokoll', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: widget.protokoll.leeren,
                child: const Text('Leeren'),
              ),
            ],
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: _groesseGeaendert,
            child: ListenableBuilder(
              listenable: widget.protokoll,
              builder: (context, _) {
                final e = widget.protokoll.eintraege;
                return ListView.builder(
                  controller: _scroll,
                  itemCount: e.length,
                  itemBuilder: (context, i) {
                    final x = e[i];
                    final (symbol, farbe) = _symbole[x.art]!;
                    return ListTile(
                      dense: true,
                      leading: Icon(symbol, color: farbe, size: 18),
                      title: SelectableText(
                        x.text,
                        style: const TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 12.5,
                        ),
                      ),
                      trailing: Text(
                        _zeit(x.zeit),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
